# Plan JB — Voice by Description ("warmer, slower, a Scottish accent")

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built. **2026-10-19:** P3 (organisation
voice) added after the question "could an organisation set one voice across its phones?" — yes,
through the organisation profile; the shapes and the limit are in P3.
**Extends:** `TextToSpeechService` (engine chain `TTSEngineSelector`: ElevenLabs → Kokoro → system),
`ServicesSettingsView` (voice pickers), `Persona` (`Models/Persona.swift`).
**Related:** Plan [FY](FY-rename-to-avenkin.md) (how the name is pronounced on each tier — owed on
device), Plan [ID](ID-ecosystem-review-hardening-bundle.md) §5 (a second cloud voice tier and the
egress checklist any new voice endpoint must ship with), Plan [HQ](HQ-eu-ai-act-second-tranche.md)
(a synthetic voice is already disclosed on every artefact that leaves the phone), Plan
[EU](EU-remediation-roadmap.md) W04.2 (route registry), Plan [CT](CT-org-configuration-profiles.md)
(the organisation profile P3 extends: `ConfigProfile.aiModel` is the shape an organisation voice
copies, `OrgEnrolmentService.modelKey` the way its key is entered, `organizationAccentColor` the
set-and-locked precedent).

---

## Trigger

The assistant's voice is chosen from a list of ids. On the cloud tier that is a picker over the
wearer's account voices plus a monospaced "Voice ID" field; on the iOS tier a picker over installed
voices; on the on-device tier nothing at all. Nobody who is not already a customer of the voice
vendor knows what "21m00Tcm4TlvDq8ikWAM" sounds like, there is no way to hear a voice before
choosing it, and the natural request, "sound a bit warmer and slower", has no home. A wearer who
runs several personas cannot give them different voices.

## Outcome

- By voice: "Change your voice: warmer, slower, with a Scottish accent." The assistant answers in
  a candidate voice: "This is how I'd sound. Keep it, hear another, or go back?" — "Another." —
  (second candidate) — "Keep it." Done. "Go back to your old voice" reverts.
- In Settings: a **Describe a voice** field, Generate, three Play buttons, Keep. A short line under
  the current voice: "Warm, slower, Scottish — made 18 Oct".
