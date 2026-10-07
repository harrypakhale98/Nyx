## Engineering (reliability, architecture, performance, data, release) — findings

Static review on 2026-10-07 at commit c7918ba. I did not run any builds or simulators. "Unverified" marks every claim that needs a device or a runtime check.

### Verdict
The engineering base is unusually disciplined for a solo pre-launch app:
- Swift 6 language mode, MainActor-by-default isolation, actors for the network services, an allowlisted transport that never follows redirects, atomic cache writes, a reminder ledger, and 166 Swift Testing tests.

It is not yet launch-grade on four things, and each one comes back on a launch day or a featuring day:
1. **The shared NPS key breaks at about 1k daily users.** The fix the team's own behaviour audit called "fix before release" (one bulk alerts call for all 63 parks) was never built. Below 1k DAU, closures (the safety signal) quietly go stale for everyone.
2. **The SwiftData store has no versioned schema.** If the store fails to open, the whole app is replaced by an error screen. So a 1.2 migration mistake would brick the planner, not just the journal. The journal also has no export.
3. **The launch path that real users hit has never been measured.** The only launch metric runs a DEBUG scenario that skips the production work.
4. **Release engineering is manual and fragile.** There is no CI. The shipping archives and dSYMs live in `/tmp`, and the repo sits in iCloud-synced `~/Documents` with Optimize Storage on.

Performance budgets in the docs are stale against the code: the gauge now redraws at the display rate, and the Real Sky has 904 stars.

### Findings

#### Networking and offline

