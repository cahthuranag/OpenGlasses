# Plan JD — Podcasts by Name, in Apple Podcasts

**Status:** ✅ Shipped 2026-10-18 — `play_podcast`: "play the latest episode of The Daily" looks the
show up in Apple's public podcast directory, picks the episode, and opens it in the Podcasts app;
the same PR lets `open_app` open Tidal and Amazon Music and frees it from the fifty-scheme cap.
**Owed:** device checks — that the episode link opens Podcasts and starts playing rather than
landing on the episode page; a phone without Podcasts installed says so; a temple tap pauses what
Podcasts is playing after the hand-off; the lookup is refused under Medical Local Only.
**Extends:** `music_control` (Plan [GS](GS-spotify-control.md)), `open_app`.
**Related:** Plan [CH](CH-media-button-trigger.md) / [GJ](GJ-remappable-temple-gestures.md)
(temple taps keep working on whatever is playing), `DiscoverCapabilitiesTool`.

---

## Trigger

A wearer asked whether the assistant plays Spotify, Tidal, Amazon Music or Apple Podcasts. Music
is answered by Plan GS (Apple Music and Home Assistant speakers; Spotify's policy forbids voice
control). Podcasts had nothing: `open_app` could launch the Podcasts app and that was all. "Play
the latest episode of …" is the obvious glasses request — hands busy, phone in a pocket.

## What exists today (verified 2026-10-18)

- `open_app` opened apps by URL scheme after a `canOpenURL` pre-check, which iOS answers only for
  the first fifty `LSApplicationQueriesSchemes`; the plist was exactly at fifty.
- `music_control` drives Apple Music through `SystemMusicPlayer` and Home Assistant media players.
  Neither can play a podcast: `MPMusicPlayerController` reaches the Music app only.
- Apple publishes no API that plays a show in Podcasts from another app. What it does publish is
  the podcast directory (search and lookup, no key) and universal links on `podcasts.apple.com`,
  which the Podcasts app claims.

## Decision 1 — hand off, never host

The alternative was to fetch the show's RSS feed and play the episode inside Avenkin with
`AVPlayer`. Rejected: the app would then own Now Playing and fight the temple-tap claim
(`MediaTriggerService`), need its own transport, queue and resume state, and duplicate an app
every iPhone already has. Opening the episode in Podcasts keeps playback where the wearer's
subscriptions, downloads and position already live. The cost is honesty about transport: Avenkin
cannot pause or skip Podcasts, and the tool's description says so.

## Design (shipped)

**Core, pure, tested headlessly:**

- `PodcastRequestParser` — the words → `PodcastRequest(show:, episode:)`. Leads ("play", "the
  latest episode of", "an episode of"), a trailing "podcast", "about …" → `.about(topic)`. The
  model's `episode` argument ("latest", or words) wins over words in the query.
- `PodcastDirectoryParser` — the directory's JSON → `PodcastShow` / `PodcastEpisode`; keeps only
  `kind == podcast` / `podcast-episode` rows, reads ISO-8601 dates with and without fractions.
- `PodcastRanker` — an exact title (case, accents, leading "the", trailing "podcast" ignored) beats
  the directory's first result; the newest episode for "latest" and for nothing said; for
  "about …", the newest episode whose title or notes carry every topic word, then any word, then
  the newest with `matchedTopic == false` so the reply says so.
- `PodcastDeepLink.openable` — only an `https://podcasts.apple.com/…` page is ever handed to the
  system; a URL on any other host from the JSON is refused. Opening uses
  `UIApplication.open(_:options: [.universalLinksOnly: true])`, so a phone without Podcasts
  returns `false` and the tool says the app is missing instead of falling into Safari.

**Edge:** `AppleLookupPodcastDirectory` (`PodcastDirectorySearching`) over the search and lookup
endpoints, `MedicalEgressGuard.check(.podcastDirectory)` before every request. New
`NetworkRoute.podcastDirectory`: `publicWeb`, `promptText` only, blocked under Medical Local Only.

**Tool:** `play_podcast` (`PodcastTool`), actions `play` (query, optional episode) and `search`.
Posts `MediaTriggerService.userPlaybackRequested` before the hand-off, as `music_control` does, so
the temple-tap claimer stands down before Podcasts takes Now Playing. Semantics: external,
best-effort cancellation, intrinsically idempotent. Listed as everyday core, internet-requiring,
untrusted output (titles come from the web), `needsNetwork` offline; Settings → Tools and the
Services screen name it "Podcasts". `music_control`'s description points podcasts here.

**`open_app`:** opens directly and reads success from the completion, so its table no longer
depends on the fifty query schemes; Tidal (`tidal://`) and Amazon Music (`amznmp3://`) join it and
the Discover tool's installed-apps list. Two query schemes nothing opened (`wechat`, `weibo` —
the code uses `weixin` and `sinaweibo`) left the plist to keep the Discover probes within fifty.

## Tests

`PodcastRequestParserTests`, `PodcastRankerTests`, `PodcastDirectoryParserTests` (invented ids and
titles; URL building; only Apple pages openable), `PodcastToolTests` (fake directory and opener:
latest opens the newest episode and stands the trigger down; topic pick; unmatched topic says so;
a foreign host is never opened; no episodes → show page; missing app; unreachable directory;
search opens nothing). `NetworkRouteRegistryTests`, `OfflineToolPolicyTests`,
`ToolEffectClassificationTests` and `JobAheadTests` (fifty schemes) cover the wiring.

## Risks

- **Autoplay is unverified.** A `podcasts.apple.com` episode link opens the episode in Podcasts;
  whether playback starts without a tap is a device check. If it does not, the reply wording
  ("Opening … in Podcasts") is still true, and a follow-up may look at the Podcasts app's
  `?action=play`-style parameters, none of which Apple documents.
- **Directory ranking** is Apple's; the exact-title rule covers the common miss. Region comes
  from the phone's locale.

## Out of scope

Pausing, skipping or reading Podcasts' playback (no API); other podcast apps; playing inside
Avenkin; Spotify (Plan GS Decision 1 stands).
