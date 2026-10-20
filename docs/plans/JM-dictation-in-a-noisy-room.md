# Plan JM — Dictation in a Noisy Room (heard right on site, a way to type or check when it isn't, and a cloud recogniser as an option)

**Status:** 📝 Drafted 2026-10-21 — nothing implemented. Raised by a tester after a demo over lunch
in a noisy restaurant: the assistant kept mishearing them, it works well somewhere quiet, and
background conversation or equipment noise on site would be a problem. They asked for a typed
fallback, a chance to correct the transcript before it goes, and whether a cloud recogniser through
"the existing ChatGPT connection" would hear better.
**Track:** Field Assist first (the on-site case), but every phase is app-wide: the recogniser,
the typed path and the review step are the phone's, not the trade's.
**Related:** [CU](CU-voice-turn-latency.md) (end of turn, the HFP mic's noise floor, the turn
ledger that measures any latency this adds), [AQ](speaker-diarization.md) (the Deepgram transport
and its gate), [BU](BU-offline-live-session.md) and Additional Capabilities #8 (the on-device
recogniser and `ASREngineSelector`), [GU](GU-wake-word-audio-and-power.md) (the mic route and the Bluetooth session),
[FO](FO-guided-job-flow-and-job-tab.md) (a typed turn belongs to the job conversation),
[DM](DM-privacy-safe-production-logging.md) (no transcript text in a log), [DQ](DQ-third-party-telemetry-opt-out.md)
(a new vendor is disclosed in the same PR), [CT](CT-org-configuration-profiles.md) (an organisation
pins a setting), [EV](EV-ai-governance-and-eu-ai-act.md) (nothing here is a listed practice; a
cloud recogniser is a processor and is named in the privacy copy).

---

## Why

Speech is the whole interface on site, and it is the one part of the app the wearer cannot route
around when it fails. A mishearing costs a turn, a wrong part number costs a drive, and a technician
who has been misheard three times in a row stops using the assistant in front of the customer.

What the code does today, read on 2026-10-21:

- **Dictation gets no help from what the app knows.** `WakeWordService` passes the wake phrases
  to Apple Speech as contextual strings; `TranscriptionService` passes nothing. The recogniser
  that hears "Carrier 58MVC" or a part number has no idea that those words are likely, even when
  the job's equipment identity, the vault's manual titles and the van stock all name them.
- **The glasses mic is the worst mic in a restaurant.** The default route is the glasses, a hands-free
  Bluetooth link that [Plan CU](CU-voice-turn-latency.md) already describes as 8 kHz and noisy.
  The phone's own mic is wider-band, and the Realtime engine turns on Apple's voice processing
  (noise suppression and echo cancellation) on its input; dictation does not.
- **Typing already exists and already goes through the agent.** The dock's **Type** button opens
  the chat input bar, and `sendTextMessage` runs the same turn as a spoken one: the job thread,
  retrieval, tool calls, the spoken reply. The tester did not find it. It is hidden in the two
  Realtime modes.
- **There is no moment to check the transcript.** `onTranscriptionComplete` hands the text
  straight to the turn. Nothing between the recogniser and the model can show it, let alone edit it.
- **The ChatGPT sign-in cannot transcribe.** It is the subscription chat backend — a bearer token
  and an account header, chat completions only. The OpenAI Realtime mode uses a separate API key.
  What makes the ChatGPT app feel better in noise is its transcription model on the phone's mic, and
  that model is reachable with an API key, not the sign-in.
- **A cloud recogniser is already wired, for something else.** `DeepgramSTTService` streams the
  shared audio engine's buffers to Deepgram's nova-3 for diarised captions, and
  `DeepgramBatchService` transcribes saved recordings. Both sit behind the diarisation opt-in, a
  key, and HIPAA off (`isDiarizationConfigured`), and both are counted egress in
  `NetworkRouteRegistry`. Nothing routes a dictation turn through them.
- **Sending raw audio to the model instead** works for Gemini and OpenAI chat, and tools still
  fire because it is the ordinary turn with an audio part — but Claude takes no audio, the job
  thread needs text, and Field Assist retrieval needs the query as words to search the manuals.
  The transcript is needed anyway. Not pursued.

So the plan is four things in the order they pay back: make the recogniser we have hear the words
we know are coming (P0), make the typed path findable and give the wearer a moment to fix a
transcript before it goes (P1), add a cloud recogniser as a disclosed, gated option (P2), and build
the one tool that settles "which hears better in *this* room" with numbers rather than impressions
(P3).

## Principles

1. **Hands-free stays hands-free.** Every fallback here is optional and off by default. A wearer
   who never touches the phone sees no change.
