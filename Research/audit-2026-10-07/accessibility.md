## Accessibility & Inclusivity — findings

Scope: static review of every custom control in Nyx/, NyxWidgets/, NyxWatch/, NyxWatchShared/, NyxVision/, plus Research/Screenshots, Research/contrast.json, NyxUITests/AccessibilityAuditTests.swift, NyxTests/AccessibilityDepthTests.swift, Store/1.1/accessibility-nutrition-labels.md. No builds or simulators. APIs verified against iPhoneOS27.0.sdk `.swiftinterface` / headers.

### Verdict
At the code level Nyx is already well above "compliant". Every Canvas control speaks a data summary rather than "image". There are Audio Graphs on the river, the month and the sky arc, and rotors, adjustable actions, input labels and SSML. Reduce Motion, Reduce Transparency, Increase Contrast, Differentiate Without Color, Reduce Highlighting, Cross-Fade and reduced resources are all honoured behind correct `#available` guards (verified: 26.4 env values in SwiftUICore, `systemPrefersReducedResourceUsage` and `.crossFade` at 27.0, `accessibilitySpeechSSML` at anyAppleOS 27.0). What holds it back from an unforgettable Inclusivity case:
- **(a)** None of the audio, haptic, rotor, Voice Control or Switch Control work has ever run on a real device or with a disabled user.
- **(b)** The signature red night mode, which is Nyx's core "inclusive by design" claim, drops below 4.5:1 for protanopes, and field mode forces it at 12% brightness with no way out.
- **(c)** Several new iOS 26.x accessibility affordances that fit Nyx exactly are not adopted: the Assistive Access scene, the Action Slider Alternative preference and Show Borders.
- **(d)** A few real correctness bugs remain in the custom controls, notably a VoiceOver/Voice Control activation on the time river that probably jumps to a random night.

### Findings

- **[AX-01] No device pass with any assistive technology, and no disabled testers. The Inclusivity case rests on simulator evidence** — Severity: P1
  - Evidence: PHASE_STATUS.md:160 ("the sound, haptics, Audio Graphs, rotors, Voice Control names and SSML pronunciations can only be judged on a device… (INPUT_NEEDED 1)"). Store/1.1/accessibility-nutrition-labels.md: every label except Dark Interface is "declare after the device pass". AUDIT.md: "not a certificate". There is no record of a blind, low-vision, motor-impaired or deaf tester anywhere in DECISIONS.md or Research/.
  - Why it matters: Inclusivity judges reward demonstrated impact. Today none of the five Nutrition Labels Nyx wants can honestly be declared, and the haptic and sonification features have never been felt or heard.
  - Recommendation:
    1. Run the INPUT_NEEDED 1 matrix on an iPhone (VoiceOver, Voice Control with "Show numbers", Switch Control single-switch scanning, Full Keyboard Access on iPad, AX5 with Bold Text, Increase Contrast with night vision).
    2. Recruit 3–5 testers through blind-astronomy or NFB-adjacent groups and wheelchair-user stargazers; log their quotes in Research/ as award narrative material.
    3. Declare the Nutrition Labels only after both steps.
  - Effort: M

- **[AX-02] Night-vision and field-mode red is below 4.5:1 for protanopes, and Increase Contrast cannot raise it** — Severity: P1
  - Evidence: `NightVisionFilter` multiplies by (1, 0.27, 0.23) (Nyx/DesignSystem/NyxTheme.swift:130). In night vision, `ink` is white and `muted` is 0.96 (NyxTheme.swift:6,10), so `highContrast` changes nothing for text. Research/contrast.json measures 6.16:1 with normal colour vision only. A Machado 2009 full-protanopia simulation, computed here, gives:
    - Primary text on black: **4.30:1**
    - Secondary text: **4.02:1**

    Both fall below WCAG AA. Field mode forces red (Nyx/App/FieldSession.swift:47) and screen brightness of 0.12 (FieldSession.swift:30,96). There is no in-field option to change either; the menu at FieldView.swift:89-98 has none.
  - Why it matters: about 1% of men are protan, and red is exactly the wavelength their eyes under-weight. Low-vision users with dimmed screens get the same problem. This undercuts the "genuinely usable with night-adapted eyes" pillar and the Sufficient Contrast label.
  - Recommendation:
    - Under Increase Contrast, and as an explicit "Brighter red" choice in Settings and the field options menu, multiply by ≈(1, 0.36, 0.31). That measures 6.9:1 normally and 5.1:1 protan, and still reads red.
    - Under Increase Contrast or AX text sizes, raise field mode's brightness floor (e.g. 0.2), or offer "Keep my brightness".
    - Add protan and deutan columns to contrast.json.
  - Effort: S

