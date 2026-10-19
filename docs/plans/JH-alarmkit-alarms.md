# Plan JH — A Real Alarm (AlarmKit)

**Status:** ✅ Built 2026-10-19 (with the round-4 tester fixes) — `set_alarm` schedules an AlarmKit
alarm first and falls back to its old local notification only when the alarm permission is refused;
every string the model reads says which it got and that neither is in the Clock app.
**Owed (device):** the permission prompt on first use; an alarm ringing through silent mode with the
phone locked; the Stop button; `list` after a relaunch (labels come from `AlarmLabelStore`); the
fallback wording with the permission refused; the App Review usage string.
**Related:** `set_timer` (still a notification), `reminder` (Apple Reminders, with an alert at the
time), Plan [CJ](CJ-survey-hardening-sweep.md) item 2 (relative times).

## Why

A tester asked for an alarm at seven, was told it was set, asked whether he would see it in the
Clock app, was told yes, found nothing there, and asked the assistant not to claim an alarm it had
not set. The tool had done exactly what it does — scheduled a time-sensitive local notification —
and nothing it said to the model distinguished that from an alarm. A notification does not ring on
a silenced phone and no Apple app lists it.

Apple offers no API for an alarm in the Clock app. What it offers, from iOS 26, is AlarmKit: an
alarm the app owns that the system rings like a Clock alarm — full-screen on the lock screen,
through silent mode and Focus, with a Stop button the system draws. The app's minimum is iOS 26.

## What was built

- **`AlarmScheduler`** (seam): `authorize()`, `schedule(_:)`, `pending()`, `cancelAll()`. Two
  implementations — `AlarmKitScheduler` (iOS 26.1 — the alert-only presentation initialiser is new there; 26.0 falls back to the notification — `AlarmManager.shared`, a fixed-date schedule, an
  alert-only presentation so no widget extension is required) and `NotificationAlarmScheduler`
  (the old path, moved out of the tool). `AlarmSchedulers.realAlarm` is nil where AlarmKit is not
  available, which sends the tool straight to the notification.
- **`AlarmBackendChoice.decide(authorization:)`** (pure): authorized → AlarmKit; denied → the
  notification with `permissionDenied`; unavailable → the notification with `unavailable`. An
  AlarmKit refusal after authorization (`maximumLimitReached`, an error) → `schedulingFailed`.
- **`AlarmTool`** takes both backends (tests inject fakes and a fixed "now"); `resolveDate` is
  pure. `Wording`: a real alarm is described as ringing "like a Clock alarm, even on silent, with a
  Stop button"; the fallback says it is a notification, that it will not sound on silent, and why;
  both end with "It is NOT an alarm in the iPhone's Clock app and never appears there", which the
  tool's description carries too, with "never say it is in the Clock app" and the Clock app / Siri
  route for a wearer who wants one there.
- **`AlarmLabelStore`**: AlarmKit's `Alarm` carries no title, so labels are kept by id in
  `UserDefaults` for `list`, pruned to the alarms still scheduled.
- **`NSAlarmKitUsageDescription`** in `Info.plist` (AlarmKit refuses to schedule without it);
  `AlarmToolTests` guards it.

## Not built

- A countdown presentation (the Live Activity on the lock screen before the alarm) — it requires
  the widget extension to render `AlarmAttributes` and is a separate piece of work.
- Repeating alarms (`Alarm.Schedule.Relative` with weekdays): the tool's arguments are one-shot.
- Moving `set_timer` to AlarmKit's timer form.
