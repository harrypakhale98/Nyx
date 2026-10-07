## Multi-platform (Watch, Vision Pro, iPad, widgets, Live Activity, controls, Mac, CarPlay) — findings

Review method: code and existing captures only (no builds). API claims checked against the installed SDKs (iPhoneOS27.0, WatchOS27.0, XROS27.0 swiftinterfaces and headers). Anything not checkable there is marked "unverified".

### Verdict
Nyx already reaches four platforms with real engineering behind each: a red-first watch app with measured contrast and WatchConnectivity budgeting, a RealityKit sky that respects comfort and accessibility, a width-driven iPad layout with a menu bar, and a widget plus Live Activity pair that needs no server. The weakness is shape, not effort. The watch is a faithful read-only port of the phone's three screens, with no wrist-native interaction (no Crown, Double Tap or haptics) and one complication kind. Vision Pro is one window plus one immersive sky, and it shows a score that differs from the phone's. The iPad is a good stretched-and-recomposed phone app but has no windowing, drag and drop, Handoff or pointer craft. Widgets are one static kind. The Live Activity, the thing most likely to be seen on Watch, CarPlay and the Mac menu bar, has no small-family design and goes quietly wrong after its second milestone. Moonlitt was cited for being native on every platform; Nyx has to be native in feel, not only present, to match it.

### Findings

#### Live Activity (Lock Screen, Dynamic Island, Watch Smart Stack, CarPlay, Mac menu bar)

- **[MP-01] The Live Activity has no small-family design, so Watch Smart Stack and CarPlay get whatever the system derives** — Severity: P1
  - Evidence: `NyxWidgets/FieldLiveActivity.swift` builds `ActivityConfiguration` with no `.supplementalActivityFamilies([.small])` and nothing reads `\.activityFamily`. The SDK confirms the API (`WidgetKit.swiftinterface` lines 750–790: `ActivityFamily { small, medium }`, `supplementalActivityFamilies`, `activityFamily`; iOS 18+). The Lock Screen face (`FieldActivityLockView`) is an iPhone-width layout: 16 pt padding, a park and score row, a serif headline plus 110 pt timer, a 16 pt night line with up to 8 ticks, and two caption2 "later" marks (`Nyx/DesignSystem/FieldActivityView.swift`). On a 205 pt Watch card that would either scale to illegibility or be replaced by a system default. What the default is, and which family CarPlay in iOS 26 uses, is unverified; the SDK has no prose. Apple's WWDC24 Watch session says the small family is the one Smart Stack uses (unverified from memory; check the session).
  - Why it matters: Interaction and Inclusivity. A stargazer on a trailhead glances at the wrist, not the phone, and the roadmap's own "wrist is the right screen" premise depends on this card. Nothing in `Research/Screenshots` shows the activity on Watch or CarPlay.
  - Recommendation: add `.supplementalActivityFamilies([.small])` and branch on `activityFamily`. Small face: milestone symbol, `Text(timerInterval:)` at one large size, and the park's short name. Nothing else, and red when `nightVision`. Pair it with MP-02's stale logic. On iOS 26 use `Activity.request(...start:)` only if the owner wants a scheduled "dusk" start (see MP-27). Verify on a paired Watch and in a CarPlay simulator or head unit.
  - Effort: S–M

