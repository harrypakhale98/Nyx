## Platform APIs (iOS 26 / iOS 27 showcase) — findings

Method: inventoried every availability guard and platform framework in `Nyx/`, `NyxWidgets/`, `NyxWatch*/`, `NyxVision/`; checked each candidate symbol against the installed `iPhoneOS27.0.sdk`, `WatchOS27.0.sdk` and `XROS27.0.sdk` `.swiftinterface`/header files (availability copied from them below). Nothing was built or run.

### Verdict
Nyx's newer-OS adoption is unusually deep and correct. Nearly every row of the roadmap's "Newer-OS APIs" table is shipped behind correct guards, and no iOS 27 branch falls back to an empty view. What's missing is less about new APIs than about a few iOS 26 capabilities that change what the night feels like. The Live Activity can't start itself at dusk, nothing refreshes a "Pristine Friday" reminder after it is scheduled, and NPS closure text isn't translated for the Spanish UI. The Live Activity has no designed wrist or CarPlay layout, there is no in-app "night in progress" accessory, and Liquid Glass serves as a background material rather than an interaction material. Moonlitt, which won Interaction in 2026, was cited for "best-in-class Liquid Glass integration", so that last gap matters. One iOS 26 fallback is second-rate: on iOS 26, VoiceOver still reads "Bortle" as "bottle", even though an iOS 15 API can fix it.

### Inventory (what is already used, verified in source)
- **iOS 27, guarded:** `topBarPinnedTrailing` (Nyx/Views/ParkViews.swift:379), `NavigationTransition.crossFade` (Nyx/DesignSystem/NyxAccess.swift:54), `toolbarMinimizationBehavior(.onScrollDown,for:)` (ParkViews.swift:508), `systemPrefersReducedResourceUsage` (NyxAccess.swift:32-39), `accessibilitySpeechSSML` (NyxAccess.swift:88), MetricKit Swift `MetricManager` + `.pixelLuminance` (Nyx/Services/LuminanceProof.swift:57-79), `CMDeviceMotion.headingAccuracy` (FieldServices.swift:156), `AlarmConfiguration(…appEntityIdentifier:)` (FieldServices.swift:110), `UNMutableNotificationContent.appEntityIdentifiers` (NotificationScheduler.swift:31), `IndexedEntityQuery.reindex*` (Nyx/Intents/NyxIntents.swift:41), `CSSearchableItem.relatedAppEntityIdentifier` (SpotlightIndexer.swift:19), `IntentSystemContext.isVoiceOnly` (BestNightIntent.swift:31), FoundationModels `ContextOptions(reasoningLevel:)` (OnDeviceGuide.swift:41,88), throwing `AVAudioEngine.connectNode` (NightSound.swift:194).
- **iOS 26.4:** `accessibilityReduceHighlightingEffects`, `accessibilityPrefersCrossFadeTransitions` (NyxAccess.swift:16-24), `SystemLanguageModel.contextSize` / `tokenCount(for:)` (OnDeviceGuide.swift:64,80).
- **iOS 26 / earlier, used:** Liquid Glass `glassEffect` (NyxTheme.swift:59, CelestialGauge.swift:81, TonightView.swift:261) and `.buttonStyle(.glass)` (FieldView.swift:397); `Tab` + `.sidebarAdaptable`; zoom transitions; `sensoryFeedback`; Core Haptics; TipKit; AlarmKit (26.1 alert init); ActivityKit Live Activity + Dynamic Island; AlarmKit Live Activity; Control widgets (toggle + button); `WidgetRelevance`; interactive snippet `SnippetIntent` (BestNightIntent.swift:107); `IndexedEntity` + `associateAppEntity`; `SetFocusFilterIntent`; `supportedModes` (not the deprecated `openAppWhenRun`); `EKEventEditViewController`; `AXChartDescriptor`; accessibility rotors; FoundationModels tools and `@Generable`; watch `RelevanceConfiguration` (NyxWatchWidgets/NyxWatchWidgetsBundle.swift:86); visionOS progressive `ImmersiveSpace` + `RealityView` + ornaments.
- **Availability guards: all correct.** Every iOS 27 or 26.x symbol above sits behind `if #available` or `@available` at the right version. I checked the deployment target (26.0, `project.yml:7`) against the SDK annotations, and `SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` (`project.yml:26`) means an unguarded symbol couldn't compile. I found no `@available` misuse and no iOS 27 branch whose `else` is empty. Second-rate fallbacks are covered in PA-4 and PA-19.

