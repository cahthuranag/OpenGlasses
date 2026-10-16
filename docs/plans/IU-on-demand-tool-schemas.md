# Plan IU — Tool Definitions on Demand

**Status:** ✅ Shipped 2026-10-17 — the pure decision, the core set, `lookup_tools`, the safety net,
the setting with its organisation pin, the prompt block and the log line, built and tested headless
in one PR, with the app guide's new listening line beside it. Device-pending: an on-device model
turn (the log line only, since that path is unchanged), and a ChatGPT turn under **Always** that
needs a tool outside the core set. See *As built* below.
**Origin:** A tester's support report (build 497). Every ChatGPT-subscription turn estimated
`tools 76575` — the request-budget weight of the tools block (`RequestContextBudget.estimate`, an
upper bound of about one token per byte), roughly 121 tool schemas sent in full on every round trip.
**Related:** Plan [GB](GB-field-test-round-3.md) P5 (declarations sorted for the prompt cache, per-tool
descriptions dropped from the prompt when schemas ride along), Plan [GD](GD-field-test-round-3-closeout.md)3
(the field-mode tool profile), Plan [BF](BF-llm-turn-hygiene.md) (Anthropic caches the tools block),
Plan [BG](BG-spine-refactor.md) (the shared tool loop and the generated tool list), Plan
[CT](CT-org-configuration-profiles.md) (organisation profiles).
One PR. Pure core first; the provider edge is thin.

## The gap

Every Direct-mode request declares the full JSON schema of every enabled tool:
`ToolDeclarations.openAITools` / `geminiRESTTools` / `anthropicTools` build them from every
declarable native tool (filtered only by enabled, HIPAA and the Field Assist job profile) plus every
offered MCP tool and OpenClaw's `execute`. On a model with a large window that costs little — the
provider caches it. On a small window it is most of the room the conversation has: the headless
registry alone measures tens of kilobytes, and a real install with the camera, memory, Field Assist
and MCP tools reaches the tester's ~76 KB.

The prompt already carries a compact list of every tool's name (`Built-in tools: …`), generated
from the registry, so the model knows what exists even when it does not have every definition.

## The rule (the owner's decisions)

1. **On-demand schemas.** The prompt keeps the compact list of available tools. The request
   declares in full only a **core** set, every tool already used or looked up in this conversation,
   and a new **`lookup_tools`** tool that returns the full definitions of named tools. Once looked
   up, a tool is declared from the next model round onward.
2. **A setting with three values** — **Automatic** (default, recommended), **Always**, **Never** —
   in Settings › AI & Personality, under *Tools*. An organisation profile can pin it. Hidden in
   Simple Mode (the whole AI & Personality screen is). A turn in flight keeps the mode it began with.
3. **Automatic is a context rule, not a model-quality rule:** on demand only when the full declared
   set would take more than a tenth of the model's context window. Large cloud windows keep today's
   full list; on-device and small-window models get on-demand. **Always** is on-demand for every
   model; **Never** is the full list always — today's behaviour.
4. **Logged per turn, count-only**: which exposure, why, how many schemas were declared and how many
   were available.

## Design

### The pure core — `ToolExposurePolicy` (`Services/LLM/ToolExposurePolicy.swift`)

`decide(mode:available:fullSetBytes:contextWindow:core:remembered:) -> ToolExposureDecision`

| Mode | Window | Exposure | Reason |
|---|---|---|---|
| Never | any | `full` | `setting` |
| Always | any | `core` | `setting` |
| Automatic | known, full set > ⅒ of it | `core` | `contextShare` |
| Automatic | known, full set ≤ ⅒ of it | `full` | `contextShare` |
| Automatic | unknown | `full` | `default` |

- The full set's size is the serialized bytes of every available declaration, at the house estimate
  of four characters a token (`HistoryHygiene`, `HandoffTranscriptBridge`, `MemoryContextSnapshot`
  use the same). "More than a tenth" is strict: exactly a tenth keeps the full list.
- `declared` is every available tool on `full`; on `core` it is (core ∪ remembered) ∩ available.
- `roundDeclared(_:promoted:)` is nil on `full` (no filter) and, on `core`, `declared` plus
  everything promoted since the turn began, within what is available.
- `isUndeclaredCall(_:declaredThisRound:available:)` — the safety net's test: an available tool the
  round did not declare. A name outside `available` (invented, disabled) is the router's to refuse,
  as before.

### Context windows — `ModelContextWindow`

Each provider's window, from what the app already knew, plus a small family table where it knew
nothing:

| Provider | Source | Window |
|---|---|---|
| ChatGPT subscription | `RequestContextBudget.resolve` with the account catalog (`ChatGPTContextCatalog`) | 272k (catalog default), or the account's own |
| OpenAI API (`api.openai.com`) | `RequestContextBudget.openAIAPIContext` | 128k (gpt-4o) to 1.05M (gpt-5.4+); unknown model 128k |
| OpenAI-compatible on another host (Azure) | — | unknown (per-deployment) |
| Anthropic `claude-*` | family table | 200k |
| Gemini / Vertex `gemini-*` | family table | ~1M (`gemini-1.0` 32k) |
| DeepSeek `deepseek-*`, Mistral, Groq | family table | 128k / 128k / 131k |
| On-device MLX | `LocalModelBudget.contextWindow` | 4k–32k |
| Qwen, MiniMax, xAI, Z.ai, OpenRouter, custom | — | unknown → full list (`default`) |

