# Plan IG — HeyCyan Glasses Connectivity

**Status:** 📝 Drafted 2026-10-11 — no implementation. Hardware, firmware, protocol details,
vendor SDK redistribution terms, and the media-transfer flow need verification before a backend is
selected. The first useful target is BLE control plus retrieval of a captured still; live frames
are not part of the claim.
**Origin:** Drafted 2026-10-11 to see whether HeyCyan-compatible glasses can work beside Meta's,
from what is publicly reported about how these glasses are controlled and how their media is
retrieved, read against Avenkin's own camera and device seams. None of that reporting is verified,
and the reports disagree with each other in places (see "Evidence and limits").
**Related:** Plan [CQ](CQ-third-party-glasses-backends.md) (generic camera backend and OEM transport
work), Plan [HX](HX-glasses-link-and-device-state.md) (Meta-only connection diagnosis), Plan [CP](CP-outbound-frame-privacy.md)
(camera egress privacy), Plan [AH](even-display-backend.md) (separate BLE device backend precedent).
One PR per phase; pure decision cores first, hardware edges behind seams.

## Outcome

An owner of a verified HeyCyan-compatible glasses model can connect from Avenkin, use it as a
Bluetooth audio device where iOS exposes its HFP route, trigger a glasses capture, and retrieve the
resulting full-resolution media to the phone when supported by that exact model. The app reports
the device's actual tier and does not imply that a stored-media transfer is a live camera stream.

Meta DAT remains the Meta connection and camera path. HeyCyan pairing, commands, Wi-Fi joining,
permissions and errors must not pass through Meta registration or camera-permission logic.

## Evidence and limits

Three integration routes are reported for these glasses, and they may not all apply to one model:

- On Android, BLE controls the glasses and Wi-Fi P2P carries media off them.
- On iOS, CoreBluetooth controls the glasses and `NEHotspotConfiguration` joins a hotspot the
  glasses raise. The glasses report an IP address over BLE, and media is fetched from it over HTTP.
- On iOS, the vendor's QCSDK binary wraps capture and control operations behind its own API.
- Audio reaches iOS as an ordinary HFP Bluetooth route. Nothing reported shows continuous camera
  frames arriving in a host app.

The reported media index disagrees with itself: one account names `/files/media.config`, another
`/manifest.json`. Treat both the endpoint and the IP/transfer sequence as unverified until they are
reproduced against the selected model and firmware. A command that works on one HeyCyan-branded
model is not evidence that it works on another.

No licence is assumed for any third-party code, and none would extend to the vendor's QCSDK binary,
whose terms are the vendor's. Any linked SDK also needs a review of its default telemetry, privacy
manifest and in-app disclosure before adoption, under Plan [DQ](DQ-third-party-telemetry-opt-out.md).

## P0 — Choose a supported device and an integration route

Acquire the intended hardware and record the commercial model, hardware revision, firmware,
companion-app version and iPhone/iOS versions. Reproduce discovery, connect, battery/version reads,
one still capture, BLE notification delivery, hotspot join and one full-resolution download.
Record protocol evidence from an independently operated device session; do not infer command UUIDs,
opcodes, packet framing or endpoint paths from a different model.

Compare the QCSDK wrapper with a direct CoreBluetooth implementation. Prefer the QCSDK only after
written redistribution/commercial-use terms and binary compatibility are established. Otherwise,
use a clean-room implementation from independently documented behavior and our own captures; do
not port third-party code or vendor artifacts. Decide whether the KMP host is a useful
reference or whether a native Swift implementation is smaller and supportable.

**Gate:** if there is no suitable device, no reproducible capture/transfer path, or no licensable
SDK and insufficient evidence for a clean-room protocol, stop at documented audio-only support.
Do not ship a guessed transport.

## P1 — Connection and audio-tier path

Add a HeyCyan-specific device owner for discovery, explicit user-selected connect/disconnect,
connection state and device identity. It must not alter `GlassesConnectionService`'s Meta
registration, permission diagnosis or DAT link truth. Start foreground-only; background BLE,
state restoration and automatic reconnect are separate decisions.

Use the existing Bluetooth audio route if the glasses present a usable HFP input/output. Check
whether `MicRoutePolicy.glassesNameMarkers` already recognizes the actual advertised/route names;
only extend its data and tests if needed, including a false-positive corpus so earbuds are not
misclassified. Do not add a second microphone pipeline or claim camera/microphone concurrency until
the hardware has been measured.

Tests: pure connection-state transitions and stale-callback handling; fake-transport lifecycle;
name-marker positives and negatives. Hardware: scan/connect/disconnect, route appearance, call
quality, and whether the route returns after app foreground/background transitions.

## P2 — BLE command transport and capture control

Introduce a small HeyCyan transport seam and a typed command/reply layer based only on P0-attested
behavior. CoreBluetooth is the production edge; tests use a recording fake. Bound notification
buffers and command timeouts, serialize commands where the device requires it, and make disconnect
cancel pending operations. Persist only the selected peripheral identifier using the same
least-surprising device-local storage rules as other hardware pairing.

