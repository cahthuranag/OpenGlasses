# Realtime protocol fixtures

These sanitized event sequences were constructed from official provider
references checked on 2026-10-11. They are documentation-derived contract tests,
not recordings from authenticated sessions. Keys, endpoints, audio and tool
values are synthetic.

- Qwen: https://www.alibabacloud.com/help/en/model-studio/server-events
  and https://www.alibabacloud.com/help/en/model-studio/client-events
- Doubao: https://docs.volcengine.com/docs/DoubaoVoice/endtoend-realtime-voice-full-duplex-version?lang=zh
- OpenAI Realtime (current protocol, `openai-realtime-v1.json`, checked 2026-10-29):
  https://developers.openai.com/api/reference/resources/realtime/server-events
  and https://developers.openai.com/api/reference/resources/realtime/client-events

`RealtimeProviderTests` checks decoding, tools and capability restrictions.
`RealtimeSessionEngineTests` uses a fake transport and clock for setup readiness,
packetization, stale callbacks, terminal authentication errors and cancellation.
These do not establish deployed-server compatibility; live verification needs
account credentials and real audio/tools.

Text-delivery contracts are covered by `RealtimeTextContractTests` and
`LiveAnnouncementDeliveryTests`. Qwen Audio uses the separately documented
Qwen-Audio client/server contracts, rather than assuming Omni accepts user text:
https://www.alibabacloud.com/help/en/model-studio/fun-audiochat-client-events
https://www.alibabacloud.com/help/en/model-studio/qwen-audio-realtime-server-events