### Findings

- **[PA-1] The night's Live Activity can't start itself. iOS 26 can schedule it for dusk** — Severity: P1
  - Evidence: `FieldActivities.start` calls `Activity.request(attributes:content:)` only while the app is open in field mode (Nyx/Services/FieldServices.swift:44-50). In the SDK, `ActivityKit.swiftinterface:61-68` declares `@available(iOS 26.0, *) public static func request(attributes: Attributes, content: ActivityContent<…>, pushType: PushType? = nil, style: ActivityStyle, alertConfiguration: AlertConfiguration, start: Foundation::Date) throws -> Activity<Attributes>`. Its swiftdoc says: "The system starts the Live Activity at the specified date, even if the app is in the background… The ActivityState for a scheduled but not yet started Live Activity is `pending`." The `startDate:` spelling is deprecated in 26.0.
  - Why it matters: Interaction and Innovation. Field mode is the signature moment, but today it starts only if someone opens Nyx at the site, on a phone with no signal, in the dark. A scheduled activity means the night begins on the Lock Screen and the wrist by itself. "Follow Friday at Joshua Tree" on Wednesday, and at dusk Friday the countdown appears with no app launch and no push server. That keeps §13 intact: everything is computed on device.
  - Recommendation: add a "Follow this night" action on the detail, the calendar night peek and `FindBestNightIntent`'s snippet. It calls the `start:` overload with `style: .standard`, `alertConfiguration: AlertConfiguration(title: "Tonight at Joshua Tree", body: "True darkness at 7:42 pm", sound: .default)` and `start` = sunset − 30 min. Choose the start so that 8 hours of activity covers the darkest part on long winter nights; Apple's limits are about 8 h active plus 4 h on the Lock Screen (from documentation, not in the SDK — **unverified**). Cancel it from the same row. Pending activities count toward the system's concurrent-activity limit (swiftdoc), so keep one per night. This needs no iOS 27 path. Test that the existing `refresh(nightVision:)` handles `.pending`.
  - Effort: M

- **[PA-2] Nothing refreshes saved-park forecasts in the background, so a "Pristine" reminder fires on a forecast that may be two weeks old** — Severity: P1
  - Evidence: Reminders are planned only when the app becomes active (RootView.swift:99-103, `updateSaved`). A ≥90 reminder fires at 18:00 the evening before the night (NotificationScheduler.swift:80-91), using whatever forecast existed at planning time, for any of the next 14 nights. No `BGTaskScheduler`, no `.backgroundTask(.appRefresh…)` and no `UIBackgroundModes` exist (`grep` over Nyx/ and Config/: the only `backgroundTask` is the watch's `.watchConnectivity`, NyxWatch/NyxWatchApp.swift:8). The widget handles this by dropping forecasts older than 36 h (NyxWidgetsBundle.swift:73); notifications have no equivalent.
  - Why it matters: honesty is the brand, and §5 says "driving four hours … is the worst outcome". "A promising night at Death Valley: 94/100", sent on a forecast from 12 days earlier, is the most misleading thing Nyx can do. The body's "Forecasts can change" doesn't undo the title.
  - Recommendation: on iOS 16+ (first-class on 26), add `WindowGroup { … }.backgroundTask(.appRefresh("com.harrypakhale.nyx.refresh")) { await refreshSavedForecastsAndReplan() }` and submit `BGAppRefreshTaskRequest(identifier:)` with `earliestBeginDate` about 6 h after each refresh. Add `UIBackgroundModes: [fetch]` and `BGTaskSchedulerPermittedIdentifiers` in project.yml. Requests stay on `api.open-meteo.com` with park coordinates only, so §13 is unchanged. Refresh the widget snapshot and `WatchBridge` from the same task. Independently, re-check the forecast's age at planning time: a reminder for a night more than about 5 days out should wait, or fall back to "moon and darkness" wording. iOS 27 adds nothing needed here; the `submit(_:) async` form in BGTaskScheduler.h:145 is optional.
  - Effort: M

- **[PA-3] NPS closure alerts and ranger programs stay in English inside the Spanish app. On-device translation exists since iOS 17.4** — Severity: P1
  - Evidence: Alert title and description are shown verbatim (Nyx/Views/ParkViews.swift:296-303), and so are program descriptions (ParkViews.swift:368). Spanish ships (DECISIONS.md:403-413), and no decision covers NPS text. In the SDK, `_Translation_SwiftUI.swiftinterface:13-18` declares `@available(iOS 17.4, *) func translationPresentation(isPresented: Binding<Bool>, text: String, attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds), arrowEdge: Edge = .top, replacementAction: ((String) -> Void)? = nil)`. `translationTask(source:target:action:)` is iOS 18, and `TranslationSession(installedSource:target:)` is iOS 26 (`Translation.swiftinterface:188`).
  - Why it matters: Inclusivity. The jury criterion names languages, and the closure text is the safety-critical part, not decoration. A Spanish speaker sees a fully Spanish app except for "Road closed."
  - Recommendation: when `Locale.current.language` isn't English, add a "Traducir" button under "All park alerts" and each program that calls `translationPresentation`, which is a system sheet and user-initiated. Optionally, on iOS 26, pre-translate with `TranslationSession(installedSource:target:)` only when the language pack is already installed, labelled "Traducción automática". It runs on device, but **unverified** whether the first language-asset download counts against "Data Not Collected" (it is Apple's system download, like dictation). Confirm on a device in airplane mode and add one line to PRIVACY.md.
  - Effort: S

