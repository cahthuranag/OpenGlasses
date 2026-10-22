# Plan JP — Hermes Agent's API server (talk to Hermes directly, and say why a connection fails)

**Status:** 🚧 Built 2026-10-23 — pure core, live client, settings, turn routing, conversation reset
and the bridge probe fix are in; a live check against a real Hermes API server, a device pass and
the catalog sync for the new strings are owed (see [Owed](#owed)).
**Builds on:** Plan [CL](CL-design-language-and-field-polish.md) P5 (the Hermes bridge client, its
settings screen and the "any failure falls through to the normal path" turn rule), Plan
[ID](ID-ecosystem-review-hardening-bundle.md) item 4 (`GatewayAddress`: a host typed without a
scheme gets the one the wearer meant), `EndpointPolicy` + `NetworkRouteRegistry` (W04.2),
`MedicalEgressGuard`/`MedicalEgressCoordinator`, the privacy chokepoint
(`CameraService.filteredStill(for:source:)`, `OutboundFrameConsumer`), and the conversation-reset
vocabulary (`ConversationResetOutcome`).

---

## Trigger

A user turned on Hermes Agent's built-in OpenAI-compatible API server, typed its address and API
key into our "Hermes Bridge" settings, and could not connect. Nothing told them why.

Two things were wrong at once:

- **We only spoke one of Hermes's two doors.** The bridge client speaks the JSON-over-WebSocket
  protocol of the separate glasses bridge script (`hermes_bridge.py`, port 8765, `?token=`).
  Hermes Agent's own API server (port 8642, `Authorization: Bearer`, OpenAI Responses shape) is a
  different thing, and the settings screen gave no hint that the two exist, let alone which one the
  wearer had set up. The API key went into a field that is the bridge script's token.
- **Test Connection could not fail usefully.** `checkConnection()` returned `true` as soon as a
  ping frame was *sent* — URLSession queues a send before the socket is open, so an address with
  nothing listening, or one serving plain HTTP, still showed a green tick. A red cross, when it
  came, carried no reason.

## Outcome

- Settings › Gateways › **Hermes Agent** has a **Connection** picker: *API server* (Hermes Agent's
  own server) or *Bridge script* (the glasses bridge script). Each kind shows only its own fields,
  and a footer that says exactly what to set on the Hermes machine.
- **Test Connection says what happened in a sentence**, read by VoiceOver: reachable and the key
  works (with the model the server advertises); the server only listens on its own machine by
  default (`API_SERVER_HOST=0.0.0.0`); the key was refused; something answered that isn't Hermes's
  API server; this looks like the API server — switch Connection; the bridge refused the token.
- A port that belongs to the other kind (8642 on the bridge kind, 8765 on the API kind) gets a
  one-line suggestion to switch.
- With the API kind on, a turn goes to Hermes over `POST /v1/responses`; turns are chained with
  `previous_response_id` so Hermes replays the conversation itself, and "new topic" drops the
  chain. A visual question carries one filtered glasses still. Any failure falls through to the
  normal path exactly as the bridge does today.
- Existing bridge users see no change: an install that already has a bridge host keeps the bridge
  kind.

## Design

### Pure core (`Services/HermesBridge/HermesAgentAPI.swift`)

- **`HermesConnectionKind`** — `apiServer` / `bridgeScript`, each with its default port. The default
  for an install that never chose: `bridgeScript` when `hermesBridgeHost` is non-empty (an existing
  bridge user), `apiServer` otherwise. Pinned once at launch so typing a host later cannot flip it.
- **Base URL** from host + port through `GatewayAddress` — the same scheme rule as the gateway and
  the bridge (http on the wearer's own network, https for a public name, a typed scheme honoured,
  `ws`/`wss` read as `http`/`https`). A typed path is kept as a prefix so a profile served under
  `/p/<profile>/` works; a trailing `/v1` is dropped because the client appends it. An address
  with a user name is refused.
- **Requests** — `POST <base>/v1/responses` with `Authorization: Bearer`, JSON body
  `model: "hermes-agent"`, `store: true`, `stream: false`, `previous_response_id` when chaining,
  `input` as a plain string, or as the content-array form with an `input_image` data URL when a
  JPEG is attached, and short `instructions`: the reply is spoken aloud through glasses — brief,
  plain sentences, no markdown, lists or URLs. `GET <base>/health` (no key) and
  `GET <base>/v1/models` (with the key).
- **Reply parsing** — the `output_text` parts of `message` items, joined; tool items ignored; a
  top-level `output_text` accepted as a fallback; `failed`/`incomplete` status or an empty reply is
  a typed error carrying the server's message.
- **HTTP errors** — 401/403 key refused, 404 not found, 429 busy, 503 unavailable, anything else
  with `error.message`. Server text is trimmed, capped and has the key redacted before it can reach
  a debug line or the screen.
- **Diagnosis** (`HermesConnectionDiagnosis`) — one pure mapping per probe step (health, models,
  bridge socket failure) and the port hint. Every user-facing sentence is `String(localized:)`,
  plain, and never contains the key.

### Live edge

- **`HermesAgentAPIClient`** (`@MainActor`) over a `HermesHTTPTransport` seam (production:
  ephemeral `URLSession`, 120 s request timeout, the bridge's query timeout). Before every request
  `EndpointPolicy.requireOpenable(url:for: .hermesAgentAPI)` — the endpoint rule and the medical
  local-only rule in one call. The last response id is held in memory only (never persisted);
  `resetConversation()` drops it; a chained request answered 404 drops the id and retries once
  without it. Conforms to `MedicalEgressTeardown`: Local Only turning on cancels in-flight work.
  The key lives in the Keychain (`hermesAgentAPIKey`) and is never logged.
- **Bridge probe** — `HermesBridgeService.checkConnection()` now waits up to 5 s for the `welcome`
  frame (or a `pong` when already connected) and diagnoses a failure from what URLSession exposes:
  the HTTP status when the upgrade was refused (a plain HTTP answer → "this looks like the API
  server"), close code 4401 (token refused), and the `URLError` code (unreachable). `HermesSocket`
  gains a `diagnostics()` read with a default, so scripted test sockets keep working.
- **Fold-in:** the bridge's "connecting to …" debug line no longer prints the `?token=` value.

### Route, privacy and reset

- **`NetworkRoute.hermesAgentAPI`** — `.localNetwork`, carries prompt text, transcript, frame and
  credential, owned by `URLSessionHermesHTTPTransport`, blocked under medical Local Only like the
  bridge.
- **Frames.** The API kind attaches a still only when the turn is visual — the same decision the
  cloud path makes (live frame, "always" camera behaviour, smart-camera cooldown,
  `VisionIntentDetector`) without the "is the selected model vision-capable" gate, because Hermes
  decides vision itself — under `PrivacyFilterScope.agentAttachment`. The bridge's
  photo-on-request used to send `capturePhoto()` bytes unfiltered; it now asks
  `filteredStill(for: .agentAttachment, source: .photoOnly)` and answers `photo_error` when the
  picture cannot be prepared. Both are on the `OutboundFrameConsumer` roster.
- **Conversation reset.** The `.hermes` backend resets by kind: the bridge sends `new_session`
  (still `issuedUnverified` — the protocol has no acknowledgement); the API kind drops the chain id
  on the phone, which is locally observable, so `completed` — every later request starts a new
  chain. Hermes's own long-term memory is a separate store and is not touched by either, as with the
  gateway. The API kind joins the reset plan whenever it is enabled; it has no socket to be "up".
- Only the bridge kind ever opens the WebSocket: launch, the settings switch and the org-policy
  path all check the kind.

## Tests

`HermesAgentAPITests` (base-URL table, request building for text / image / chained, reply parsing
variants, HTTP error mapping, key redaction, default-kind rule, port hint, diagnosis for both
kinds), `HermesAgentAPIClientTests` (scripted transport: chaining across two asks, reset dropping
the chain, 404 retry-once, policy refusal before any request, probe sequence),
`HermesBridgeProbeTests` (scripted socket: welcome → connected, HTTP answer → API-server hint,
4401 → token refused, silence → no welcome; token redaction in the debug line), and the reset
adapter for the API kind. Existing guards updated: `NetworkRouteRegistryTests`,
`EndpointPolicyTests`, `OutboundFrameConsumerTests`, `ConversationResetCoordinatorTests`.

## Owed

- **A live check against a real Hermes API server** — health, models, a text turn, a chained
  follow-up, a visual turn with an image, a 401 with a wrong key, and the `/p/<profile>/` prefix.
- **A device pass** — the settings screen in both kinds with VoiceOver reading the Test Connection
  sentence; a bridge-script user upgrading keeps the bridge kind; a turn with a picture.
- **The catalog sync** for the new strings (they ship un-synced, English only, until then).

## Out of scope

Streaming replies (`stream: true`) and showing Hermes's tool calls; Hermes's own long-term memory
(not reachable through the API, and not ours to clear); OAuth or any key other than
`API_SERVER_KEY`; changes to the bridge script's protocol.