Expose only verified actions (initially device info and still capture; video/audio recording
controls only if independently verified). Distinguish command accepted, capture completed, media
available, timeout and unknown reply; an acknowledgement must not be presented as a successful
photo. No guessed retry of a shutter command, since retrying an unobserved command can take an
unintended second picture.

Tests: command encoding/decoding against project-owned capture fixtures, notification
fragmentation if observed, unknown replies, timeouts, disconnect during a command, duplicate
completion, and command serialization. Fixtures must be generated from our device evidence or
published vendor specifications, not copied implementation code.

## P3 — Stored-media retrieval over the glasses Wi-Fi link

Model media retrieval as an explicit foreground operation: request/observe capture, obtain the
glasses-reported network address, join the expected hotspot using the supported iOS API, fetch and
validate the media index, download a bounded file, then restore the prior network posture before
any cloud/model work begins. Resolve the `/files/media.config` versus `/manifest.json` discrepancy
on hardware before fixing an endpoint in code. Never trust a filename or URL from a device response
without constraining it to the expected local origin and path.

First run the cellular/Wi-Fi route experiment: while joined to the glasses AP, can URLSession still
reach the public internet over cellular? If not, confirm that leaving/rejoining the AP is reliable
and that the app waits for a routable path before handing the image to a model. A failed transfer
must produce an explicit failure (or a separately supported thumbnail), never a stale prior frame.
Check the existing Hotspot Configuration entitlement and App ID/App Store requirements; its
presence for DAT does not by itself prove this flow is approved or correct.

Pure tests: transfer state machine, host/path/filename validation, size and timeout bounds,
ordering of join → download → leave → network-ready, cancellation, partial download cleanup and
thumbnail fallback only if its format/meaning are verified. Hardware tests cover hotspot
permission, captive/no-internet behavior, cellular continuity, repeated transfer and recovery after
cancel or interruption.

## P4 — Still-only camera backend integration

Conform to the existing `GlassesCameraBackend` only if the API fits the proven HeyCyan operation;
otherwise make the smallest adjustment to the seam rather than model Meta sessions. Declare
`liveFrames: false`, `stillCapture: true` only when a full-resolution still can actually be returned,
`stillLatency: .seconds`, and the measured `concurrentWithMic` value. A BLE thumbnail alone is not
vision-quality evidence. Keep `CameraService` as the consumer surface and preserve its readiness,
staleness and explicit phone-fallback rules.

Route imported/captured pixels through the established still-image privacy policy and outbound
consumer roster; do not publish them as fresh live frames or attach them directly to a model. Add a
HeyCyan device/backend choice only after connection and transfer are independently testable. Show
the available tier and unsupported live-camera features using existing capability-gate patterns.

Tests: fake-backend coordinator tests, capability matrix (photo available; every live-frame
feature unavailable), capture-source and stale-image rejection, and privacy-roster enforcement.
Meta regression tests must remain unchanged and green.

## P5 — Live-frame feasibility spike (optional, separately approved)

Only after P3 works on the chosen model, investigate whether a documented local stream can provide
frames to the phone. A video recording stored onboard, a remote RTMP push, or a thumbnail
notification does not satisfy `CameraService.framePublisher`. Time-box the experiment and report
measured in-process frame rate, end-to-end latency, decode cost, thermals, battery, audio
coexistence and background behavior. Do not change `liveFrames` to true unless frames reach the
app reliably and pass through the same freshness and privacy boundaries as Meta frames.

## Non-goals

- Replacing or wrapping Meta DAT with HeyCyan connectivity.
- Claiming HeyCyan model/firmware compatibility from a brand name alone.
- Porting QCSDK binaries or source without explicit rights.
- Supporting the vendor AI service, account, cloud, OTA or firmware modification.
- Claiming local live frames based on onboard recordings, remote ingest, or BLE thumbnails.
- Generalizing all glasses connection services before a second concrete non-Meta device path
  demonstrates the shared contract.
- Enabling background scanning or silent hotspot joins in the first usable version.

## Open decisions

1. Which exact HeyCyan model and firmware are the first target, and can hardware be acquired for
   repeatable testing?
2. Is QCSDK redistribution explicitly permitted for this app, and does its binary build with the
   current Xcode/iOS toolchain? If not, is the observed protocol sufficiently documented for a
   clean-room native transport?
3. Which media index endpoint and IP source are correct for the target firmware?
4. Does the Wi-Fi transfer interrupt cellular access, and can iOS reliably return to the prior
   route after the transfer?
5. Does still capture or video capture suspend the HFP microphone, and what should an active voice
   session do while capture is in progress?
6. Do imported media pixels require a distinct still-source policy in the privacy roster, or can
   the existing filtered-still path express the correct treatment without exempting them?
7. Is there a locally consumable video stream at all? P5 is a measurement decision, not a promised
   feature.
