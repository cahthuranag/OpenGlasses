# Plan IZ — Product Lookup and Price Alerts ("what is this, what does it cost, tell me if it drops")

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
**Extends:** `BarcodeScannerTool` (`scan_code`), `WebSearchTool` (`web_search`), the structured-vision
pattern (`StructuredVisionService` / `AssessmentSchema`), `AgentScheduler` (background checks).
**Related:** Plan [GF](GF-recipe-add-ons.md) (`http`/`extract` steps — not the route, see Decisions),
Plan [GN](GN-agent-notebook.md) / [IW](IW-goals-and-activity-trail.md) (where a watched price
surfaces), Plan [BZ](BZ-notification-digest.md) (delivery), Plan [DZ](DZ-local-gguf-and-durable-agent-runtime.md)
PR6 (durable scheduler — a dependency for alerts that survive a relaunch), Plan
[R](R-mcp-egress-and-tool-poisoning-screen.md) (egress screening), Plan
[GP](GP-nearby-opening-hours.md) (the same "one external data source behind a route" shape).

---

## Trigger

Shopping is the oldest glasses demo and the app half-does it three different ways: a "Price Check"
quick action that reads a tag with the model, a shopping persona whose prompt *claims* barcode
lookups and price comparison it cannot perform, and `scan_code`, which decodes an EAN and then says
"Found EAN barcode: 9415…" and stops. Nothing turns a code into a product, nothing fetches a price,
and "tell me if it gets cheaper" has no mechanism at all — the only scheduler runs model prompts
and only in Agent Mode.

## Outcome

- "What's this?" over a barcode → "That's a 500 g bag of Whittaker's dark chocolate. Around twelve
  dollars at the two supermarkets I can see online; reviews are good, 4.6 from a few hundred."
- No barcode → the camera still (filtered) goes to the model with a product schema; the lookup
  continues from the name and brand it reads, with "I think" when the read is uncertain.
