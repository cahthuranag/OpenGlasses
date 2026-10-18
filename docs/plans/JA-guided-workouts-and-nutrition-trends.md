# Plan JA — Guided Workouts and Nutrition Trends (coaching that keeps time, meals that add up)

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
**Extends:** `FitnessCoachingTool` (`fitness_coach`), `FoodAnalysisTool` (`analyze_food`) and the
`QuickVisionMode.health` prompt, `HealthSummaryTool` (Plan [GI](GI-health-summaries.md): reader seam,
cache, delivery policy, phraser), `LocationService`, `PedometerTool`.
**Reuses:** `ScanAssistPolicy` (clock-driven cue machine, Plan [FB](FB-scan-assist.md)),
`NavigationCuePolicy`/`DistanceFormatter` (Plan [CA](CA-walking-navigation.md)), `MotionActivityProvider`
(Plan [W](W-presence-aware-agent-throttle.md)), `StructuredVisionService` (schema-validated vision).
**Related:** Plan [GM](GM-watch-map-and-list-surfaces.md) P3 (a watch `HKWorkoutSession` — the
watch half of a guided workout, not built), Plan [GL](GL-cycling-driving-navigation-and-road-alerts.md)
P2 (the `location` background mode — the same gap bites here), Plan [DY](DY-my-day-everyday-briefing.md)
(My Day sources), Plan [B](B-personal-health-vault.md) (`dietary_context` in the health vault), Plan
[AB](health-safety-advisor.md) (`can_i_eat` — safety, not nutrition).

---

## Trigger

**Workouts.** `fitness_coach start_workout` records a start time in a static and says "Workout
started." Nothing is spoken during the run: no split, no pace, no "halfway", no interval change.
`stop_workout` writes a `HKWorkoutBuilder` workout with one energy sample from `MET × 70 kg × hours`
(the weight is a constant) and no distance, route or heart rate, then saves a note. A wearer with
glasses on a run has the best possible coaching surface and gets a stopwatch.

**Nutrition.** `analyze_food` returns a sentence telling the wearer to take a photo. The actual
analysis is a free-text vision prompt asking for calories and macros "conversational for TTS"; the
nutrition persona's prompt says to "accumulate a daily running total" and the total lives in the
conversation until it is forgotten. Nothing is parsed, nothing is saved, no `HKQuantityTypeIdentifier.dietary*`
sample is written anywhere, and `health_summary` cannot say what the wearer ate.

## Outcome

- "Start a 30-minute easy run" → "Starting. I'll give you your pace every kilometre." … "One
  kilometre, five twelve. Heart rate one forty-eight." … "Halfway." … "Last two minutes." …
  "Done: five point six k in thirty minutes, average five twenty. Saved to Health."
- "Start intervals: eight times one minute hard, one minute easy" → a cue at each change, with a
  tone first so it lands over music, and the count ("Hard. Three of eight.").
- "Pause" / "resume" / "stop" / "how am I doing?" by voice, temple tap mapped to pause (Plan
  [GJ](GJ-remappable-temple-gestures.md)), cues yield to a navigation cue or a call.
- Saved to Health as a workout with distance, route, energy and the heart-rate samples Health already
  has from the wearer's watch (never synthesised).