- Every tier does something honest. Cloud: a voice generated from the description. iOS and
  on-device: the nearest installed voice, with rate and pitch adjusted from the description, and a
  spoken note of what could not be matched ("I don't have a Scottish voice installed, so I've
  picked a British one").
- A persona may carry its own voice; a persona without one uses the default.
- Never a clone of a real person. Description only.

## What exists today (verified 2026-10-18)

- `Services/TTS/TTSEngineSelector.swift`: `TTSEngine { elevenLabs, kokoro, system }`,
  `TTSEnginePreference` (`Config.ttsEnginePreference`), chain building; `.high` urgency promotes
  Kokoro. `TurnRecorder.noteSpeechEngine`.
- `TextToSpeechService.speakWithElevenLabs(text:apiKey:)`: `POST /v1/text-to-speech/<voiceId>`,
  `model_id: eleven_flash_v2_5`, `voice_settings` **hard-coded** (`stability 0.5, similarity_boost
  0.75, style 0.3`), no `speed`. `fetchElevenLabsVoices(apiKey:)`: `GET /v1/voices` decoding only
  `voice_id`, `name`, `category` (not `preview_url`, `labels`, `description`); **no cache**, the
  list lives in the settings view's `@State`. Both calls are inline on `URLSession.shared` — **there
  is no ElevenLabs client type.** `CloudVoiceRejection` classifies quota/refusal;
  `elevenLabsQuotaExhausted` is per session.
- `Config.elevenLabsVoiceId` (UserDefaults, default Rachel), `Config.iosTTSVoiceId` ("" = auto).
  The API key is in the Keychain (`Config.migratableStringSecretKeys`).
- System tier (`speakOnceWithiOS`): `rate = default × SpeechUrgency.rateMultiplier` (1.0/1.15/1.3);
  `pitchMultiplier = 1.0` and `volume = 1.0` hard-coded; voice from `TTSVoiceResolver.resolve` over
  `Locale.preferredLanguages`. `TTSVoiceResolver.Voice { identifier, language, quality, name }`.
- Kokoro: `KokoroSynthesizer.synthesizeWAV(_:speakerId: Int32 = 0, speed: Float = 1.0)` — the
  engine always passes the defaults; **no speaker catalogue, no Config key.** Bundle
  `kokoro-int8-multi-lang-v1_1` (English and Chinese lexicons).
- `Persona` has `name, wakePhrase, alternativeWakePhrases, modelId, presetId, enabled, icon,
  isBuiltIn, soulOverride, chattinessRaw, allowedTools, ownedTaskIds` — **no voice attribute.**
  `AppState.applyPersonaRouting` changes model and preset only.
- **No preview or sample playback anywhere.** Tones and the thinking pad are generated WAVs.
- Routes: `NetworkRoute.elevenLabsSpeechSynthesis` (`[.transcript, .credential]`) and
  `.elevenLabsVoiceCatalog` (`[.credential]`), class `.userConfiguredCloud`, owner
  `TextToSpeechService`, `blockedWhenLocalOnly`. `NetworkRouteRegistryTests` scans for `URLSession`
  owners; `PrivacyManifestReconciliationTests` pairs routes with the manifest;
  `MedicalEgressCanaryTests` asserts `api.elevenlabs.io` is never reached in Local Only.
- `SpokenSymbolExpander` → `SpeechPronunciation` ("Avenkin" → "Ah-Ven-Kin") runs on every
  utterance; `GatewayWire.GatewaySpokenReplyControl` strips a gateway's voice-control JSON line
  (`voice`, `speed`, `stability`, …) so it never reaches TTS — the only voice-attribute vocabulary
  parsed today.
- Tests: `TTSEngineSelectorTests` (14), `TTSVoiceResolverTests` (15), `CloudVoiceFallbackTests`
  (9), `SpokenSymbolExpanderTests` (31), `SynthesizerHealthTests`, `SpeechUrgencyTests`. No
  request-shape test for the ElevenLabs body; no settings-view test.

## Design

### Vocabulary (`VoiceTraitParser`, pure)

A description is free text. The parser extracts what the local tiers can act on and passes the
whole text to the cloud tier untouched:

- `rate`: slower/slowly/unhurried → 0.85; faster/quick/brisk → 1.15; "much" scales ±0.1 more;
  clamped 0.75–1.25. Stacks with urgency (`rate × urgency`), the combined value clamped.
- `pitch`: deeper/lower → 0.9; higher/lighter → 1.1; clamped 0.8–1.2 (system tier only).
- `gender hint`: male/man/masculine, female/woman/feminine, neutral; a hint, never a filter that
  leaves zero candidates.
- `locale hints`: a table of demonyms and places → BCP-47 prefixes (Scottish, British, English,
  Irish, Welsh → `en-GB` (Scottish/Welsh noted as *approximate*), Australian → `en-AU`, Kiwi/New
  Zealand → `en-NZ`, American → `en-US`, Indian → `en-IN`, South African → `en-ZA`, Canadian →
  `en-CA`, plus the non-English languages the app ships UI for). Unknown words are kept for the
  cloud tier and reported as unmatched locally.
- `warmth`/`calm`/`energetic`/`formal`: kept as adjectives for the cloud description; locally they
  nudge rate (calm → −0.05, energetic → +0.05) and nothing else.
- Output `VoiceTraits { rate, pitch, genderHint, localePrefixes, adjectives, unmatched }`,
  deterministic, with a `summary` line for the settings screen ("warm, slower, Scottish").

### Candidates per tier

- **Cloud (`ElevenLabsClient.designPreviews(description:sampleText:)`)**: the vendor's
  text-to-voice design call returns a small set of generated previews (audio + a temporary
  generated-voice id); keeping one calls the vendor's save-from-preview call and yields a
  permanent voice id in the wearer's account. **The exact endpoints, limits and credit cost are
  re-read from the vendor's API reference at P1 and recorded in this section** (the shape is known
  to exist; the field names are not pinned here on purpose). Request bodies carry the description
  and the fixed sample text only. The previews are played from memory and discarded on revert; the
  saved voice's id goes into the existing `Config.elevenLabsVoiceId` (or the persona).
