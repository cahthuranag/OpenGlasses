# Plan II — Glasses Status on the Home-Screen Widget

**Status:** ✅ Shipped 2026-10-15 — snapshot, writer, presentation core, timeline and views built and tested headless. Device-pending: the widget refreshing within seconds of a connect/disconnect with the app in the background, and the stale entry appearing after a force-quit with glasses connected. See *As built* below.
**Origin:** A 2026-10-14 comparison with another companion app for the same glasses, whose
home-screen widget and quick-settings tile lead with the state of the glasses. Ours leads with the
wake word and says nothing about the glasses at all.
**Related:** Plan [HX](HX-glasses-link-and-device-state.md) (the one truth for "connected", battery
only while connected), Plan [FY](FY-rename-to-avenkin.md) (brand, accent), the
`GlassesActivityWidget` extension (Live Activity, home widget, the two controls).
One PR. Pure presentation core first; the extension edge is thin.

## The gap

`OpenGlassesHomeWidget` (`GlassesActivityWidget/HomeScreenWidget.swift`) reads one value,
`SharedAppState.isListening`. Its status dot is green when listening is on, not when glasses are
connected. Its gallery description says "Glasses status and a quick Listen toggle", and it shows no
glasses status. It refreshes on a listening change or every 15 minutes, never on a glasses change.

The app already knows everything the widget needs. `GlassesConnectionService` folds the SDK's
state into `GlassesConnectionPhase` (`noGlassesAdded` / `addedDisconnected` / `connecting` /
`connected`), the device name, the live battery (only while connected) and the charging state.
`AppState.applyGlassesUse()` is the one writer of `glassesPhase`, `glassesStoodDown` and
`isConnected`. The Live Activity carries connection and battery. The widget is simply never told.

The two Control Centre / Action Button controls (`ListeningControlWidget`,
`AskAvenkinControlWidget`) are already more than the comparison app offers, and App Shortcuts cover
its launcher shortcuts. This plan does not touch them.

## Outcome

A wearer who glances at the home screen sees whether the glasses are connected, connecting, not
connected, paused, or not added yet, and the battery when it is a live reading, beside the existing
Listen toggle and quick actions. The widget never shows a connected state or a battery figure that
the app has not recently confirmed.

## Design

### Shared snapshot

`SharedAppState` gains a small `Codable` value, `WidgetGlassesSnapshot`, stored under one App Group
key:

| Field | Source | Notes |
|---|---|---|
| `phase` | `glassesUse.link` | `GlassesConnectionPhase` mirrored as a plain string enum the extension can decode |
| `stoodDown` | `glassesUse.stoodDown` | Connected link, deliberately out of use (Disconnect, `GlassesSleepPolicy`) |
| `deviceName` | `GlassesConnectionService.deviceName` | Only while connected or connecting |
| `battery` | `GlassesConnectionService.batteryLevel` | Nil unless connected. Never a remembered value |
| `charging` | `GlassesConnectionService.isCharging` | Only while connected |
| `writtenAt` | wall clock | How old the snapshot is |

The app writes it from `applyGlassesUse()` (only when it changes) and when the live battery or
charging state changes, then calls `WidgetCenter.shared.reloadTimelines(ofKind:)` for the home
widget only. Writes are coalesced so a burst of battery updates is one reload, not ten; WidgetKit
budgets reloads.

The key name is a storage identifier and goes into `StorageIdentifierGuardTests` the day it ships.

### Presentation core (pure, headless-tested)

`WidgetGlassesPresentation.render(snapshot:now:) -> WidgetGlassesLine` decides the words, symbol and
tone. It compiles into the extension and the test target.

- `noGlassesAdded` → "No glasses added". No battery.
- `addedDisconnected` → "Glasses not connected". No battery.
- `connecting` → "Connecting…".
- `connected`, `stoodDown` → "Glasses paused".
- `connected` → "Connected" plus "· 72%" when `battery` is present, with a charging glyph when
  charging.
- No snapshot yet (fresh install, never written) → the same as `noGlassesAdded` when
  `Config.glassesAdded` was never set, otherwise "Glasses not connected".

**Staleness.** A widget renders out of process and cannot know whether the app is still alive. A
"Connected · 72%" written by an app the system has since killed would be a lie the widget keeps
telling. So the timeline provider emits two entries per snapshot: one at `writtenAt` with the live
line, and one at `writtenAt + staleAfter` in which any `connected` or `connecting` snapshot becomes
"Last seen connected 14:02" with no battery. `staleAfter` is a constant in the core (proposed 20
minutes, see open questions). The app's next write replaces both entries.

