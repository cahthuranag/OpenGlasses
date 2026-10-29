# Plan KA — Model Kinds Across Providers (one rule for what a listed model is for)

**Status:** 📝 Drafted 2026-10-29 — nothing built. Owner decision the same day: chat pickers
**label** non-chat models rather than hide them; PR 885 stays as it is (hiding Gemini's by name)
until P0 replaces it.
**Origin:** the 2026-10-29 support report on build 581. A speech-only Gemini model was chosen as the
chat assistant, so every turn was refused. PR 885 fixes it for Gemini by name. The owner asked for
one approach across every provider, because the same thing can happen elsewhere, and Plan
[JZ](JZ-gemini-cloud-voice.md)'s speech-model picker needs the opposite filter on the same lists.
**Related:** Plan [JZ](JZ-gemini-cloud-voice.md) (Gemini voice), Plan
[ID](ID-ecosystem-review-hardening-bundle.md) item 5 (OpenAI and xAI voices), PR 885 (the Gemini
chat-picker filter and model-form check).

---

## Why

Each provider's model list is shown in the chat picker as it comes, except in two places:

- xAI drops image, video, voice and embedding ids by name (`XAIOAuth.isChatModel`).
- Gemini drops speech, image and embedding ids by name (PR 885, `ModelFetcher.isGeminiChatModel`).

OpenAI, Groq, Mistral, Z.ai, Qwen, MiniMax, OpenRouter and custom servers are not filtered. An OpenAI
key's list carries speech (`tts-1`, `gpt-4o-mini-tts`), transcription (`whisper-1`,
`gpt-4o-transcribe`), realtime (`gpt-realtime*`), image (`gpt-image-*`), embedding and moderation
models. Any of them can be picked as the assistant, and every turn then fails the way the report's
did. Two hand-kept name lists also drift: each was written for one provider's naming.

## What the providers give us (docs checked 2026-10-29)

| Provider | Kind in the list itself | Non-chat kinds that appear | Speech (TTS) |
|---|---|---|---|
| OpenAI | none (`id`, `owned_by`, `shutdown_date`) | speech, transcription, realtime/audio, image, embedding, moderation | `/v1/audio/speech`; **`tts-1`, `tts-1-hd`, `gpt-4o-mini-tts` removed 2027-01-06**, replacement `gpt-realtime-2.1-mini` |
| Anthropic | feature flags only; chat-only list | none | none |
| Gemini | `supportedGenerationMethods` | speech (`*-tts`), live/native-audio, embedding, image, video, music | `generateContent` / interactions (Plan JZ) |
| Groq | none | transcription (`whisper-*`), speech (`canopylabs/orpheus-*`), guard models | OpenAI-shaped `/audio/speech`; English and Saudi Arabic only, wav, 200-character input |
| DeepSeek | `input_modalities` / `output_modalities` | none | none |
| Mistral | `capabilities` flags (`completion_chat`, `audio_speech`, `audio_transcription`, `ocr`, `moderation`, …) | transcription, speech, OCR, embedding, moderation | `/v1/audio/speech` (Voxtral), voices from `/v1/audio/voices`, base64 in JSON |
| Z.ai | list shape undocumented | transcription, OCR, image, video documented; presence in the list unconfirmed | none documented |
| Qwen | list shape undocumented | speech, transcription, realtime/omni, embedding, rerank, image, video | DashScope's own API, not OpenAI-shaped |
| MiniMax | list shape undocumented | speech (`speech-*`), music, image, video | `/v1/t2a_v2`, not OpenAI-shaped |
| xAI | modalities on `/v1/language-models`; `/v1/models` mixes in image/video | image, video, voice | `/v1/tts` (shipped) |
| OpenRouter | `architecture.output_modalities` (text, image, audio, speech, transcription, embeddings, rerank, video) | every kind, but the list defaults to text output | OpenAI-shaped `/api/v1/audio/speech`; speech models via `?output_modalities=speech` |

Four lists say what a model is for: Mistral, DeepSeek, OpenRouter, and xAI's language-model list.
Gemini's methods come close. For the rest, the id is all there is.

## Design

1. **One pure classifier.** `ModelKind` is one of `chat`, `speech`, `transcription`, `realtime`,
   `image`, `video`, `music`, `embedding`, `rerank`, `moderation`, `ocr` or `other`.
   `ModelKindClassifier.kind(provider:id:metadata:)` reads, in order:
   1. **The list's own field** where there is one: Mistral's `capabilities`, OpenRouter's and
      DeepSeek's `output_modalities`, Gemini's `supportedGenerationMethods`. Anthropic's list is
      chat by construction.
   2. **Shared id words** for the rest. An id is split on `-`, `.`, `_`, `/` and `:`, and whole
      words are matched, never substrings. That keeps `tts` from matching inside another word, and
      `speech` from a chat model's name. Examples: `tts`, `orpheus` → speech; `whisper`,
      `transcribe`, `asr` → transcription; `realtime`, `live`, `native-audio`, `audio-preview` →
      realtime; `image`, `imagen`, `dall-e`, `cogview`, `imagine` → image; `video`, `veo`, `sora`,
      `hailuo` → video; `lyria`, `music` → music; `embed`, `embedding` → embedding; `rerank`;
      `moderation`, `guard`, `safeguard` → moderation; `ocr`.
   3. **A short per-provider table** for families the shared words miss (MiniMax `speech-*`, Qwen
      `qwen3-tts-*`, `wan*`).
