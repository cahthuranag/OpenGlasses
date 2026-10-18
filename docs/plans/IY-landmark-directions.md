# Plan IY — Landmark Directions ("turn left at the pharmacy")

**Status:** 📝 Drafted (not scheduled), 2026-10-18 — nothing built.
**Extends:** Plan [CA](CA-walking-navigation.md) (walking navigation: `RouteModel`, `ManeuverPhraser`,
`NavigationCuePolicy`, `WalkingRouteService`).
**Related:** Plan [GL](GL-cycling-driving-navigation-and-road-alerts.md) (travel modes — landmarks
are a walking-only cue in v1), Plan [GM](GM-watch-map-and-list-surfaces.md) (`RouteSnapshot` carries
the landmark), Plan [HH](HH-conversation-map-surface.md) (the map card shows it), Plan
[GP](GP-nearby-opening-hours.md) (shares the place-category vocabulary), Plan
[J](J-low-vision-navigation.md) / [FF](FF-blind-assistant-readiness.md) (camera "landmarks" are a
different thing — see Design).

---

## Trigger

A walking cue today is "In 80 metres, turn left onto Queen Street." A pedestrian rarely knows the
name of the next street, often cannot read the sign (glare, distance, low vision, a foreign script),
and MapKit sometimes gives no street at all, so the cue degrades to "In 80 metres, turn left." People
give each other directions by what is there: "left at the pharmacy", "past the park, then right".
The assistant has the route, the maneuver point and a map service that knows what stands on each
corner; it just never asks.

## Outcome

- "In 80 metres, turn left at the pharmacy." → "Turn left at the pharmacy now."
- "In 200 metres, bear right at the church, onto Victoria Street" when the street is short and
  known; "In 200 metres, bear right at the church" when it is not.
- No usable landmark → today's wording, unchanged, word for word (the existing tests keep passing).
- HUD: "← 80 m · pharmacy" (the landmark replaces the street in the HUD line when present).
- A setting: **Landmarks in directions** — On (default) / Only when there is no street name / Off.
- Never a landmark that is the destination itself, never one across a wide intersection without
  saying so, never two cafés on one corner ("the café" would be ambiguous → street name instead).

## What exists today (verified 2026-10-18)

- `Services/Navigation/RouteModel.swift`: `RouteStep { instruction, maneuver, streetName?,
  maneuverPoint, inboundLeg, inboundDistance }`. `Maneuver.parse(instruction:)` keyword-parses
  MapKit's **English** instruction text; non-English becomes `.continueStraight`. No landmark field.
- `ManeuverPhraser.spoken(maneuver:streetName:bandedMeters:metric:)` and `hudLine(…)` take exactly
  those four inputs. `DistanceFormatter.banded` (≤15 m → "now"). `NavigationCuePolicy`: one
  **approach** cue when a step becomes active, one **imminent** cue at band 0. Nothing time-based.
- `WalkingRouteService`: `MKLocalSearch` (destination) → `MKDirections` (`.walking`) →
  `buildSteps(route:origin:)` (maneuver point = head of the step's own polyline; inbound leg = the
  previous step's polyline) → `RouteProgressTracker` (advance 20 m, off-route 30 m × 4 fixes,
  reroute throttle 30 s, arrival 25 m). Injected seams `localSearch` and `directions` exist for
  tests. `streetName(from:)` splits on " onto " / " on to " / " on " — **untested**.
- `LocationSearchTool` (`find_nearby`) uses `MKLocalSearch` with a natural-language query and drops
  coordinates and `pointOfInterestCategory`. **No file in `OpenGlasses/Sources` references
  `MKPointOfInterestCategory`, `pointOfInterestFilter` or `MKLocalPointsOfInterestRequest`**, and no
  category-to-noun vocabulary exists (GP proposes `OSMCategoryMap`; unbuilt).
- Spoken cue strings ("turn left", "In …", "You've arrived", "metres") are Swift literals, not in
  `Localizable.xcstrings`; only `NavigationSettingsView`'s labels are localised. GL lists localised
  guidance as out of scope.
- `Services/Accessibility/NavigationAssistService` (Plan J) speaks camera-seen hazards and
  "landmarks" from the LLM every 2.5 s with its own dedup; it does not use `ManeuverPhraser` or the
  route. CA's co-run question with Plan J is still open.