- **[E1] The shared NPS key still has a break point of about 1,000 DAU. The audited bulk-alerts fix was never built.** Severity: P0
  - Evidence:
    - `DataServices.swift:323-328` builds one request per park (`parkCode=park.apiCode`).
    - `PlanModel.swift:201-206` loops park by park.
    - `TonightView.swift:58` refreshes every park in the radius. The radius goes up to 1,000 mi (`TonightView.swift:248`).
    - Events page up to 10 times per park (`DataServices.swift:355-360`).
    - `Research/behavior-audit.md` A1 (build 3) says the bulk call was "verified: one call returned alerts for Acadia, Joshua Tree, Yellowstone and Death Valley together" and lists it as "Fix before release". Only the backoff half shipped (`DataServices.swift:12-19`, DECISIONS:495).
    - NPS documents "1,000 requests per hour" per key ([nps.gov developer guides](https://www.nps.gov/subjects/developer/guides.htm)). `parkCode` takes a comma-delimited list ([MS connector doc](https://learn.microsoft.com/uk-ua/connectors/nationalparkserviceip)).
  - Load model, using `parks.json` with the default 200 mi radius:
    - About 3.0 parks fall within 200 mi of a typical park (Las Vegas 8, LA 5).
    - Per daily user: about 3.6 alerts calls on Tonight, about 1 for saved parks, and 2–4 events calls when opening details. That is roughly **8 calls per DAU per day**.
    - Evening planning puts about 13% of daily use in the peak hour, so the break point is 1,000 / (8 × 0.13) ≈ **960 DAU**. Even if traffic were perfectly flat it would be ≈ 3,000 DAU.
    - At **10k DAU**, about 10,400 calls are wanted in the peak hour, and the quota is spent about 6 minutes in.
    - At **100k DAU** (a featured day), the quota is gone in about 35 seconds of each hour.
    - One user on the 1,000 mi radius near Las Vegas costs about 20 sequential calls per refresh.
  - What degrades: `Backoff` keeps the last alerts, or shows "Access not checked" (`PlanModel.swift:217`). New installs never get closures at all.
  - Second problem: per-park alerts tell NPS roughly where the user is (the parks within their radius). That contradicts the stated reason for always fetching all 63 forecasts (`PlanModel.swift:181-182`).
  - Why it matters: closures are the one safety-critical data point (the product brief §4), and they fail exactly when Nyx is featured. This costs Social Impact credibility and is real user harm.
  - Recommendation:
    1. One `alerts?parkCode=<all 63>&limit=500` call per 6 h per device, shared across every screen. This removes about 4.6 of the 8 calls and the location leak.
    2. Fetch events only on park detail, and keep them fresh for 24 h (programs are scheduled weeks ahead).
    3. Persist `retryAfter` to disk so a 429 survives relaunch.
    4. Add a designed "Park alerts are busy; check nps.gov conditions" state with a `Link`.
    5. With these, the break point rises to about 2.7k DAU. Past that, only an NPS limit increase helps (INPUT_NEEDED #10). That request should be made before submission, not "if Nyx grows".
  - Effort: M

- **[E2] Anyone can extract the NPS key from the IPA, and there is no rotation path.** Severity: P1
  - Evidence:
    - The key ships as plaintext Info.plist `NPS_API_KEY` (`project.yml:42`).
    - `release-verification.json` shows `"npsKeyEmbedded": true`.
    - The key is read with `Bundle.main.object(forInfoDictionaryKey:)` (`PlanModel.swift:174`).
  - Why it matters: one scraper can burn the hourly quota for every install, or get the key revoked. With no server, rotating the key requires an app update and review.
  - Recommendation:
    - Accept that the key is public, and reduce the blast radius with E1.
    - Keep a second registered key ready.
    - Add an optional "Use your own NPS key" field under Your privacy → Advanced. It is free, needs no server, and lets power users and reviewers get around a shared-quota outage.
    - Note in SUBMISSION that obfuscation is not a control.
  - Effort: S

- **[E3] The Open-Meteo free tier is "non-commercial, 10,000 calls/day". At scale, Nyx's per-IP burst and total volume are both at risk.** Severity: P1
  - Evidence:
    - One full refresh costs about 265 weighted calls: clouds 63 × (17 d / 14) ≈ 76, plus models 63, layers 63 and air 63 (`DataServices.swift:141-144, 238-250`). DECISIONS:196 says "≈ 250".
    - Terms: 600/min, 5,000/h, 10,000/day, and "We reserve the right to block applications and IP addresses that misuse our service" ([terms](https://open-meteo.com/en/terms), [pricing](https://open-meteo.com/en/pricing)).
    - The DECISIONS budget assumes one device per IP. Carrier CGNAT, lodge or visitor-center Wi-Fi, and a ranger star party all share IPs.
  - Scenarios:
    - **Three fresh launches behind one NAT within a minute** is 795 calls, over the 600/min limit. That 429 starts a 1 h per-kind backoff (`DataServices.swift:149, 254`) right when the crowd wants tonight's clouds.
    - **A featured day:** 100k DAU × about 2 refreshes × 265 ≈ **53M calls/day** on a free tier. Every request carries the same `Nyx/… CFNetwork` user agent, so a single block takes forecasts away from everyone.
  - Recommendation:
    1. Refresh the three detail kinds every 12 h, and only after the first park detail of a session. Still request all 63 parks, so the privacy property holds. This cuts launch cost to about 76 calls.
    2. Use `forecast_days=15` with `past_days=1` (16 days total, weight 1.14).
    3. Set `allowsConstrainedNetworkAccess = false` on detail requests (see E7).
    4. Owner action: get written confirmation from Open-Meteo that a free, ad-free App Store app is non-commercial, and give them expected volume before featuring.
  - Effort: S (code) + owner email

- **[E4] Losing signal makes the score go up. The audit's A4 is still open.** Severity: P1
  - Evidence:
    - `Forecast.swift:11` drops any forecast older than 36 h.
    - `ScoreEngine.swift:21` then divides by 0.75.
    - Example: moon 35, Bortle 17.5, length 10, clouds 90%. That scores 65 with clouds and **83 "Estimate"** without them.
    - Flagged as "Fix before release" in `Research/behavior-audit.md` A4. The code is unchanged.
    - Offline at the park (the core offline-first case), a cloudy night therefore reads as Excellent.
  - Why it matters: the score must never rise because data aged out. The project's own honesty rule is fixed in the product brief §17.
  - Recommendation: keep the last forecast past 36 h, labelled with its age ("clouds as of Fri 8 AM"). At minimum, never show a no-cloud score above the last known with-cloud score for that night.
  - Effort: S

- **[E5] Tonight never refreshes on return, so data shown as current can be days old.** Severity: P2
  - Evidence:
    - `.task(id: homeID+radius+location)` (`TonightView.swift:58`) re-runs only when its key changes.
    - Activation refreshes only saved parks (`RootView.swift:96-97, 255-263`). Location is never re-requested.
    - This is audit A2, partially open.
  - Recommendation:
    - Refresh Tonight's candidates on `scenePhase == .active` when the data is more than 1 h old.
    - Re-request location if it is authorized.
    - Show "as of {time}" once data is more than 6 h old.
  - Effort: S

- **[E6] A captive portal or any 3xx/4xx triggers a 15-minute blackout. Each request also pays for a new session and TLS handshake.** Severity: P3
  - Evidence:
    - `HostGuard` refuses redirects (`DataServices.swift:25-28`). The 302 then becomes `HTTPStatusError(302)` (`:50`), and `Backoff.delay` returns 900 s for every non-429 status (`:16-18`).
    - At a campground Wi-Fi portal, forecasts stay off for 15 minutes after the user signs in.
    - `SafeHTTP.get` builds and invalidates a new ephemeral `URLSession` per call (`:41-47`). That means about 20 sequential TLS handshakes for a 1,000 mi Tonight refresh.
  - Recommendation:
    - Back off only on 429 and 5xx. Treat 3xx as offline.
    - Keep one ephemeral session per transport instance, with the same configuration and delegate.
  - Effort: S

- **[E7] Low Data Mode and Low Power Mode are ignored for network.** Severity: P2
  - Evidence: there is no `allowsConstrainedNetworkAccess` or `allowsExpensiveNetworkAccess` anywhere (grep). Every refresh pulls about 4 multi-park responses.
  - Recommendation:
    - On constrained networks, fetch clouds only and skip models, layers and air.
    - Label it in the outlook ("Forecast detail paused in Low Data Mode").
  - Effort: S

#### Persistence and data safety

- **[E8] There is no `VersionedSchema` or `SchemaMigrationPlan`, and a store failure takes out the whole app.** Severity: P1
  - Evidence:
    - `Persistence.swift:4-21` defines plain `@Model` classes.
    - `NyxApp.swift:11-12` uses `ModelContainer(for:SavedPark.self,JournalEntry.self,…)`. On a throw, `NyxApp.swift:22` shows `CalmState` *instead of* `RootView`.
    - Grep finds no `VersionedSchema` anywhere.
  - Why it matters:
    - In 1.2, any non-lightweight change fails container creation. Examples: moving `photos: [Data]` to a `JournalPhoto` relationship, or renaming `observedBortle`.
    - When it fails, Tonight, Parks and Calendar, which need no journal, all disappear. That breaks "AI and network never load-bearing" at the storage layer.
    - The message says "this iPhone" on iPad as well.
  - Recommendation (before the first public build, because the first shipped store defines V1):
    - Wrap the current models in `enum NyxSchemaV1: VersionedSchema`, add an empty `NyxMigrationPlan`, and pass it to `ModelContainer(for:migrationPlan:configurations:)`.
    - On failure, run the planner with an in-memory container, show a journal-only banner, and leave the on-disk store untouched for the next build to recover.
    - Add a test that opens a V1 fixture store on disk.
  - Effort: S–M

- **[E9] Journal: no export, so data is lost with the phone, and no data is shared between iPhone and iPad.** Severity: P1
  - Evidence:
    - The store is the default `Application Support/default.store`. It is not excluded from backup, so it is in iCloud or Finder device backup. Settings already says this honestly (`SettingsAndLearn.swift:100`).
    - JournalViews has no `fileExporter` or `ShareLink` (grep). The only exit is a device backup.
    - The app is now universal, so an iPad has a separate, empty journal and nothing tells the user.
  - Why it matters: "Your journal never leaves this phone" also means it dies with the phone for anyone without iCloud Backup. A keepsake app without export reads as user-hostile to judges (Inclusivity, Social Impact) and to reviewers.
  - Recommendation:
    - Add Journal → Export (iOS 26): a `fileExporter` or `ShareLink` of a `.nyxjournal` package (entries JSON plus JPEGs) and an import. It is fully local and keeps the privacy label.
    - Add one line on iPad: "Journals stay on each device."
    - CloudKit stays out of v1 (§13).
  - Effort: M

- **[E10] Photos are stored as one `[Data]` external blob, so opening an entry loads every photo.** Severity: P3 (unverified)
  - Evidence: `@Attribute(.externalStorage) var photos: [Data]` (`Persistence.swift:15`). There are up to 4 photos of 2,400 px JPEG (`JournalViews.swift:168-172`). I believe SwiftData encodes an array attribute as a single value, so the whole array faults in at once (unverified).
  - Recommendation: model it as `JournalPhoto` (`@Attribute(.externalStorage) data`) with a relationship. Do it in the V2 migration that E8 makes possible.
  - Effort: M

#### Notifications

- **[E11] Reminders fire on forecasts the app itself would call expired.** Severity: P1
  - Evidence:
    - `scorePlans` qualifies any night ≥90 within 14 nights that has a forecast (`NotificationScheduler.swift:80-91`). It fires at 18:00 the evening before, with no limit on lead time.
    - Plans are rebuilt only when the app becomes active (`RootView.swift:96-97`). There is no `BGTaskScheduler` (grep) and no `UIBackgroundModes`.
    - So a night 13 days out, planned from a day-13 forecast, fires 12 days later saying "94/100, Pristine". Meanwhile `Forecast.mean` refuses any forecast older than 36 h (`Forecast.swift:11`).
  - Why it matters: this is the one proactive channel, and staleness is invisible there. It contradicts the app's own 36 h rule.
  - Recommendation:
    - iOS 26: schedule a score reminder only if `fireDate − forecast.updated ≤ 36 h`.
    - Add a `BGAppRefreshTask` (`fetch` mode plus `BGTaskSchedulerPermittedIdentifiers`; same three hosts, privacy unchanged) to refresh clouds for saved parks and re-plan. This lets reminders reach 2–5 days out honestly.
    - On iOS 27+, keep the `appEntityIdentifiers` path.
  - Effort: M

- **[E12] The tapped notification opens tonight, not the reminded night. Two iPad windows run `updateSaved` twice.** Severity: P3
  - Evidence:
    - `userInfo` carries only `parkID` (`NotificationScheduler.swift:29`). This is audit A5, still open.
    - `savedUpdating` is per-view `@State` (`RootView.swift:18`), so two scenes reschedule concurrently and race on the `issuedReminders` read-modify-write (`NotificationScheduler.swift:47-55`). Same-ID adds keep this benign, but it is wasted work.
  - Recommendation:
    - Add the night stamp to `userInfo` and route through `DeepLink.whatsUp`.
    - Move the saved-park sync into `PlanModel`, one per process, not per window.
  - Effort: S

#### Watch, widgets, Live Activity

- **[E13] The watch drops every context when the phone app and watch app versions differ.** Severity: P2
  - Evidence: `WatchContext.init?(data:)` requires `decoded.version == Self.currentVersion` (`WatchContext.swift:49`). Watch apps update on their own schedule, so the first shape change (1.2 "Field") leaves updated phones paired with old watches showing no saved parks or clouds.
  - Recommendation:
    - Decode tolerantly: new fields optional, version ≥ minimum.
    - Have the phone send both shapes for one release.
    - Add a test that decodes the v1 fixture.
  - Effort: S

- **[E14] Widget snapshot and isolation drift across targets.** Severity: P3
  - Evidence:
    - `SavedSkySnapshot` encodes whole `Park` structs with no version (`SharedSettings.swift:21-23`). Adding a non-optional `Park` field blanks the widget until the app is opened.
    - The snapshot carries no closures (audit A3, still open). The widget can say "91 Pristine" for a closed park.
    - `NyxWatchWidgets` lacks `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (`project.yml:181-205`) but compiles the same shared files as targets that have it. The same source therefore has different isolation in different targets.
  - Recommendation:
    - Add a `version` field and a closure title per park to the snapshot.
    - Set the isolation in `NyxWatchWidgets`, or mark shared files explicitly `nonisolated`.
  - Effort: S

#### Launch and performance

- **[E15] The production launch path has never been measured. The 2.2–3.8 s figure is a Debug run of a DEBUG scenario.** Severity: P1
  - Evidence:
    - `testOfflineLaunchResponsiveness` launches with `-nyx-screen tonight -nyx-state no-forecast -nyx-reduce-motion` (`NyxUITests.swift:8-11, 62-68`).
    - `DebugScenario.screen != nil` skips the cache reads (`PlanModel.swift:60`), onboarding, the reveal, `FirstLightWatcher`, `LuminanceProof`, Spotlight and `updateSaved` (`RootView.swift:84-93`).
    - `Research/performance.md` and `launch-metrics.json` are dated 2026-10-02 (15 tests, iPhone only). They predate iPad, Real Sky and field mode.
  - Synchronous main-actor work before the first frame (static reading):
    1. `ModelContainer` open (`NyxApp.swift:11`).
    2. `NyxShortcuts.updateAppShortcutParameters()` (`:16`).
    3. `SkyGlow.lightSources` decodes 48 KB of JSON (`:17`).
    4. `PlanModel.init`: `parks.json` at 98 KB, plus **189 cache reads and decodes**: weather, park and detail files for 63 parks, about 1.5 MB in a simulator container. Each miss costs a second failed open on the legacy path (`DataServices.swift:73`).
    5. `RootView.currentMoonIcon()` `ImageRenderer` in a `@State` initializer.
    6. Tonight ranks candidates (astronomy per park), then `SkyProjection` decodes `stars.json` and projects 904 stars.
    - Then the actors read the same 126 forecast and detail files again on the first refresh (`DataServices.swift:105, 184`).
  - Recommendation:
    - Wrap each phase in `os_signpost` (`OSSignposter`).
    - Measure a Release build on the oldest supported iPhone with Instruments App Launch, cold and warm, on iOS 26 and 27. Record the results in `performance.md`.
    - Move cache hydration into the actors, off the main thread, and paint from parks.json plus bundled data first.
    - Render the moon icon after first frame.
    - Load each cache once, not twice.
  - Effort: M

- **[E16] The gauge redraws at the display rate indefinitely, and ProMotion above 60 Hz is not enabled anyway.** Severity: P2
  - Evidence:
    - `TimelineView(.animation(minimumInterval:nil,…))` (`CelestialGauge.swift:117`) runs whenever the gauge is visible, not only during the count-up. It redraws radial gradients and 28 orbit particles every frame, over Real Sky's 30 Hz `TimelineView` (`RealSky.swift:24`) and 30 Hz Core Motion (`MotionTilt.swift:32`).
    - The audit text still claims "decorative timelines at 20 Hz".
    - Info.plist lacks `CADisableMinimumFrameDurationOnPhone`. Per Apple's ProMotion guidance, that caps custom animation on iPhone at 60 Hz, so the brief's 120 Hz scrub and gauge are not delivered (device effect unverified).
  - Why it matters: this is Interaction award depth (time river scrub) against battery cost.
  - Recommendation:
    - Cap ambient layers at 30 Hz and the gauge at 30 Hz after the count-up.
    - Set `CADisableMinimumFrameDurationOnPhone = YES` and request high rates only during gestures (the time river drag and the count-up).
    - Measure on a 120 Hz device.
  - Effort: S

- **[E17] Field mode can keep the screen and sensors on all night with no battery or thermal guard.** Severity: P2
  - Evidence:
    - `isIdleTimerDisabled=true` until exit (`FieldSession.swift:49`).
    - "Where to look" runs a 30 Hz Canvas plus 30 Hz device motion (`FieldCompass.swift:45`, `FieldServices.swift:150`).
    - There is no `thermalState` or `powerStateDidChange` handling anywhere (grep). `isLowPowerModeEnabled` is only read in `body` or `begin()`, so turning on Low Power Mode mid-session changes nothing (`MotionTilt.swift:31`, `RealSky.swift:24`).
    - A phone left in a pocket with field mode open stays awake until dawn.
  - Recommendation:
    - Re-enable auto-lock after about 10 minutes without touch (the Live Activity carries the night).
    - Pause the compass on `.serious` thermal state.
    - Observe `NSProcessInfoPowerStateDidChange`.
    - On iOS 27, also honour `systemPrefersReducedResourceUsage` in field mode (it exists only on anyAppleOS 27; already gated in `NyxAccess.swift:32-35`).
  - Effort: S

#### Concurrency and architecture

- **[E18] Swift 6 strict mode is in place, but there are three latent races.** Severity: P3
  - Evidence:
    - (a) `ParkStore.enrichment`: a waiter resumes from `inFlight` (`DataServices.swift:302`) before the owner clears it (`:308`). The `inFlight[park.id] == nil` guard (`:304`) then returns cached data without programs. Opening a park while Tonight's alerts request is in flight can show "programs not checked".
    - (b) With `SWIFT_APPROACHABLE_CONCURRENCY`, `nonisolated async` functions inherit the caller's actor. So `NotificationScheduler.reschedule`/`plans` and `showerPlans` (which recomputes `WhatsUp.Events` for 14 × N nights, `NotificationScheduler.swift:100-101`) run on the main actor when called from `RootView.publishSaved`.
    - (c) `FieldPresenter` and `RootView.open` push `UIHostingController`s onto "the key window" (`RootView.swift:196-201`, `FieldSession.swift:~150`). On iPad with two windows this can present in the wrong scene, and it bypasses SwiftUI state.
  - Recommendation:
    - (a) Loop until `inFlight` is nil, then re-evaluate `due`.
    - (b) Mark heavy planners `@concurrent` (already used in `GuideTools.swift:103`).
    - (c) Route through each scene's own `SceneCommands`, using the scene that received the URL or activity.
  - Effort: S

- **[E19] "Sky + forecast → Night" is composed in seven places.** Severity: P2
  - Evidence:
    - `PlanModel.swift:86`, `NightPlanner.swift:17`, `SharedSettings.swift:32`, `TripPlanner.swift:112`, `NyxIntents.swift:92`, `WatchSky.swift:47`, `VisionModel.swift:21/146`.
    - Rules like the 36 h expiry `now:`, closures and ERA5 rank scores must be kept in sync by hand across app, widget, Siri, watch and Vision. Audit A3 was exactly this kind of drift.
  - Recommendation: make `NightPlanner.night(park:sky:forecast:now:)` the only constructor, and add one test that compares every surface for a fixture night.
  - Effort: M

- **[E20] Code density and debug hooks in shipping files.** Severity: P3
  - Evidence:
    - 250 lines over 200 chars and 69 over 300; the longest is 1,087 chars (`SettingsAndLearn.swift:184`, `JournalViews.swift:264` at 916).
    - Statements are packed with semicolons and no spaces around `=`.
    - `DebugScenario.` appears 82 times across 14 non-debug files. The release values compile to nil, which is correct, but the noise is high.
    - The `Debug*.swift` files are properly `#if DEBUG` (checked: DebugField, DebugForecasts and DebugPlatform are wrapped whole; DebugScenario returns nil in Release).
    - There is no `try!`, `fatalError` or `@unchecked` beyond the two WatchConnectivity delegates, which are lock-guarded.
  - Recommendation:
    - Run `swift format` once (it ships with the toolchain).
    - Inject a `Scenario` value instead of global lookups.
  - Effort: S

#### Tests, CI and reproducibility

- **[E21] There is no CI. The evidence files are stale, and the release check passes even with no NPS key.** Severity: P1
  - Evidence:
    - There is no `.github`, `ci_scripts` or `.xctestplan`.
    - `test-26.json` and `test-27.json` report 17 tests (dated 2026-10-02). The suite now has 166 Swift Testing and 7 UI tests (grep counts).
    - `verify_release.py:72-78` asserts only that the key is "not unexpanded". With no `Secrets.xcconfig`, the key is empty and the check passes.
    - `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` applies to Release too (`project.yml:25-26`). An Xcode point release with new deprecations blocks a launch-day hotfix.
  - Recommendation: add Xcode Cloud, which is Apple-native.
    - `ci_scripts/ci_post_clone.sh` writes `Config/Secrets.xcconfig` from a secret environment variable and fails if it is empty.
    - Workflow "PR/main": build `Nyx`, `NyxWatch` and `NyxVision`; test `NyxTests` and `NyxUITests` on an iOS 26.x and an iOS 27 simulator with a pinned Xcode.
    - Workflow "Release" on tag `v*`: archive `Nyx` and `NyxVision`, set `CURRENT_PROJECT_VERSION=$CI_BUILD_NUMBER`, run `verify_release.py`, and send to internal TestFlight.
    - Turn warnings-as-errors off for Release and on for CI.
    - Add a `Nyx.xctestplan` with a "Release-like" configuration.
  - Effort: M

- **[E22] Test gaps where the risk is.** Severity: P2
  - Not covered:
    - SwiftData migration or on-disk open. The only journal test is `NyxTests.swift:267`, in memory.
    - Watch-context version skew.
    - Widget timeline time and memory, plus snapshot decode across versions.
    - Captive-portal and 3xx handling.
    - The `ParkStore` in-flight race.
    - Notification lead time against forecast age.
    - Launch with populated caches.
    - Visual regression for the hero renderings (gauge, moon, river, sky arc).
  - Fragility:
    - 10 tests read the wall clock (`Date.now`).
    - `FieldModeTests.swift:284` builds a real `PlanModel()`, which reads the host's real caches and `UserDefaults.standard`.
    - The watch and Vision apps have no test targets of their own.
  - Recommendation:
    - Add the cases above.
    - For visuals, render with `ImageRenderer` at fixed sizes and compare against PNG goldens with a perceptual tolerance in Swift Testing. No third-party code is needed.
    - Inject clocks.
  - Effort: M

- **[E23] Repo hazards: iCloud Drive with Optimize Storage, and Secrets on one Mac only.** Severity: P1
  - Evidence:
    - `~/Documents` carries `com.apple.file-provider-domain-id`, and `com.apple.bird` has `"optimize-storage" = 1`. iCloud can therefore evict `.git` objects or sources to dataless files.
    - It already dropped "name 2" conflict copies into synchronized source folders (`PHASE_STATUS.md:7`). Synchronized folders compile any stray `.swift` file.
    - `Secrets.xcconfig` exists only in that folder.
    - Mitigation already in place: `origin` on GitHub is up to date (0 commits ahead).
  - Recommendation:
    - Move the repo to `~/Developer/Nyx`, outside iCloud. This is the owner's call; it is already in INPUT_NEEDED.
    - Store the NPS key in the Xcode Cloud secret plus a password manager.
  - Effort: S

#### Release engineering

- **[E24] The shipping archives and dSYMs live in `/tmp`.** Severity: P1
  - Evidence:
    - `release-verification.json` names `/tmp/Nyx-1.1-7.xcarchive` and `/tmp/NyxVision-1.1-7.xcarchive`. The 1.1 (7) archive has `dSYMs/` there, with `Distributions → Uploaded`.
    - `~/Library/Developer/Xcode/Archives` holds only another app's archives.
    - macOS purges `/tmp` on reboot, after which the symbols for the build under review are gone locally. If the upload's symbols were incomplete, Organizer crash logs cannot be symbolicated (unverified whether symbols were uploaded).
  - Recommendation:
    - Move both archives into `~/Library/Developer/Xcode/Archives/2026-10-06/` now.
    - Archive to that location from now on, or let Xcode Cloud keep the artifacts.
    - Confirm "Include symbols" in the upload.
  - Effort: S

- **[E25] The first release gets no phased rollout, and crash data depends on users opting in.** Severity: P2
  - Evidence:
    - 1.0 never shipped, so 1.1 is the first version. Phased release applies only to updates, so the build reaches 100% of installs on day 1.
    - Crash reporting is Organizer only, which needs users to opt into "Share with App Developers".
    - MetricKit is used only for luminance (`LuminanceProof.swift`). `MXCrashDiagnostic` and `MXHangDiagnostic` are not kept.
    - Nothing has run on a physical device yet (INPUT_NEEDED #1).
    - The "What's New" text for a first version is not shown on the product page (`SUBMISSION.md:21`).
  - Recommendation:
    - Run an external TestFlight round (25–100 testers, iOS 26 and 27, including older hardware) before submitting.
    - Keep MetricKit crash and hang diagnostics on device, and offer "Copy diagnostic report" in Support. It is user-initiated, so still Data Not Collected.
    - Use phased release from 1.1.1.
  - Effort: S–M

- **[E26] Review-risk scan: clean, with small items.** Severity: P3
  - Clean:
    - No `UIBackgroundModes` are declared, so there is no unused-mode rejection risk.
    - `NSAlarmKitUsageDescription` and `NSSupportsLiveActivities` are present, and AlarmKit is gated to iOS 26.1 (`FieldServices.swift:~70`).
    - Location is When In Use only.
    - `EKEventEditViewController` needs no calendar permission string.
    - PhotosPicker needs no usage string.
    - There are no SPM packages.
  - Small items:
    - If E11 adds `BGAppRefreshTask`, `fetch` mode must be declared, used, and explained in review notes.
    - The `CalmState` store-failure text says "iPhone" on iPad (`NyxApp.swift:22`).
  - Effort: S

### Strengths worth protecting
- The `SafeHTTP` allowlist, per-host toggles, refusal of redirects, and `verify_release.py`'s static host and URL scan. This is privacy enforced in code, not just stated in docs.
- The actor-based services with in-flight dedupe, multi-coordinate batching, and "a failed request never wipes known closures or forecasts" (`DataServices.swift:342-348`).
- Swift 6 language mode with MainActor default isolation, zero warnings, no `try!` or `fatalError`, and the `#if DEBUG` hygiene.
- The honest 36 h expiry and estimate labelling, the reminder ledger, and DST-correct `UNCalendarNotificationTrigger` with the park's time zone and gregorian calendar.
- The watch makes no network calls, verified by the release script. The watch context is byte-budgeted.

### Open questions for the owner
1. Will you ask NPS for a raised limit *before* submission, and accept an optional "use your own key" field?
2. Will you email Open-Meteo to confirm non-commercial status and the expected volume? If they decline at scale, which matters more: fewer detail refreshes, or dropping a detail kind?
3. Do you approve one background mode (`fetch`) so reminders can be re-checked against fresh forecasts?
4. Journal export format: a private `.nyxjournal` package (round-trips), or a human-readable folder (JSON plus photos)?
5. Will you move the repo out of iCloud Drive before launch week?
