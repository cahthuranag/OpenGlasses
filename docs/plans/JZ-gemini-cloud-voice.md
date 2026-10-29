# Plan JZ — Gemini as a Cloud Voice (spoken replies through the Gemini key)

**Status:** 📝 Drafted 2026-10-29 — nothing built. Owner decisions 1–3 taken the same day (below); 4 keeps its default.
**Origin:** the 2026-10-29 support report on build 581. A tester had picked `gemini-3.8-flash-tts`,
a speech-only Gemini model, as their chat assistant, so every turn was refused. The model-setup fix
(PR 885) keeps such models away from the chat picker. That leaves them with no use anywhere in the
app: the voice setting offers ElevenLabs, OpenAI (fixed `gpt-4o-mini-tts`), xAI, Kokoro and the iOS
voice, and the wearer chooses an engine and a voice, never a speech model. That tester's phone is
in Russian. Gemini's speech models read 100+ languages and detect the language themselves, so a
Gemini voice suits wearers who don't speak English, using a key many of them already have.
**Related:** Plan [ID](ID-ecosystem-review-hardening-bundle.md) item 5 (OpenAI and xAI voices, PR
814; this plan follows it step for step), Plan [HZ](HZ-direct-mode-sentence-streamed-speech.md) (streamed replies
synthesise sentence by sentence), Plan [AI](provider-auth-and-fallbacks.md) (Vertex sign-in),
`.claude/rules/dat-conventions.md` (telemetry posture: a new egress is disclosed in the same PR).

---

## Why

- A Gemini key is the one most wearers outside the English-speaking markets bring, often on its
  own. With it they get chat today, but replies are spoken by Kokoro (English-first) or the iOS
  voice, unless they also pay for ElevenLabs, OpenAI or xAI.
- The speech models PR 885 keeps out of the chat picker then have a real place to go. Plan
  [KA](KA-model-kinds-across-providers.md) P0 (owner decision 2026-10-29) shows them in the chat
  picker as "Can't be your assistant", labelled as speech output; that label points to this voice.

## The wire (checked against Google's docs, 2026-10-29)

Google's speech-generation guide now leads with the newer Interactions API
(`POST /v1beta/interactions`). The `generateContent` reference still carries the same feature,
and the guide names it for the output-format switch (`AUDIO_L16` "in generateContent"). This plan
uses `generateContent`, which the Gemini chat path already speaks:

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
x-goog-api-key: <key>          ← a header, never ?key= in the URL
Content-Type: application/json

{ "contents": [{ "role": "user", "parts": [{ "text": "<reply text>" }] }],
  "generationConfig": {
    "responseModalities": ["AUDIO"],
    "speechConfig": { "voiceConfig": { "prebuiltVoiceConfig": { "voiceName": "Kore" } } } } }