- "What did I eat?" after a day of "log this" photos → "About eighteen hundred calories so far,
  ninety grams of protein. Lunch was the biggest, around seven hundred." Logged meals are written
  to Health as dietary energy, protein, carbohydrate and fat samples (opt-in), and `health_summary`
  gains `nutrition` and a seven-day trend ("your protein has been under a hundred grams five days
  running"). Every number is the model's estimate and is said so; a label read with the camera is
  preferred to an estimate when there is one.
- My Day's evening slot can include one nutrition or workout line when the wearer enables it.

## What exists today (verified 2026-10-18)

- `FitnessCoachingTool` (485 lines): `start_workout, stop_workout, log_exercise, check_form,
  workout_history, step_goal`; `private static var activeWorkout: ActiveWorkout?` (in memory, lost on
  relaunch, one per process); MET table (running 9.8, cycling 7.5, walking 3.5…); `HKWorkoutBuilder`
  with one `activeEnergyBurned` sample; `workout_history` reads 7 days gated on
  `Config.shareHealthDataWithAI` (default false — it just refuses); `step_goal` in UserDefaults that
  nothing reads; `PoseAnalyzer` over one still. `ToolPermissionGate` asks for *read* steps/energy,
  which does not match what the tool does. Tests: two `FeatureHonestyTests` on `check_form`; nothing
  on the session, MET or save.
- `PedometerTool` (`step_count`): one `CMPedometer.queryPedometerData` for today; no live updates.
  `LocationService`: 100 m default, `beginPrecisionGuidance()` → Best / 3 m / `.fitness`; **does not
  accumulate distance; nothing reads `CLLocation.speed`**; no `allowsBackgroundLocationUpdates`.
  `MotionActivityProvider` → `MotionSample { kind: walking/running/cycling/…, confidence }`.
- HealthKit: entitlement declared (`project.base.yml`, committed + personal entitlements,
  `HealthEntitlementGuardTests` pins the usage strings to the read types); reads heartRate,
  restingHeartRate, sleepAnalysis, stepCount, workouts, energy statistics; writes workoutType and
  activeEnergyBurned; **no dietary types, no distance types, no `HKWorkoutRouteBuilder`, no
  `HKLiveWorkoutBuilder`/`HKWorkoutSession`**. `NSHealthUpdateUsageDescription` mentions workouts
  only. GI's `HealthSampleReading` seam + `HealthKitSampleReader` + `HealthSummaryCache` (24 h,
  Application Support) + `HealthSummaryDeliveryPolicy` (speak-direct, on-device-only) + phraser;
  GI excluded writes, workouts, trends and background delivery on purpose. Reads throw
  `protectedDataUnavailable` when locked.
- Food: `FoodAnalysisTool` is a 35-line canned reply; `QuickVisionMode.health.prompt` (free text:
  kcal/protein/fat/carbs per item) via `capturePhotoAndSend`; `preset-nutrition-analyzer` persona;
  `HealthVault dietary_context.md` holds allergies and preferences, no targets; `HealthSafetyTool
  can_i_eat` is an interaction check. No structured result, no store, no tests.
- Cue machinery to reuse: `ScanAssistPolicy` (monotonic clock seam, generation counter, pause
  keeps remaining, `nextWakeDeadline`), `ScanAssistCueGate` (defers while the wearer, assistant or
  VoiceOver is speaking; drops stale after 10 s), `ScanAssistSpeaking` protocol on
  `TextToSpeechService` (`speakCue`, `playTone`), `CPRMetronome` (catch-up ticks),
  `NavigationCuePolicy` (approach/imminent once per step), `DistanceFormatter.spoken`.
  **Every new utterance cancels the one playing**; `SpeechUrgency.high` prefixes "Important:".
- Background: `UIBackgroundModes` = audio, bluetooth-central, external-accessory; the process stays
  alive through the audio engine; with when-in-use location, fixes stop in the background
  (`LocationService.awaitFix` comment); `PresenceEvaluator` → `.away` when backgrounded, which pauses
  `LoopThrottle` loops; Scan Assist pauses on background by design. GL P2 plans the `location` mode
  and `allowsBackgroundLocationUpdates` only while guiding, with `BackgroundLocationLifecycleTests`.
- Watch: a remote only; **no HealthKit entitlement, no workout session, no location** on the watch
  target. GM P3 plans `startWatchApp(toHandle:)` + `WatchWorkoutController`, not built.
- My Day: adding a source means a `MyDaySource` case, a protocol, an `MyDayInputs` field, a
  `MyDaySourceSelection` flag, a composer rank and a `MyDayKind` (exhaustive icon switches).
  Digest: `DigestSource` exhaustive. No health source anywhere in My Day.
- `AIFeatureRegistry`: `fitnessCoaching` (switch `fitnessCoachingEnabled`, "erasure unavailable —
  workouts belong to Apple Health"); `healthSummaries`; `healthVault`. `analyze_food` has **no
  feature record and no store**.

## Design

### Part A — Guided workouts

**`WorkoutPlan` (pure).** `{ activity: .run | .cycle | .walk, mode: .steady(duration?|distance?) |
.intervals([Segment]) , cues: CueSchedule }`. `Segment { kind: .hard | .easy | .warmup | .cooldown,
duration | distance }`. `WorkoutPlanParser` (pure, deterministic) turns the common spoken forms into
a plan: "30-minute easy run", "5 k", "8 by 1 minute hard 1 minute easy", "warm up 5 then 20 at
tempo"; anything it cannot parse is handed to the model with the plan's JSON schema (one
`completeStructured` call), then validated by the same parser rules (segment count ≤ 40, total ≤ 4 h,
no zero segments). The model never drives the clock.

