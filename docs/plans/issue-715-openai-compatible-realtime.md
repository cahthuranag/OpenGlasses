# Issue 715: OpenAI-compatible Realtime

Source: https://github.com/straff2002/OpenGlasses/issues/715

The initial compatible-endpoint implementation below has been extended by
[the implemented live-provider architecture](live-provider-adapters.md), including
native Qwen/Doubao JSON adapters and shared Gemini/OpenAI session coordination.
The current setup flow and live-test limitations are documented in
[Realtime setup](../compatible-realtime.md).

## Initial accepted scope

Add **OpenAI-compatible Realtime** as a separate conversation mode. Configure a full
WebSocket endpoint, API key and model ID under Settings → AI & Personality. This mode
shares the existing OpenAI Realtime wire protocol and session manager. Existing OpenAI
and Gemini modes retain their defaults and credentials. Native Qwen/Doubao protocol
adapters and a Gemini endpoint override are follow-ups, not compatibility claims made here.

## Implementation

1. Add a pure connection configuration/request builder. Preserve custom paths and query
   parameters; encode the model parameter; require a WebSocket scheme and usable host;
   use Bearer authentication. Send OpenAI's beta header only to the built-in backend.
2. Persist endpoint, model and key in Keychain, since URLs may include gateway tokens.
   Add a settings editor with validation and a discoverable conversation-mode option.
3. Snapshot the chosen configuration at session start, before camera/audio acquisition.
   Use that snapshot on reconnect. Route both OpenAI modes through the same manager;
   update start/stop, mode switching, frame delivery, transcripts, recovery and launch gates.
4. Apply the existing endpoint and medical policies to custom connections. Explicit custom
   servers may be on the LAN; public servers require TLS in Release. Medical local-only
   continues to block live network sessions even when the custom server is on the LAN.
5. Show only the custom destination host in the processing summary. Document the existing
   protocol contract (PCM16 mono 24 kHz both ways, session.created/session.updated,
   existing image/tool events) and the setup flow.

## Verification

- Test independent availability, configuration persistence, default requests, query/model
  encoding, invalid endpoints, private/public endpoint rules and medical restrictions.
- Verify the service snapshots configuration across reconnects and mode transitions use
  the shared manager without switching back to the built-in OpenAI endpoint.
- Run relevant unit suites and compile the app. A live proxy/TestFlight session remains
  the integration check: audio both ways, interruption, optional images/tools, reconnect.

## Progress

- [x] Configuration and request builder
- [x] Settings and mode selection
- [x] Session/lifecycle integration
- [x] Destination reporting and documentation
- [x] Automated verification and build

## Implementation result

Implemented 2026-10-11. The shared manager retains both its session mode and its
connection snapshot. Startup checks the session identity after suspension points,
so a superseded startup cannot configure or tear down its replacement. The URL
builder retains percent-encoded gateway query values and encodes the model separately.

Validation: the app and unit-test target compiled under Xcode 27; 136 selected tests
passed on the iPhone 18 Pro simulator, including 13 new compatible-Realtime tests.
The privacy logging gate and `git diff --check` passed. Simulator tests used ad-hoc
signing so Keychain persistence was exercised with valid entitlements.

The initial compatible-endpoint scope above has now been extended with native Qwen
Omni, Qwen Audio and Doubao adapters, saved provider templates, and shared
Gemini/OpenAI session coordination. See [Live provider adapters](live-provider-adapters.md)
for the implemented architecture and [Realtime setup](../compatible-realtime.md)
for the current contracts and verification limits. Authenticated provider audio,
interruption, tools and reconnect testing, plus TestFlight validation, remain owed.
