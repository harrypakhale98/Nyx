# Nyx — Accessibility Nutrition Labels (App Store Connect answers)

Where: App Store Connect → Apps → Nyx → App Information → Accessibility → Set up Accessibility Nutrition Labels (answered per device type: iPhone, iPad, Apple Watch, Apple Vision Pro).

## Apple's rules (verified 2026-10-05)

Source: [Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels), summarized by a page fetch.

- The labels are voluntary today and will become mandatory over time for new apps and updates. You are responsible for keeping them accurate. App Review can contact you if a label looks misleading (Guideline 2.3).
- **The test:** you may declare a feature only if users can complete **all of the common tasks** of the app using that feature. Common tasks are: the primary functionality you market (description, screenshots, previews), the first-launch experience (onboarding, which may be skipped), login (Nyx has none), purchase (Nyx has none), and settings (accessibility and privacy adjustments).
- Apple recommends a matrix: rows are common tasks per device, columns are the features. Test with the real assistive technology, prefer system implementations, and do not invent your own versions of VoiceOver or Voice Control.
- Features and Apple's definitions, with the devices each applies to:

| Label | Apple's description | Devices |
|---|---|---|
| VoiceOver | Navigate by gestures, keyboard, braille and speech | All |
| Voice Control | Navigate and type by voice (tap, swipe, click, type) | iPhone, iPad, Mac, Vision Pro |
| Larger Text | Text scales to 200% or more | iPhone, iPad, Apple Watch, tvOS, Vision Pro |
| Dark Interface | A dark scheme that reduces eye strain | All |
| Differentiate Without Color Alone | Shapes or text in addition to color to distinguish information | All |
| Sufficient Contrast | Higher contrast between text/icons and background | All |
| Reduced Motion | Modifies or reduces animations that may cause motion sickness | All |
| Captions | Time-synchronized text for video or audio content | iPhone, iPad, Mac, tvOS, Vision Pro |
| Audio Descriptions | Time-synchronized narration describing video | iPhone, iPad, Mac, tvOS, Vision Pro |