- **[AX-03] Time river: a VoiceOver double-tap or "Tap River" probably selects the middle night** — Severity: P1 (verify on device)
  - Evidence: Nyx/DesignSystem/TimeRiver.swift:96 sets `.onTapGesture { location in choose(nearest(location.x,…)) }` on the view that becomes one accessibility element at :105-117. That element has no explicit default action. SwiftUI activates tap-gesture elements at their activation point, which is the centre, so the result is night ≈15. The same applies to Voice Control "Tap River" and Switch Control "Tap".
  - Why it matters: this silently changes the chosen night and score for the users the river's adjustable action was built for. It sits on the Interaction showcase control.
  - Recommendation: add `.accessibilityAction { }` with a meaningful default, such as announcing the current night or opening its breakdown, or mark the element `.accessibilityRespondsToUserInteraction` with adjustable only. Add a UI test that activates the element and asserts that the value is unchanged.
  - Effort: S

- **[AX-04] The river has no low-dexterity path at default text sizes; the iOS 26.1 "prefers action slider alternative" setting is not read** — Severity: P2
  - Evidence: `AccessibilitySettings.prefersActionSliderAlternative` (iOS 26.1) and its change notification exist in Accessibility.framework (AXSettings.h:37-38, swiftinterface "extension AccessibilitySettings … @available(iOS 26.1"). Grep finds zero uses. The river's per-night targets are about 10.8 pt wide (30 nights across about 330 pt, TimeRiver.swift:170-177). The large stepper exists, but only at AX sizes (:54-56,136).
  - Why it matters: Apple defines this setting for "items that rely on a prolonged, continuous swipe". That is literally the time river. Motor-impaired users at default text size currently face 10-pt targets and a drag.
  - Recommendation: show the existing `stepper`, or previous/next night buttons, when `prefersActionSliderAlternative` (26.1+, observed through the notification), `accessibilitySwitchControlEnabled` or AX sizes is true. Do the same for the calendar month swipe (CalendarView.swift:248), which already has buttons.
  - Effort: S

- **[AX-05] The hero gauge shrinks its text below the user's text size with `scaleEffect`** — Severity: P2
  - Evidence:
    - CelestialGauge.swift:32 lays out the band and "DARKNESS / 100" for a 300-pt dial, then applies `.scaleEffect(dialScale)` (:71, down to 0.5).
    - The Tonight hero is 240 pt (TonightView.swift:103), a scale of 0.8.
    - The onboarding dial is 188 pt (SettingsAndLearn.swift:270), a scale of ≈0.63.

    So caption2 (11 pt) renders at ≈8.8 pt on Tonight and ≈6.9 pt on onboarding. Research/Screenshots/onboarding-offline-onboarding-page-1-27.png shows "DARKNESS / 100" visibly tiny. The Dynamic Type audit cannot see this, because the font size it reads is unchanged.
  - Why it matters: Larger Text and older users. It is the first screen a judge sees.
  - Recommendation: drop `scaleEffect` for text. Scale only the drawing, and let band and units use their own text styles, wrapping below the dial when they don't fit, as AX sizes already do.
  - Effort: S

- **[AX-06] The Accessibility Audit is blind to the states that matter most** — Severity: P2
  - Evidence: NyxUITests/AccessibilityAuditTests.swift:
    - :30 always launches with `-nyx-reduce-motion` at the default content size, in only two palettes (offline and night vision). It never runs at AX5, with Increase Contrast or Bold Text, or with motion on.
    - :66 globally ignores every `.dynamicType` issue whose description contains "partially", on every screen.
    - :87 ignores every contrast issue described as "nearly".
    - :15-17 do not audit the Live Activity, widgets, watch or Vision.
  - Why it matters: regressions in exactly the AX5 and contrast states the Nutrition Labels claim go undetected. The AX5 checks are currently by-eye screenshot reviews.
  - Recommendation:
    - Add audit passes with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and the `-nyx-contrast` / `-nyx-bold` flags.
    - Replace the blanket "partially" exemption with per-element allow-lists.
    - Add a watchOS UI-test audit target.
  - Effort: M