2. **No new egress without a switch, a route, a HIPAA stop and a line of copy.** A cloud recogniser
   is a new processor of the wearer's voice. It is off until chosen, named in the privacy copy and
   the manifest in the same PR, refused outright under HIPAA, counted in `NetworkRouteRegistry`,
   and pinnable off by an organisation profile.
3. **The transcript is never logged.** `PrivacyLog` carries counts and tokens — the length of the
   vocabulary list, which engine answered, how long it took — never a word the wearer said.
4. **Measure before preferring.** No engine becomes the default on a demo impression. P3 exists so
   the comparison is a word-error figure on the wearer's own noisy sample.
5. **Pure core first.** Every decision — what goes in the vocabulary, when the Type chip shows,
   whether a transcript waits for review, which engine runs — is a value computation with tests.
   The audio session, the recognisers and the network are the edge.

## P0 — Hear the words we know are coming

**Vocabulary hints.** A pure `DictationVocabulary` builder produces the contextual-string list for
a dictation turn from what the app already holds:

- the active job's `EquipmentIdentity` (manufacturer, model, the serial's prefix);
- the loaded vaults' manual titles, product families and model numbers (`VaultManifest`);
- van stock part names and the parts-order lines of the active job;
- the active persona wake phrases (so a mid-turn "hey …" still matches, as today);
- a per-trade glossary that ships with the vault's trade (`FieldTrade`): refrigerant names, duct
  and pipe sizes said aloud, breaker and wire gauges, the abbreviations technicians say letter by
  letter.

Deduplicated, bounded (a cap, with the job's own equipment first and the glossary last, so the
cap trims the generic end), rebuilt when the job or vault changes, and read by
`TranscriptionService.startRecording()` into `contextualStrings` for Apple Speech. The on-device
SenseVoice engine takes no hints and ignores the list. Customer names and site addresses are **not**
in the list: the recogniser does not need them, and a list of customers' names handed to a
server-capable recogniser is a disclosure nobody asked for.

**Phone mic voice processing.** `DictationCapturePolicy` (pure) says whether to ask the input node
for Apple's voice processing: yes on the phone's built-in mic in a conversation, never on a
Bluetooth route (the glasses do their own, and the LC3/HFP link cannot take it), never while the
wake-word listener owns the engine in a mode that voice processing would reformat. Shipped behind a
developer switch and **measured on the device before it defaults on**: voice processing changes
the input format and can add latency, and [Plan CU](CU-voice-turn-latency.md)'s ledger is where
that shows.

**A route hint, not a route change.** When the route is the glasses and a turn ends with no
speech recognised, the session card says once per session that the phone's mic hears better in a
loud room, with the mic-route switch beside it. The default route does not change.

Tests: `DictationVocabularyTests` (sources, order, cap, dedupe, no customer fields, empty job),
`DictationCapturePolicyTests` (route × mode table), the route-hint policy (once per session, only
after a no-speech end, never in Realtime modes).

## P1 — A way to type, and a moment to check

**Type instead.** `TypeInsteadPolicy` (pure) decides when the chat input bar offers itself: after
two consecutive turns that ended on the no-speech timeout or on a transcript shorter than a word,
or any turn whose reply was the assistant saying it did not understand. The chip reads "Type
instead", opens the existing bar, and clears after one typed turn or one good spoken one. Never in
the Realtime modes (the bar is hidden there today and stays so). Nothing changes for a wearer who
is heard first time.

**Check before sending.** A conversation option, off by default, worded as *Check what I said before
sending*. With it on, a finished transcript lands in the chat input bar instead of going straight to
the model, with a countdown ring on the send button (3 s by default, 2–10 s adjustable). Untouched,
it sends itself when the ring completes — the hands-free path is a short pause, not a gate. Touching
the text cancels the countdown; the wearer edits and taps send. "Cancel" (spoken or tapped) drops the
turn and returns to the wake word.

`SendReviewPolicy` (pure) says whether a transcript waits: only when the option is on, the app is in
the foreground with the screen on, and the mode is Direct. Locked phone, CarPlay, Watch, a
glasses-only turn, the Realtime modes: the transcript goes as it does today, because there is
nothing to read it on. A reviewed-and-edited turn is a typed turn for the job thread
([Plan FO](FO-guided-job-flow-and-job-tab.md)): it carries `TranscriptOrigin` as edited, so a work
record can say the wearer corrected what was heard.

Tests: `TypeInsteadPolicyTests` (the counters, the reset, the mode exclusion),
`SendReviewPolicyTests` (option × foreground × mode table, the countdown's cancel-on-edit, the
timeout send), and a `TranscriptOrigin` case for an edited transcript.