- **[PA-4] Second-rate iOS 26 fallback: VoiceOver says "bottle" for Bortle on iOS 26, though an iOS 15 API fixes it** — Severity: P2
  - Evidence: `SpokenText.make` returns plain `Text(verbatim:)` below iOS 27 (Nyx/DesignSystem/NyxAccess.swift:87-98). In the SDK, `Accessibility.swiftinterface:67` declares `public let accessibilitySpeechPhoneticNotation: …IPANotationAttribute` inside `AccessibilityAttributes` with `@available(iOS 15.0, *)` (line 53). Only `accessibilitySpeechSSML` is `anyAppleOS 27.0` (line 70-71).
  - Why it matters: Inclusivity, and the brief's "complete, first-class iOS 26 experience". Bortle appears on every detail page.
  - Recommendation: in the iOS 26 branch, set `attributed[range].accessibilitySpeechPhoneticNotation = "ˈbɔɹtəl"` for "Bortle". Keep SSML on 27, which can also handle "A*" and the language switch. Extend AccessibilityDepthTests.swift:158 to cover both paths.
  - Effort: S

- **[PA-5] The Live Activity has no designed layout for the Apple Watch Smart Stack or CarPlay** — Severity: P2
  - Evidence: `FieldLiveActivity` and `FieldAlarmLiveActivity` declare no `.supplementalActivityFamilies` (NyxWidgets/FieldLiveActivity.swift:11,53), and there is no `activityFamily` read anywhere (grep). In the SDK, `WidgetKit.swiftinterface:770-777` declares `@available(iOS 18.0, *) func supplementalActivityFamilies(_ families: [ActivityFamily]) -> some WidgetConfiguration` with `ActivityFamily { case small, medium }` (line 750), and `EnvironmentValues.activityFamily` (787). The fixed `maxWidth:52/90` caps (FieldLiveActivity.swift:29,70,73) are what iOS 27's `@available(iOS 27.0, *) var isDynamicIslandLimitedInWidth: Bool` (WidgetKit.swiftinterface:604-611; "applies to compactLeading, compactTrailing, and minimal") was made for.
  - Why it matters: the roadmap says "at a dark site the wrist is the right screen." watchOS shows iPhone Live Activities in the Smart Stack. Without `.small`, the system composes one from the compact views (Apple documentation, **unverified** in the SDK). The same family is reported to drive iOS 26 CarPlay Live Activities (**unverified**).
  - Recommendation: add `.supplementalActivityFamilies([.small])` and branch on `@Environment(\.activityFamily)` to a red-only, large-numeral "True darkness in 14 min" card. On iOS 27, read `isDynamicIslandLimitedInWidth` to drop the countdown to minutes only rather than truncating. Review on a paired watch (add to INPUT_NEEDED item 2).
  - Effort: S