- "Tell me if it drops under ten dollars" → a **price watch**: checked once or twice a day, spoken
  or put in the digest when the condition is met or after 30 days ("still twelve dollars; keep
  watching?"). "What am I watching?" lists them; "stop watching the chocolate" removes one.
- Honest about sources: prices are what a web search returned, with the store named; never an
  invented number, never a price without a store, and "I couldn't find a price" when there is none.
- Phone: a product card (name, brand, image if the source gave one, prices by store, watch button);
  HUD: one line, name and best price.

## What exists today (verified 2026-10-18)

- `BarcodeScannerTool`: `VNDetectBarcodesRequest` over `filteredStill(for: .onDeviceVision)`
  (`cachedFrameOnly`, never captures), symbologies ean8/ean13/upce/code39/93/128/itf14/pdf417 (+ qr),
  **output is a sentence**, no structured payload; in `untrustedOutputTools`; hidden when glasses are
  disconnected; `PhoneCapturePolicy .askOnPhone`. No dedicated tests (routing tests only).
- `WebSearchTool`: Perplexity → Tavily → Brave → SearXNG → Tavily keyless → DuckDuckGo, each
  returning `String?`, **free text only**, each with its own `URLSession`; route `.webSearch`
  (`[.promptText]`, `.publicWeb`, `blockedWhenLocalOnly`, manifest `SearchHistory`); in
  `hipaaDisabledTools` and `untrustedOutputTools`. Native arguments are **not** egress-screened
  (`EgressScreen` runs on the MCP seam only). Tests cover SearXNG URL building only.
- Hardened fetch exists: `BoundedHTTPClient` (DNS-pinned, profiles with byte caps and MIME lists)
  + `URLFetchGuard` (SSRF) + `UntrustedNetworkFeaturePolicy`, used by `QRContextTool` (8000-char raw
  text, no HTML stripping). `HTMLTextStripper` is EPUB-oriented. `PlaybookStore.executeHTTPStep` is
  the only generic `http` step. GF's `RecipeRunner`/`extract` do not exist.
- Structured vision: `AssessmentSchema { kind, jsonSchema, systemPrompt, confidenceFloor, makeCard,
  backstop }` registered in `AssessmentSchemaRegistry` (`instrument_reading`, `first_aid_triage`);
  `StructuredVisionService.assess` = filtered still → `analyzeFrameStructured` → card → qualifier
  with `AIProvenance`. `look_closely` already says "a price, a total" in its description.
- Prompts and personas that promise this: `QuickAction "price-check"`, `preset-shopping-assistant`
  ("scan barcodes… for product information and reviews", "price comparisons"), the wine preset,
  `VisionIntentDetector` phrases ("how much does", "what's the price"), `UncertaintyDetector`
  freshness regex `price of`.
- Scheduler: `AgentScheduler.ScheduledTask { prompt, intervalMinutes, … }` runs a **full LLM turn**
  per task, Agent-Mode-gated, foreground timer only, at most one task per 5/30 min cycle, result
  reaches the wearer only via `agentNotificationQueue.enqueue` when `speakResult`. Non-agent
  periodic mechanisms: `ProactiveAlertService` (calendar, 30 s timer), `MyDayDelivery` (60 s),
  `GeofenceTool` (region monitoring), local notifications (`TimerTool`, `PomodoroTool`). **No
  BGTaskScheduler anywhere**; `UIBackgroundModes` = audio, bluetooth-central, external-accessory.
- Digest: `DigestSource { calendar, geofence, proactive, agent, reminder, sync }` (exhaustive
  switches in `MyDayDigestPolicy`); `NotificationDigestService.ingest(...)`, 50 items, staleness by
  priority (low 30 min, medium 2 h, high never).
- A new tool must also appear in: `ToolEffectClassification` row, `OfflineToolPolicy` table,
  `ToolEffectClass` classification, `PhoneCapturePolicy` (camera), `ToolsSettingsView` name,
  `Config.internetRequiringTools`, a `NetworkRoute` if it owns a transport, an
  `OutboundFrameConsumer` case if it reads a still, `untrustedOutputTools` if it returns web content.

## Design

### One tool, three steps (`product_lookup`)

`identify → price → (optional) watch`, each a pure, testable stage behind a seam.

**Identify (`ProductIdentity`, pure + two seams).**
- Barcode path: `scan_code`'s decoder is lifted into `BarcodeDecoder` (pure over `VNBarcodeObservation`
  values: symbology, payload, GTIN normalisation — EAN-8/13, UPC-A/E to a 14-digit GTIN with check-digit
  validation, `ProductCode { gtin, raw, symbology }`). `scan_code` keeps its spoken output and gains a
  structured `codes` field the router can hand on.
- Camera path (no code): a `product_read` `AssessmentSchema` — `{ name, brand, variant/size,
  category, visibleText[], confidence }` through the existing `StructuredVisionService` (filtered
  still, scope `.visionAssessment`, provenance-qualified). Confidence under the floor → "I can't
  make out the product; try the barcode."
- `ProductQuery` = `{ gtin? , name?, brand?, variant? }` with a `spokenName` and a `searchPhrase`
  builder (brand + name + size; GTIN appended when present — search engines index GTINs well).

**Price (`PriceSearch`, pure parsing over the search seam).**
- Reuses `WebSearchTool`'s provider chain through a new structured entry point
  `WebSearchTool.structured(query:) -> SearchResultSet { answer?, results: [{ title, url, snippet,
  price? }] }` (the providers already return titles/URLs/snippets internally; today they are
  flattened to a string). No new transport, same `.webSearch` route, same Local-Only refusal.