- **[AX-07] Assistive Access is not supported, though the iOS 26 scene API exists** — Severity: P1 (award)
  - Evidence: `public struct AssistiveAccess<Content>: Scene` is `@available(iOS 26.0…)` (SwiftUI swiftinterface ≈18511). `accessibilityAssistiveAccessEnabled` is in SwiftUICore (≈894). Zero uses in the repo, and there is no Info.plist key: project.yml has only `UIUserInterfaceStyle`. The plist key name is expected to be `UISupportsAssistiveAccess` (unverified).
  - Why it matters: this is the cognitive-disability and older-user case. Nyx's single-question product ("where and when is it darkest?") is ideal for Assistive Access, and almost no third-party apps ship a designed Assistive Access scene. It would be a standout Inclusivity story on the minimum OS.
  - Recommendation: add an `AssistiveAccess { }` scene with two large buttons, "Tonight" and "Saved parks".
    - Tonight shows one park and one word ("Excellent night") with the Moon picture and "Dark from 8:40 PM".
    - Include an optional "Remind me" button. Drop the river, calendar, journal and AI.
    - It shares PlanModel and needs no new data.
  - Effort: M

- **[AX-08] Park rows put closures last in a very long spoken label; `accessibilityCustomContent` is never used** — Severity: P2
  - Evidence: ParkViews.swift:41 speaks name, state, step-free, road, score, band, forecast, the whole week summary, and only then "Closure alert". Grep finds 0 uses of `accessibilityCustomContent`. The label also inserts empty segments, which create double spaces and stray pauses.
  - Why it matters: the spec says a closure is the worst outcome Nyx can cause. VoiceOver users swiping a 63-row list hear about 25 words before it.
  - Recommendation: label = name, score, band, then closure if any. Move the week summary, forecast and step-free status into `accessibilityCustomContent` ("More content" rotor), with the closure at `.high` importance. Apply the same treatment to Tonight's "more parks" rows.
  - Effort: S

- **[AX-09] Share cards travel without alt text** — Severity: P2
  - Evidence: ShareCard.swift:38, YourSkyViews.swift:114 and :274 call `ShareLink(item: image, preview: …)` with no `message:`. The SDK has `init(item:subject:message:preview:label:)` (swiftinterface ≈23750). The recipient gets a bare PNG with no description.
  - Why it matters: a VoiceOver recipient in Messages hears "image". Shared content is Nyx's Social Impact surface.
  - Recommendation: pass `message: Text(card.summary)`, which already exists as `ShareCard.summary`, so the description travels with the image.
  - Effort: S

- **[AX-10] First light auto-dismisses on a timer, exempting only VoiceOver and Switch Control** — Severity: P2
  - Evidence: FirstLightView.swift:63-65 dismisses about 14 s after the text appears. The text fades in at about 4.9 s (:57) and dismissal is skipped only for `voiceOver || switchControl`. Voice Control, Full Keyboard Access, Zoom, AX5 readers and slow readers all lose the moment. Any tap anywhere also dismisses it (:48).
  - Why it matters: this is a WCAG 2.2.1 timing issue, and it hits the cognitive/older and tremor audience on a signature moment.
  - Recommendation: never auto-dismiss at AX sizes or when `UIAccessibility.isVoiceControl…` / FKA is in use. A simpler alternative is to never auto-dismiss at all and keep only the Continue button and escape. Drop the full-screen tap-to-dismiss, or require a deliberate swipe.
  - Effort: S

- **[AX-11] Show Borders / Button Shapes is not handled for 25 plain-styled buttons** — Severity: P2
  - Evidence: `.buttonStyle(.plain)` is used 25 times (e.g. ListenView.swift:26 and :66 amber text buttons, TonightView.swift:166/207/222 capsules, TripPlannerView.swift:175/232/237, ScoreReadout.swift:49). `accessibilityShowBorders` is back-deployed (`@backDeployed(before: iOS 26.1)`, suicore ≈23446) and `AccessibilitySettings.showBordersEnabled` exists (26.1). Grep finds 0 uses of either.
  - Why it matters: users who turn on Button Shapes or Show Borders get no affordance on Nyx's text-only actions (cognitive and low-vision users).
  - Recommendation: in a shared `NyxActionStyle`, draw a hairline capsule border or underline when `accessibilityShowBorders` is true. Use that style instead of `.plain` for actionable text.
  - Effort: S

