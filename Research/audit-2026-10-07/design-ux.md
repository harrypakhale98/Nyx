## Design & UX (ADA juror lens) — findings

Audit date 2026-10-07. Build: `Nyx` scheme, Debug, built clean (0 warnings). Every claim below was looked at in a capture; downscaled copies are in `shots/` beside this file. Runtimes/devices: iPhone 18 Pro iOS 27.0 (prefix `27-`), iPhone 17 Pro iOS 26.5 (`26-`), iPhone 17e iOS 27.0 (`17e-`), iPad Pro 13" iOS 27.0 landscape + portrait via `NyxUITests/ScreenshotTests` , real Settings text size AX5 (`27-ax5-*`), real Increase Contrast (`27-contrast-*`). Interaction was driven with the simulator touch API (scrolls, river scrub, calendar long-press, search typing, filter menu). Reviewed existing store art in `Store/Framed/6.9-inch/` and `Store/Screenshots/iPad/`.

### Verdict

Nyx's craft floor is genuinely high: the serif score, the moon (onboarding page 1 is print-quality), the calendar night cells, the red field mode and the honest copy would hold up next to Flighty or Gentler Streak, and iOS 26.5 is visually identical to iOS 27. But it no longer reads as one calm answer to "where and when is the sky darkest?". The app has grown into a five-tab, 1,152-string product whose park page is about five iPhone screens of a dozen stacked panels. Every tab spends its first ~120 pt on a poetic eyebrow plus a serif title that repeats the nav title. The strongest visual assets (the real sky, the moon disc, the sky arc) are thumbnails or buried, and the most repeated one (the gauge) is on three of the first four store frames. A juror opening it cold would see a beautiful instrument wrapped in a long, text-heavy report. The award case now depends more on **subtraction and staging** than on any new feature. Two live defects matter beyond taste: state-name search returns nothing, and the field-mode countdown reads as a clock time.

### Findings

