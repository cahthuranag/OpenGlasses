# Plan JO — Watchers ("tell me the score", "tell me when they announce a show near here", "I'm waiting on a letter")

**Status:** 📝 Drafted (not scheduled), 2026-10-21 — nothing built.
**Builds on:** `AgentScheduler` (typed tasks, as Plan [IW](IW-goals-and-activity-trail.md) P2's goal
check-ins), `AgentNotificationQueue`, Plan [BZ](BZ-notification-digest.md) (digest, `NotificationPriority`),
Plan [DY](DY-my-day-everyday-briefing.md) (`MyDayDeliveryPolicy`, quiet hours), Plan IW (activity
trail, goals), `PresenceMonitor`, `NetworkRouteRegistry`, `LocationService`, `MediaPlayerLibrary`.
**Sits beside:** Plan [GN](GN-agent-notebook.md) (the assistant's notes about *your* data — a watcher
is a standing question about the *outside world*; both need the same background runner, see P2),
Plan [IZ](IZ-product-lookup-and-price-alerts.md) (a price watch becomes one watcher kind rather than
its own scheduler), Plan [IX](IX-scoped-grants-and-read-only-integrations.md) (read-only mail, P4,
is an IX integration), Plan [GG](GG-readable-memory.md) (suggestions read memory; every watcher is
readable and removable the same way a fact is).

---

## Trigger

Two things a good personal assistant does that this one cannot.

**It volunteers.** "Your team kicks off at 7:35, here's the line-up", "full time, 24–17",
"that band you play every week just announced a show in town", "there's a road closure on your way
home". Today the assistant knows none of this unless asked. The pieces that look proactive are all
about the wearer's own data — calendar alerts (`ProactiveAlertService`), My Day, goal check-ins,
geofences — and the one scheduler that could ask the outside world (`AgentScheduler`) runs a
free-text model prompt on a `Timer`, which means it only runs while something else keeps the process
alive, costs a model call every time, and can't say "only tell me if it changed".

**It connects what you're waiting for with what arrives.** "I'm waiting on a letter from the
council" should make the assistant watch for it — in calendar entries, reminders, the gateway's
events and, once there is a way to read it, mail — and say so when it shows up, the way it would if
it had been told the parcel's tracking number. Nothing holds an expectation today; IW goals hold
steps, not things the wearer is waiting to *receive*.