An unknown window keeps today's full list rather than guessing small: the rule says on demand
*only when* the set crowds the window, and the request-budget's conservative 32k for unknown
endpoints exists for overflow safety, the opposite question.

**How Automatic resolves** for the tester's ~76.6 KB set (≈19.1k tokens): ChatGPT 272k → 7.0%,
full; Claude 200k → 9.6%, full; Gemini ~1M → 1.8%, full; gpt-4o / DeepSeek / Mistral at 128k →
15%, core; Groq 131k → 14.6%, core. A larger install (more MCP tools) can tip Claude to core; the
decision is per turn, so the cost is one cache miss when it flips.

### The core set — `ToolExposureCore`

Chosen from the app's own evidence of what everyday turns use, not from taste:

- the on-device path's safe set (`LLMService.localSafeTools`: weather, time, timers, alarms,
  calendar, reminders, location, device, music);
- the Voice tab's home grid (`HomeGridCatalog`: calendar, reminders, the daily brief, weather, a
  quick note, a timer, scanning a document, reading text);
- the general essentials half of `FieldToolProfile.names` (web search, directions, nearby places,
  calls, messages, contacts, notes, units, arithmetic);
- seeing (`capture_photo`, `look_closely`), recall (`memory_search`, `brain` — remembering is the
  prompt's `[REMEMBER]` tag), the loop's own controls (`new_topic`, `yield_to_human`), and
  `health_check`, which the prompt's mandatory routing rule names.

An active mode adds what it is built on: **a Field Assist job adds the whole field profile**, and
**accessibility mode adds its sight tools** (`reading_assist`, `navigation_assist`,
`identify_color`, `identify_money`). The core is 32 names, well under a third of the registry.

### `lookup_tools` — `ToolLookupTool`

A `NativeTool` registered in `NativeToolRegistry.init()`, read-only (`.read(.notCancellable)`),
classified `.local` offline. Its description tells the model to look a tool up from the list before
calling it. It returns the full `{name, description, parameters}` of up to eight named tools, drawn
from **exactly the declarations' own filter** — `ToolDeclarations.nativeToolDeclarations` (enabled,
not HIPAA-disabled, inside the job profile during a job) plus the router's offered MCP tools — so a
disabled tool's schema can never leak through it; any other name answers "Not available".

It is infrastructure, not a feature: `declarableNames` and `registry.toolNames` leave it out, so
the full list and the prompt are byte-identical to before it existed; the Tools screen and the Siri
action picker do not offer it. It is declared only on `core` exposure, by
`ToolDeclarations.exposedDeclarations`.

### The safety net — turn back, never guess

If the model calls an available tool that its round did not declare, the dispatcher does **not**
run it: it returns `failedBeforeExecution` ("was not run: its definition was not attached yet … call
it again with arguments that match that definition"), promotes the tool, and the next round declares
it. Chosen over "execute if the arguments validate" because it is both safer and simpler: the
arguments were written without the schema, the app has no JSON-schema validator, and an acting tool
(a message, a call, a smart-home command) on guessed arguments is the one outcome worth a round trip
to avoid. `failedBeforeExecution` is authoritative — nothing ran — so a retry is safe by the loop's
own rules. The check is against the set the round *was written against* (`declaredThisRound`),
not the set as a lookup in the same round grew it. A core turn's loop gets two extra rounds (seven,
not five) for a lookup and one turned-back call.

### Wiring — `LLMService`

- `sendMessage` resolves the turn's exposure once (`resolveToolExposure`) for any cloud turn that
  attaches schemas, before the prompt is built, and binds it task-locally (`ToolExposureScope.turn`)
  around the provider call. A turn in flight keeps it; the cascade resolves per candidate model.
- Each provider builds its tools per round with `declaring: roundToolFilter()` — Anthropic, Chat
  Completions, Gemini REST, the OpenAI Responses route and the ChatGPT subscription (the last two
  used to build them once per turn and now do so per round, so a lookup reaches the next request).
- The dispatcher promotes what `lookup_tools` returned and every available tool the model reached
  (`toolExposureMemory`, cleared with the conversation and on loading a thread).

### The prompt

On `full` exposure nothing changes — the prompt is byte-identical, and declarations stay sorted by
name. On `core`, the tools block gains `SystemPromptBuilder.onDemandToolGuide`: how to get a
definition, then a one-line summary (first sentence, ≤ 110 characters) of every available native
tool outside the core set, and connected-server (MCP) tools by name only — a server's own words are
not raised into the system prompt. The block is built from what is *available*, never from what has
been looked up, so it is the same from turn to turn and the cacheable head does not move.