- **[MP-02] After the second milestone passes with no app update, the Live Activity shows a past event as if it were next** — Severity: P1 (honesty)
  - Evidence: `FieldActivityAttributes.shown(_:isStale:)` returns `isStale ? after(next).first : next` (`Nyx/Models/FieldActivity.swift`). `staleDate` is the next milestone's time (`FieldServices.swift:35`), and updates happen only when the app is foregrounded (`RootView` scenePhase `.active` → `FieldActivities.refresh`; there is no BGAppRefresh anywhere, grep of `BGTask|BGAppRefresh|UIBackgroundModes` is empty). The phone is in a pocket for the whole night. At 7:44 PM the face flips to the milestone after "true darkness", for example Moonset 9:00 PM, as a clock time. At 9:01 PM the state is still stale, still shows "Moonset 9:00 PM", and the countdown has long gone. The capture `Research/Screenshots/recovered-live-activity-stale-27.png` demonstrates exactly one step of stale and nothing beyond it.
  - Why it matters: a field tool that is confidently wrong at 2 AM breaks the brief's "honest about uncertainty" and the "calm, precise" voice. The Lock Screen card is also what Watch, CarPlay and the Mac menu bar mirror.
  - Recommendation: with no push server, make the stale face a schedule, not a "next" claim. When stale, list the remaining milestones as fixed clock times (they stay true), name none of them "next", and add one muted line, "Updated 7:44 PM. Open Nyx to refresh." Chain a local notification at each milestone (the app already schedules reminders); tapping it opens Nyx, which refreshes the activity. Add a test that renders the face three hours after `next`.
  - Effort: M

#### Apple Watch

- **[MP-03] Watch "Dark adaptation" is only a milestone countdown, not the adaptation clock that makes the phone's field mode distinctive** — Severity: P1
  - Evidence: `DarkAdaptationView` (`NyxWatch/WatchViews.swift` ~345) shows the next milestone's `Text(timerInterval:)` plus a static paragraph "Eyes take 20 to 30 minutes to adapt". The phone's field screen has the real clock ("Eyes adjusting, 4 of about 30 minutes", `Research/Screenshots/ipad-field-landscape.png`). In `Store/Screenshots/Watch/05-dark-adaptation-ultra.png` the paragraph runs off the screen. The view has no haptic, no notification at "eyes adapted", and cannot run with the wrist down beyond watchOS's default return-to-clock (the app keeps no extended runtime, correctly, since no session type fits stargazing).
  - Why it matters: Interaction. This is the one place the wrist beats the phone for dark adaptation, and the roadmap's "nothing else on the App Store does it" feature is missing there.
  - Recommendation: on tap of the eye button, start a 30-minute ring (arc like the gauge, shared spring) with minutes in the Always-On state, and schedule a local notification at +25/+30 min ("Your eyes have adapted. Keep the screen red."), which fires on the wrist with a haptic whether or not the app is frontmost. Reset copy on re-entry. Drop the paragraph into an info sheet. Use `.handGestureShortcut(.primaryAction)` (watchOS 11+, verified in `WatchOS27.0.sdk` SwiftUI interface line 521) on the Start button.
  - Effort: M

- **[MP-04] One complication kind, no configuration, and red-on-everything by default** — Severity: P1
  - Evidence: `NyxWatchWidgets/NyxWatchWidgetsBundle.swift`: a single `StaticConfiguration` "NyxTonight" (circular, rectangular, corner, inline) plus a Smart Stack `RelevanceConfiguration`. `WatchSky.nightVision(.red)` returns true always, and the palette default is `.red` (`WatchSky.palette`), so a face with a daytime colour theme gets a red complication in full-colour mode even at noon. Complication park is the darkest saved park with no way to choose (no `AppIntentConfiguration`). Colours are fixed `ink`, so only the system's accented/vibrant overrides rescue tinted faces; there is no rendering-mode check (`widgetRenderingMode` is unused in watch code; `widgetAccentable` appears only on three numerals).
  - Why it matters: watch faces are personal and are judged in daylight in review videos. A face-matching, face-variety complication set is the first thing a Watch-literate juror sees. The brief's "darkness at a glance" can also be told several ways.
  - Recommendation: (1) Add an "Automatic" palette that is the default: standard Nyx colours by day, red from civil twilight at the followed park (or home park). Keep "Red light" and "Starlight" as explicit choices. (2) Add two more kinds: **Moon** (phase symbol, illumination, rise/set, all families, no score, no clouds needed, therefore never stale) and **Next dark** (countdown to true darkness or "Moon down in 2 hr"). (3) Make the score kind configurable with a park parameter (`AppIntentConfiguration`, `WidgetConfigurationIntent` already exists as `DuskNight`). (4) In `.accented` or `.vibrant`, drop opacity levels and use `widgetAccentable` on score plus gauge only; verify on a real watchOS 26 tinted face.
  - Effort: M