**`WorkoutSession` (pure state machine, `ScanAssistPolicy`'s shape).** States `ready → running →
paused → ended(reason)`; events `start, pause, resume, stop, fix(location), hr(sample), tick,
segmentBoundary`; outputs `cue(WorkoutCue, generation)`, `tone`, `segmentChanged`, `summary`. Clock
is an injected monotonic `now`. Pause keeps elapsed and distance; resume does not back-fill. Auto-pause
when speed < 0.5 m/s for 20 s (toggle), auto-resume on movement. Ends on `stop`, plan complete, or 60
min without a fix/movement.

**`WorkoutMetrics` (pure).** Distance from fixes with accuracy ≤ 20 m, speed filtered (median of the
last 3 fixes; `CLLocation.speed` used when ≥ 0 and the fix is fresh), rolling pace (last 200 m), split
pace per kilometre or mile (`Config.navigationUnits`), elapsed, heart rate (latest sample ≤ 15 s old
from GI's reader; absent → not spoken, never estimated), energy by MET × **body mass from Health**
(`HKQuantityTypeIdentifier.bodyMass`, read; the 70 kg constant goes), falling back to the constant
with a one-time spoken note.

**`CueSchedule` and `WorkoutCuePhraser` (pure).** Distance cues at each unit ("One kilometre, five
twelve"), time cues (halfway, last two minutes, last 30 s), interval boundaries (tone, then "Hard.
Three of eight."), heart rate every other distance cue when available, zone words only when the
wearer has set a target ("above your target"). Phrases ≤ 12 words; numbers spoken as pace, not
decimals. `WorkoutCueGate` = `ScanAssistCueGate` generalised: defer while speaking, drop stale after
8 s, **yield to a navigation cue** (a `navigate` route may be active: CA's imminent cue wins, the
workout cue is dropped, not queued) and to a call (`ScanAssistPauseReason.call` → session pauses).

**Live edge (`GuidedWorkoutService`, `@MainActor`).** Starts `LocationService.beginPrecisionGuidance()`,
subscribes `$currentLocation` and `MotionActivityProvider`, polls the heart-rate reader every 10 s
(foreground only; the cache tells it when a sample is stale), drives the session on a 1 s `Timer`,
speaks cues through `ScanAssistSpeaking`, shows the HUD line ("5.2 km · 5:14 · ♥148"), and on end
builds the Health workout: `HKWorkoutBuilder` with `distanceWalkingRunning`/`distanceCycling`
samples per split, `activeEnergyBurned`, a route via `HKWorkoutRouteBuilder` from the accepted
fixes, metadata `HKMetadataKeyIndoorWorkout = false`; heart rate is **not** written (Health already
has it from the wearer's watch; writing a copy would double-count). Save requires the Health
write permission for the two distance types (`NSHealthUpdateUsageDescription` rewritten;
`HealthEntitlementGuardTests` updated). On failure the summary is still spoken and kept in the
activity trail (Plan [IW](IW-goals-and-activity-trail.md)) with "couldn't save to Health".

**Background.** Phase 1 is honest about the gap: a guided workout runs while the process is alive
(the audio engine keeps it alive; cues are audio) **but location fixes stop when the phone locks
with when-in-use permission**, so distance would freeze. Therefore P1 ships *time-based* coaching
(duration and intervals, heart rate when foreground) and names distance cues as foreground-only;
P2 adopts GL P2's `location` background mode and `allowsBackgroundLocationUpdates` **only while a
session runs** (the same lifecycle test GL names). The watch half (GM P3: `HKWorkoutSession` on the
watch, watch GPS, watch heart rate at 1 Hz) is the better long-term shape and is left to GM.

**Tool.** `fitness_coach` gains `start_guided` (`plan` text, `activity`), `pause`, `resume`,
`status` ("how am I doing"), and `stop` folds into the guided session when one is running;
`start_workout`/`stop_workout` keep today's behaviour for gym sessions. `ToolPermissionGate` is
corrected to the permissions the tool actually uses. A GJ temple-tap action `pause_workout`.
Semantics stay `.local()`; `physicalActuation` is not involved.

### Part B — Nutrition that adds up

**`MealEstimate` (schema).** A `meal_read` `AssessmentSchema` replaces the free-text health prompt:
`{ items: [{ name, portion, kcal, protein_g, carbs_g, fat_g, confidence }], source: .estimate |
.label , labelText? }`. When a nutrition label is in frame the schema asks for the label's figures
and the serving count rather than an estimate (`source: .label`). Confidence floor 0.4; a card
below it is spoken as "roughly" and not logged unless the wearer says "log it anyway".

**`MealLog` and `NutritionLedger` (pure + store).** `MealEntry { id, at, items, totals, source,
provenance (AIProvenance), note? }` in `MealLogStore` (`Application Support/Nutrition/meals.json`,
`completeUntilFirstUserAuthentication`, backup-excluded, 90-day retention, `DataStoreRegistry`
entry with `deleteAll`, a `SensitiveStore.mealLog` of class health). `NutritionLedger` (pure)
computes day totals, meal breakdown, 7- and 28-day averages, and a `Trend` (`.under(target)`,
`.over`, `.steady`) per nutrient against **targets the wearer sets** (`Config.nutritionTargets`,
none by default — no target, no judgement). `NutritionPhraser` (pure, GI style): "about eighteen
hundred calories so far, ninety grams of protein; lunch was the biggest at around seven hundred";
always "about"; never a verdict on the food.

**Health writes (opt-in).** `HealthNutritionWriter` behind a seam: `dietaryEnergyConsumed`,
`dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal` samples per logged meal, metadata
`HKMetadataKeyFoodType` = item names, `HKMetadataKeyWasUserEntered = false`. Off by default
(`Config.nutritionWritesToHealth`); the first "log this" asks once. Deleting a meal deletes its
samples (`HKHealthStore.delete` by the sample UUIDs kept on the entry). Reads for the summary come
from the ledger, not Health, so a wearer who logs in another app is not double-counted here.

**Tool and summary.** `analyze_food` becomes real: `estimate` (default; camera → schema → spoken
estimate), `log` (estimate and append; or `log_last`), `today`, `undo_last`, `targets` (`set`,
`clear`). `health_summary` gains `metric: nutrition` through GI's delivery policy (speak-direct,
on-device-only) and a `trend` phrase. `AIFeatureRegistry` gains `nutritionLogging` (switch, store,
erasure via `MealLogStore.deleteAll`). The nutrition persona's prompt is rewritten to name the tool
and drop the "running total" instruction. `can_i_eat` (Plan AB) stays separate and is **not** fed
by the ledger (safety and nutrition are different questions).

**My Day.** A `health` source (protocol `HealthDaySource { loadHealthLine(now:) }`) producing at
most one `MyDayItem` of kind `.update` in the evening slot: today's workout summary or the
nutrition line, whichever the wearer enabled; `MyDaySourceSelection.healthIncluded` default off.
Delivery through `HealthSummaryDeliveryPolicy` rules (never spoken when protected data is
unavailable).

### Privacy and modes

- A meal photo is a still that leaves the phone → `filteredStill(for: .visionAssessment)` through
  `StructuredVisionService` (roster: `.foodAnalysisTool` case moves from "no camera" to the
  chokepoint). Faces at the table are blurred by the scope.
- HIPAA / Local Only: estimates need the cloud model (local VLM optional via GE's offline tier);
  the ledger and Health writes are local and allowed; `health_summary nutrition` is on-device-only
  as GI already requires. Meal entries honour `Config.hipaaRetentionDays`.
- `PrivacyLog.health(.mealLogged, kcal bucket:)`, `.workoutCue(kind:)`, `.workoutSaved(distance
  bucket:)` — buckets and counts, no food names.
- Not agentic; no Agent Mode gate. Organisation profiles may close both features (`closedTools`).

## Phases (one PR each)

**P0 — Pure core.** `WorkoutPlan` + `WorkoutPlanParser`, `WorkoutSession`, `WorkoutMetrics`,
`CueSchedule` + `WorkoutCuePhraser` + `WorkoutCueGate`; `MealEstimate` schema, `MealEntry`,
`NutritionLedger`, `NutritionPhraser`. Tests: `WorkoutPlanParserTests` (table of 20 phrases;
unparseable → nil), `WorkoutSessionTests` (pause keeps distance; auto-pause/resume; plan-complete
ends; stale generation dropped; nav cue wins), `WorkoutMetricsTests` (accuracy filter, median speed,
split at exactly 1000 m, miles), `WorkoutCuePhraserTests` (exact strings; ≤ 12 words; pace never a
decimal), `NutritionLedgerTests` (day boundary in the wearer's time zone; averages ignore days with
no log; no target → no trend), `NutritionPhraserTests`, `MealReadSchemaTests` (label beats estimate;
floor).

**P1 — Workouts live, time-based.** `GuidedWorkoutService`, tool actions, HUD line, tone + cue
through `ScanAssistSpeaking`, heart rate from the GI reader, Health save with distance types and
route, body mass read, `ToolPermissionGate` fix, `NSHealthUpdateUsageDescription` and
`HealthEntitlementGuardTests`, GJ tap action. Tests: `GuidedWorkoutServiceTests` (fake clock,
fixes, reader, speaker: a 30-min run speaks halfway and last-two; intervals count; a call pauses;
save builds the expected samples), `HealthWorkoutWriterTests` (fake store).

**P2 — Nutrition live.** `analyze_food` real actions, `MealLogStore` + registry + ET matrix,
`HealthNutritionWriter` (opt-in, delete pairs), `health_summary nutrition` + trend, feature record,
persona rewrite, Settings › Health › Nutrition (targets, Health writes, retention). Tests:
`FoodAnalysisToolTests` (fake assess + store: estimate, log, undo, today, label path),
`HealthNutritionWriterTests`, `HealthSummaryToolTests` extension, `DataStoreRegistryTests` /
`AIFeatureRegistryTests` / `OutboundFrameConsumerTests` green.

**P3 — Background location and My Day.** GL P2's `location` mode and `allowsBackgroundLocationUpdates`
scoped to a running session (`BackgroundLocationLifecycleTests` shared with GL), distance cues no
longer foreground-only; the My Day `health` source. Device pass (owed): a 5 k with the phone locked
in a pocket (cue timing, distance vs the watch's own record, battery), an interval session over
music, a meal with a label and one without, and the Health app showing one workout with a route and
four dietary samples per meal.

## Risks

- **Double counting in Health.** Energy and distance from this app plus a watch's own workout for
  the same run. The summary says "saved to Health" and Settings explains the overlap; a wearer with a
  watch can turn saving off (`Config.workoutSavesToHealth`). GM P3 is the proper fix.
- **Nutrition estimates are guesses.** Always "about", label preferred, no targets unless set, and
  the ledger is the wearer's own record to edit or delete. The App Store health-data rules (5.1.3)
  already govern the vault; the same copy applies.
- **Cue clash.** Navigation, calls, the assistant answering and workout cues share one voice; the
  gate's yield rules and ≤ 12-word cues are the defence; tones carry the interval change when words
  cannot.
- **Background.** Until P3 the honest product is time-based coaching; the plan says so in copy.

## Decisions for Greig

1. **Time-based first (P1) and distance in the background at P3** (recommended), or wait for GL P2
   and ship distance from the start?
2. **Heart rate: never write it** (recommended) — or write when no watch workout overlaps?
3. **Nutrition Health writes opt-in** (recommended) or on by default once the wearer logs a meal?
4. **Targets:** wearer-set only (recommended), or offer a default from Health's body mass?
5. **Persona rewrite vs retire** for the nutrition and fitness personas.

## Out of scope

Rep counting or live form coaching from video (`check_form` stays a still), strength-training
progression plans, the watch workout session (GM P3), training-load or recovery scores, food
recognition from a barcode (Plan [IZ](IZ-product-lookup-and-price-alerts.md) identifies products;
feeding its result into a meal is a later link), medication or allergy advice (Plan AB), and
sharing nutrition or workouts with anyone.