The honest constraint underneath both: **an iOS app is not a server.** A watcher that must fire at
half-time needs the process alive at half-time. This plan builds the watcher once, runs it wherever
the app can run — alive, foreground, iOS background refresh, location wakes — and says plainly what
each of those can and can't promise. An always-on tier is named and left for later (see
[Later](#later-always-on)).

## Outcome

- **Ask once, hear it when it matters.** "Tell me the Blues scores" → a watcher: before the game (if
  the app is awake), at the end, and the half-time score when the app is listening at the time.
  "Tell me if Fat Freddy's announce a show near here" → checked a few times a day; one sentence when
  a new date within the wearer's radius appears, never again for the same date.
- **Local, coarse, and sourced.** "Tell me about anything happening around here" → local news for the
  suburb (never precise coordinates sent anywhere), and official emergency alerts where a region
  publishes them. Every finding names where it came from.
- **Noticed, then offered — never silently set up.** "You've asked about the Blues three times this
  fortnight. Want me to tell you their scores?" One offer, at a free moment; "no" means it isn't
  asked again for 90 days. The assistant never creates a watcher the wearer didn't say yes to.
- **Waiting on something.** "I'm waiting on a letter from the council" → an expectation watcher;
  when a matching item appears in a source the app can read, "the council letter you were waiting
  on — your mail digest says it arrives today". "What am I waiting on?" lists them.
- **Bounded.** At most three unprompted spoken findings a day across all watchers (the rest wait in
  the digest), never in quiet hours, a meeting or a live session, and a finding that has gone stale
  (a half-time score after full time) is dropped, not delivered late.
- **Readable.** "What are you watching?" lists them; "stop watching the Blues"; "why did you tell me
  that?" names the watcher and the source. Phone: Settings › AI & Personality › Watching, each
  watcher with its last check, last finding and a pause/remove control.
- **Honest about timing.** The watcher screen and the first confirmation say which promises hold:
  "I'll tell you the final score. If I'm listening at half-time you'll hear that too." Never a
  promise the platform can't keep.

## What exists today (verified 2026-10-21)

- `AgentScheduler` (`Services/AgentScheduler.swift`): a `Foundation.Timer`, re-armed after each
  cycle at `Config.agentConnectedInterval`/`agentDisconnectedInterval`. It runs while the process is
  alive, which in practice means while the `audio` background mode holds it (the listener, a live
  session) or the app is in the foreground. Prompt tasks go to the model; **typed** tasks (IW P2 goal
  check-ins) never reach it and have their own due policy — the shape a watcher check should take.
  Once-daily tasks are due by calendar day (`ScheduleDuePolicy`, fixed in Plan JC).
- **No background execution of its own.** `UIBackgroundModes` is `audio`, `bluetooth-central`,
  `external-accessory`; nothing registers a `BGTaskScheduler` task and there is no
  `BGTaskSchedulerPermittedIdentifiers`. The only background-time request is
  `beginBackgroundTask` in `VaultIndexingMonitor` (finishing work already started).
- **Location wakes half exist.** `LocationService` requests Always authorization and monitors
  `CLCircularRegion`s for `GeofenceTool` — region events relaunch a suspended app. No
  significant-location-change monitoring.
- **No push.** No `registerForRemoteNotifications`, no `aps-environment` entitlement, no sender.
  `OpenClawEventClient` receives the gateway's heartbeat/cron events over a WebSocket and speaks them —
  only while the app is alive and connected.
- **Delivery is solved.** `AgentNotificationQueue` (priority, reconnect delivery, "told you" log),
  `NotificationDigestService` + `NotificationPriority` (staleness: low 30 min, medium 2 h, high never),
  `MyDayDeliveryPolicy` (quiet hours, protected data), `PresenceMonitor`, `HeldRecommendationStore`.
- **Activity trail** (IW): `ActivityRecorder`/`ActivityStore` record what the assistant did; a
  finding becomes an entry.
- **Sources today:** `NewsTool` reads a news RSS search with a fixed US locale (`hl=en&gl=US`);
  `WebSearchTool` returns free text only (and is `hipaaDisabled`, untrusted-output). No sports,
  events or local-alerts source. `NetworkRouteRegistry` is where a new egress is declared.
- **Taste on the device:** `MediaPlayerLibrary` queries the on-device library (albums, playlists,
  songs) for playback; play counts and last-played dates are available on the items but not read.
- **Mail:** compose only (`send_via channel:email`); IX records that there is no mail-reading tool.
- **Drafted neighbours:** GN plans a `BGAppRefreshTask` pass as its P2; IZ's price watch needs
  "checked once or twice a day" and names DZ PR6 (durable scheduler, unbuilt) as a dependency.

## Design

### The watcher

```swift
struct Watcher: Codable, Identifiable {
    let id: UUID
    var kind: WatcherKind          // .fixture(team) .artistShows(artist, radiusKm) .localNews(area)
                                   // .topic(query) .price(productRef) .expectation(Expectation)
    var label: String              // "Blues scores" — what the wearer hears and sees
    var origin: Origin             // .asked(utteranceAt) | .acceptedSuggestion(because)
    var state: State               // .active | .paused | .ended(reason)
    var lastChecked: Date?
    var seen: [String]             // fingerprints already told (bounded, oldest dropped)
    var endsAt: Date?              // a fixture watcher can end with the season; an expectation after 30 days asks "still waiting?"
}
```

Stored in one `JSONStore` file, registered in `DataStoreRegistry` (erasure, export). Not memory: a
watcher is not ingested into `BrainStore`; a fact the wearer says while making one ("I support the
Blues") goes through the normal memory path.

### Sources — typed, pure parsers, one route each

`protocol WatchSource { func observations(for: WatcherKind, area: CoarseArea?) async throws -> [Observation] }`
where `Observation` is typed (`.fixture(kickoff, teams, score?, status)`, `.event(artist, venue, city,
date)`, `.headline(title, publisher, published, link)`, `.price(...)` from IZ, `.item(source, text,
date)` for expectations). Each source is a `NetworkRoute` (declared, egress-classified, `.publicWeb`,
`blockedWhenLocalOnly`) using `BoundedHTTPClient`; its parser is pure and tested from recorded
fixtures. Output is untrusted (never instructions; phrased from typed fields, not passed raw).

**Location is coarse by construction.** `CoarseArea` is a suburb/city name from reverse geocoding (on
the device) or coordinates rounded to ~1 km; precise coordinates never leave the phone for a watcher.

### Matching (`WatchMatcher`, pure, deterministic)

Observation + watcher + `seen` → `Finding?` with a fingerprint and a `because`. New-since-seen
semantics (a show date, a final score, a headline id are each told once). Thresholds are rules, not
model judgement: inside the radius, after the watcher was made, not older than the source's staleness
bound. An expectation matches by the wearer's own words plus the sender/subject tokens they gave,
and reports *where* it matched; a weak match is said as "this might be the letter you meant".

### Cadence (`WatchCadence`, pure)

Each kind proposes its next check: a fixture watcher schedules around kickoff (before, half-time,
expected end + margin, then a final-score retry); show and news watchers a few times a day; an
expectation when its sources change (digest refresh, calendar/reminder change, gateway event) plus
daily. Cadence is a wish; the runner checks what is due whenever it gets the chance.

### Delivery (`WatchDeliveryPolicy`, pure)

Reuses `MyDayDeliveryPolicy`'s context (quiet hours, presence, busy, protected data) and GN's
rules: no speech in a meeting or live session; **≤ 3 unprompted spoken findings a day across all
watchers, ≥ 60 min apart** (decision 6); each finding carries a time-to-live (half-time score: until
full time; a show announcement: a day; a news item: 2 h) and is dropped when it lapses. Allowed →
`agentNotificationQueue.enqueue` at a mapped `NotificationPriority`; otherwise a digest entry. Phone-
only wearers (no glasses) get a local notification in place of speech.

### Wording

A deterministic `WatchPhraser` floor from typed fields ("Full time: Blues 24, Chiefs 17.") is the
default and costs nothing. A model rewrite is optional and off by default — a watcher check never
needs a model call.

### The runner and when it runs

`WatchRunner.runDue(now:budget:)` — one entry point, called from:

1. **Alive:** an `AgentScheduler` typed task (like goal check-ins) — never a model prompt.
2. **Foreground and wake-word catch-up:** on becoming active, and right after a wake word, run what
   is overdue (cheap; bounded to a few seconds).
3. **iOS background refresh** (P2): one `BGAppRefreshTask` identifier shared with GN's pass through
   a single `BackgroundRefreshCoordinator` — whichever plan lands first builds it, the other plugs in.
   Hard ~25 s budget, cancellation honoured, cloud-free (watchers need no model). iOS decides when.
4. **Location wakes** (P2): significant-location-change (or region exit around home) re-evaluates
   `.localNews` watchers for the new area.

What each can promise is written into the watcher's confirmation and screen (see Outcome): the
final score and "a show was announced today" are realistic in the background; half-time and
minute-level news are only realistic while the app is alive.

### Suggestions — notice, then offer (`WatchSuggester`, pure)

Inputs, all on the device: repeated asks in recent conversations (the same team/artist/topic ≥ 3
times in 14 days, from the tool-call trail, not transcripts), GG memory facts in preferences/places,
and on-device library play counts (top artists over 30 days). Output: at most one suggestion a day,
with a `because`, delivered through `WatchDeliveryPolicy` as a question. Yes → a watcher with
`origin: .acceptedSuggestion`; no → that subject is not offered again for 90 days; "stop suggesting
these" turns suggestions off. Suggestions are Agent-Mode-gated (decision 1); a watcher the wearer
asks for directly is not.

### Expectations and digging

`Expectation { text, senderHints, subjectHints, sources, expiresAt }`. "I'm waiting on…" and IW goal
steps phrased as waiting ("wait for the quote from the plumber") create one. Sources in order of
availability: calendar, reminders, the gateway's events (P3), mail (P4). Digging is the same matcher
run on demand: "is there anything about reference 48-2211?" searches the readable sources for the
token and reports matches with where they were found — never a guess at what the reference is.

### Gates and modes

- **HIPAA mode:** watchers off (every source is public-web egress, as `WebSearchTool`); expectations
  over calendar/reminders still work.
- **Local-only mode:** sources blocked (`blockedWhenLocalOnly`); expectations over local sources only.
- **Organisation profile** can pin watchers and suggestions off.
- **Power:** no background checks under `reserve`; `conserve` halves cadence.
- **Privacy copy and `PrivacyInfo.xcprivacy`:** each new route is disclosed in the same PR — the
  source learns the team/artist/area being watched, nothing else.

## Phases (one PR each)

**P0 — Watcher core (headless).** `Watcher`/`WatcherKind`/`Observation`/`Finding`, `WatcherStore`
(+ `DataStoreRegistry`), `WatchMatcher`, `WatchCadence`, `WatchDeliveryPolicy`, `WatchPhraser`,
`WatchRunner` with an injected clock and fake sources; the `watch` tool (add / list / pause / remove /
"why did you tell me"); the alive-only typed scheduler task; activity-trail entries. First real
source: `.topic` over the existing news RSS (locale taken from the device, not fixed US). Tests:
matcher dedupe and staleness, cadence around a kickoff, delivery caps/quiet hours/TTL drop, phraser
floor, store round-trip and erasure.

**P1 — Sources.** Fixtures/scores, artist shows, local news by `CoarseArea`, official alerts where a
region publishes a feed; each a declared route + pure parser + recorded fixtures; the Watching screen
in Settings with honest timing copy. Provider choice per decisions 2–4; privacy copy + manifest.

**P2 — Background.** `BackgroundRefreshCoordinator` (`BGAppRefreshTask`, `fetch` mode,
`BGTaskSchedulerPermittedIdentifiers`), significant-location-change wakes, foreground/wake-word
catch-up. Pure budget/cancellation logic tested headless; **device pass owed** (a fixture's final
score heard after a locked evening; a show watcher firing on a morning unlock).

**P3 — Suggestions and expectations.** `WatchSuggester` (repeated asks, memory facts, library play
counts), the 90-day decline memory, `Expectation` over calendar, reminders and gateway events, IW
"waiting" steps, and on-demand digging over those sources.

**P4 — Read-only mail.** One mail route per decision 5, as an IX read-only integration (read, never
send, never delete); expectations and digging gain mail as a source; the mail credential lives in the
keychain; HIPAA keeps it off.

## Later: always-on

A watcher that must fire at a given minute regardless of the phone needs a process that is always
running and a way to wake the phone: the gateway or Avenkin Office running the same watcher kinds,
and a push sender (APNs entitlement + a server-held key). That is its own plan, an **addition** to the
phone tier, never a prerequisite for it — every watcher in this plan works phone-only.

## Risks

- **Over-promising timing.** iOS background refresh is opportunistic and often silent overnight. The
  defence is the per-kind promise in the copy, and P2's device pass measuring what actually arrives.
- **Nagging.** Global daily cap, spacing, TTL drop, one suggestion a day, 90-day decline memory.
- **Source terms and rate limits.** Choose providers whose terms allow alerting use; cache; back off;
  a source failing quietly degrades to "I couldn't check the Blues score" on request, never a wrong one.
- **Interest leakage.** Queries reveal interests to the source; disclose per route, send coarse
  area only, and keep the watcher list on the device.
- **Expectation false positives.** A weak match is said as "might be"; a match always names where.

## Decisions for Greig

1. **Agent Mode gate.** *Recommend:* a watcher the wearer asks for works without Agent Mode (like a
   reminder or geofence); suggestions and expectations-from-goals need Agent Mode.
2. **Sports data.** One provider that covers NZ/AU codes (rugby, league, netball, cricket) with terms
   that permit alerts, or web search as a fallback only. *Recommend* deciding at P1 from a short
   terms-and-coverage comparison.
3. **Concert/show data.** A public event-listing API with a free tier. *Recommend* one provider, with
   the radius in kilometres and default 50 km.
4. **Hyper-local scope.** *Recommend* local news for the suburb plus official emergency/civil-defence
   feeds only — no police-scanner or crime-report aggregators (accuracy and bystander privacy).
5. **Mail route (P4).** IMAP with an app password (any provider, no third-party assessment, clunkier
   setup) vs Gmail's read-only API (smooth sign-in, but a restricted scope that needs Google's
   security assessment before broad release — confirm the current policy) vs mail read on the gateway
   only. *Recommend* IMAP first.
6. **Daily cap.** *Recommend* 3 spoken findings a day, ≥ 60 min apart, the rest in the digest.
7. **Always-on tier.** *Recommend* a separate plan after P2's device pass shows what the phone tier
   delivers.

## Out of scope

Inferring watchers without asking; reading other apps' notifications (iOS does not allow it);
live play-by-play; ticket purchase; scanner/crime feeds; any model call on a routine check; the
always-on tier (see above).