- **System (`LocalVoiceMatcher`, pure)**: rank `TTSVoiceResolver.Voice` candidates by locale
  prefix match (exact language-region 3, language 1), gender hint from the voice's name against a
  small known-name table (iOS voices have no gender metadata; unknown = 0), quality (premium 2,
  enhanced 1), with the current voice as a tie-break. Returns up to three; `rate`/`pitch` from the
  traits are applied at playback. Zero candidates → the current voice with the adjustments and a
  spoken note of the unmatched hints.
- **On-device Kokoro**: a `KokoroSpeakerCatalog` (static table: speaker index → name, gender,
  language, from the model card; the count is asserted against `voices.bin` at load so a bundle
  change fails loudly) ranked by the same matcher; `speakerId` and `speed` are finally passed to
  `synthesizeWAV`. Pitch is not available on this tier and is reported as unmatched.

### Session (`VoiceDesignSession`, pure state machine)

`idle → generating → previewing(index, of: n) → kept | reverted`, with `next`, `keep`, `revert`,
`fail(reason)`. The previous `VoiceSelection` is held for the life of the session and for 24 h
after `kept` so "go back to your old voice" works the next morning. Every preview is spoken through
the normal chain **pinned to the candidate's tier** (a cloud preview never silently falls back to
the system voice — that would be the wrong voice being auditioned); a failure says so and offers a
local candidate instead.

`VoicePreviewScript` (pure): one fixed sentence per language that exercises the sanitiser and the
name: "Hi, I'm Avenkin. It's twenty to eight and eighteen degrees outside." (the name comes from
`AssistantIdentity`, so a renamed assistant previews under its own name — and the FY owed
pronunciation check becomes something the wearer hears before they keep a voice).

### Selection model

`VoiceSelection { engine: TTSEngine, identifier: String (voice id / voice identifier / speaker index),
traits: VoiceTraits?, description: String?, createdAt: Date }`, stored as the default
(`Config.voiceSelection`, replacing the two separate id keys through a one-way migration that
keeps today's values) and optionally per persona (`Persona.voice: VoiceSelection?`, `Codable`,
default nil, so stored personas decode). `TextToSpeechService` resolves **active persona voice →
default** at speak time; `applyPersonaRouting` no longer needs to know. The realtime session cue
synthesiser (`RealtimeSessionManager.localCueSynth`) is unchanged.

### Rate and pitch as settings

`VoiceTraits.rate/pitch` become the first user-facing speed and pitch controls: two sliders in the
Voice section (default 1.0) that the parser also writes. The cloud body gains `speed` where the
model accepts it; the system tier multiplies; Kokoro passes `speed`. Urgency keeps stacking.

### Consent, cost and egress