2. **Unknown means chat.** A custom server's or a new provider's id that matches nothing is shown
   as an ordinary chat model. The classifier only labels what it recognises as something else; a
   wrong label on the wearer's own model is worse than an odd model offered as chat.
3. **Every chat picker labels, never hides (owner decision, 2026-10-29).** For every provider,
   the chat picker shows chat models as today. Below them, non-chat models sit in a dimmed "Can't
   be your assistant" section, where they can't be selected. Each one carries a label naming where
   it can be used: live voice mode, speech output (a voice), transcription, images, embeddings,
   safety filters. Once Plan JZ's Gemini voice lands, the speech-output label points to the voice
   picker. The xAI and Gemini name lists (`XAIOAuth.isChatModel`, PR 885's
   `ModelFetcher.isGeminiChatModel`) become the classifier's rows, with their tests carried over.
   PR 885 hides Gemini's non-chat models until P0 replaces that with the label.
4. **Every voice picker reads it.** A cloud voice's model picker offers its provider's `.speech`
   models. Plan JZ's Gemini picker is the first. OpenAI's voice can do the same if it keeps a
   speech-endpoint model.
5. **A typed id gets the same warning.** The model form uses the classifier, so a speech or image
   id typed by hand gets the label's warning: what the model is for, and where it can be used.
   PR 885's Gemini check becomes the general rule. No plan letters appear in the wording.
6. **A saved model that can't answer is flagged.** A model already saved as the assistant whose id
   the classifier calls non-chat shows a warning in Settings, with the same label. That reaches a
   wearer who saved one before any filter existed, such as the report's saved `gemini-3.8-flash-tts`.
7. **Pure and fixture-tested.** Each provider gets a list fixture built from its documented
   shape, with invented ids where real ones aren't needed. Each family above gets its expected
   kind, plus one test that unknown ids stay chat.

## Phases

- **P0 — the classifier and labelled chat pickers (one PR, after PR 885 merges).** This is the
  labelling PR the owner asked for after PR 885. It is built from `main` by the session that owns PR
  885. It covers:
  - the classifier, the shared words and the per-provider rows;
  - every provider's chat picker with the "Can't be your assistant" section and its labels;
  - the typed-id warning and the saved-model warning in Settings;
  - folding in the xAI and Gemini name lists.

  **Cleanup:** PR 887's `GeminiThinkingStyle.none` marker list (tts, native-audio, embedding,
  imagen, veo, aqa ids get no `thinkingConfig`) comes from the classifier instead of being a second
  list. Full unit suite and Release build.
- **P1 — voice pickers.** Plan JZ's Gemini speech-model picker reads `.speech`, replacing its own
  filter; its URL-safety check on the id stays. The OpenAI voice's model follows from decision 3.
- **P2 — live lists.** Fetch the real list with a key for every provider, above all Z.ai, Qwen and
  MiniMax, whose list shapes are undocumented. Correct the rows, and record each provider's shape
  in this plan.

## Decisions

Taken (owner, 2026-10-29): chat pickers label non-chat models, don't hide them; a typed non-chat id
gets the same warning; a saved one that can't answer is flagged in Settings; PR 885 stays as it is
and the labelling is P0, a separate PR after it.

Open:

1. **Order against Plan JZ.** *Default: Plan JZ's code PR ships with its own Gemini speech filter*,
   and P1 switches it to the classifier once P0 is in. That way neither waits on the other.
   *Alternative:* JZ's code waits for P0.
2. **The OpenAI voice after 2027-01-06.** OpenAI removes every model its speech endpoint takes, and
   names a realtime model as the replacement. That is a different transport (a session, not a POST
   per sentence). *Options:* move the OpenAI voice to the realtime model; or retire it, saying so
   to anyone who chose it, and offer OpenRouter's or another provider's voice instead. This needs
   its own plan before the end of 2026.
3. **More voices.** Mistral (Voxtral, multilingual, a voice list), MiniMax, Qwen and OpenRouter (one
   key for several vendors' voices) all have speech. Groq's is English and Saudi Arabic only.
   *Default: none scheduled;* each would be its own plan in the shape of Plan JZ.