Per Apple, third-party content (the parks' NPS descriptions, alerts and event text) need not be made accessible by you; Nyx still renders it with Dynamic Type and VoiceOver.

## Nyx's common tasks (the rows of the matrix)

1. First launch: the three onboarding pages (skippable) with no permission request.
2. Tonight: read the top parks and the score, choose a starting park by hand, change the radius.
3. Parks: search, filter, open a park.
4. Park detail: read the score and its breakdown (moon, clouds, sky glow, dark hours), read What's up tonight (core, planets, showers), forecast agreement, smoke, closures, viewing spots (step-free filter), sky arc, moon.
5. Calendar and time river: choose a night, read its breakdown, find the new moon window.
6. Save a park; set reminders (notification permission explainer).
7. Journal: create, edit, delete an entry, add selected photos.
8. Field mode: read the countdown, milestones and dark-adaptation clock; "Where to look"; set an alarm; Live Activity; Control Center control; Focus.
9. Widgets (Home and Lock Screen), App Intents (Siri, Shortcuts), share card.
10. Trip planner, your constellation (1.1).
11. Settings: night vision, Your privacy toggles (three services), About the data.
12. Apple Watch: countdown, Moon, complications. Apple Vision Pro: the sky under a park and night, time scrub. iPad: calendar and detail side by side.

Not applicable: login, purchase, account recovery.

## What to declare, per feature

"Evidence" is what the repository shows today (README, AUDIT.md, DECISIONS.md, the accessibility audit tests). "Gap" is what only a device can settle. **Do not declare a label until its gap is closed and signed in `AUDIT.md`.** The simulator audit (Apple's `performAccessibilityAudit`) is evidence of structure, not a certification, and `AUDIT.md` says so itself.

### VoiceOver — declare after the device pass

- **Answer:** Yes for iPhone and iPad, Apple Watch, Apple Vision Pro, only after the pass below.
- **Evidence:** every custom control has a VoiceOver summary: celestial gauge (score, band, caveat), moon disc (phase, which side is lit), time river (adjustable action; native stepper at accessibility sizes), sky arc (spoken timing summary including the core), calendar nights (date, score, forecast state, event), score readout (one button, value lists the four parts), week strip. Decorative elements are hidden. The accessibility audit runs on every screen in both palettes on iOS 26 and 27 and passes. 1.1 adds audio graphs (`AXChartDescriptor`) for the river, calendar month and sky arc; a spoken list is the default for "Where to look" under VoiceOver and at accessibility text sizes; milestones are announced as they happen; the field countdown's label is a full sentence. Journal photos get per-photo labels.
- **Gap:** actual VoiceOver focus order, rotor behavior, and every common task completed with VoiceOver on a real iPhone (`AUDIT.md`, procedure step 3, "unverified"). Watch and Vision Pro need their own passes.
- **Justification text (for your records):** "All of Nyx's common tasks, from reading a park's Darkness Score to setting an alarm, can be completed with VoiceOver. Custom charts expose a data summary and audio graphs."

### Voice Control — **verify on device**

- **Answer:** Do not declare yet. Declare only after a pass.
- **Evidence:** every custom control and icon-only button now has short `accessibilityInputLabels` (time river "River"/"Nights", its accessibility-size stepper "Night", gauge "Score", each calendar night by day number or weekday and day, month arrows "Previous"/"Next", save, filter, sky arc, "Listen", "Feel the Moon", field mode's "Leave" and "Options"); the river also takes VoiceOver/Voice Control actions "Best night" and "Next of the best nights". Nyx uses system buttons, lists, toggles, steppers, search, sheets and menus almost everywhere, which Voice Control handles. Custom controls (time river drag, calendar night cells, celestial gauge tap targets, the compass "Hold still") are the risk. The roadmap itself says: "add a Voice Control pass to the audit first."
- **Gap, the test:** with Voice Control on, "Show numbers" and "Show names", complete every common task above by voice. Check that every control has a spoken name (visible text matches the accessibility label, so "Tap Why this score" works), that the time river can be moved by voice (the adjustable stepper at accessibility sizes helps; add `accessibilityAdjustableAction` and test "Swipe left on the river" or a button for previous and next night), that calendar nights are individually addressable, and that Dwell and swipe gestures are never the only route.
- **If it fails:** add visible, named previous and next night buttons beside the river and the calendar; ensure `accessibilityInputLabels` for controls whose spoken label differs from the visible label.
- **Not available on Apple Watch** (Apple lists iPhone, iPad, Mac and Vision Pro only).

### Larger Text — declare after the device pass (and a few checks)

- **Answer:** Yes for iPhone and iPad, Apple Watch and Apple Vision Pro, after checking the items below.
- **Evidence:** Dynamic Type to AX5 reviewed on every main screen in the simulator, with Simulator content-size captures; layouts reflow instead of shrinking (calendar becomes stacked rows, river becomes a stepper, gauge labels move below the ring, the legend stacks). Widgets prefer full scaling and fall back to bounded compact labels with a full spoken summary. Field mode moves the eye clock into the scroll at accessibility sizes and swaps the drawn compass for a list.
- **Known exceptions to state honestly:** the share-card image is fixed artwork at its own type size (it is an exported picture, not UI); the compass sky's labels stop growing at the first accessibility size (the list carries every size); widget and Live Activity footprints are fixed by the system.
- **Gap:** Apple's definition is text that scales to 200% or more. AX5 is far more than that. Check Live Activity and Dynamic Island text, the Watch app and its complications, and Vision Pro windows. If the Live Activity cannot scale to 200%, say so in notes and decide whether the label is still honest for that surface (it is a glanceable summary of information that also exists in the app).

### Dark Interface — declare

- **Answer:** Yes on every device.
- **Evidence:** Nyx is dark by design and always dark: void black, deep indigo, starlight text, amber accents; no light mode exists. A red night-vision palette goes further. Sheets, system alerts and permission dialogs follow the dark appearance.
- **Gap:** none beyond ordinary checking that no screen flashes white (system share sheets and the Photos picker follow the system appearance, which is dark when the device is).

### Differentiate Without Color Alone — declare after a grayscale pass

- **Answer:** Yes, after the pass below.
- **Evidence:** scores are numerals and words (Pristine, Excellent, Good, Fair, Poor) before they are colors; calendar and river marks encode the score by dot size, with hollow marks for "no forecast", a cloud glyph for overcast and a ring for the new-moon window, not by color alone; the cloud meter's "Unknown" is dashed and labeled; model agreement is words ("Models agree", "Roughly agree", "Models differ") plus a range bar; closures and smoke caveats carry text and an icon, not only an amber color; night-vision mode is monochrome red by definition, so the whole interface already relies on shape, size and text there, and the design notes say black text on amber and red actions survive the monochrome filter.
- **Built (2026-10-06):** Nyx reads the system's Differentiate Without Color setting (`accessibilityDifferentiateWithoutColor`) and adds shape where colour or brightness alone carried meaning: Excellent and Pristine nights become four-pointed stars on the calendar, the time river and the week strip (hollow still means no forecast); the river's three best nights, otherwise marked only by an amber glow, gain a small triangle beneath; moonlit hours on the sky arc are hatched as well as lighter, and the Sun's path is labelled; past calendar nights, otherwise only dimmer, are struck through. Legends gain a sentence saying so, only while the setting is on. DEBUG flag `-nyx-differentiate` forces it for review captures (`Research/Screenshots/a11y-differentiate-*`).
- **Gap:** a grayscale pass on a device with the setting both off and on (System Settings → Accessibility → Display & Text Size → Color Filters → Grayscale): score bands, calendar, river, Tonight's week strip, the sky arc, and the 1.1 additions not yet built (step-free marks, the planner's per-night assignment).
- **Justification:** "Meaning is carried by numbers, words, shape and size. With Differentiate Without Color on, Nyx adds shapes, rings, hatching and strike-throughs wherever colour or brightness alone marked something."

### Sufficient Contrast — declare after a device sampling

- **Answer:** Yes after the sampling below.
- **Evidence:** `Scripts/contrast.py` computes WCAG relative luminance for the design tokens (`Research/contrast.json`): primary and secondary text on the normal panel 16.7:1 and 8.9:1; signal red on black 6.2:1, red primary and secondary on the dark panel 5.6:1 and 5.3:1; black labels on amber 11.9:1 and on red 6.2:1. Increase Contrast and Reduce Transparency switch glass panels to opaque. The audit's contrast checks run in both palettes; documented exclusions cover text behind the tab bar and animated stars. 1.1 adds a "Reduce bright effects" mode (iOS 26.4 and later) for glow and halos.
- **Gap:** `AUDIT.md` states plainly that token ratios do not prove every antialiased, disabled or composited native pixel; native glass and forms in red need device sampling. Test with Increase Contrast on and off, in both palettes, outdoors at low brightness. Sample the new 1.1 surfaces: field mode, the Watch app in red, Vision Pro windows.

### Reduced Motion — declare after the check

- **Answer:** Yes for iPhone and iPad, Apple Watch, Apple Vision Pro.
- **Evidence:** the starfield, gauge orbit, count-up reveal, constellation lines, scrub animation, tilt parallax, shooting star and calendar slide stop or become static under Reduce Motion; on iOS 26.4 and later "Prefers Cross-Fade Transitions" replaces the zoom transition with a cross-fade. The setting is read from the system. Haptics are separate from motion.
- **One honest exception to decide on:** "Where to look" turns the sky with the phone's real orientation. That is direct manipulation by the person's own movement, not decorative animation, so it stays on under Reduce Motion (the design notes say so); "Hold still" freezes it, and a list is the alternative. Apple's definition concerns "animations that may cause motion sickness"; this view responds one-to-one to hand movement and has no autonomous motion. Keep the exception in your notes; if you doubt it, default the view to the frozen state under Reduce Motion.
- **Gap:** run every common task with Reduce Motion on, on a device, and confirm nothing autoplays (including the Vision Pro immersive scene, which must not animate the sky on its own).

### Captions — not applicable

- **Answer:** Do not declare (not applicable). Nyx has no video and no spoken audio. The label applies to time-synchronized text for video or audio content. Nyx's only sounds are the "Listen to tonight" sonification tones (pitch for darkness, a pulse for moonrise and moonset, a chime for the core), which carry no speech; the sonification has a text equivalent beside its button, a transcript that highlights each moment as it plays, and VoiceOver hears each moment announced.
- **Check before you decide:** if the sonification is accompanied by any spoken narration, or if any in-app video appears, revisit. The App Preview video on the product page is store content and has no narration; its text overlays are the captions.

### Audio Descriptions — not applicable

- **Answer:** Do not declare (not applicable). No video content in the app. The App Preview video is a silent screen recording with text overlays.

## Recommended declaration

| Feature | iPhone | iPad | Apple Watch | Apple Vision Pro | Condition |
|---|---|---|---|---|---|
| VoiceOver | Yes | Yes | Yes | Yes | Device pass for each |
| Voice Control | Yes | Yes | n/a | Yes | **Only after the Voice Control pass** |
| Larger Text | Yes | Yes | Yes | Yes | Check Live Activity, Watch, Vision Pro |
| Dark Interface | Yes | Yes | Yes | Yes | None |
| Differentiate Without Color Alone | Yes | Yes | Yes | Yes | Grayscale pass |
| Sufficient Contrast | Yes | Yes | Yes | Yes | Device sampling |
| Reduced Motion | Yes | Yes | Yes | Yes | Device check; note the compass |
| Captions | No (n/a) | No | n/a | No | No video or speech |
| Audio Descriptions | No (n/a) | No | n/a | No | No video |

If a pass has not been completed by the submission date, leave that label undeclared. Undeclared costs nothing; an inaccurate label risks a Guideline 2.3 inquiry. Add the label in a later update when the pass is done.

## Device pass, ordered, to unlock the labels

1. Install the TestFlight 1.1 build on a physical iPhone (and an iPad, Watch and Vision Pro if shipping them).
2. For each setting in turn (VoiceOver, Voice Control, AX5 and 200% text, Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text, Smart Invert, grayscale), complete every common task in the list above. Record pass or fail with the build number in `AUDIT.md`.
3. Test with night-adapted eyes outdoors, in both palettes.
4. Ideally have a VoiceOver user, and a Voice Control user, do tasks 2, 4, 5 and 8 unaided and note where they stall (`AUDIT.md` step 6 already asks for this).
5. Fix failures, rerun the audit on iOS 26 and 27, and only then complete the form.

## App Store Connect steps

1. App Information → Accessibility: select each device type; for each feature choose "Supports", with the common-tasks statement above.
2. Provide the optional accessibility support URL if the form offers one (not verified for this account). A good page would reuse the paragraphs above and the audit's honest limits.
3. Update the answers in each release where a feature changes.

## Copy for the product page and nominations (gated, C11)

The same device-pass gate applies to every public sentence, not only to the labels (Guideline 2.3.1).

**Before the device pass (use now: store description, press kit, case study, nominations):**

> Nyx is designed for VoiceOver and the largest text sizes. Audio graphs let you hear a month of darkness, haptics can follow the Moon's phase, and a red mode keeps the whole app readable to night-adapted eyes.

This names only what the code and the simulator audit show: the features exist and are built for these settings. It does not claim that every task has been completed with them on a device.

**After the pass, for each feature signed in `AUDIT.md`:**

> Nyx works with VoiceOver, Larger Text, Reduce Motion, Reduce Transparency and Increase Contrast, …

Add only the features that passed, in the same order as the labels declared in App Store Connect. Voice Control is added last, after its own pass.

| Surface | Wording today | Switch to "works with" when |
|---|---|---|
| App Store description (`metadata.md`, FOR MORE PEOPLE) | "designed for VoiceOver and the largest text sizes" | VoiceOver and Larger Text pass on iPhone |
| visionOS description (`metadata-visionos.md`) | "Reduce Motion, Reduce Transparency and Increase Contrast are respected" | Vision Pro pass; cut the sentence if it is not done by submission |
| Press kit, case study (`docs/`) | "designed for…", plus "testing on physical devices … is the next step" | the pass is signed; then replace the last sentence with what was tested |
| Award entries (`award-entries.md`) | "testing … is under way" | state exactly what was tested, never more |