- **[PA-6] No in-app sign of a night in progress. iOS 26's tab bottom accessory is the native pattern** — Severity: P2
  - Evidence: The `TabView` in RootView.swift:44-53 has no `tabViewBottomAccessory`. `FieldActivities.isFollowing` is read only inside field mode (FieldView.swift:379,388). In the SDK, `SwiftUI.swiftinterface:17566-17579` declares `@available(iOS 26.0, *) func tabViewBottomAccessory<Content>(content:)`, `@available(iOS 26.1, *) func tabViewBottomAccessory<Content>(isEnabled: Bool, content:)` and `EnvironmentValues.tabViewBottomAccessoryPlacement` (iOS 26, line 6822-6824).
  - Why it matters: Liquid Glass and Interaction. While following a night, someone browsing Calendar has no glass "now playing"-style strip that says "Joshua Tree · darkness in 14 min ▸" and returns to the red field screen. That accessory is the most recognisable iOS 26 shell element, and Nyx has a reason to use it that most apps don't.
  - Recommendation: on iOS 26.1+, `.tabViewBottomAccessory(isEnabled: FieldActivities.current != nil) { NightInProgress() }`, compact when `placement == .inline`. On 26.0, nothing (negligible installed base). Under night vision use the solid capsule already used by `ParkPill` (TonightView.swift:252-262). It is iPhone-only (unavailable on visionOS), and sidebar iPad gets nothing extra.
  - Effort: S

- **[PA-7] Liquid Glass is a background material only, with no interactive, morphing or grouped glass** — Severity: P2
  - Evidence: Four call sites, all static backgrounds (see the inventory above). `GlassEffectContainer`, `glassEffectID`, `glassEffectUnion`, `.interactive()` and `glassEffectTransition` have zero uses (grep). The 2026 Interaction winner was cited for "best-in-class Liquid Glass integration" (Research/award-roadmap.md:20).
  - Why it matters: Visuals and Graphics and Interaction. The time river, night-vision toggle and calendar month switcher are where judges touch the app, and none of them responds as glass.
  - Recommendation: make the time river's scrub position a small `.glassEffect(.regular.interactive(), in: .circle)` lens that refracts the river under the finger. Morph the Tonight park pill into the park picker with `glassEffectID` in a `GlassEffectContainer`. Group field-mode's control cluster in one container. Keep the existing solid fallbacks for night vision, Reduce Transparency and Increase Contrast (NyxTheme.swift:56-58). Before writing, check the `.interactive()` / `GlassEffectContainer` signatures in SwiftUICore; they are iOS 26 per the interface, but the exact spelling was **unverified** here.
  - Effort: M

- **[PA-8] Logging a night means lighting the screen. The iOS 18 journal schema allows logging by voice** — Severity: P2
  - Evidence: There is no `@AppIntent(schema:)` or `@AppEntity(schema:)` in the repo (grep). In the SDK: `AppIntents.swiftinterface:10944` declares `@available(iOS 18.0, *) macro AppIntent<T>(schema: T)`, line 10769 declares `macro AppEntity<T>(schema: T)`, and lines 13300-13345 declare `@available(iOS 18.0, *)` `.journal` with `CreateJournalEntryIntent` (`createEntry`), `UpdateJournalEntryIntent` and `JournalEntity` (`.journal.entry`).
  - Why it matters: Inclusivity and the night itself. "Siri, add to my Nyx journal: Milky Way overhead from the dunes" keeps dark adaptation intact. A notes screen at full brightness costs 20 minutes of it. It also makes the journal available to Apple Intelligence and Shortcuts without new UI.
  - Recommendation: `@AppEntity(schema: .journal.entry) struct JournalEntryEntity` mapped from `JournalEntry` (date → entryDate, notes → message, photos → mediaItems). The location should be a `CLPlacemark` built offline from the park; no geocoding. Then `@AppIntent(schema: .journal.createEntry)` writes to SwiftData with the active field park as default. Let the macro diagnostics confirm the required property set (**unverified** in detail). `.journal.search` is deprecated in 27 for `.system.searchInApp` (line 13332), so skip search.
  - Effort: M

- **[PA-9] The brief's flagship Siri question returns words only** — Severity: P2
  - Evidence: `DarknessIntent.perform() -> some IntentResult & ProvidesDialog` (Nyx/Intents/NyxIntents.swift:79-92), while `FindBestNightIntent` already has an interactive snippet (BestNightIntent.swift:107-123). Neither intent returns a value (`ReturnsValue`), so Shortcuts and the "Use Model" action can't chain the score.
  - Why it matters: the product brief §5.13's example ("What's the darkness score at Joshua Tree tonight?") is the intent people will actually try, and it is the visual moment judges see in a demo.
  - Recommendation: return `ShowsSnippetView` with the static gauge and Moon disc (reuse `BestNightSnippetView`'s layout and the share card's static gauge), plus `ReturnsValue<Int>` (score). Give `FindBestNightIntent` `ReturnsValue<ParkEntity>` or a date. Add `@ComputedProperty(indexingKey:)` (`@available(iOS 26.0, *)`, AppIntents.swiftinterface:3966) for state, Dark Sky designation and Bortle on `ParkEntity`, so Spotlight and Shortcuts can filter "Dark Sky parks in Utah".
  - Effort: S