- **[MP-05] Stale data is silent on the wrist, and nothing on the phone keeps it fresh** — Severity: P2
  - Evidence: `Forecast.mean(...)` returns nil when `now - updated >= 36 h` (`Nyx/Models/Forecast.swift:11`). The watch then shows "Moon and darkness only. No cloud forecast for this night." (`WatchSky.forecastNote` when `context != nil`), which is indistinguishable from a night beyond the forecast horizon. `WatchBridge.push` runs only from `RootView.updateSaved`, which runs on foreground, so a phone not opened for two days gives a watch with a two-day-old context and no age shown. There is no BGAppRefreshTask in the iPhone app.
  - Why it matters: the design decision "the watch cannot network" is fine only if the failure is legible. The user at a trailhead with a dead phone connection has the wrong mental model ("no cloud forecast for tonight") when the truth is "your last update was Monday".
  - Recommendation: show the age ("Clouds from Mon 4 PM") on the watch whenever a context exists, with a distinct line when the forecast has expired: "Forecast expired. Open Nyx on iPhone." On the iPhone, add a `BGAppRefreshTask` (BackgroundTasks, no new host) that refreshes saved-park forecasts, rewrites the widget snapshot and calls `WatchBridge.push`. Even a best-effort refresh once or twice a day removes most cliffs.
  - Effort: M

- **[MP-06] Smart Stack and widget relevance know the time, not the place** — Severity: P2
  - Evidence: `DuskProvider.relevance()` and `TonightProvider.relevance()` build only `.date(interval:)` contexts (`NyxWatchWidgetsBundle.swift`, `NyxWidgetsBundle.swift`). `RelevantContext.location(_ exact: CLRegion)` exists in RelevanceKit (`iPhoneOS27.0.sdk`, RelevanceKit swiftinterface lines 19–45; the watch SDK also ships RelevanceKit). A card that appears at dusk for a saved park on a Good night fires equally from the kitchen.
  - Why it matters: relevance is the headline benefit of Smart Stack and of the iOS 26 widget stack. "It surfaces when you are at the park" is the demo.
  - Recommendation: add a `.location(CLCircularRegion(center: spot, radius: 25_000, ...))` attribute per saved park beside each date window, and use the park's named viewing spots (already in `parks.json`). No Nyx location permission is needed for the system to match the region; verify on device.
  - Effort: S

- **[MP-07] The watch week page degenerates without clouds, and it omits the iPhone's climate fallback** — Severity: P2
  - Evidence: `Research/Screenshots/watch/ultra3-week-red.png`: Big Bend shows 93, 95, then five nights at 96, all ringed, with "Darkest: Wed, Oct 7 and 4 more". The iPhone ranks far nights with each park's usual clouds (`CloudClimate`, `NightPlanner`, git `f200da6`), but `NyxWatch` and `NyxWatchWidgets` in `project.yml` list neither `CloudClimate.swift`, `cloud-climate.json` nor `NightPlanner.swift`.
  - Why it matters: the week page's one job is "which night", and five rings answer nothing. It also contradicts the phone for the same park (the phone has a recommended night).
  - Recommendation: compile `CloudClimate` and `cloud-climate.json` into both watch targets (they are small) and use the phone's tie-break and ranking, with the honest "usual clouds" labelling. At minimum, break ties by moon-free hours and say so.
  - Effort: S–M