### Views

- **Small:** the glasses line replaces the listening caption; the Listen button stays. The dot
  follows the glasses (connected = accent, otherwise neutral), and listening moves to the button's
  own on/off state, which it already shows.
- **Medium:** the glasses line and battery on the left, Listen and Photo on the right as today.
  Photo is dimmed when the glasses are not connected (the deep link still opens the app, which
  explains).
- **Large:** a glasses row at the top (name, line, battery), then Listen, then the three quick
  actions.
- The widget description says what it now shows.
- Text is written as string literals, like the widget's existing text, so it localises with it. No plan letters
  in rendered text.

### What this plan deliberately leaves out

- **Case battery.** DAT does not report it.
- **A remembered battery while the glasses sleep or sit in the case.** The comparison app shows the
  last reading. Our rule (Plan HX) is that battery is shown only while connected, never stale.
- **A latest-photo tile.** The wearer's own photos are unfiltered by product decision
  (`capturePhoto()`), so a home-screen thumbnail could show a bystander's face to anyone who sees
  the phone. If wanted, that is a separate opt-in decision.
- **A tap that reconnects.** A widget button runs an App Intent in the extension. Reconnecting
  means the app's `GlassesConnectionService`, which an extension cannot drive. The tap opens the
  app, as it does today.
- **A glasses-status Control.** A Control could show the same line through a value provider. Worth
  doing only if wearers ask; the Control Centre slots are scarce and both current controls act.

## Tests

- `WidgetGlassesPresentationTests`: every phase × stood-down × battery present/absent × charging;
  the never-written snapshot; the stale entry for `connected` and `connecting`, and that
  `addedDisconnected` / `noGlassesAdded` are not aged (they do not claim anything live).
- Snapshot round-trip through `Codable`, and decoding a snapshot with an unknown phase string as
  "not connected" rather than failing.
- A writer test with an injected store: no write when nothing changed; a battery burst coalesces.
- `StorageIdentifierGuardTests` gains the new key.

**Device-pending:** the widget refreshes within a few seconds of connect/disconnect while the app
runs in the background; the stale entry appears after the app is force-quit with glasses connected.

## Open questions

1. `staleAfter`: 20 minutes, or shorter? Shorter is more honest after a kill, but the app may be
   alive in the background and simply have had nothing to say.
2. Should the Photo quick action hide rather than dim when the glasses are not connected?
3. Does the Live Activity want the same stood-down ("paused") wording? Today it only knows
   connected or not.

## As built (2026-10-15)

- `WidgetGlassesSnapshot`, `WidgetGlassesLine` and `WidgetGlassesPresentation` live in
  `OpenGlasses/Sources/Shared/WidgetGlassesStatus.swift`, compiled into the app (and so the tests)
  and the widget extension, like `LockScreenActivityLayout`. The App Group key is
  `widgetGlassesSnapshot`; it and the widget kind are pinned in `StorageIdentifierGuardTests`.
- `WidgetGlassesStatusWriter` (app only) takes the reading at the end of a 1.5 s window rather than
  when asked, because the service publishes in `willSet`. The first reading after launch is always
  written, since whatever the App Group holds was stamped by an earlier run.
- **Open question 1, answered for now:** `staleAfter` is 45 minutes, and a running app re-stamps an
  unchanged live snapshot once it is 30 minutes old (checked every 10, so by 40 minutes at the
  latest), so an app that is alive but has nothing new to say is not shown as gone.
- **WidgetKit's reload budget.** An app in the background, which this one mostly is, gets a few
  dozen widget reloads a day, and once they are spent reloads are dropped and the widget ages out
  to "Last seen connected" while the glasses are on. So every write is a reload worth spending:
  phase, paused, name and charging write at once, but the battery writes only when it has moved 5
  points from the value last written, crossed 20% or 10% (either way), or appeared or gone. The
  widget shows the battery as last written, a few points behind at most. While connected that is
  about two re-stamps and about two battery steps an hour, and a re-stamp only in an hour with
  nothing else to write.
- **Open question 2:** Photo is dimmed, not hidden, as drafted. Paused glasses dim it too.
- A link that reads "never added" for someone the app knows has added glasses (`Config.glassesAdded`)
  is written as "not connected", matching the app. Before the app has written anything the
  extension cannot read `Config.glassesAdded`, so the never-written case shows "No glasses added"
  until the first launch of this build.
- The widget's rendered glasses words come from the core as strings (the house pattern for
  pure presentation); the widget extension has no string catalog of its own yet.
- The timeline keeps its 15-minute refresh: the app changes listening without reloading the widget.