- **[PA-10] A user-initiated Maps hand-off is ruled out, though Nyx already hands off to Safari** — Severity: P2
  - Evidence: DECISIONS.md:180 says "no Maps hand-off, so the app still names no host beyond the two in the brief." The app already opens Safari to nps.gov and Globe at Night (Nyx/Views/SkyGlowViews.swift:126,184).
  - Why it matters: the user's actual next step after "where and when" is driving to a named viewing spot, and copying coordinates by hand is not award-grade. Opening `maps://?daddr=<lat>,<lon>&dirflg=d` through `openURL` makes no request from Nyx's process. It is the same class of hand-off as the Safari links, and Apple Maps supports downloaded offline maps.
  - Recommendation: owner decision (see the open questions). If approved, add "Directions in Maps" beside "Copy coordinates" on each viewing spot, with no MapKit import and no in-app map tiles. Note the hand-off in PRIVACY.md. In-process MapKit, MKLocalSearch and the iOS 27 `MKPointOfInterestCategoryRangerStation` (MapKit headers, `API_AVAILABLE(ios(27.0))`) stay out under §13.
  - Effort: S

- **[PA-11] visionOS: the room stays bright under the "night sky", and there is no visionOS widget** — Severity: P2
  - Evidence: There is no `preferredSurroundingsEffect` anywhere in NyxVision (grep). The immersive space is progressive at 0.35…1 (NyxVision/App/NyxVisionApp.swift:13-16), so the person's room is visible at partial immersion. In the XROS SDK, `SwiftUI.swiftinterface:2779` declares `@available(visionOS 1.0, *) func preferredSurroundingsEffect(_ effect: SurroundingsEffect?)`, with `.semiDark/.dark/.ultraDark` from visionOS 2.0. No visionOS widget target exists (project.yml lists only the iOS `NyxWidgets`), while `WidgetKit` (XROS) declares `@available(visionOS 26.0, *) supportedMountingStyles([.elevated, .recessed])`, `widgetTexture(.glass/.paper)` and `levelOfDetail`.
  - Why it matters: Visuals and Graphics, and Moonlitt's "every platform". "Stand under tonight's sky" in a lit room undercuts the planetarium. A recessed widget pinned to a wall, a window into tonight's sky over the saved park, is a natural and rare visionOS 26 showcase.
  - Recommendation: apply `.preferredSurroundingsEffect(.ultraDark)` to `SkySpace` (`.dark` when Reduce Transparency is on), tied to the immersion amount via `onImmersionChange`. Add a `NyxVisionWidgets` extension with one recessed widget (moon and darkness only; Vision has no network), simplified at `levelOfDetail == .simplified` to the numeral and Moon.
  - Effort: S (surroundings) / M (widget)

- **[PA-12] The AlarmKit alert's only secondary action is Snooze, never "open the sky in red"** — Severity: P2
  - Evidence: `AlarmPresentation.Alert(title:secondaryButton: snooze, secondaryButtonBehavior: .countdown)` with no `secondaryIntent` (FieldServices.swift:104-111). In the SDK, `AlarmKit.swiftinterface:43-45` declares `SecondaryButtonBehavior { case countdown, custom }`, and `AlarmConfiguration(…, secondaryIntent: (any LiveActivityIntent)? = nil, …)` is iOS 26 (line 259) with the iOS 27 `appEntityIdentifier` overload (line 324).
  - Why it matters: the 3 a.m. "core rising" alarm currently leads to the bright Lock Screen. A custom "Open sky" button that lands in field mode with night vision forced on protects dark adaptation at the moment it matters most.
  - Recommendation: offer `.custom` with a `LiveActivityIntent` (`supportedModes: .foreground`) that posts `FieldModeRequest`, keeping snooze as the default for "wake me" alarms and "Open sky" for "core rises" (one secondary button is allowed). On iOS 26.0, where the rows are hidden, nothing changes.
  - Effort: S