- **[MP-08] No wrist-native interaction: no Double Tap, no Digital Crown scrub, no haptics, no Watch controls** — Severity: P2
  - Evidence: grep of `NyxWatch`, `NyxWatchShared`, `NyxWatchWidgets` for `handGestureShortcut|digitalCrownRotation|sensoryFeedback|WKInterfaceDevice` is empty. The Crown only pages the vertical `TabView`. The Watch SDK supports controls (`ControlWidget` is `watchOS 26.0` in `WidgetKit.swiftinterface`), but the watch widget bundle has no control.
  - Why it matters: Interaction award criteria weigh "feels physical". The phone has a draggable time river with a detent haptic per night; the wrist has none of that.
  - Recommendation: Crown scrub on the Tonight page with `digitalCrownRotation(detent:)` stepping through the week (the Moon disc morphs, detent haptics for free); Double Tap as the primary action on the Dark adaptation start button and "Show on Tonight"; a watchOS 26 control "Red light" that flips the palette; light `.sensoryFeedback` on the score count-up.
  - Effort: M

- **[MP-09] Always-On is handled only on the gauge and the dark view** — Severity: P3
  - Evidence: `isLuminanceReduced` is read in `WatchGauge.swift` and `DarkAdaptationView` only. The "Starlight" palette keeps amber accent, white-ish ink and the unlit-moon at full level in Always-On elsewhere. The system clock at the top of every screen stays white (`DECISIONS.md` known limits; seen in `ultra3-dark-red.png` and `ultra3-week-red.png`). `WKRunsIndependentlyOfCompanionApp` is not set in `project.yml` (unverified whether the generated plist adds it; check the built Info.plist).
  - Recommendation: dim all non-essential text and drop glows in `isLuminanceReduced` in every page, not just the gauge. For the white clock, test `toolbar(.hidden, for: .navigationBar)` plus a custom leading item or a full-screen container in the dark view (unverified that watchOS allows hiding the clock). Decide independence on purpose: the watch has no network, so an independent app could install from the watch's own App Store.
  - Effort: S

#### Vision Pro

- **[MP-10] The Vision Pro score is not the phone's score, and nothing personal reaches it** — Severity: P1
  - Evidence: `NightPlan` always passes `cloudCover: nil` (`NyxVision/App/VisionModel.swift`), so the score is "moon and darkness only". `NyxVision` lists no `ForecastDetail`, `DataServices` or saved-park source. The window shows Joshua Tree 89 (`Research/Screenshots/vision-window.png`), the phone shows 93 for a similar night (`ipad-detail-portrait.png`); the park list is alphabetical with no saved or nearby markers; there is no journal, no clouds, no Handoff.
  - Why it matters: Innovation and Visuals. A planner whose headline number cannot be compared to the phone makes the immersive sky a demo, not the next step of a trip. The strongest version of "stand under tonight's sky" shows tonight's clouds in the sky.
  - Recommendation: (a) owner decision: allow the existing Open-Meteo host on visionOS behind the same "Your privacy" toggle, cached per park. Then draw the forecast overhead: stars dim with cloud cover and a soft cloud layer drifts in at the hours the forecast says, so scrubbing the night is also scrubbing the cloud. (b) Independently of (a), add Handoff (`NSUserActivity` with `isEligibleForHandoff`, same bundle ID as the phone) so "Stand under this sky" can continue from a park open on iPhone or iPad. Handoff is device to device, no Nyx host.
  - Effort: M (Handoff S, forecast M)