- **[DX-01] Information architecture has outgrown "calm and focused"; consolidate before submission** — Severity: P1
  - Evidence: 5 tabs (`Nyx/App/RootView.swift:44-50`). Park detail stacks hero, river, alerts, shape of the night + Listen, What's up + alarms, Moonlight + Feel the Moon, What the sky may hold (clouds, air, the night itself, Bortle, satellite lights, horizon glow), Places to settle in, Ranger programs, Protect this sky, Share, NPS description and About the data (`Nyx/Views/ParkViews.swift:212-345`). That is about 4,500 pt, roughly five iPhone screens (`27-detail-01…07.png`). Two overlapping recaps sit in Journal: "Year under the stars" in the ⋯ menu and an AI "Reflect on this season" (`JournalViews.swift:41,54`). Ask Nyx is a lone bordered button at the bottom of Tonight (`TonightView.swift:128`, `shots/27-tonight-bottom.jpg`). Trip planner is reachable **only** from a card below the footnote on Tonight (`TonightView.swift:212`), yet it is store frame 07. Learn holds a full tab slot for six essays that all read "2 minute read" (`shots/ipad-learn.jpg`). 1,152 catalog strings (`Localizable.xcstrings`).
  - Why it matters: the Interaction and Delight juries reward a clear core loop. Right now "where × when" is split across Tonight, Parks (sort), Calendar, the river on detail and the trip planner, and none of them owns "plan". First-impression calm (Calm, Moonlitt, Tide Guide) comes from one strong spine.
  - Recommendation: (1) Make Calendar a **Plan** tab: month grid, plus "I'm free…" (the trip planner) as its second mode, so "when" has one home. (2) Remove Learn as a tab. Essays already link in context (`WhatsUpPanel.swift:24-26`, `SkyGlowViews.swift:161`). Move the index under Settings/"About the sky", or under Journal as "Field notes", and give the freed slot to nothing (four tabs is calmer). (3) Collapse park detail into three chapters with a pinned segmented control or `ScrollView` sections: **Tonight** (hero, river, before-you-go), **The sky** (shape of the night, What's up, Moonlight), **The place** (light, spots, programs, protect). Fold "Listen" and "Feel the Moon" into a single "Sound and touch" row that expands. (4) Merge the two recaps into one Year card, using AI phrasing when available. (5) Put Ask Nyx inside Plan as "Explain this plan", not as a free-floating Tonight button.
  - Effort: L

- **[DX-02] Field-mode hero countdown "22:39" reads as a clock time** — Severity: P1
  - Evidence: `shots/27-field-night.jpg`, `shots/ipad-field.jpg` and store frame `04-field-mode.png` show "True darkness in / **22:39**". The cards directly below use clock times in the same serif face ("7:42 PM", "8:54 PM"), and "in 23m" sits under the first card. Source: `Text(timerInterval:…,countsDown:true,showsHours:true)` (`Nyx/Views/FieldView.swift:188`). Under an hour it renders `mm:ss`, which is indistinguishable from 22:39 (10:39 PM) on a 24-hour device.
  - Why it matters: this is the signature in-the-dark screen (Interaction), read by dark-adapted eyes at a glance. A misread costs the moment the app exists for.
  - Recommendation: drop seconds for any countdown over 2 minutes and write units: "23 min", or "1 h 31 min" in serif with smaller unit glyphs, ticking each minute (the watch already does this, DECISIONS.md:251). Keep `mm:ss` only for the last 2 minutes. VoiceOver already speaks a sentence.
  - Effort: S

- **[DX-03] Search promises "Park or state" but state names return nothing** — Severity: P1
  - Evidence: typing "utah" shows "No parks in this sky" (`shots/27-parks-search-utah.jpg`). `Park.matches` searches `[name, state] + aliases`, and `state` holds only codes ("UT", "CA,NV") (`Nyx/Models/Park.swift:38-43`, `Nyx/Resources/parks.json:386`).
  - Why it matters: this is a broken core flow on a P0 screen. "Utah" is one of the most likely first searches for a national-park app.
  - Recommendation: add the full state and territory names (localized, through `Locale`/a small table) to `matches`. Also render multi-state codes with a separator and space ("CA · NV"): the rows currently print "CA,NV" (`shots/27-parks-darkest.jpg`, `ParkViews.swift:46`).
  - Effort: S

- **[DX-04] The "preamble tax": eyebrow + serif title + duplicate nav title on every screen** — Severity: P2
  - Evidence: Tonight says "Tonight" / "THE NIGHT IS WAITING" / "Where the sky is darkest" / "YOUR DARKEST NEARBY SKY" before any answer (`shots/27-tonight-live.jpg`). Detail says "Joshua Tree" (nav) / "A NIGHT BENEATH THE STARS" / "Joshua Tree" (`shots/27-detail-01.jpg`). Calendar says "Calendar" / "MAKE TIME FOR THE NIGHT" / "Choose your night". Trip says "Plan a trip" (nav) / "REASONS TO GO" / "Plan a trip". Journal and Learn follow the same pattern. There are 34 `Eyebrow` call sites, most with ornamental copy (`grep Eyebrow Nyx/Views`).
  - Why it matters: Visuals/Interaction. It costs 100-150 pt above the fold on every tab, pushes the starting-point panel under the tab bar on iPhone, and the repeated lyrical eyebrows start to read as a tic, not a voice. HIG: titles should orient, not repeat.
  - Recommendation: on each tab root, keep either the system large title or the serif display title, never both. Hide the inline nav title until the serif title scrolls away (`.toolbarTitleDisplayMode(.inlineLarge)` on iOS 26, or a scroll-driven title). Keep eyebrows only where they carry data (dates, park · night, "Darkest tonight first"). Tonight's first line should be the answer: "Death Valley · 97 · Pristine".
  - Effort: S–M

- **[DX-05] The Moon, the app's most beautiful asset, is a 70 pt thumbnail five panels down** — Severity: P1 (Visuals & Graphics)
  - Evidence: Moonlight panel `MoonView … .frame(width:70,height:70)` (`ParkViews.swift:310`, `shots/27-detail-04.jpg`). On Tonight it is a 40 pt disc that reads as a black dot in the corner (`shots/27-tonight-live.jpg`, `TonightView.swift:69`). The river's moon is about 30 pt. Only onboarding page 1 shows it at hero scale (`shots/27-coldlaunch-onboarding1.jpg`). That screen is the single most award-looking frame in the app, and no store frame shows it.
  - Why it matters: the product brief §14 calls the Moon "pixel-obsessed… a moon disc you could print". Moonlitt won Interaction with a moon that fills the screen. Nyx's NASA-textured, correctly tilted moon is hidden.
  - Recommendation: give the moon a hero moment on detail. Either the gauge and the moon share the hero as a two-page swipe, or the Moonlight panel opens a full-bleed moon (about 280 pt) with phase, terminator and rise/set, which morphs as the river scrubs (the river already drives `selected`). Use it as store frame 02 or 03.
  - Effort: M

- **[DX-06] The real sky is rendered everywhere but never shown as a first-class view on iPhone** — Severity: P1 (Visuals & Graphics, Innovation)
  - Evidence: `RealSky` (stars, Milky Way, planets, radiant; `Nyx/DesignSystem/RealSky.swift`) only appears as a faint `NightBackground` behind text. The one place it is the subject is the red field compass, which is "mostly black" by its own team's review (PHASE_STATUS 2026-10-06, `05-where-to-look.png`). The Bortle essay explains the scale in five paragraphs of text with no picture (`shots/ipad-essay.jpg`).
  - Why it matters: Visuals jurors need one frame that makes them stop. Tide Guide won with its data turned into the scene. Nyx has the scene and uses it as wallpaper.
  - Recommendation: (a) "Tonight's sky over <park>": a full-screen, non-red RealSky for the selected night and hour, scrubbable with the same river (Vision Pro already does this; port the 2D projection). (b) In "Reading the Bortle scale", an interactive slider that re-renders the same RealSky at Bortle 1→9. That is the single most explanatory and shareable visual this app could have, and it carries the Social Impact story. Both should be store frames.
  - Effort: M–L

- **[DX-07] Hero alert shows trivia in warning amber; NPS copy leaks Title Case and exclamation marks** — Severity: P2
  - Evidence: Tonight's hero line under the gauge is "⚠ Gas Pumps at Panamint Springs Resort are Closed at Night" (`shots/27-tonight-live.jpg`, store frame `01-tonight.png`). The over-flagging is documented as a known limit in PHASE_STATUS 2026-10-06. Detail ends with the NPS description "…Come explore for yourself!" set in Nyx's own type with no attribution (`shots/27-detail-07.jpg`), which breaks the "no exclamation points" voice rule (§2). Nyx's own catalog has 0 exclamation marks (scripted scan of `Localizable.xcstrings`).
  - Why it matters: in the very first store frame, the most prominent sentence after the score is irrelevant, and it trains users to ignore the closure line that §4 calls the most important safety signal. Data that ships in the brand voice reads as the brand.
  - Recommendation: show the hero warning only for road, area or park closures. Route everything else to "Before you go (n)". Normalise NPS Title Case to sentence case for display. Label the description "From the National Park Service", or cut it (it adds about 200 pt for no planning value).
  - Effort: S

- **[DX-08] Calendar "new moon window" ring contradicts the scores beside it** — Severity: P2
  - Evidence: on Oct 7 the ring marks Oct 8-12 (scores 95, 85, 86, 94, 86) while Oct 13-15 (89, 94, 92) are unringed (`shots/ipad-calendar.jpg`, `shots/27-calendar-live.jpg`). The window is moon-only by design (`CalendarView.swift:325-328`), and the caption has to apologise for it ("Clouds and access may change the best choice"). Past nights Oct 1-4 render as hollow rings, the same glyph the legend assigns to "moon and darkness only", while Oct 5-6 render as dimmed filled dots (`shots/27-calendar-live.jpg`).
  - Why it matters: Interaction. When the highlight and the numbers disagree, users stop trusting both. Hollow means one thing in the legend and another for past nights.
  - Recommendation: while forecasts exist, ring the best five consecutive nights by `rankScore`, and keep the moon window as the fallback beyond the horizon ("Best stretch" vs "Darkest moon stretch"). Render all past nights one way: dimmed, no ring, no score, or hidden entirely.
  - Effort: S

- **[DX-09] Night vision, a signature moment, is two taps deep behind an icon that reads as "filters"** — Severity: P2
  - Evidence: the only in-app night-vision switch is in Settings (`SettingsAndLearn.swift:15`), and Settings is reached only through `slider.horizontal.3` on Tonight (`TonightView.swift:54`), the same glyph users associate with the radius and filters on that screen (`shots/27-tonight-live.jpg`). Parks uses `line.3.horizontal.decrease` for filters (`shots/27-parks-live.jpg`). Nowhere else exposes the toggle.
  - Why it matters: §6 lists the night-vision toggle as a signature moment, and Inclusivity depends on it being reachable in the dark in one gesture. The Control Center control helps, but juries judge the app.
  - Recommendation: add a moon/eye toolbar button (or a long-press on the Tonight tab's moon icon) on every root that toggles night vision with the existing spring and haptic. Change the Settings glyph to `gearshape`.
  - Effort: S

- **[DX-10] At AX5 the hero numeral shrinks, and the compass header truncates** — Severity: P2 (Inclusivity)
  - Evidence: `CelestialGauge.swift:24,68` fixes the dial at 220 pt and drops the numeral from 108 to 82 pt at accessibility sizes, so on Tonight and detail "97" ends up about the same height as "Pristine" and smaller than "DARKNESS / 100" (`shots/27-ax5-tonight.jpg`, `shots/27-ax5-detail.jpg`). The field compass header truncates the band to "86 · Excell…" and the drawn sky is gone from the first screen (`shots/27-ax5-compass.jpg`). The AX5 calendar list starts at Oct 1, so six past nights come before tonight (`shots/27-ax5-calendar.jpg`).
  - Why it matters: the score is "the hero of every screen" (§6). At AX5 the hierarchy inverts. Truncation at AX5 is an explicit §3 failure.
  - Recommendation: at AX sizes keep the numeral at least 1.6× the band label (scale the dial with `@ScaledMetric`, capped at the width). Let the field header wrap the band or drop "Excellent" to its own line. Scroll the AX calendar list to tonight (`defaultScrollAnchor` / `scrollPosition(id:)`) and hide or collapse past nights.
  - Effort: S

- **[DX-11] Liquid Glass used on content cards; the glass layer is effectively invisible** — Severity: P2
  - Evidence: every `Panel` applies `.glassEffect(.regular.tint(…))` over an 80%-opaque indigo fill on iPhone (`Nyx/DesignSystem/NyxTheme.swift:56-59`). Apple's Liquid Glass guidance reserves glass for the control and navigation layer floating above content. In captures the panels read as flat indigo cards (`shots/27-detail-02.jpg`), so the effect costs compositing on a dozen stacked cards with no visible benefit. Settings and Your privacy, meanwhile, fall back to stock system-gray grouped forms (`shots/27-settings.jpg`, `shots/27-privacy.jpg`), which is a different surface language from the rest of the app.
  - Why it matters: "best-in-class Liquid Glass integration" was the cited reason Moonlitt won. Glass on content is the most common Liquid Glass misuse jurors look for. Two surface systems (indigo cards vs system gray) read as two apps.
  - Recommendation: content panels become solid `palette.panel` with the hairline. Reserve glass for floating controls: the park pill, river thumb, tab bar, toolbar groups, the field segmented control, and a floating "I'm here tonight" bar. Give Settings and Privacy `scrollContentBackground(.hidden)` over the night background with the same panel fill.
  - Effort: S
  - (Verify the iOS 26 HIG wording on content-layer glass before citing it externally; unverified quote.)

- **[DX-12] Viewing spots: raw coordinates and the same disclaimer repeated per spot** — Severity: P2
  - Evidence: each spot prints "33.954, -116.163 · approximate" and then a three-line "Approximate coordinates… This is not a navigation guide." block. The sentence repeats verbatim for every spot (`shots/27-detail-05.jpg`, store frame `10-every-sky.png`). The coordinates are not tappable or copyable from the row.
  - Why it matters: it is the least designed panel in the app, and it is store frame 10. It also creates a mixed message: Joshua Tree scores 94 "Pristine", yet both spots say "Among the brightest national parks · Brighter than the park's center" with 5 of 5 glow dashes (`shots/27-detail-05.jpg`).
  - Recommendation: render spots as a small RealSky-horizon thumbnail or a mini map glyph of the park outline with spot dots (bundled outline, no network), with name, glow meter and step-free. Put a single disclaimer at the panel foot. Make the coordinates a copy action (`.contextMenu` → Copy). Reconcile the glow wording with the score: say "Brighter than this park's other spots" rather than ranking against all parks.
  - Effort: M

- **[DX-13] Time river needs a paragraph to explain itself** — Severity: P2 (Interaction)
  - Evidence: under the river: "Drag along the river. Pale bars span three forecast models; dashed, hollow nights are moon and darkness only. Small marks above a night are a meteor shower's peak or a lunar eclipse." (`shots/27-detail-river.jpg`). The model-spread bars render as I-beam glyphs that read like text cursors (`27-detail-river-crop.png`). Scrubbing works and the moon morphs well (`shots/27-detail-river-scrubbed.jpg`).
  - Why it matters: §14 says "When a custom control confuses in testing, simplify". A legend paragraph is the tell.
  - Recommendation: replace the paragraph with a one-time TipKit tip, and let the selected night's caption carry the meaning ("Oct 27 · 43 · forecast not yet available"). Draw model spread as a soft vertical glow band behind the dot instead of capped bars. Label the forecast horizon once with a subtle "forecast ends" tick.
  - Effort: S

- **[DX-14] Score saturation makes "darkest tonight" a five-way alphabetical tie** — Severity: P2 (cross-ref score/engine lens)
  - Evidence: sorted by "Darkest tonight", the top five are all 97 and appear in alphabetical order: Big Bend, Bryce Canyon, Capitol Reef, Crater Lake, Death Valley (`shots/27-parks-darkest.jpg`).
  - Why it matters: the app's core question gets a non-answer near new moon, the best week to use it.
  - Recommendation (UX side): break ties visibly by the most informative secondary signal (Bortle, then longer true darkness, then lower cloud spread) and show it in the row ("97 · Bortle 1"). The engine lens should judge whether the 20% Bortle weight compresses too much.
  - Effort: S

- **[DX-15] iPad: some screens are stretched phones, others have a void below the fold** — Severity: P2
  - Evidence: Plan a trip on a 13" landscape iPad is a single centred phone column of form rows (`shots/ipad-trip.jpg`). The sky arc stretches to about 670 pt wide at a fixed height, so the arc flattens to a line (`shots/ipad-detail.jpg`). Tonight leaves the bottom third empty in portrait (`shots/ipad-tonight-portrait.jpg`, store `store-ipad-01-tonight-13.png`). Strong layouts: the Parks three-column split, the Calendar with an inline breakdown, and the Journal with constellation plus list (`shots/ipad-parks.jpg`, `shots/ipad-calendar.jpg`, `shots/ipad-journal.jpg`).
  - Why it matters: Apple features iPad apps that use the canvas. This is half done.
  - Recommendation: Trip uses two columns (inputs on the left, route map plus nights on the right). Sky arc keeps an aspect ratio of about 2.4:1 and uses the extra width for a larger moon or the core path. Tonight in portrait fills the lower area with "Next 7 nights across parks in reach" (a compact grid of rows × nights), which is the "when" answer.
  - Effort: M

- **[DX-16] Ask Nyx looks like a debug console** — Severity: P2
  - Evidence: `TextField(...).textFieldStyle(.roundedBorder)`, then a prominent "Ask using these records" button, then "THE ORIGINAL RECORDS" printed as semicolon-joined strings ("1. Death Valley; Fri, Oct 2; score 76/100 Excellent; clouds unknown…") (`Nyx/Views/GuideView.swift:44-62`, current build `shots/17e-ask.jpg`, earlier `Research/Screenshots/ask-offline-27.png`).
  - Why it matters: Foundation Models is a showcase API, and this presentation undercuts it. Jurors try the AI feature.
  - Recommendation: present records as the same `ParkRow`/night cells used elsewhere. Make citations tappable chips that open the night. Use a glass input bar pinned at the bottom with suggested prompts ("Best weekend this month?"). Or apply DX-01 and fold it into Plan as "Explain this plan".
  - Effort: M

- **[DX-17] Count-up is a linear ramp, not a physical one** — Severity: P3
  - Evidence: `CelestialGauge.swift:52-58` steps 0→score by 2 every 12 ms, about 0.6 s at constant speed, with a spring applied per step. Haptics fire only at 70 and 90. §6 says "nothing linear".
  - Recommendation: drive the displayed value from a decaying spring (fast start, long settle over the last 10 points, like an odometer), with the arc's sweep leading the numeral by about 80 ms. Add a light tick at the band boundary the score lands in. Device testing should confirm 120 Hz smoothness (unverified in simulator).
  - Effort: S

- **[DX-18] Small polish** — Severity: P3
  - "DARK HOURS" wraps to two lines on 402 pt and narrower phones while the other three labels stay on one, so the four values sit at uneven heights (`shots/27-detail-01.jpg`, `shots/17e-detail.jpg`). Use "DARKNESS" or let all four labels share a two-line slot.
  - Compass cardinal "S" is clipped by the control tray (`shots/27-field-compass.jpg`, `shots/17e-compass.jpg`). The reticle circle sits about 60 pt above the core's glow with the "Milky Way core" label between them, so it reads as if the circle marks the core (`FieldCompass.swift:163-174,178`). Separate the reticle style (crosshair) from target markers.
  - What's up leads with "October Draconids · about 2 an hour" above the Milky Way core (`shots/27-whatsup-link.jpg`). Order events by expected payoff and demote showers under about 10 an hour to a one-line mention.
  - Onboarding page 2's bars show the **weights** (40/25/20/15%) filled almost full, which reads like a perfect score rather than a recipe (`shots/27-onboarding2.jpg`). Label them "share of the score" or draw them as proportional segments of one bar.
  - Onboarding page 3's art is a nearly invisible new moon (`shots/27-onboarding3.jpg`). End on the brightest frame (full real sky or the moon), not the darkest.
  - Default Parks sort is Name (`shots/27-parks-filtermenu.jpg`). For the core question, default to "Darkest tonight".
  - Ranger program cards print the full NPS description unclamped with no time or place (`shots/27-detail-06.jpg`). Clamp to 3 lines with "More" and show the time.
  - Trip plan lists consecutive nights at the same park as separate rows, each with its own "Add to Calendar" (Death Valley ×3, `shots/17e-trip.jpg`). Group them as "3 nights at Death Valley · Oct 7-9" with one calendar action.
  - Learn cards: six identical templates at about 230 pt each show only two and a half per iPhone screen (`shots/27-learn.jpg`).

- **[DX-19] App Store product page: the first three frames would not get this featured** — Severity: P1 (App Store Awards, featuring)
  - Evidence (`Store/Framed/6.9-inch/`): Frame 01 (Tonight) has a strong caption ("Where is the sky darkest tonight?"), but the most prominent line after the score is the gas-pumps alert, and the floating tab bar half-covers a truncated "More skies" row at the bottom. Frame 02 (Score) is the same gauge again, with the same layout as 01. Frame 03 (What's up) is a wall of text on an indigo card with no visual. So three of the first four frames are gauges or text. Frames 04/05 (field mode) show the white status bar and **green** battery over the red night screen, which contradicts the dark-adaptation pitch. The production field presenter hides the status bar (`FieldSession.swift:156`); the store route is a DEBUG view that doesn't. Frame 05's header says "Moon and darkness only. Clouds unknown." Frame 06 (calendar) has its "Five nights near the new moon" card under the tab bar. Frame 10 is the coordinates-and-disclaimer panel (DX-12). No frame shows the moon at size, the real sky in colour, or the river mid-scrub. iPad frames are raw and uncaptioned, while iPhone frames are captioned (`Store/Screenshots/iPad/*.png`). `Store/Framed/README.md` and PHASE_STATUS call them landscape, but they are 2064×2752 portrait. No App Preview video exists; only a script (`Store/1.1/app-preview-script.md`).
  - Why it matters: editors decide in the first three frames and the preview. These three sell "a dark weather app with a big number", not "a planetarium in your pocket".
  - Recommendation: re-sequence: (1) the real sky over a park in colour with the score as a small overlay, captioned "Where is the sky darkest tonight?"; (2) the river mid-scrub with the moon morphing, captioned "Find the night worth the drive"; (3) the full-size moon; (4) field mode, captured through the production presenter or with `-nyx-screen field` patched to hide the status bar; (5) the calendar, with the tab bar not covering content (capture with the bar minimised or scrolled). Caption the iPad set. Produce the 15-30 s App Preview: score reveal → river scrub → night-vision toggle.
  - Effort: M

### The 3 strongest screens
1. **Onboarding page 1** (`shots/27-coldlaunch-onboarding1.jpg`): a large, correctly lit crescent with earthshine, one serif line and one action. This is the app's award frame, and it isn't in the store set.
2. **Field mode, "The night"** (`shots/27-field-night.jpg`, `shots/ipad-field.jpg`): red-only, large serif times, one idea per card, an honest eye-adaptation clock. It is distinctive and purposeful, though DX-02 needs fixing.
3. **Calendar month** (`shots/27-calendar-live.jpg`, `shots/ipad-calendar.jpg`): night cells sized by score, a cloud glyph, hollow horizon nights, a long-press peek with a native preview and actions (`shots/27-calendar-peek.jpg`), and an inline breakdown on iPad. Dense, legible and native.

### The 3 weakest screens
1. **Park detail below the river** (`27-detail-02…07.png`): a dozen similar indigo cards, about five screens long, with repeated disclaimers, raw coordinates, an unclamped NPS essay and a 70 pt moon. This is where focus is lost (DX-01, DX-05, DX-12).
2. **Ask Nyx** (`Research/Screenshots/ask-offline-27.png`): a stock rounded text field and semicolon records. It is the least crafted screen in the app and sits next to a showcase API (DX-16).
3. **Where to look at AX5, and in its store frame** (`shots/27-ax5-compass.jpg`, `05-where-to-look.png`): truncated header, no sky above the fold at AX5, a status bar over red in the store art, and a reticle that reads as the core marker (DX-10, DX-18, DX-19).

### Strengths worth protecting
- Typography system: serif numerals and headings, SF for UI, and calm, honest copy. There are zero exclamation marks in Nyx's own 1,152 strings.
- iOS 26.5 parity is genuinely first-class (`26-*.png` match `27-*.png` pixel for pixel in layout).
- Increase Contrast and night-vision palettes hold up across screens (`27-contrast-*.png`, `shots/27-tonight-nightvision.jpg`, `shots/27-detail-nightvision.jpg`).
- Native-first controls where they belong: menus, peek and context menus, sheets, the `.sidebarAdaptable` tab, and the iPad three-column Parks split.
- Honesty surfaces such as "Estimate", renormalised breakdown weights (`shots/27-detail-river-scrubbed.jpg`: 3/53, 20/27, 20/20) and "moon and darkness only" are part of the brand. Keep them; just stage them.

### Open questions for the owner
1. Will you accept consolidation (a four-tab IA with Plan = Calendar + Trip, Learn moved out of the tabs, park detail in three chapters) for the award build, even though it moves features you shipped in 1.1?
2. Should the calendar ring mean "least moonlight" (as the spec says today) or "best stretch by score while forecasts exist" (DX-08)?
3. Should the NPS park description stay on detail at all, given the voice rule and its length?
4. Which hero should lead the product page: the real sky (needs DX-06), the moon (DX-05), or the score? The current set leads with the score twice.