- `PriceExtractor` (pure): finds currency amounts in titles and snippets (`$12.50`, `NZ$`, `€`,
  `£`, `12,50 €`, "from 12.00"), binds each to the result's **host** as the store, drops amounts
  that are clearly not a unit price (ranges without a low, "save $X", percentages, totals in reviews),
  converts nothing (the wearer's currency only; others reported as-is), and returns
  `[PriceObservation { amount, currency, store, url, observedAt, isApproximate }]`. Deterministic,
  table-tested against snippet fixtures. Two or more observations within 15 % → "around"; one → "one
  store lists it at"; none → "I couldn't find a price".
- `ReviewSummary` (pure): rating + count when a snippet carries "4.6 (312)", "4.6 out of 5",
  "312 reviews"; absent otherwise. No sentiment inference.
- `ProductPhraser` (pure): the spoken line (name, approximate price, stores, rating), ≤ 2 sentences;
  HUD line "Whittaker's Dark 500 g · ~$12". Prices are read with the store; never a bare number.

**Watch (`PriceWatch`).**
- `PriceWatch { id, query: ProductQuery, condition: .below(amount, currency) | .anyDrop(from:) ,
  createdAt, lastChecked, lastBest: PriceObservation?, state: .watching | .met | .expired |
  .stopped, expiresAt (30 d) }` in `PriceWatchStore` (`Application Support/Shopping/price-watches.json`,
  registered in `DataStoreRegistry`, deleteAll, 20 watches cap).
- `PriceWatchChecker` (pure decision over a `SearchResultSet`): met when the best observation
  satisfies the condition from a store seen before **or** two stores agree; a single new cheaper
  store is "possibly" and said so. Each check records the best observation (history capped at 10
  per watch) so "how has it moved?" has an answer.
- **Scheduling without Agent Mode.** A new `PeriodicCheckService` (foreground/alive timer like
  `ProactiveAlertService`, 60 s tick, presence-throttled) runs due checks: default **twice a day**
  (morning and evening slots shared with My Day), one network search per watch per check, under a
  daily budget (default 10 searches), skipped under `PowerPosture.reserve`, offline or Local Only.
  It is not an agent prompt — no model turn, no `[NOTHING]` convention — so it needs no Agent Mode.
  When Plan DZ PR6's durable scheduler lands, the checker plugs into it unchanged. A `BGAppRefreshTask`
  path is **not** in v1 (GN decides background refresh for the app as a whole).
- Delivery: `DigestSource.shopping` (new case; `displayTag` "Price"; eligible for My Day as an
  `update` when `met`), ingested with `priority .medium` (met → `.high` so it does not go stale),
  threadKey = watch id; spoken through `agentNotificationQueue.enqueue` only when `met` and the
  wearer is present (the queue already handles disconnected/quiet). Expiry (30 d) produces one
  digest line asking to keep or stop; no reply → stopped.

### Tool surface

`product_lookup` actions: `identify` (default; uses the last `scan_code` result if under 60 s old,
else the camera schema), `price` (for a named product, no camera), `watch` (`below`, `currency`),
`watches`, `stop_watch`. Semantics `.external(.bestEffort)` → `write` only for `watch`/`stop_watch`
(shape-keyed, Plan [IX](IX-scoped-grants-and-read-only-integrations.md)); `identify`/`price` are
reads. In `untrustedOutputTools` (web content), `internetRequiringTools`, `OfflineToolPolicy
.needsNetwork` (identify-by-barcode alone is `.degraded`: it can still say what the code is).
`PhoneCapturePolicy .askOnPhone` ("Frame the product or its barcode, then take the photo.").
Roster: `.productLookupTool` scope `.visionAssessment` via the chokepoint (the barcode read stays
`.onDeviceVision` inside `scan_code`).

### Honesty and safety

- The shopping persona and quick-action prompts are **rewritten to name the tool** instead of
  promising abilities; the wine preset likewise. `VisionIntentDetector`'s price phrases route to
  `product_lookup`.
- Search arguments pass through `EgressScreen` on the native seam for this tool (a product name
  is not a secret, but the screen is cheap and a model could put anything in `query`).
- No purchasing, no carts, no account connections, no affiliate links; a URL may be opened by the
  wearer from the phone card only.
- `PrivacyLog.shopping(.identified | .priced | .watchChecked | .watchMet, provider:, observations:)`
  — counts and provider, never the product name or query (search history is a manifest-declared
  data type already; the log stays content-free).
- Local Only / HIPAA: `web_search` is already disabled; `product_lookup` inherits — identify by
  barcode still names the code type, nothing else.

## Phases (one PR each)

**P0 — Pure core.** `BarcodeDecoder` + GTIN normalisation, `ProductQuery`, the `product_read`
schema (prompt + JSON schema + `makeCard`), `SearchResultSet` + per-provider structured parsing
(fixtures for Perplexity citations, Tavily results, Brave `web.results`, SearXNG, DuckDuckGo
instant answers), `PriceExtractor`, `ReviewSummary`, `ProductPhraser`, `PriceWatch` + codec +
`PriceWatchChecker`. Tests: `BarcodeDecoderTests` (UPC-E expansion, EAN-8 → GTIN-14, bad check digit
refused, code128 is not a GTIN), `PriceExtractorTests` (table of 25 snippets: currencies, European
decimals, "from", "save", percentages, review-count false positives, two stores agree → around),
`ReviewSummaryTests`, `ProductPhraserTests` (exact lines; never a bare price), `SearchResultSetTests`
(each provider fixture → same shape; a provider with only `answer` yields zero priced results),
`PriceWatchCheckerTests` (met rules, single-store "possibly", expiry, history cap),
`ProductReadSchemaTests` (card from fixtures; floor).

**P1 — Tool and surfaces.** `product_lookup` registered with every roster/table entry,
`WebSearchTool.structured`, `scan_code` structured field, `StructuredVisionService` schema
registration, prompt rewrites, product card and HUD line, egress screen on the native seam for
this tool. Tests: `ProductLookupToolTests` (fake search + fake assess: barcode path, camera path,
uncertain read, no price, Local Only), `OutboundFrameConsumerTests` / `OfflineToolPolicyTests` /
`ToolEffectClassificationTests` green, `PromptInjectionPolicyTests` includes the tool.

**P2 — Watches.** `PriceWatchStore` + registry entry, `PeriodicCheckService` (slots, budget,
power, presence), `DigestSource.shopping` + My Day eligibility + exhaustive-switch updates,
`watch`/`watches`/`stop_watch` actions, Settings › Shopping (watches list, check frequency, budget).
Tests: `PeriodicCheckServiceTests` (fake clock: two slots a day, budget stops at 10, reserve skips,
offline skips, a met watch enqueues once), `DigestCoreTests` update, `DataStoreRegistryTests` green
(ET matrix regenerated). Device pass (owed): ten real supermarket barcodes (hit rate of the identify
step by provider), three camera-only products, a watch across two days, and the phone-locked check
(expected: skipped until foreground — recorded as a limit).

## Risks

- **Price quality.** Snippets are noisy; the extractor is conservative on purpose and the phrasing
  always names the store. The device pass measures hit rate per provider and the plan may end with
  "Perplexity only" if the free providers are too thin.
- **Provider terms.** Shopping queries at scale on free tiers (Tavily keyless, DuckDuckGo) may be
  rate-limited; the daily budget and twice-a-day cadence keep it small. No scraping of retailer
  pages in v1 (that is why `BoundedHTTPClient` is not used here).
- **Background reality.** Checks run only while the app is alive; a wearer who never opens the
  app gets checks only when they do. Stated in the Settings copy; DZ PR6 / GN decide more.
- **Region.** Currency symbols are ambiguous (`$`); the wearer's currency is assumed and said when
  it matters ("twelve dollars, if that's New Zealand dollars").

## Decisions for Greig

1. **Not a GF recipe.** The price extractor and watch checker are the value and must be tested
   native code; GF has no extraction logic yet. *Recommend native.* (A GF add-on could later add a
   retailer-specific source.)
2. **Watch cadence** twice a day (recommended) or hourly with a smaller budget?
3. **Camera-only identify in v1** (recommended; it is what the quick action already pretends to do)
   or barcode-only first?
4. **Rewrite the shopping persona** to the tool (recommended) or retire it?
5. **Provider for priced results**: all providers through the structured parser, or Perplexity /
   Tavily only (they return structured citations; DuckDuckGo rarely has prices)?

## Out of scope

Purchasing or carts, retailer accounts, affiliate links, retailer-page scraping, a product
database or offline catalogue, nutrition from barcodes (Plan [JA](JA-guided-workouts-and-nutrition-trends.md)
reads labels with the camera), currency conversion of foreign prices, and any background refresh
beyond the alive-app timer.