- **[PA-13] Journal photos are announced only as "Journal photo 1"** — Severity: P2
  - Evidence: `accessibilityLabel("Journal photo \(i+1)")` (Nyx/Views/JournalViews.swift:264). In the SDK, FoundationModels.swiftinterface:2831-2862 declares `@available(iOS 27.0, *) struct Attachment<Content>` with `init(_ cgImage: CGImage, orientation:)`, `PromptRepresentable`, and `LanguageModelCapabilities.Capability.vision` (line 1509-1512).
  - Why it matters: Inclusivity. A blind user's journal is a list of anonymous images.
  - Recommendation: on iOS 26, add an optional "Describe this photo" field (stored with the entry, used as the label). On iOS 27, when `SystemLanguageModel.default.availability == .available && capabilities.contains(.vision)`, offer a one-line draft ("A photo of a starry sky over a ridge") that the person edits or accepts. Never auto-save it, label it "suggested on this iPhone", and never infer sky facts from it. This is availability-gated per §12.
  - Effort: M

- **[PA-14] Park detail publishes no `NSUserActivity`, so there's no Handoff between iPhone and iPad and no Siri on-screen awareness** — Severity: P2
  - Evidence: There is no `.userActivity(` in the repo; only `onContinueUserActivity(CSSearchableItemActionType)` exists (RootView.swift:117). In the SDK, `AppIntents.swiftinterface:10380-10386` declares `@available(iOS 18.2, *) extension NSUserActivity: AppEntityAnnotatable { var appEntityIdentifier: EntityIdentifier? }`.
  - Why it matters: Nyx now ships on iPhone and iPad (DECISIONS "iPad"). Planning on the iPad and continuing on the phone in the car is a real flow. With `appEntityIdentifier`, "Siri, remind me about this park" or "what's the score here" understands the park on screen.
  - Recommendation: `.userActivity("com.harrypakhale.nyx.park") { a in a.title = park.shortName; a.targetContentIdentifier = park.id; a.appEntityIdentifier = EntityIdentifier(for: ParkEntity.self, identifier: park.id); a.isEligibleForHandoff = true }`. Handle it in the existing `onContinueUserActivity`. Add `NSUserActivityTypes` via project.yml.
  - Effort: S

- **[PA-15] There is no Lock Screen inline widget on iPhone, though the watch has one** — Severity: P3
  - Evidence: TonightWidget's families omit `.accessoryInline` (NyxWidgetsBundle.swift:90). The watch provides it (NyxWatchWidgets/NyxWatchWidgetsBundle.swift:16).
  - Recommendation: "☾ 94 Joshua Tree" above the clock, with the forecast basis in the VoiceOver label.
  - Effort: S

