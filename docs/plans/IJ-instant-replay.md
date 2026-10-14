# Plan IJ — Instant Replay (save the last minute of the glasses' view)

**Status:** 📝 Drafted 2026-10-14 — nothing implemented.
**Origin:** A 2026-10-14 comparison with another companion app for the same glasses, whose live
view keeps the last two minutes in memory so a moment can be saved after it happened. Memory Rewind
does this for audio; nothing does it for video.
**Related:** Plan [CP](CP-outbound-frame-privacy.md) (the outbound frame roster and the relay),
Plan [FO](FO-guided-job-flow-and-job-tab.md) P2b (`JobClipRecorder`, the nearest existing recorder),
Plan [HW](HW-glasses-stream-integrity.md) (stream stalls and background frames), Plan
[CT](CT-org-configuration-profiles.md) (organisation ceilings), `MemoryRewindService` (the audio
precedent). One PR per phase; the pure ring core first.

## Outcome

While the glasses camera is already streaming, a wearer who has turned Instant Replay on can say
"save that" or "save the last minute", or press a button in the live view, and get the last N
seconds as a video, filed like any other recording. Nothing is kept once the stream stops, and
nothing is kept at all unless the wearer turned it on.

## Why not the comparison app's way

That app receives the glasses' compressed video directly, so it holds the compressed frames in
memory, trims to a keyframe and writes them out without encoding anything. We cannot do that:

- The compressed video we get from DAT is the glasses' raw view, before the bystander blur. A saved
  replay is a recording (`PrivacyFilterScope.recording`). Under the roster rules it must read from
  `OutboundFrameRelay.publisher`, like `VideoRecordingService` and `JobClipRecorder`.
- The relay hands out decoded `UIImage`s. Holding those is out of the question: one 720×1280 frame
  is about 3.7 MB, so two minutes at 24 fps would be more than 10 GB.

So we encode the relay's frames ourselves, into short segment files on disk, and join the newest
ones when asked.

## Design

### P0 — Segment ring policy (pure, headless-tested)

`ReplaySegmentRing` is a value type that decides, without touching a file:

- **Rotation.** When the open segment reaches `segmentSeconds` (proposed 10 s), close it and start
  the next one.
- **Retention.** After each close, drop the oldest closed segments while the rest still cover
  `windowSeconds + segmentSeconds`. The extra segment exists because a join can only start on a
  segment's first keyframe.
- **Selection.** `segments(toCover seconds:, now:)` returns the newest closed segments, plus the open
  one once it is flushed, that cover the request, and the trim range.
- **Gaps.** A stream stall (`StreamPausePolicy` / Plan HW) closes the open segment. A gap longer
  than `maxGapSeconds` clears the ring, so a replay never splices two separate moments together as
  if they were continuous.
- **Budget.** A disk budget in bytes. Over budget, or below the free-space floor that
  `VideoRecordingService.storageVerdict` already computes, drop to the minimum and report
  `.storageLow`.
- **States.** `.off`, `.holding(seconds)`, `.paused(reason)` (thermal, recording in progress,
  storage), published so the live view can show "Last 1:12 held".

The segment and window constants live in the core. `windowSeconds` is a setting (30 / 60 / 120 s,
default 60).

### P1 — Segment writer and the join

- **`ReplaySegmentWriter`** owns one `AVAssetWriter` per segment. It uses H.264 video only, at the
  same settings as `JobClipRecorder` so the segments join without re-encoding. It subscribes to
  `OutboundFrameRelay.publisher` and is listed in the roster as
  `OutboundFrameConsumer.instantReplay` under `.recording`. `OutboundFrameConsumerTests` picks the
  subscription up and fails until the roster entry exists.
- **Segment storage.** Segments go in `ComplianceFileProtection.inProgressDirectory`, a
  `replay/` subfolder, protected as in-progress recording data. Launch sweeps it, so a crash never
  leaves a ring behind.
- **`ReplayExporter`** joins the selected segments with an `AVMutableComposition`, trims with a
  passthrough `AVAssetExportSession` (the trim snaps to a keyframe, which is acceptable), applies
  `RecordingProvenanceMetadata`, and files the result through `VideoRecordingService`'s existing
  filing plan (Recordings folder, the wearer's chosen folder, and Photos unless turned off).
- **Lifecycle.** The ring starts when the camera stream delivers its first frame with Instant
  Replay on, and stops and deletes every segment when the stream stops. It never starts the camera
  itself: no extra battery, no extra privacy LED.

**Audio: off, deliberately.** The same reasoning as `JobClipRecorder`. A replay is saved after the
fact, so the people in the room never had a moment to object. A face can be blurred; a voice cannot.
v1 is silent. Revisit only with a consent design.

### P2 — Triggers and surfaces

- **Native tool `save_replay`** (`seconds`, optional, clamped to the window). It answers with what
  it actually saved ("Saved the last 48 seconds") or why not ("Replay isn't on" / "The camera isn't
  streaming" / "Only 6 seconds held"). Its description feeds `SystemPromptBuilder` like every tool.
- **A live-view control:** a "Save replay" button next to record, showing the held duration.
- **Settings › Devices & Privacy › Glasses:** an Instant Replay toggle (off by default), the window
  picker, and one line on what it does and that it keeps no sound.
- **Optional, later:** an App Intent, so the Action Button or a Control can save a replay.

### Gates

- **Off by default.** Turning it on is a deliberate choice in Settings.
- **HIPAA mode (`Config.hipaaMode`):** hard-disabled, like diarization. A rolling video buffer is
  exactly the unplanned PHI capture that mode exists to prevent.
- **Organisation profile (Plan CT):** a ceiling key can pin it off.
- **Thermal (`PowerPolicyService`):** paused at the same level that already sheds camera work. The
  pause shows in the held-duration label, never silently.
- **While a recording runs:** the ring pauses; the recording covers that time. Whether the ring
  should instead keep running so a replay can reach back before the recording started is open
  question 2.

## Tests

- **P0:** `ReplaySegmentRingTests` cover rotation, retention at each window, selection for exact,
  short and over-long requests, gap handling, budget and storage-low, and pause/resume transitions.
  Everything is deterministic with injected clocks.
- **P1:** a writer test with synthetic frames (fresh instances, never the `.shared` camera, per the
  Wearables rule): segments rotate on time and each one is playable; an exporter test that joins
  three synthetic segments and checks duration and trim; a launch-sweep test.
- **Roster:** `OutboundFrameConsumerTests` green with the new case and nothing else touched.
- **P2:** `save_replay` result strings for every refusal, and the clamp.

**Device-pending:**
- encoder cost and thermals over a 20-minute live session;
- whether `AVAssetWriter` keeps encoding with the phone locked while the stream runs (Plan HW found
  GPU work denied in the background, and the hardware encoder may be treated the same);
- the keyframe snap at the start of a saved replay;
- disk churn on a nearly full phone.

## Open questions

1. Default window: 60 s, or 120 s like the comparison app? Longer costs disk churn, not memory.
2. Keep the ring running during a recording, so "save the last minute" can reach back before the
   recording began? It costs a second encoder.
3. Should a saved replay be announced on the glasses ("Saved the last minute") even when it was
   triggered from the phone?
4. Field Assist: does a replay saved during a job attach to the job like a clip, or stay a personal
   recording? Default: personal. Attaching to customer records goes through the job clip path.