- **[MP-11] Vision is a window and a sphere: no widget, no volume, nothing in the shared space** — Severity: P1
  - Evidence: `NyxVisionApp.swift` has one `WindowGroup` and one `ImmersiveSpace`. There is no widget extension for visionOS even though `WidgetKit` is available on visionOS 26 (`WidgetRenderingMode` is `visionOS 26.0`, `widgetTexture(_:)` and `supportedMountingStyles(_:)` are visionOS-only/26 in the iPhoneOS and XROS SDKs; `NyxWidgets` already compiles `TonightWidgetView`). No `.volumetric` window or `Model3D`, though the app already ships a NASA moon map and the Moon Metal shader.
  - Why it matters: visionOS 26 juries expect persistence in the room. A moon you can place on a shelf, lit at today's true phase and tilted for the park, is the single most photogenic thing Nyx could ship on this platform and works without leaving passthrough, which suits seated, low-effort sessions and people who cannot or will not use full immersion.
  - Recommendation: (1) a visionOS widget target reusing `TonightWidgetView` with `.widgetTexture(.glass)` or `.paper` and `supportedMountingStyles` chosen on device. (2) A volumetric "Moon on your table" window: a RealityKit sphere, the NASA albedo map, a directional light at the true phase angle, orientation from `moonGeometry`. Let the window's slider scrub the date. (3) Nothing else needs a server.
  - Effort: M (widget S, volume M)