### MCP, OpenClaw, realtime, on-device

- **MCP tools** go on demand under Always / Automatic-core like any other non-core tool; they are
  named in the prompt and looked up through the same tool.
- **OpenClaw `execute`** stays declared whenever OpenClaw is on — it is a single small gateway tool
  and the prompt tells the model to fall back to it.
- **Realtime backends** (Gemini Live, OpenAI Realtime) declare tools once at session setup and
  cannot add one mid-session without a reconfiguration; they keep their current behaviour.
- **On-device models** keep the path they have always had: names only, for a reduced safe set
  (`localSafeTools`), single-shot — already narrower than any core set, and a lookup round does not
  fit a single-shot `<tool_call>` path. They log exposure `core`, reason `onDevice`.
- **The agentic fast tier's cloud fallback** (`sendViaLocalAgent` → `sendCloud`) builds its own
  prompt with every description and is not bound to a turn's exposure; it keeps the full list.

### The setting and the organisation pin

`Config.toolDefinitionsMode` = the organisation's pin (`SettingKey.organizationToolDefinitionsMode`,
profile-owned string, `automatic` / `always` / `never`; any other value is a named drop) or the
wearer's own (`toolDefinitionsMode`, Automatic by default). The row — "Look Up Tools on Demand" in
AI & Personality — follows `SettingsVisibilityPolicy`: pinned, it is hidden from the technician and
read-only for the administrator. The profile tool (`Scripts/make-org-profile.swift`) knows the key.

### What is logged

`PrivacyLog.model(.toolExposure, …)` per turn: `detail` `full`/`core`, `reason`
`setting`/`contextShare`/`default`/`onDevice`, `count` (schemas the first request declares,
including `lookup_tools` and `execute`), `total` (tools available), `tokens` (the full set's
estimate). Mid-turn additions log `detail=added` with `reason` `lookup` or `undeclaredCall` and a
count. No tool names. It lands in the support report's event log through the diagnostics ring like
every model event.

## Also in this PR — the app guide's listening line

A tester asked whether the wake phrase works with the phone locked in a pocket; the guide had no
facts, so the model said iOS limits background listening and to keep the app open. Verified against
the code and added to `SystemPromptBuilder.appGuide`: while listening is on (not push-to-talk) the
wake phrase works with the phone locked or in a pocket; with *Listen for the wake word on* set to
Same as Microphone and the glasses as the microphone, the request and reply go through the glasses
(`TurnMicHandoff.sessionSwitch` keeps the idle hands-free session, PR #755) and glasses taken off
for 30 seconds stop listening until put back on (`GlassesSleepPolicy`); on iPhone, the default, the
phone's own mic listens (`WakeListenPolicy`).

## As built

- `ToolExposurePolicy`, `ToolExposureCore`, `ModelContextWindow`, `ToolExposureTurn` /
  `ToolExposureScope` — `Services/LLM/ToolExposurePolicy.swift`.
- `ToolLookupTool` — `Services/NativeTools/ToolLookupTool.swift`; registered, classified, offline
  table entry.
- `ToolDeclarations.exposedDeclarations` / `availableToolSet`, `declaring:` on the three provider
  mappers; `declarableNames` and `registry.toolNames` exclude the lookup tool.
- `LLMService`: per-turn resolution and log, per-round filter on all five cloud send paths,
  dispatcher safety net and promotion, conversation memory, two extra rounds on core.
- Setting, profile key, Settings row, Tools/Siri pickers filtered.
- Tests: `ToolExposurePolicyTests` (every table row, the measured sizes, context windows, the core
  set against 27 everyday asks and against the tool sources, declarations, the lookup's filter and
  bound, the prompt block, the setting and pin, the log line reaching the diagnostics ring) and
  `ToolExposureLoopTests` (through the real Chat Completions loop: a core request, a lookup
  promoting the tool for the next round, an undeclared call turned back without dispatching, Never
  identical to no turn at all, memory cleared with the conversation); `SystemPromptBuilderTests`
  pins the listening line.
- **Measured** on the headless test registry (the narrow one: no camera, memory or Field Assist
  services, no MCP): the full set is 51.6 KB over 73 tools; core exposure declares 30 schemas
  (29 core tools present plus `lookup_tools`) in 17.7 KB, and the prompt's on-demand block for the
  other tools is 4.3 KB — together about 43% of the full set here, and a smaller share on a real
  install, where the extra ~50 tools are all outside the core.
- Strings are new English only; the catalog picks them up at the next sync (no guard requires a
  catalog entry, and the coverage floor holds).

## Owed

- **Device:** an on-device model turn (expect `toolExposure detail=core reason=onDevice` and no
  behaviour change); a ChatGPT turn under **Always** that needs a tool outside the core set (expect
  a `lookup_tools` round, then the call, then the answer, and `toolExposure detail=added
  reason=lookup` in the report).
- **Later, if wanted:** the fast-tier cloud fallback bound to the setting; realtime backends adding
  a tool through a session update; a learned per-wearer core (most-used tools) instead of a fixed
  one.