```

- **Answer:** `candidates[0].content.parts[].inlineData` = `{ mimeType, data }`, `data` base64.
- **Format:** both formats occur. The guide says the 3.8 models return a complete WAV (RIFF header,
  24 kHz, mono, 16-bit signed little-endian) for a unary request, and headerless `audio/l16` when
  streamed or asked for. The earlier preview models return headerless PCM labelled like
  `audio/L16;codec=pcm;rate=24000`. The player accepts both: a RIFF body plays as it is, and L16/PCM
  is wrapped in a WAV header at the rate the MIME type names (24 kHz if it names none). Anything
  else is a failed synthesis, never a guess. `AVAudioPlayer` then plays it the way it plays Kokoro's
  WAV.
- **Text is a verbatim transcript** for the 3.8 models: reply text is read, not obeyed, so a reply
  that says "say it cheerfully" is not acted on. Style (`speech_metadata.style`) and inline vocal
  tags are not used.
- **Models (2026-10-29):** `gemini-3.8-flash-tts` and `gemini-3.8-flash-lite-tts` (current, same
  schema; 130+ and 100+ languages); `gemini-3.1-flash-tts-preview` and `gemini-2.5-pro-preview-tts`
  (older previews).
- **Voices:** 30 prebuilt names (Zephyr, Puck, Charon, Kore, Fenrir, Leda, Orus, Aoede, Callirrhoe,
  Autonoe, Enceladus, Iapetus, Umbriel, Algieba, Despina, Erinome, Algenib, Rasalgethi, Laomedeia,
  Achernar, Alnilam, Schedar, Gacrux, Pulcherrima, Achird, Zubenelgenubi, Vindemiatrix, Sadachbia,
  Sadaltager, Sulafat). The guide also describes a larger voice library behind `GET /v1beta/voices`,
  plus designed and replicated voices. Replicated voices are out of scope (see Privacy).
- **Not documented:** an input-length limit for the speech models, and speech pricing or free-tier
  limits (those are on Google's separate billing and rate-limit pages, which change). The plan
  quotes no figures from them.

## Design

The OpenAI and xAI voices set the pattern, and every rule they follow applies here:

1. **One engine, one route.** `TTSEngine.gemini`, `TTSEnginePreference.gemini`,
   `NetworkRoute.geminiSpeechSynthesis` (the reply text and the key, owned by
   `TextToSpeechService`). The medical local-only rule blocks it as it blocks the other speech
   routes, both in the chain and again where the request is built.
2. **The key comes from the saved Gemini model.** `CloudVoiceCredentials.geminiKey(savedModels:)`
   returns the key of the first saved `.gemini` model whose base URL is Google's own
   (`generativelanguage.googleapis.com`, or empty for the default). A key saved on a Gemini model
   pointed at another server belongs to that server and is never sent to Google. Vertex sign-in
   (`.geminiVertex`) does not count: it uses a different host and a bearer token (see later work).
3. **Fixed address, key in a header.** `CloudVoiceRequests.geminiSpeech(text:apiKey:voice:)` builds
   the request as a value: Google's fixed URL with the model in the path, the key only in
   `x-goog-api-key`. The Gemini chat and model-list calls put `?key=` in the URL; the voice does
   not, so the key cannot reach a logged URL.
4. **A chosen cloud voice falls back to the phone, never to another paid cloud.** It works as the
   three existing voices do: the chain is Gemini → Kokoro → iOS voice. On Auto it comes last of
   the cloud voices (decision 3).
5. **Rejections.** A 401/403 is "refused" under the shared rule. Gemini also refuses a bad key with
   a 400 whose body names `API_KEY_INVALID`, so that marker counts as refused. A 429
   (`RESOURCE_EXHAUSTED`) is not latched in P0, because Google uses it both for a per-minute rate
   limit and for a spent daily quota. Telling the two apart from the body is a P1 measurement. Until
   then a 429 falls through for that utterance, and the streamed-reply schedule's two-failure
   demotion keeps a reply from stuttering.
6. **Audio as a value.** `GeminiSpeechAudio.playableAudio(from:)` decodes the JSON, picks the first
   audio part, and returns WAV `Data` or throws. It is pure and tested on both shapes, on a 200 with
   no audio part (a candidate finished for safety or another reason), and on bad base64.
7. **Both speaking paths.** The whole-reply chain and the streamed-reply queue both call one
   `fetchGeminiAudio(text:apiKey:)`, as they call `fetchXAIAudio`.
8. **Disclosed in the same PR.** That means the `PrivacyInfo.xcprivacy` comment, `privacy.html`
   (the cloud-voice row and the Google entry), the in-app processing summary (`vendorName`
   "Gemini"), the system prompt's settings path, and the voice-engine footer.

## Owner decisions (2026-10-29)

1. **Speech model: a picker, filled from the key's own model list.** A fixed default
   (`gemini-3.8-flash-lite-tts`) is used until the wearer picks one. The list is Google's
   `GET /v1beta/models`, asked by the voice itself with the key in `x-goog-api-key`, on its own
   route (`geminiSpeechModelCatalog`). The picker shows **speech models only**. The same list
   carries chat, image (`…-image`, Imagen), embedding and Live (`native-audio`) models, so an entry
   is offered only when its id names `tts` as a word of its own and it answers `generateContent`. A
   saved id is also checked before it goes into the request's URL path (letters, digits, `.`, `-`,
   `_`, and it must name `tts`), and anything else reads as the default. This filter is the voice's own
   until Plan KA's shared classifier lands; KA P1 then switches the picker to it, and the URL-safety
   check stays. This is where the speech
   models PR 885 keeps out of the chat picker can be chosen.
2. **Voices: the 30 prebuilt names, default `Kore`**, names only. The descriptions wait for a
   catalog pass. The larger voice library stays later work.
3. **Auto uses it, last of the cloud voices**: ElevenLabs, then OpenAI, then xAI, then Gemini, each
   only when its key is saved. A Gemini key saved with a Gemini model turns the Gemini voice on.
   With no Gemini key it is never offered or tried. On Auto, a wearer with only a Gemini key now
   hears the Gemini voice, paid from that key's quota, so the Auto footer and the privacy page name
   it.
4. **Cost wording:** no answer yet; the default stands. The footer reads "Spoken replies use that
   key's quota, separately from chat", with no prices or free-tier figures.

## Phases

### P0 — the engine, headless-tested (one PR)

- `CloudVoiceRequests`: `geminiSpeechURL(model:)`, `defaultGeminiSpeechModel`, `geminiVoices`,
  `defaultGeminiVoice`, `geminiSpeech(text:apiKey:model:voice:)`, `isGeminiSpeechModelID(_:)`, and
  the speech-model list (`geminiSpeechModelCatalog(apiKey:)`, `parseGeminiSpeechModels(_:)`).
- `GeminiSpeechAudio`: the answer parser and the L16 → WAV wrap (rate from the MIME type).
- `CloudVoiceCredentials.geminiKey(savedModels:)`.
- `TTSEngine.gemini` (vendor "Gemini", route `.geminiSpeechSynthesis`), `TTSEnginePreference.gemini`
  (display name, detail), `TTSEngineSelector.Availability.geminiReady`, and the chain placement by
  decision 3: `cloudVoices` lists all four cloud voices, in the order Auto tries them.
- `NetworkRoute.geminiSpeechSynthesis`: purpose, data classes (reply text + credential, like the
  other speech routes), vendor endpoint class, blocked when local-only, owner `TextToSpeechService`.
  `NetworkRoute.geminiSpeechModelCatalog` (credential only) for the picker's list.
- `CloudVoiceRejection`: `api_key_invalid` counts as refused.
- `Config.geminiTTSVoice` / `geminiTTSModel` and their setters (an unknown voice or an unsafe
  model id falls back to the default).
- `TextToSpeechService`: `speakWithGemini` / `fetchGeminiAudio` (medical check, empty-key refusal,
  request, `cloudVoiceAudio`, parse), wired into the whole-reply chain and the streamed queue.
  `ProcessingFacts` availability.
- Settings › Connections › Services & Integrations: the engine option, a "Gemini Voice" section
  shown when a Gemini key is saved (the speech-model picker, loaded from the key's list, and the
  voice picker), and the no-key footer.
- Disclosure (Design 8).
- **Tests:** the request (URL, method, header key, no key in the URL, body shape, an unknown voice
  falls back, the model is in the path); the parser (RIFF passthrough, L16 wrapped with a correct
  44-byte header at 24 kHz and at a named rate, no audio part, bad base64, error JSON); the key
  (Google host, empty base URL, a foreign base URL ignored, Vertex ignored, the first with a key
  wins); the speech-model filter (only `tts` models that answer `generateContent`, never an image,
  embedding, Live or chat model, never an id that is unsafe in a path) and the list request (key
  in a header); the selector (Gemini chain, Auto order pinned by decision 3, high urgency promotes Kokoro,
  every cloud voice's route is blocked in local-only); the medical canary at `fetchGeminiAudio`;
  the rejection classes; the processing summary names Gemini. Full unit suite and a Release
  build before the PR.

### P1 — the live edge (device)

- **Listening check on the phone and the glasses**, in English and in one language other than
  English (Russian, for the report that prompted this). Check that it speaks, which format came
  back (WAV or L16), the time to first audio for a whole reply and for the first streamed sentence
  against the OpenAI voice, and that barge-in and cancel stop it.
- **429 bodies.** Capture a per-minute and a daily-quota refusal from a free-tier key. If the daily
  one can be told apart (Google's quota id names the period), add that marker so a spent day
  latches the voice off for the session with the out-of-credit notice. Otherwise leave it as it is.
- **Model access.** Confirm the default model and the picker's list on a free-tier key and a paid
  one. If a chosen model is refused for a key, decide between falling back to the default and
  refusing.
- **Locked phone / background.** Confirm the request and playback work with the phone locked
  during an always-on session, as the other cloud voices do.

### Later (only if wanted, not scheduled)

- The voice library (`GET /v1beta/voices`, filtered to the phone's language) as another route.
- Gemini's own streaming (`audio/l16` chunks) instead of a request per sentence.
- The Vertex sign-in as a credential (`aiplatform` host, bearer token).

## Privacy

- The data is the same as the other cloud voices send: the reply text and the wearer's own key,
  sent to a vendor the wearer already sends their chat to. It is still a new purpose for that
  destination, so it is disclosed as a voice in its own right.
- No replicated or designed voices. Replicating a voice needs reference audio of a person, and
  that is a different consent question this plan doesn't open.
- The key is never in a URL, so it cannot reach a log line, a support report or the network
  monitor's request list.
- The reply text is never logged, only its engine, length and status, as for every voice.