- **[AX-12] Watch: truncation at accessibility sizes, and no wrist haptics for field milestones** — Severity: P2
  - Evidence:
    - NyxWatch/WatchViews.swift:93 (forecast note), :115-116 (now-line) and :122 (time line) use `lineLimit(1)` + `minimumScaleFactor` even at AX sizes. Only :118 lifts the limit for AX.
    - Research/Screenshots/watch/s11-ax-red.png shows the countdown line cut at the bottom edge.
    - NyxWatch and NyxWatchShared contain no `WKInterfaceDevice.play` and no `sensoryFeedback`.
  - Why it matters: Larger Text on watch. A wrist tap at "true darkness begins" is the natural non-visual, non-auditory signal in the field, for deafblind users and for anyone keeping eyes dark-adapted.
  - Recommendation: lift line limits at AX sizes, as :118 does. Add a watch haptic (`.sensoryFeedback(.start/.success)` on the milestone change) while the countdown screen is up. Optionally use an extended runtime session during field mode.
  - Effort: S/M

- **[AX-13] Smaller polish items with evidence** — Severity: P3
  - TimeRiver.swift:108: the hint "Swipe up or down…" duplicates VoiceOver's own adjustable hint and is wrong for Switch Control, FKA and Voice Control. Use "Moves one night at a time."
  - MoonView.swift:45-50: the label omits the phase name and waxing/waning ("Moon, 34 percent illuminated, lit from the right"). Prepend `moon.name`, e.g. "Waxing crescent".
  - SkyMapView.swift:55: inset names are drawn at a fixed 8 pt. They are decorative and audit-exempt (AccessibilityAuditTests.swift:98), but they are the only names for Alaska, Hawai'i and the Samoa and Virgin Islands insets that sighted users get.
  - SkyMapView.swift:141-148: overlapping 44-pt star buttons where parks cluster (Utah). The VoiceOver order follows array order, not geography.
  - SkyArc.swift:39: Canvas labels are capped at `.xxLarge`. This is not listed among the "known exceptions" in the Nutrition Labels doc, though FieldCompass's AX1 cap is.
  - Notification body "94/100" (NotificationScheduler.swift:90) and share preview "94/100" are read as "94 slash 100". Use "94 out of 100" for the spoken or notification text.
  - Hard-coded directional symbols: CalendarView.swift:191/200 and NyxVision/Window/NightControls.swift:27/39 use `chevron.left/right`, not `chevron.backward/forward`. The calendar swipe and the river Canvas do not mirror. This matters only if an RTL locale is ever added.
  - `palette.line` (0.22 ink) is 1.71:1 on black for graphical objects: the gauge track and the river hairline. WCAG 1.4.11 wants 3:1. Increase Contrast fixes it (0.6), but the default does not.
  - Pull to refresh signals completion only by haptic (TonightView.swift:60). Post a polite announcement such as "Updated".
  - Smart Invert: RealSky, Starfield and NightBackground lack `accessibilityIgnoresInvertColors`. The app declares `UIUserInterfaceStyle: Dark` (project.yml:71), which Apple says may exempt it, but no Smart Invert capture exists. Take one screenshot to close it.
  - iOS 27 `AccessibilitySettings.isApplicationAccessibilityEnabled` (AXSettings.h, anyappleos 27.0) could gate the lazy chart and rotor construction. This is an optional performance nicety.
  - Effort: S each

### Concrete violation inventory (static)
- **Fixed `font(.system(size:))`:** 26 occurrences.
  - Backed by `@ScaledMetric` and therefore fine: ParkViews:413, TripPlanner:168/228, FieldView:189, YourSky:150, CalendarView:82, WatchViews:385, NightDetail:53.
  - Fixed artwork or widget by design: YourSky:89/248/262, ShareCard, TonightWidgetView:139/194/212/243, BestNightIntent:146.
  - Decorative symbols: NyxTheme:117, TonightView:214, SettingsAndLearn:167.
  - Real issues: CelestialGauge:68 combined with the scaleEffect (AX-05), and SkyMapView:55 at 8 pt (AX-13).
- **`onTapGesture` on non-buttons:** 3.
  - TimeRiver:96 is a bug (AX-03).
  - FirstLight:48 is risky (AX-10).
  - ParkViews:554 is fine: a focus helper beside a real TextField.
