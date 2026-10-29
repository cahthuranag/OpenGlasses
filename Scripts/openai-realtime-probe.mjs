// OpenAI Realtime protocol probe (Plan KC P0 evidence). Node 22+ (global WebSocket with headers).
//   OPENAI_API_KEY=sk-... node Scripts/openai-realtime-probe.mjs
// Reads the key from the environment only. Prints event TYPES and error codes, never content
// or the key. Costs a few cents: each case asks for one short spoken reply.
const key = process.env.OPENAI_API_KEY;
if (!key) { console.error("Set OPENAI_API_KEY"); process.exit(2); }
const redact = (s) => String(s ?? "").replace(/sk-[A-Za-z0-9_*\-]+/g, "sk-…");

const betaSession = {
  modalities: ["text", "audio"], instructions: "Answer in one word.",
  input_audio_format: "pcm16", output_audio_format: "pcm16",
  input_audio_transcription: { model: "gpt-4o-mini-transcribe" },
  turn_detection: { type: "server_vad", threshold: 0.5, prefix_padding_ms: 300, silence_duration_ms: 500,
                    create_response: true, interrupt_response: true },
};
const gaSession = (transcribe) => ({
  type: "realtime", output_modalities: ["audio"], instructions: "Answer in one word.",
  audio: {
    input: { format: { type: "audio/pcm", rate: 24000 }, transcription: { model: transcribe },
             turn_detection: { type: "server_vad", threshold: 0.5, prefix_padding_ms: 300,
                               silence_duration_ms: 500, create_response: true, interrupt_response: true } },
    output: { format: { type: "audio/pcm", rate: 24000 } },
  },
});

const cases = [
  // What the app sends today on api.openai.com.
  { name: "app today: beta header + beta shape, gpt-realtime", model: "gpt-realtime", beta: true, session: betaSession },
  // Isolates the header: GA shape, but still with the beta header.
  { name: "GA shape + beta header, gpt-realtime", model: "gpt-realtime", beta: true, session: gaSession("gpt-4o-mini-transcribe") },
  // Isolates the shape: no header, beta shape (a compatible server's view).
  { name: "beta shape, no header, gpt-realtime", model: "gpt-realtime", beta: false, session: betaSession },
  // The fix.
  { name: "GA, gpt-realtime", model: "gpt-realtime", beta: false, session: gaSession("gpt-4o-mini-transcribe") },
  { name: "GA, gpt-realtime-2.1 + gpt-live-transcribe", model: "gpt-realtime-2.1", beta: false, session: gaSession("gpt-live-transcribe") },
  { name: "GA, gpt-realtime-2.1 + gpt-transcribe", model: "gpt-realtime-2.1", beta: false, session: gaSession("gpt-transcribe") },
];

function run(c) {
  return new Promise((resolve) => {
    const headers = { Authorization: `Bearer ${key}` };
    if (c.beta) headers["OpenAI-Beta"] = "realtime=v1";
    const ws = new WebSocket(`wss://api.openai.com/v1/realtime?model=${c.model}`, { headers });
    const types = new Map(); const errors = []; let closeInfo = "";
    const done = () => { try { ws.close(); } catch {} resolve({ types, errors, closeInfo }); };
    const timer = setTimeout(done, 20000);
    ws.onmessage = (m) => {
      const e = JSON.parse(m.data);
      types.set(e.type, (types.get(e.type) ?? 0) + 1);
      if (e.type === "error") errors.push(`${e.error?.type}/${e.error?.code}: ${redact(e.error?.message)}`);
      if (e.type === "session.created") ws.send(JSON.stringify({ type: "session.update", session: c.session }));
      if (e.type === "session.updated") {
        ws.send(JSON.stringify({ type: "conversation.item.create", item: { type: "message", role: "user",
          content: [{ type: "input_text", text: "Say the word ready." }] } }));
        ws.send(JSON.stringify({ type: "response.create" }));
      }
      if (e.type === "response.done") { clearTimeout(timer); setTimeout(done, 300); }
    };
    ws.onclose = (ev) => { closeInfo = `close ${ev.code} ${redact(ev.reason)}`; clearTimeout(timer); resolve({ types, errors, closeInfo }); };
    ws.onerror = () => {};
  });
}

for (const c of cases) {
  const r = await run(c);
  console.log(`\n== ${c.name}`);
  console.log("events:", [...r.types].map(([t, n]) => `${t}×${n}`).join(", ") || "(none)");
  for (const e of r.errors) console.log("error:", e);
  if (r.closeInfo) console.log(r.closeInfo);
}
