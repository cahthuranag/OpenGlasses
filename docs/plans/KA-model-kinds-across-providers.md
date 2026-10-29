# Plan KA — Model Kinds Across Providers (one rule for what a listed model is for)

**Status:** 📝 Drafted 2026-10-29 — nothing built.
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
2. **Unknown means chat, never hidden.** A custom server's or a new provider's id that matches
   nothing stays in the chat picker. The classifier only removes what it recognises as something
   else. A wrong removal hides the wearer's own model, which is worse than offering an odd one.
3. **Every chat picker reads it.** `ModelFetcher` keeps `.chat` for every provider. The xAI and
   Gemini name lists become the classifier's rows, with their tests carried over.
4. **Every voice picker reads it.** A cloud voice's model picker offers its provider's `.speech`
   models. Plan JZ's Gemini picker is the first. OpenAI's voice can do the same if it keeps a
   speech-endpoint model.
5. **A typed id is checked the same way.** The model form uses the classifier, so a speech or
   image id typed by hand is refused as the assistant with the reason ("this is a speech model;
   it can be your voice in Settings › Connections › Services & Integrations"). PR 885's Gemini check
   becomes the general rule. No plan letters appear in the wording.
6. **Pure and fixture-tested.** Each provider gets a list fixture built from its documented
   shape, with invented ids where real ones aren't needed. Each family above gets its expected
   kind, plus one test that unknown ids stay chat.

## Phases

- **P0 — the classifier and the chat pickers (one PR, after PR 885 merges).** The classifier, the
  shared words, the per-provider rows, and `ModelFetcher` filtering every provider. The xAI and
  Gemini filters fold in, and the model form check is generalised. Full unit suite and Release
  build.
- **P1 — voice pickers.** Plan JZ's Gemini speech-model picker reads `.speech`, replacing its own
  filter; its URL-safety check on the id stays. The OpenAI voice's model follows from decision 3.
- **P2 — live lists.** Fetch the real list with a key for every provider, above all Z.ai, Qwen and
  MiniMax, whose list shapes are undocumented. Correct the rows, and record each provider's shape
  in this plan.

## Decisions for the owner

1. **Order.** *Default: KA P0 lands before Plan JZ's code PR*, so the Gemini speech picker uses the
   shared classifier from the start, and KA P0 waits for PR 885. *Alternative:* JZ P0 ships now
   with its own Gemini filter, and KA P1 replaces it.
2. **A typed non-chat id.** *Default: refused as the assistant, with the reason and where it can be
   used.* *Alternative:* allowed with a warning, since a custom server's naming may be its own.
3. **The OpenAI voice after 2027-01-06.** OpenAI removes every model its speech endpoint takes, and
   names a realtime model as the replacement. That is a different transport (a session, not a POST
   per sentence). *Options:* move the OpenAI voice to the realtime model; or retire it, saying so
   to anyone who chose it, and offer OpenRouter's or another provider's voice instead. This needs
   its own plan before the end of 2026.
4. **More voices.** Mistral (Voxtral, multilingual, a voice list), MiniMax, Qwen and OpenRouter (one
   key for several vendors' voices) all have speech. Groq's is English and Saudi Arabic only.
   *Default: none scheduled;* each would be its own plan in the shape of Plan JZ.