- Tests: `WalkingNavigationTests` pins the exact spoken strings ("In 40 metres, turn left onto King
  Street.", "Turn left onto King Street now.") and the cue policy; `WalkingRouteServiceCoordinateStartTests`
  uses the seams. `buildSteps`, `streetName(from:)`, `renderActiveStep` have no tests.

## Design

### Model

`Landmark { name: String, category: PlaceCategory, coordinate: RoutePoint, distanceToManeuver: Double,
side: Side (.left/.right/.ahead/.opposite), noun: String }` added as `RouteStep.landmark: Landmark?`
(optional, `Codable` with a default of nil so persisted recents and any encoded routes still decode).

`PlaceCategory` is a small app-owned enum (pharmacy, supermarket, cafe, bank, atm, fuelStation,
church, school, park, station, busStop, postOffice, library, hotel, hospital, restaurant, bar,
bakery, store, parking, other) with `PlaceCategoryVocabulary` (pure): `init(mapKit:)` from the
`MKPointOfInterestCategory` raw value (so the enum, not MapKit, is what the pure code sees), a spoken
`noun` ("the pharmacy", "the supermarket", "the church", "the station"), and a `salience` 0–3
(supermarket, pharmacy, church, station, park, school, bank, fuel station = 3; café, bakery,
restaurant, post office, library = 2; store, hotel, bar = 1; parking, atm, other = 0). GP's
`OSMCategoryMap` maps onto the same enum when it is built, so there is one vocabulary.

### Picking a landmark (`LandmarkPicker`, pure)

Inputs: the step (maneuver point, inbound leg, maneuver), the destination coordinate, candidates
`[LandmarkCandidate { name, category, coordinate }]`. Rules, in order:

1. Drop the destination (same name, or within 15 m of the route's end).
2. Drop candidates farther than 40 m from the maneuver point, and any **behind** the wearer on the
   inbound leg by more than 15 m (a shop already passed is not "at the corner").
3. Compute `side` from the inbound heading (last two inbound points) and the candidate's bearing:
   within ±25° ahead → `.ahead`; left/right otherwise; more than 30 m away **and** on the far side
   of the maneuver point → `.opposite`.
4. Score = salience × 3 − distance/10 + (side matches the turn direction ? 2 : 0) + (name ≤ 3 words
   ? 1 : 0) − (`.opposite` ? 2 : 0). Salience 0 never qualifies.
5. **Ambiguity:** two surviving candidates of the same category within 40 m of each other → that
   category is dropped for this step (the noun would not disambiguate). If the best survivor's
   score is under a floor (4), no landmark.
6. Result: at most one `Landmark` per step. Deterministic for the same inputs (ties by distance,
   then name).

### Phrasing (`ManeuverPhraser` gains `landmark:`)

- Approach: `"In \(distance), \(verb) at \(noun)"`, then `", onto \(street)"` only when the street
  is ≤ 3 words and the setting is On (not "Only when no street"). Imminent: `"\(Verb) at \(noun) now."`
- `.opposite` → "opposite the pharmacy" instead of "at"; `.ahead` with `continueStraight` → "past
  the pharmacy" ("In 150 metres, continue straight past the park").
- Arrival lines unchanged. HUD: `"\(arrow) \(distance) · \(nounWithoutArticle)"`; imminent
  `"\(arrow) pharmacy"`.
- **Noun or name.** Default is the category noun; the proper name is used when the category is
  `store`/`other` ("at Whitcoulls") or when the setting *Use place names* is on (default off). Chain
  and brand names are read as given; names over 4 words are never spoken (the noun is used, else no
  landmark).
- Copy stays English literals in v1, matching CA/GL, but the nouns live in one table so that EC can
  localise them in a single place later. Copy never names a plan letter.

### Fetching (`LandmarkResolver`, live edge behind a seam)

- Seam: `pointsOfInterest: (center: CLLocationCoordinate2D, radiusMeters: Double) async throws ->
  [LandmarkCandidate]`, implemented with `MKLocalPointsOfInterestRequest` (radius 60 m) and a
  `pointOfInterestFilter` *including* only the categories in `PlaceCategoryVocabulary`. Results are
  mapped to candidates immediately so no MapKit type leaves the resolver.
- When: in `WalkingRouteService.start` after `buildSteps`, **prefetch** for every turning step
  (`turnLeft/turnRight/slightLeft/slightRight/uTurn/roundabout`; not `depart`/`arrive`/`continueStraight`
  unless the step is longer than 120 m, where "past the park" helps) — at most 20 requests per route,
  sequential, 8 s total budget, cancelled by `stop()`. Steps not resolved by the time they become
  active fall back to street phrasing; a late result is attached and used by the imminent cue only
  if the approach cue has not yet been spoken (no mid-step wording change).
- Reroute: the new steps are resolved the same way; results are cached per rounded maneuver
  coordinate (5 m grid) for the life of the route so a reroute through the same corner costs nothing.
- Failure: any error → no landmark, no spoken notice (the street cue is the product); the count is
  logged content-free through `PrivacyLog`.
- Network and privacy: MapKit already receives the route and destination (CA). Points-of-interest
  requests send the same coordinates to the same first-party service; no new `NetworkRoute` or
  privacy-manifest domain. Offline (Plan GE handoff): no landmarks, no change in wording.

### Modes and interplay

- Walking only in v1. GL's cycling and driving cues keep street names: a shop is not a safe cue at
  speed, and the lead distances differ. `GuidanceParameters` (GL) gains `landmarksAllowed`.
- Plan J / FF: camera advice ("a person ahead at eleven o'clock") stays independent. For a blind
  wearer a visual landmark is a weak cue, so when the Blind Assistant preset is active the setting
  defaults to **Only when there is no street name** and the street is always appended when known.
- GM/HH: `RouteSnapshot` and the conversation map card carry `landmark?` and show the noun.
- Power: in `PowerPosture.reserve` the prefetch is limited to the next two turning steps.

## Phases (one PR each)

**P0 — Pure core.** `PlaceCategory` + `PlaceCategoryVocabulary` (with a one-off check of the
`MKPointOfInterestCategory` constants in the iPhoneOS27.0 SDK recorded in the plan), `LandmarkCandidate`,
`LandmarkGeometry` (side, behind-the-wearer, ahead test), `LandmarkPicker`, `ManeuverPhraser`
`landmark:` overloads, `RouteStep.landmark`. Tests: `PlaceCategoryVocabularyTests` (every category
has a noun and a salience; unknown raw → `.other`), `LandmarkGeometryTests` (side on a left turn, a
right turn, a straight; a shop 20 m behind on the inbound leg is "behind"), `LandmarkPickerTests`
(table: destination dropped; two cafés → none; pharmacy 25 m same side beats supermarket 38 m
opposite; salience-0 parking never chosen; floor), `ManeuverPhraserLandmarkTests` (exact strings:
"In 80 metres, turn left at the pharmacy.", "Turn left at the pharmacy now.", "In 150 metres,
continue straight past the park.", "In 60 metres, turn right opposite the church, onto Queen
Street."; **and every existing `WalkingNavigationTests` string unchanged with `landmark: nil`**).
Also adds the missing `streetName(from:)` and `buildSteps` tests while the file is open.

**P1 — Resolver and wiring.** `LandmarkResolver` behind the seam, prefetch in `WalkingRouteService`
(budget, cancellation, cache, late-result rule), HUD line, the two settings in
`NavigationSettingsView`, the Blind Assistant default. Tests: `LandmarkResolverTests` (fake seam:
budget stops at 20, cancellation on stop, cache hit on reroute, error → nil),
`WalkingRouteServiceLandmarkTests` (a route with three turns resolves three, a slow resolver leaves
the first cue on the street and attaches the rest, no wording change after the approach cue).

**P2 — Device pass (owed).** A city-centre walk and a suburban walk: how often a usable landmark
comes back, how often it is wrong (closed, renamed, on the wrong corner), whether "opposite" reads
right at a four-way intersection, and the cost in time of the prefetch at route start.

## Risks

- **Wrong corner.** A POI's coordinate is a centroid; a mall or a park can sit 60 m from its
  entrance. The 40 m cap and the behind-the-wearer rule limit, not remove, this. The device pass
  decides whether `park` and `school` stay at salience 3.
- **Stale places.** Closed shops linger in map data; the wearer hears "at the bakery" and sees a
  phone shop. The noun is still a cue to a building, which is why nouns are preferred to names.
- **Coverage.** Suburbs and small towns return few POIs; the fallback is today's wording, so the
  feature cannot make things worse, only absent.
- **Cue length.** "In 60 metres, turn right opposite the church, onto Queen Street" is long for a
  moving wearer; the ≤ 3-word street rule and the imminent cue's brevity are the control.

## Decisions for Greig

1. **Noun by default, name on request** (recommended), or the place name whenever it is short?
2. **Blind Assistant default** of *Only when there is no street name* with the street always
   appended — or Off, treating visual landmarks as noise for that preset?
3. **English literals** with a single noun table (recommended, consistent with CA/GL), or make this
   the plan that moves the cue grammar into the string catalog (bigger, touches GL)?
4. **Prefetch budget**: 20 steps / 8 s at route start, or lazy per step with the first cue
   sometimes landmark-less?
5. **`continueStraight` "past the park"** in v1, or turns only?

## Out of scope

Cycling and driving landmarks (GL decides later), landmarks from the camera (Plan J's domain),
opening hours or any OSM data (GP), a pick list of landmarks, non-English maneuver parsing, and
saying landmarks for the destination approach ("the café is just after the bank").