- **`lineLimit` + `minimumScaleFactor` that can hide content at AX sizes:** WatchViews:93, :116, :122, and :418 (navigation title, scaled to 0.6). The app-side uses are all lifted at AX sizes.
- **Dynamic Type caps in app UI:** SkyArc:39 (xxLarge), FieldCompass:57 (AX1, with a list fallback), ParkViews:551 (AX3, inline search), plus the widget caps (TonightWidgetView:111/190/234/264/283, as low as `.large`).
- **Glass without a Reduce Transparency branch:** none found. NyxTheme:56-59, CelestialGauge:78-82, TonightView:256-261, FieldView:394-397 and the Vision windows all branch.
- **TimelineView without a Reduce Motion pause:** none found. Starfield:24, RealSky:24, CelestialGauge:117, SkyMap:123, FirstLight:30 and FieldCompass:45 all pause or freeze, and also pause in Low Power and reduced resources. Twinkle rates are ≤0.6 Hz (CelestialGauge:147), far below the 3 Hz photosensitivity threshold.
- **New SDK APIs:**
  - Adopted: reduceHighlighting (26.4), crossFade (26.4/27), reducedResources (27), SSML (27).
  - Not adopted: AssistiveAccess scene (26.0), prefersActionSliderAlternative (26.1), accessibilityShowBorders / showBordersEnabled (26.1), `AccessibilitySettings.openSettings(for:)` / `canOpenSettings` (26.4, e.g. to deep-link the Sound and touch screen to system Haptics or Assistive Touch), isApplicationAccessibilityEnabled (27).

### The award angle: from compliant to unforgettable (grounded in what exists)
1. **"The night without a screen."** Every stargazer, sighted or not, wants the phone dark. Nyx already has a sonification engine (NightSound.swift), Core Haptics Moon textures (MoonHaptics.swift), SkyCompass geometry and the field milestones. Combine them into **"Feel tonight"**: a haptic-only rendering of the night (intensity = darkness, sharp transient = moonrise, swell = the Milky Way core rising), played on the watch and the phone. Add a **spatial-audio "where to look" cue**: a soft tone positioned in AirPods toward the core or a planet, using SkyCompass bearing/altitude and AVAudioEnvironmentNode with headphone motion (Apple frameworks only). This serves blind, low-vision and deafblind users, and also everyone protecting dark adaptation. Universal design that judges can feel in a demo.
2. **Assistive Access "One answer" scene (AX-07).** Cognitive and older users get one word, one Moon, one time. Very few apps ship this, and the API is on the minimum OS.
3. **Night red for every eye (AX-02).** "Nyx's red is tuned for colour-blind eyes" is a one-line, provable claim (contrast.json with protan and deutan columns) that no astronomy app makes.
4. **"Can't travel tonight? Your own sky."** Wheelchair users without accessible transport, people who cannot drive, homebound and older users: the What's up engine plus skyglow (SkyGlow.swift, Black Marble) can answer "what can I see from home tonight" (the Moon, planets, bright showers) honestly, with no extra host. This turns Nyx from a road-trip planner into a sky for everyone. It covers both Social Impact and Inclusivity.
5. **Deepen step-free spots** (accessible-spots.json already has 85 sourced spots). Add surface, distance from accessible parking and an accessible restroom, each sourced like today, and an "accessible programs" flag where NPS event text mentions ASL, assistive listening or wheelchair access (keyword-based, labelled "from the event description"; unverified whether the NPS API has structured fields).
6. **Co-design evidence (AX-01).** Testers' words on the product page, and in the "Stargazing for everyone" essay, are what separate a winner from a checklist.
7. **Languages:** Spanish is shipped but unreviewed (INPUT_NEEDED). The SSML table (NyxAccess.swift:67-71) has three entries. Extend it to Spanish VoiceOver for English park names that Spanish speech mangles (e.g. "Joshua Tree", "Great Smoky"), using `<lang xml:lang="en-US">` on iOS 27.

### Strengths worth protecting
- Every Canvas control collapses to one element with a spoken data summary: gauge, river, sky arc, calendar cells, field countdown, sky map, Live Activity symbols.
- Audio Graphs on the river, month and sky arc. Rotors for best nights, the Moon window, closures, Pristine nights and milestones. Voice Control input labels throughout.
- Layouts reflow at AX sizes instead of shrinking: the stepper river, the list calendar, the list compass, the inline search.
- `nyxAccessibility()` centralises the newest settings correctly behind availability checks, with DEBUG flags to screenshot each one.
- FirstLight and field mode already announce and avoid timers for VoiceOver and Switch Control. Closures sit on a scrim. Honest "Estimate" wording is carried into VoiceOver.

### Open questions for the owner
- In field mode, may a person opt out of forced red or forced 12% brightness (AX-02)? Or should Increase Contrast and Larger Text only lift the floor?
- Is an Assistive Access scene in scope for 1.1, or should it wait for 1.2?
- Is a "from home" mode (award angle 4) in keeping with Nyx's national-parks identity, or should it live only in What's up?