- **[PA-16] The widget can't be pinned to a park, and there's no iOS 27 portrait extra-large size** — Severity: P3
  - Evidence: Only `StaticConfiguration` plus the cycle button exist (NyxWidgetsBundle.swift:87-91; WidgetParkIntent.swift). In the SDK, `WidgetKit.swiftinterface:952-954` declares `@available(iOS 27.0, macOS 27.0, visionOS 26.0, *) case systemExtraLargePortrait`, which the swiftdoc says "can appear on the Home Screen on iOS…".
  - Recommendation: `AppIntentConfiguration` with an optional `ParkEntity` (empty means "darkest saved park", today's behavior), so two widgets can follow two parks. On iOS 27, add `.systemExtraLargePortrait` to the iPad set (`supportedFamilies` built with `if #available`): tonight above the month.
  - Effort: S–M

- **[PA-17] watchOS 26 controls and double tap are unused on the wrist** — Severity: P3
  - Evidence: There's no `ControlWidget` in NyxWatchWidgets (the bundle has only `TonightComplication` and `DuskWidget`) and no `handGestureShortcut` (grep). In the WatchOS27 SDK, WidgetKit `StaticControlConfiguration` is `@available(iOS 18.0, macOS 26.0, watchOS 26.0, *)` (WidgetKit.swiftinterface:816), and SwiftUI `handGestureShortcut` is `watchOS 11.0`.
  - Recommendation: add a watch night-vision control (Control Center or Action button) and `.handGestureShortcut(.primaryAction)` on the watch's "next moment" view, which a hand holding binoculars can trigger.
  - Effort: S

- **[PA-18] Isolation defaults are inconsistent across targets sharing source files** — Severity: P3
  - Evidence: `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` is set for Nyx, NyxWidgets, NyxWatch and NyxVision, but not NyxWatchWidgets (project.yml:213-222), which compiles the same `Park.swift`, `AstronomyEngine.swift` and other shared files under the nonisolated default.
  - Recommendation: set it on NyxWatchWidgets, or confirm every shared type is explicitly `nonisolated`. Otherwise a future shared type can be MainActor in four targets and nonisolated in one.
  - Effort: S

- **[PA-19] Other iOS 26 fallbacks, judged acceptable but noted** — Severity: P3
  - Evidence and assessment:
    - `SkyFullBleed` does nothing on iOS 26 (ParkViews.swift:503-509). The only iOS 26 alternative, `tabBarMinimizeBehavior(.onScrollDown)` (SwiftUI.swiftinterface:11118, iOS 26.0), is TabView-wide, not per screen, so accepting it is reasonable.
    - `ParkTransition` uses the system push when cross-fade is preferred on 26.4–26.x (NyxAccess.swift:52-55). There is no iOS 26 API for a custom cross-fade navigation transition, so this is fine.
    - Alarm rows are hidden on 26.0 (FieldServices.swift:71). The deprecated-in-26.1 `Alert(title:stopButton:…)` (AlarmKit.swiftinterface:64-65) could serve 26.0, but that audience is negligible.
    - `LuminanceProof` uses `MXMetricManager` on 26 (LuminanceProof.swift:61), which is first-class.
  - Recommendation: for the iPhone only, consider `.tabBarMinimizeBehavior(.onScrollDown)` on the TabView for iOS 26 so long pages also recede there. Otherwise no action.
  - Effort: S

### iOS 27 symbols that are actually new (iPhoneOS27.0 SDK, `iOS 27.0` / `anyAppleOS 27.0`) — triage
| Symbol (availability) | Status / verdict |
|---|---|
| SwiftUI `topBarPinnedTrailing`, `.crossFade`, `toolbarMinimizationBehavior/Restoration/SafeAreaAdjustment` (iOS 27 / anyAppleOS 27) | Used (first, second and minimization). Restoration and safe-area adjustment are not needed |
| SwiftUI `EnvironmentValues.systemPrefersReducedResourceUsage` (anyAppleOS 27) | Used |
| Accessibility `accessibilitySpeechSSML` (anyAppleOS 27) | Used; fix the 26 path (PA-4) |
| MetricKit `MetricManager`, `.pixelLuminance` | Used |
| AlarmKit `AlarmConfiguration(…appEntityIdentifier:)` | Used |
| AppIntents `IntentSystemContext.isVoiceOnly`, `IndexedEntityQuery.reindex*`, `CSSearchableItem.relatedAppEntityIdentifier` | Used |
| FoundationModels `ContextOptions(reasoningLevel:)` | Used |
| FoundationModels `Attachment(_ cgImage:)` and `Capability.vision` (iOS 27) | **Recommend** (PA-13), availability-gated |
| WidgetKit `isDynamicIslandLimitedInWidth` (iOS 27) | **Recommend** (PA-5) |
| WidgetKit `.systemExtraLargePortrait` (iOS 27) | **Recommend**, P3 (PA-16) |
| AppSchema `.system.searchInApp` / `.system.open` (anyAppleOS 27; `.system.search` iOS 18 deprecated 27) | Optional: lets "Search Nyx for Utah" open Parks search. Low value next to IndexedEntity |
| SwiftData `@Query(…, sectionBy:)` + `.sections` (iOS 27, `_SwiftData_SwiftUI.swiftinterface:63-81`) | Reject: the journal is a short reverse-chronological list (JournalViews.swift:10,53) and season headers add little |
| SwiftUI `ExternalNonInteractiveAccessory` / `sceneAccessory` (iOS 27, "non-interactive content on an external display") | Reject for v1: a ranger projecting the sky at a star party is real but rare. Revisit for the Social Impact story |
| SwiftUI `TabRole.prominent`, `toolbarOverflowMenu`, `PresentationPlacement.leading`, `reorderable`, `alert(error:)`, `swipeActionsContainer`, `ToolbarPlacement.statusBar`, document APIs | Reject: no darkness question served |
| SwiftUI `BackgroundTask.processingTask` (iOS 27) | Not needed; `.appRefresh` (iOS 16) covers PA-2 |
| AppIntents `RelevantEntities` / `AppEntityContext` (only `.audio(.nowPlaying)` today), `SyncableEntity`, `OwnershipProvidingEntity`, `LongRunningIntent`, `RunSystemShortcutIntent` | Not applicable |
| FoundationModels `PrivateCloudComputeLanguageModel` (iOS 27) | **Forbidden** (network; §12/§13). Correctly unused |
| MapKit iOS 27 POI categories (`RangerStation`, `InformationBooth`, `PicnicArea`, `RestArea`) | **Forbidden** in-process (Apple servers) |
| CoreLocation `CLActivityTypeMaritime`, `headingBody`; CoreMotion `deviceMotionBody`; CarPlay iOS 27 templates | Not applicable (Nyx is not a CarPlay-category app) |
| ActivityKit, TipKit, CoreHaptics, Translation, EventKit | No iOS 27 additions; their iOS 26 APIs apply (PA-1, PA-3) |

### Rejected explicitly (one line each)
- **WeatherKit:** Apple-hosted, a fourth host; §13.
- **Private Cloud Compute / third-party LLM:** network; §12.
- **In-app MapKit, MKLocalSearch, Look Around:** Apple servers from Nyx's process; §13. Only the user-initiated `maps://` hand-off is proposed (PA-10).
- **SharePlay / GroupActivities:** social is out of scope (§11), and there's no signal at dark sites.
- **Messages extension:** ShareLink cards already cover sharing.
- **Wallet "night pass":** signing needs a server-held certificate, and it's a gimmick.
- **App Clips / Universal Links:** need a hosted domain and AASA; the share card image already carries the message.
- **Background Assets:** data is bundled and there's no server.
- **`BGContinuedProcessingTask`:** no long user-initiated job exists.
- **CarPlay app:** not an eligible category. Widgets and Live Activities reach CarPlay through PA-5 and the existing `systemSmall` (`WidgetLocation.carPlay` is iOS 26; verify its rendering in the CarPlay Simulator).
- **iOS 26 `WebView`:** Learn is bundled and offline, and web content would add hosts.
- **Rich-text `TextEditor` (AttributedString):** formatting notes in the dark serves nothing.
- **`Chart3D`:** the custom Canvas sky and time river already carry identity; a 3D chart is decoration.
- **Image Playground, Genmoji:** fabricated imagery conflicts with honesty.
- **Visual Intelligence (`IntentValueQuery` + `SemanticContentDescriptor`, iOS 26):** Nyx cannot honestly identify a park or a sky from a camera frame. Only OCR of a park name would work, and Spotlight already covers that.
- **`SpeechAnalyzer`:** keyboard dictation already works on device; PA-8 covers voice journaling.
- **Contacts, ManagedSettings, Accessory setup, EnergyKit, StoreKit:** unrelated.
- **AlarmKit timer for the dark-adaptation clock:** an alarm that rings at a dark site disturbs others; the silent in-app clock is right.

### Strengths worth protecting (short)
- Guards are precise to the point release (26.1, 26.4, 27), and both OS paths are covered by tests (`NyxTests/PlatformTests.swift:189`).
- The AI rule is respected: everything is gated on `availability == .available`, there's no PCC, tools call the engine, and output is grounded by citations (OnDeviceGuide.swift:26-58).
- Intents are modern: `supportedModes` rather than deprecated `openAppWhenRun`, an interactive snippet, `IndexedEntity` with iOS 27 reindexing, and a Focus filter.
- The LuminanceProof idea (MetricKit as on-device proof that Nyx stays dark) is a distinctive, privacy-true use of an iOS 27 API.

### Open questions for the owner
1. **Maps hand-off (PA-10):** may a viewing spot offer "Directions in Maps" via `maps://` (no request from Nyx, the same class as the existing Safari links)? It reverses DECISIONS.md:180.
2. **Background refresh (PA-2):** approve periodic background requests to `api.open-meteo.com` (and the smoke host when its toggle is on) for saved parks only, honoring the existing per-host switches?
3. **Translation (PA-3):** acceptable that the first use may prompt iOS to download an Apple language pack? Confirm "Data Not Collected" wording in PRIVACY.md.
4. **AlarmKit secondary button (PA-12):** for "core rises" alarms, which should the one secondary button be, Snooze or Open sky?