## P2 — A cloud recogniser as an option

`ASREngine` gains cloud cases, `ASREnginePreference` gains the matching choices, and
`ASREngineSelector.chain` places a chosen cloud engine first **only when online and not under
HIPAA**, with the existing on-device → Apple Speech chain as the fallback. HIPAA removes the cloud
cases from the chain entirely, and — as `DeepgramSTTService` already does — the gate is re-read on
every buffer, so a HIPAA flip mid-utterance stops audio leaving the phone at once rather than at the
next turn.

**Deepgram first.** It is already linked, already a counted route, already keyed. A dictation
configuration of the same transport: no diarisation, endpointing on, the P0 vocabulary passed as
keyterms, the result's final transcript delivered through the same `onTranscriptionComplete`. A
**separate** switch from diarisation (`cloudDictation`), a separate `NetworkRoute` case with its
own one-line purpose, and its own row in the speech settings beside the recogniser picker.

**OpenAI second.** The transcription endpoint with the OpenAI **API key** (never the ChatGPT
sign-in, which cannot reach it — the settings copy says so, because the tester's question will be
every tester's). Whole-utterance: the audio is sent when the turn ends, so this engine adds an
upload after the silence window; the turn ledger measures it and the settings copy says it. The
vocabulary rides in the prompt field.

Both: named in the privacy copy and `PrivacyInfo.xcprivacy` in the same PR
([Plan DQ](DQ-third-party-telemetry-opt-out.md)'s rule), a `SettingKey` an organisation profile can
pin (so a company that has not approved a vendor can hold dictation to the phone), and nothing
spoken aloud about the engine — a switch of engine is a setting, not an announcement.

Cost is a fraction of a cent per question on either vendor's published rates and is the wearer's
own key; the settings copy says "charged to your key" and nothing more. No figure in this plan, a
PR or the app.

Tests: `ASREngineSelectorTests` extended (cloud chosen × online × HIPAA), a dictation gate test
in the shape of the diarisation one (opt-in, key, HIPAA, mid-utterance flip),
`NetworkRouteRegistryTests` for the new cases, the telemetry-and-disclosure guard for the new
vendor copy, and `OrgProfile` pin coverage for the new key.

## P3 — Settle it with numbers

A developer-panel comparison: keep the last utterance's PCM (it is already in the shared engine's
tap; the Memory Rewind buffer holds ten minutes of it) and run it through every configured engine,
showing each transcript side by side with the time it took. The wearer types what they actually
said, and a pure `RecognizerComparison` scores each engine's word error rate against it. A session
of ten utterances in the room in question is a table, and the table is the decision.

Also the protocol for the device pass this plan owes: the same ten sentences — two part numbers, a
model, a refrigerant, a measurement with units, a question with a brand — spoken in a quiet room,
beside a running unit, and in a café, on the glasses mic and the phone mic, with vocabulary hints
on and off. Results recorded in this plan's status line, not in a PR.

Tests: `RecognizerComparisonTests` (alignment, substitutions/insertions/deletions, empty and
identical cases, a transcript with punctuation and case differences scoring as equal).

## Not in this plan

- **Sending audio to the model with no transcript.** Decided against above.
- **Changing the default mic route.** P0 hints at the phone mic in a loud room; a route change is
  the wearer's.
- **A noise-suppression model of our own.** Apple's voice processing (P0) and a cloud engine's
  own front end (P2) are the two we can have without shipping a model; a third is a later plan if
  P3's numbers say both are short.
- **Streaming the OpenAI engine.** Whole-utterance only; a streaming transcription session is a
  Realtime-mode concern.
- **The Realtime modes.** Their recogniser is the vendor's; none of P0–P2 applies, and the Type
  bar stays hidden there.

## Owner decisions owed

1. Countdown default for *Check before sending* — 3 s proposed.
2. Whether *Check before sending* is a per-conversation switch (proposed: a setting under
   Conversation, with the same name in the session card's quick actions) or a mode of its own.
3. Which cloud engine ships first — Deepgram proposed, because it is linked and counted today.
4. Whether the cloud recogniser is offered to every tier or only with Field Assist — proposed:
   every tier, since the key is the wearer's and the switch is theirs.
5. Whether the trade glossary ships inside the vault (the vault author's words) or inside the app
   (ours) — proposed: both, vault first, so a vendor's names win.

## Device pass owed

The P3 protocol, on the glasses with a running unit nearby, before any engine or the voice
processing becomes a default. Results go in the status line of this plan.