- **[MP-12] In the sky, only the Moon, planets and the core have names; 904 stars are unnamed and there are no constellations** — Severity: P2
  - Evidence: `Nyx/Resources/stars.json` rows are four numbers `[ra, dec, mag, B−V]` (no name, no constellation); `SkyScene` makes only `body:` entities tappable. `Store/Framed/Vision-Pro/02-immersive-core.png` shows an unlabelled star field. The Learn essay "Finding the Milky Way" and the roadmap's "constellation lines draw themselves" idea (the product brief §14.7) never reach the sky.
  - Why it matters: in a planetarium the first thing a visitor does is point at a bright star or ask "which one is Orion". Naming only five objects reads as a tech demo. Look-and-tap is Vision's native gesture.
  - Recommendation: bundle IAU star names for the ~60 brightest stars (the WGSN list is public) and about 30 constellation stick figures as star-index pairs (author them yourself from the standard patterns; do not import GPL data such as Stellarium's). Give named stars a hover effect and the same name card; draw lines with the existing additive material, faded in over 0.6 s, off by default under Reduce Motion, toggled in the ornament. The same table later feeds the iPhone's real-sky view.
  - Effort: M

- **[MP-13] Time is scrubbed only from the window ornament, so in full immersion the sky cannot be touched** — Severity: P2
  - Evidence: `NightControls` is a window ornament (`ornament(...scene(.bottom))`); `SkySpace` has only a `SpatialTapGesture`. In progressive immersion at `initialAmount: 1` (`NyxVisionApp.swift:7`, fully surrounding from the first frame) the person must find the window to move the sky.
  - Why it matters: Interaction. The gesture that fits is "grab the sky and turn it", which is what the sky does anyway (15° an hour).
  - Recommendation: add `DragGesture().targetedToAnyEntity()` on the dome that maps horizontal drag to `model.fraction`, reusing `comfortableTurn` (20°/s, already tested in `VisionModel.move`) as the rate limit. Start immersion near 0.6 so the room is still there on entry and the Crown reveals more, or show a one-time hint "Turn the Digital Crown to widen the sky".
  - Effort: S–M

- **[MP-14] SharePlay with Spatial Personas is the strongest social idea for this platform, but it conflicts with two written rules** — Severity: P2 (owner decision)
  - Evidence: the product brief §11 puts social features out of scope and §13 says "Exactly three network hosts... Nothing else, including Apple routing services". GroupActivities carries session state through Apple's FaceTime/Messages infrastructure. The payload Nyx would define is tiny: park ID, night offset, clock fraction, no identity. Nyx would run no server and collect nothing; whether the "Data Not Collected" label needs any change is unverified (the label covers data the developer collects, which GroupActivities does not give the developer).
  - Why it matters: "stand under the same sky with a friend, one of you turning the night" is the single most Vision-native feature one could add and is a plausible Delight and Social Impact story for the Milky Way stargazing community.
  - Recommendation: do not build until the owner explicitly relaxes §11 and §13 for system SharePlay (and then log it in DECISIONS.md). If approved, ship a minimal `GroupActivity` carrying only (parkID, evening, fraction), Spatial Persona seating via `SharedCoordinateSpace`, off by default, nothing persisted.
  - Effort: L

- **[MP-15] Moonlit frame labels the Milky Way core beside a Moon that has washed it out** — Severity: P3
  - Evidence: `Store/Framed/Vision-Pro/03-moonlit.png` shows "Milky Way core" under the Moon in a sky where the Milky Way is invisible; `coreShown` in `SkyScene.update` depends only on `visibility(.milkyWay, sunAltitude:)`, not on the moon's glare (`washed`).
  - Recommendation: hide or dim the core label and target when `milkyWayLight` is near zero, or say "Milky Way core, washed out by the Moon". It would be a nicer teaching moment than a label on nothing.
  - Effort: S

#### iPad

- **[MP-16] No windowing, drag and drop, Handoff, pointer or inspector craft: the iPad app is well composed but not an iPad-native one** — Severity: P1
  - Evidence: greps over `Nyx/` find zero uses of `openWindow`, `draggable`, `dropDestination`, `userActivity`/`NSUserActivity`, `pointerStyle`, `inspector`, `SceneStorage`. `onContinueUserActivity` exists only for Spotlight. `UIApplicationSupportsMultipleScenes` is on (DECISIONS iPad), but nothing in the UI opens a second window. `hoverEffect` is used in six files, which is good. `SceneCommands` provides ⌘1–5, ⌘F and ⌘←/→ and the menu bar (`Nyx/App/SceneCommands.swift`).
  - Why it matters: iPadOS 26's windowing, Stage Manager and menu bar are exactly what Apple's iPad-category reviewers look for: "open Joshua Tree in its own window next to Death Valley" is the natural planning gesture for this app, and the calendar is a prime drag target.
  - Recommendation: (1) park row / detail context menu "Open in New Window" with `openWindow(value: parkID)` (a `WindowGroup(for: String.self)`), plus `@SceneStorage` for per-window tab and park. (2) Make `Park` `Transferable` (a small `.nyxPark` content type plus plain text/URL `nyx://park/…`) and add `draggable` to rows and `dropDestination` to Calendar (switch park) and Journal (new entry for that park). (3) `NSUserActivity` per park/night with `isEligibleForHandoff`, which also helps Siri suggestions, for iPhone to iPad to Vision continuity. (4) A trailing `.inspector` for the score breakdown on wide windows instead of a second column. (5) `pointerStyle(.link)` on custom cells. Pencil is unneeded.
  - Effort: M

- **[MP-17] On iPad portrait and landscape the content leaves large voids, and the store set shows only portrait** — Severity: P2
  - Evidence: `Store/Framed/iPad-13-inch/01-tonight.png`: Tonight's columns end at about 75% of the height and the rest of the screen is empty black; `Store/Screenshots/iPad/04-calendar-13.png`: roughly 15% empty below the calendar; `Research/Screenshots/ipad-field-landscape.png`: one 680 pt column in a 1400 pt-wide window with "The night" and "Where to look" behind a segmented switch though both would fit side by side; `ipad-widget-xl.png` the extra-large widget grid leaves 40% of its cell empty. All six store frames are portrait; landscape and Stage Manager are the primary iPad modes.
  - Why it matters: Visuals. Empty slabs on a 13-inch canvas read as "stretched phone".
  - Recommendation: on wide Tonight, stretch the hero sky (the real sky as a banner behind the gauge) or add the week as a third column; in field mode on iPad landscape put the night timeline on the left and Where to look on the right (the compass is already width-aware); fix the XL widget's vertical rhythm; re-shoot a landscape set.
  - Effort: M

#### Widgets and controls

- **[MP-18] One static widget kind, no inline Lock Screen widget, no per-widget park, no Moon widget** — Severity: P1
  - Evidence: `NyxWidgetsBundle` = `TonightWidget` (StaticConfiguration) + two Controls + two Live Activities. Families: small, medium, large, extraLarge, accessoryCircular, accessoryRectangular. `accessoryInline` is missing from `supportedFamilies` (the family exists in the iOS SDK, line 974). The park shown is chosen by the widget (`WidgetSelection.pick`) with an in-widget cycle button; the user cannot place two widgets for two parks. There is no Moon-only widget even though the Moon is the app's emblem.
  - Why it matters: widgets are the part of an app most people see most often and the first place Moonlitt-class apps win. A stargazer wants "Moon" on the Lock Screen and "Joshua Tree" on the Home Screen.
  - Recommendation: (1) `AppIntentConfiguration` for Tonight with a park parameter whose default is "Best of my saved parks". (2) A **Moon** widget (small, circular, inline) with phase, illumination and rise/set; no forecast, never stale. (3) A **Next dark night** widget (countdown to the next "five nights near the new moon" window). (4) `accessoryInline`: "93 · Dark at 7:51 PM". (5) Consider `systemExtraLargePortrait` on iPad (iOS 27 only, skipped deliberately in DECISIONS; fine to revisit).
  - Effort: M

- **[MP-19] Tinted and clear Home Screen rendering are simulated, not seen, and the widget Moon changes with whether the app was opened** — Severity: P2
  - Evidence: the review route simulates tinted mode with `colorMultiply` and `.saturation(0)` (`TonightWidgetView.swift`, `WidgetReviewView`), and the screenshot itself says "(vibrant rendering, simulated)"; there is no capture of iOS 26's clear or glass style. The Moon is the app's pre-rendered shader image if `moon-<park>-<night>.png` exists in the App Group, else a vector `MoonDisc` through `ImageRenderer` (`moonImage(_:)`), so a user who has not opened Nyx for a few days gets a visibly different (less realistic) Moon.
  - Why it matters: the widget gallery and the Home Screen are where jurors and the App Store editorial team look.
  - Recommendation: check the actual clear, tinted and dark-icon looks on iOS 26 and 27 hardware (INPUT_NEEDED already lists the device gate; add clear glass specifically). Render the next seven nights' Moon images in the app on every foreground (cheap) and make the widget fall back to the nearest cached night rather than the vector Moon. Keep `widgetAccentable` only on the score and week dots.
  - Effort: S–M

- **[MP-20] Controls: two static toggles and no value control, none on Watch or Mac** — Severity: P2
  - Evidence: `NightVisionControl` and `FieldModeControl` (StaticControlConfiguration) only. `ControlWidget` is available on watchOS 26 and macOS 26 (`WidgetKit.swiftinterface`, `watchOS 26.0, macOS 26.0`); `NyxWatchWidgetsBundle` has no control.
  - Recommendation: add a read-only value control "Tonight 93" (a `ControlWidgetLabel` with the score, opening the park), a configurable control with a park parameter (`AppIntentControlConfiguration`), and a watch control "Red light". All are assignable to the Action Button for free.
  - Effort: S–M

#### CarPlay, Mac, Handoff

- **[MP-21] CarPlay: the widget and Live Activity were never designed for the drive, which is when "go or don't go" is decided** — Severity: P2
  - Evidence: the SDK exposes `WidgetLocation.carPlay` (iOS 26) and `disfavoredLocations(_:for:)`, and the Live Activity small family is the likely CarPlay surface (see MP-01; unverified). Nyx does neither. The Live Activity starts only when the person taps "I'm here tonight" at the park (`FieldActivities.start`); it never runs on the drive. The decision log says iOS 26's scheduled start was "not used".
  - Why it matters: a long drive toward a dark park is the moment when the closure line, "True darkness 7:44 PM at Joshua Tree" and the moon state matter and the phone is mounted on the dash. Nothing else in this category does it.
  - Recommendation: after MP-01, add a "Heading out" mode of the same activity (before arrival: sunset, true darkness, closure warning), started from the trip planner or a reminder tap, and using the small family; no ETA or routing (straight-line only, per §13). Keep CarPlay copy to one line and one number. Verify in the CarPlay simulator.
  - Effort: M

- **[MP-22] Mac: keep it off for 1.1, then test "Designed for iPad" once the hardware-bound features are guarded** — Severity: P3 (recommendation)
  - Evidence: `INPUT_NEEDED.md` and `SUBMISSION.md` turn Mac availability off because field mode, the compass, alarms and Live Activities "were never tried there". The code has no `isiOSAppOnMac` guard (grep), and it calls `AlarmManager`, `CMMotionManager` and `Activity.request` directly. The Mac already gets Nyx without the app: iPhone widgets (`WidgetLocation.iPhoneWidgetsOnMac` exists in the SDK) and, on macOS 26, Live Activities from a nearby iPhone in the menu bar (unverified how the Nyx activity renders there; treat MP-01 as the fix).
  - Why it matters: the roadmap cites a platform-wide win, but a rejected or poorly reviewed Mac listing costs more than it earns. The cost of the free Designed-for-iPad option is mostly guarding and a day of testing; Catalyst or a native Mac target is not worth it for awards at this stage.
  - Recommendation: post-1.1, run the app on "My Mac (Designed for iPad)", guard field mode, alarms and the compass behind `ProcessInfo.processInfo.isiOSAppOnMac` (hide, never error, as the product brief §12 says of unavailable features), check keyboard and pointer parity from MP-16, then tick Mac availability. Revisit native Mac only if the iPad drag, window and menu work lands well.
  - Effort: S–M (test and guard); L (native)

- **[MP-23] No Handoff or continuity across Nyx's four native platforms** — Severity: P2
  - Evidence: no `NSUserActivity` anywhere (see MP-16); the visionOS app shares the phone's bundle ID (`DECISIONS.md` 2026-10-06), which makes Handoff possible without any Nyx server or iCloud.
  - Recommendation: one activity type "park night", userInfo `(parkID, evening)` only, adopted by iPhone, iPad, Watch (watchOS supports Handoff to iPhone) and Vision. It is the privacy-compatible substitute for sync in this version.
  - Effort: S

### Strengths worth protecting
- Red-first watch palette with every red level measured (`NightRed`, tested at 4.5:1) and toolbar/title workarounds; a versioned, byte-budgeted WatchConnectivity context; no network code compiled into the watch targets (a build-time check).
- Honest labelling everywhere ("Moon and darkness only", dashed gauge, hollow dots); placeholders that show a real sky instead of an empty state.
- Vision comfort engineering: a 20°/s turn limit during scrubs, the sky closing with the window, AccessibilityComponents on every body, Dynamic Type applied to texture-rendered labels, hover effects on bodies.
- `WideLayout`: width, never device, decides columns; ⌘-hold menu bar and per-window `SceneCommands`.
- Live Activity with no push server, a system-timer night line that advances by itself, and red when night vision is on.
- Smart Stack relevance already exists on both phone and watch (`TimelineEntryRelevance`, `RelevanceConfiguration`).

### Open questions for the owner
1. Vision Pro network: may `NyxVision` use `api.open-meteo.com` (already one of the three hosts, behind its toggle) so the immersive sky can show forecast cloud? It changes the "this app makes no network requests" sentence in the Vision store copy.
2. SharePlay on Vision Pro (MP-14): relax the product brief §11/§13 for system-run SharePlay with a (park, night, time) payload, or keep Vision single-user?
3. Watch default palette: replace "red by default" with "Automatic" (red only in twilight and dark at the followed park)? It changes the first-run look in review videos.
4. Mac: is a post-1.1 test of "Designed for iPad" acceptable, with field features hidden on Mac, or should Mac stay off until native Mac is worth a target?
5. Start a "Heading out" Live Activity from the trip planner (MP-21), given it shows up on CarPlay and the Mac menu bar without a way for the person to dismiss it from the car?