- Generating previews and saving a voice **spend the wearer's own vendor credits and may use a
  custom-voice slot** on their plan. The first generation in a session says so once ("This uses
  credits on your voice account"); keeping asks "Keep this voice? It'll be saved to your account."
  through the ordinary confirmation (not high-impact; it is reversible by deleting the voice in the
  vendor's dashboard, which the settings line links to).
- New routes `elevenLabsVoiceDesign` and `elevenLabsVoiceSave` (`[.transcript, .credential]`: the
  description is wearer-written text), class `.userConfiguredCloud`, `blockedWhenLocalOnly`, owner
  `ElevenLabsClient`. **`ElevenLabsClient` is extracted first** and the two existing calls move
  into it (registry owner updated), so the service stops calling `URLSession.shared` inline. Same
  PR: `MedicalEgressGuard` cases, `EndpointPolicy`, `PrivacyInfo.xcprivacy` comment,
  `privacy.html` and `ProcessingFacts` copy — the pairing `TelemetryOptOutGuardTests` and
  `PrivacyManifestReconciliationTests` enforce.
- Local Only / HIPAA: the cloud candidates are refused with the standard message; the local
  matcher still works, so "slower and deeper" is honoured everywhere.
- Nothing about the wearer (name, memory, transcripts) is sent; the description and the fixed
  sample sentence are the whole payload. `PrivacyLog.tts` gains a `voiceDesign` event with
  character counts only.
- Cloning is out: the tool has no audio-sample path, the settings have no upload, and the vendor's
  instant-clone endpoints are not in the client.

### Tool

`voice_design` (native, not Agent-Mode gated — it is the wearer changing a setting by voice):
`describe(text)`, `next`, `keep`, `revert`, `status` ("You're using a warm, slower Scottish voice I
made on the 18th"). Refused mid-reply or during a live session (the chain is busy); available in
Direct mode and from the Settings sheet. Copy never names a plan letter.

## Phases (one PR each)

**P0 — Pure core.** `VoiceTraits` + `VoiceTraitParser`, `LocalVoiceMatcher`, `KokoroSpeakerCatalog`
(table + count assertion), `VoiceSelection` + migration, `VoiceDesignSession`, `VoicePreviewScript`,
`ElevenLabsClient` request/response types decoded from fixtures (synthesis, catalogue, design,
save), `ElevenLabsClient` extraction with an injected transport. Tests: `VoiceTraitParserTests`
(table: "warmer, slower, Scottish" → rate 0.85, en-GB approximate, adjectives [warm], unmatched
[]; "much faster, deeper, Australian woman"; "like a pirate" → unmatched, cloud-only; empty),
`LocalVoiceMatcherTests` (region beats language, name-gender table, zero-candidate fallback keeps
the current voice), `VoiceDesignSessionTests` (next wraps, keep stores, revert restores, 24 h undo,
failure offers local), `VoiceSelectionMigrationTests` (today's two keys land unchanged),
`ElevenLabsClientTests` (exact body for synthesis **including today's hard-coded settings**, so the
extraction is proven byte-for-byte; `speed` present only when set), `NetworkRouteRegistryTests`
and `PrivacyManifestReconciliationTests` updated for the new owner and routes.

**P1 — Cloud design, tool, settings.** Design and save calls (after re-reading the vendor
reference), `voice_design` registered, previews pinned to tier, credit notice and keep
confirmation, Describe-a-voice UI with three Play buttons, speed and pitch sliders, system-tier
rate/pitch applied, Kokoro `speakerId`/`speed` passed through. Tests: `VoiceDesignFlowTests` (fake
client: generate → preview 2 → keep writes the selection; quota error → local candidate offered;
Local Only → cloud refused, local still works), `TextToSpeechVoiceSelectionTests` (persona voice
wins; default otherwise).

**P2 — Per-persona voice and device pass (owed).** `Persona.voice` in `PersonasView`, the
preview sentence under each persona; device: three descriptions on each tier, the pronunciation of
the name on a generated voice, the time from "describe" to the first preview on a phone, and the
vendor dashboard showing exactly one saved voice after keep.

**P3 — Organisation voice.** An organisation that enrols its phones can set the voice every one of
them speaks in, the way it already sets the accent colour and the AI model. The goal is one voice
across the crew; the limit is that a voice can only be pinned to a tier the phone can play, so the
profile names a tier and an identifier, never a voice file.

- **Shape.** A `voice` block on `ConfigProfile`, beside `aiModel`, not a `SettingKey`: `{engine,
  identifier, rate?, pitch?, description?, fallback?}`, decoded without failing and resolved by a
  pure `OrgVoice.resolve` into a `VoiceSelection` — a malformed or unknown engine is a named drop
  that leaves the phone's voice alone, like a bad model entry. `fallback` is a second `{engine,
  identifier}` for when the first tier is unavailable; absent means the normal chain. The block is
  **set and locked** (the `organizationAccentColor` precedent): the Voice section shows the
  selection read-only with "Set by <organisation>", the sliders are disabled, `voice_design` is
  refused with "your organisation sets the voice on this phone", and the organisation voice wins
  over a persona voice (P2) for as long as the profile is in force. Leaving the organisation
  (`OrgDeparture`) restores the wearer's own selection, which is kept, not overwritten.
- **Three shapes, in order of what they cost the organisation.**
  1. *An Apple voice* — `engine: system`, the `AVSpeechSynthesisVoice` identifier, optional rate
     and pitch. Free, offline, backgrounded, identical on every phone that has the voice
     installed. If it is not installed, enrolment says so and points to iOS Settings ›
     Accessibility › Spoken Content › Voices; until then `LocalVoiceMatcher` plays the nearest
     installed voice for the same language and the enrolment summary lists the voice as owed.
  2. *A Kokoro speaker* — `engine: kokoro`, a speaker index from `KokoroSpeakerCatalog`, optional
     rate. Free and offline; the model download is offered at enrolment (Wi-Fi) and the Apple
     fallback speaks until it lands.
  3. *A voice in the organisation's own cloud account* — `engine: elevenLabs`, a voice id, optional
     rate and the description it was made from (for the settings line only). The organisation
     designs or clones the voice in its own account; a voice it first made elsewhere and cloned
     into that account is its affair and is synthetic, so the no-real-person rule holds, and the
     app itself still never clones. The account key never travels in the profile — it is entered on
     the phone at enrolment through the same step as the model key (`OrgEnrolmentService.modelKey`
     gains a `voiceKey` case), stored in the Keychain, and `fallback` says which local voice speaks
     when the cloud is refused, in Local Only, or offline. The key's provider entry and routes are
     the P1 ones; nothing new leaves the phone.
- **What it cannot do.** The phone's own tiers have fixed speakers, so an organisation wanting its
  *own* voice has the cloud shape only, and offline moments on that shape speak the pinned
  fallback — a different voice, said once ("the organisation's voice needs a connection; using the
  built-in voice until then"). A self-hosted voice server on the organisation's own network, which
  would give a designed voice with no vendor and no egress, is a separate later plan (a fourth
  engine in `TTSEngineSelector`, a wire contract to pin, a commercially licensed model to choose);
  this phase leaves `VoiceSelection.engine` open for it.
- **Tests.** `OrgVoiceResolveTests` (the three shapes resolve; unknown engine, missing identifier
  and an HTTPS-less field are named drops; a missing Apple voice yields the nearest installed voice
  and an owed line; `fallback` resolves independently), `ProfileApplierTests` (voice applied and
  locked, sliders and tool refused, persona voice overridden, departure restores the wearer's
  selection byte-for-byte), `SettingsVisibilityPolicyTests` (Voice rows read-only under a profile
  with a voice, untouched without one), and the existing secret-disjointness test extended so a
  profile cannot carry a voice key. Device pass (owed): a crew link with each shape on two phones,
  the Apple voice not yet installed on one of them, and the cloud shape with the key refused.

## Risks

- **Vendor drift.** The design endpoints are younger than the synthesis one and have changed
  shape before; the client isolates them and the fixtures pin what we send.
- **Credits and slots.** A wearer on a free plan can hit a slot limit on the first keep; the
  refusal must name it ("your voice account has no free custom-voice slot"), not fall back silently.
- **Approximate accents.** iOS has no Scottish voice; saying "I've picked a British one" is the
  honest version of the feature on that tier, and the plan prefers that to pretending.
- **Audition in the wrong tier.** Pinning previews to their tier is what makes a kept voice the
  voice that was heard.

## Decisions for Greig

1. **Tool by voice in P1** (recommended: that is the glasses-first value), or settings-only first?
2. **Per-persona voice** in scope (P2) or a later plan?
3. **Speed and pitch sliders** exposed as settings (recommended), or traits-only without UI?
4. **Default voice**: stay on the current cloud default, or ship a designed default voice for new
   installs once the vendor path is proven?
5. **Kokoro speaker table**: maintain the static catalogue (recommended, with the count
   assertion) or expose a bare "speaker 0–N" picker?
6. **Organisation voice precedence** (P3): the organisation voice wins over a persona voice
   (recommended — one voice across the crew is the point), or personas keep theirs?
7. **Which shape to recommend to an organisation first**: an Apple voice (recommended — free,
   offline, identical on every phone, nothing to enrol) until it asks for its own voice, which is
   the cloud shape; the self-hosted server stays a later plan until a tester asks for speech that
   never leaves their network.

## Out of scope

Voice cloning from audio, emotion or sentiment-driven delivery (removed on purpose, Plan HR),
changing the wake phrase, the realtime providers' own `voice` fields, the gateway's spoken-reply
control line, any voice for the watch or CarPlay beyond what the phone already speaks there, a
self-hosted voice server (see P3), and any voice file or sample carried in an organisation profile.
