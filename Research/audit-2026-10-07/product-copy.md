## Product coherence, copy, content and story — findings

Scope: the product brief §2/§16; `Nyx/Resources/Localizable.xcstrings` (all 1,152 keys extracted), `InfoPlist.xcstrings`, `NyxVision/Resources/Localizable.xcstrings` (205 keys); Learn essays; onboarding (`Nyx/Views/SettingsAndLearn.swift:194-297`); Tonight, detail, settings, notifications, Ask Nyx, share card; `Store/1.1/*`; `docs/` + press; store frames (`Scripts/make_store_frames.swift`, `Store/Framed/6.9-inch/01,02,03,06` viewed); `Research/localization/`. No build, no simulator.

### Verdict
The voice is the strongest thing here: across 1,152 strings there is **no exclamation mark and no marketing adjective** (scan below), uncertainty is stated everywhere, and the Spanish is fully translated with a real glossary and a consistent tú register. The product, though, has outgrown its own question. 1.1 added roughly twenty features in five days (field mode, Watch, Vision, iPad, trip planner, constellation, year recap, sonification, Moon haptics, sky glow, smoke, three-model agreement, planets, meteors, eclipses, alarms, Focus, Live Activity, alternate icons, first light, MetricKit proof), none of them tried on a device. The "where and when" answer is fast and clear. The loop then breaks at every hand-off: **decide → go → remember**. Saving a park offers nothing. The closure sits under the river on the detail page. Nothing in the app hands you coordinates or a calendar entry for a chosen night. The night never ends in "keep this night". The first-run answer for anyone outside Southern California is about Joshua Tree. The store page, press kit and nominations disagree with each other about what version this is. A juror would find a beautiful, honest, over-furnished app with no human evidence behind it.

### Findings

**Product coherence and IA**

- **[PC-1] The loop breaks after "decide": saving, going and remembering are disconnected** — Severity: P1
  - Evidence: Saving a park only inserts a row (`Nyx/Views/ParkViews.swift:383` `saveButton`). It never offers the promising-night reminders, which live only at Tonight → slider icon → Settings → "Saved parks" (`SettingsAndLearn.swift:17-25`) and are off by default. "Add to Calendar" exists only in the trip planner (`TripPlannerView.swift:236`), not on a park's night, the calendar breakdown or the river. A viewing spot's coordinates are reachable only through a long-press context menu (`SkyGlowViews.swift:96`). Field mode ends with "The night is over. Rest your eyes." (`FieldNight.swift:129`), with no way to record the night. The journal is reachable only from the Journal tab's "+" (`JournalViews.swift:42,46`), and `JournalEditorView()` takes no park or date.
  - Why it matters: this is the core loop in the product brief ("which nights to take off work") and the Interaction category. Each step is one tap from the next only if someone builds the bridge.
  - Recommendation: (1) The first save presents the existing `PermissionExplainer` for reminders, in context, as §8 of the brief intends. (2) Add "Add to Calendar" (the same `EKEventEditViewController` path, no permission) to a chosen night on the detail page and in the calendar breakdown. (3) Make "Copy coordinates" a visible row button. Owner decision on a "Open in Maps" hand-off (a `maps://` URL opens Apple's app at the user's tap, as nps.gov links already do; §13 forbids Nyx calling routing services, not the user leaving the app). (4) At dawn in field mode, and on the park's detail the morning after a field session, show "Keep this night", which opens the editor prefilled with park, date, score, Moon and the observed-Bortle default.
  - Effort: M

- **[PC-2] On the park page, the closure sits below a 30-night river, not beside the score** — Severity: P1
  - Evidence: the detail hero (`ParkViews.swift:273-292`) shows name, date, access note, gauge, polar and forecast caveats, smoke, readout and "I'm here tonight", but no closure. Closures appear in "Before you go" (`ParkViews.swift:297`) after the river panel. Tonight does put the closure beside the score (`TonightView.swift:107`). The press kit claims "Closures beside the score" (`docs/press/index.html`).
  - Why it matters: the product brief §4 calls a closed road "the worst outcome this app can cause". The press claim is currently false for the detail page.
  - Recommendation: reuse Tonight's scrimmed closure label in the detail hero under the date, and keep "Before you go" for the full list. Also see ST-2: the over-flagged "gas pumps closed at night" then becomes the most prominent line on the page, so rank alerts (road or area closure first, amenity notices folded into "All park alerts").
  - Effort: S

- **[PC-3] Too many "when" tools, scattered across three places** — Severity: P2
  - Evidence: the 30-night time river (detail; also Tonight on iPad), the Calendar tab (one park per month, its own park picker), the trip planner (a card at the bottom of Tonight, `TonightView.swift:211`), the "Darker on…" nudge (`TonightView.swift:187`), widgets "best of the next 7 nights", and Siri "Find the best night". The trip planner (multi-park, the real "which nights do I take off" tool) is the most buried.
  - Recommendation (proposed IA, owner decision):
    - Tabs: **Tonight** (where, plus one "darker on" line and your saved parks' best night), **Parks**, **Plan** (rename Calendar; a segmented control: *One park* month / *My free nights* trip planner), **Journal** (entries, constellation, year), **Learn**. With four or five tabs, keep Learn; if Apple's tab bar ever feels crowded, Learn is the one to fold into Parks/Settings.
    - Detail page from 9 panels to 6: Score + closure → River → **Tonight's sky** (sky arc + What's up + alarms) → **Conditions** (Moon, clouds and models, air, cold/dew/wind, light pollution as one panel with disclosure) → Viewing spots and programs → Protect this sky. Share moves to the toolbar (the system pattern). "Listen to this night" and "Feel the Moon" stay, but as one compact row plus accessibility custom actions, not inline buttons inside the sky and Moon panels.
    - Settings: reachable from every tab (today only Tonight, `TonightView.swift:54`). Remove the dead "Distance units: Device locale" row (`SettingsAndLearn.swift:30`); it is not a control. Rename the "Your iPhone" section "Privacy and data".
  - Effort: M (IA) / S (settings)

- **[PC-4] Clever but not serving the question (the product brief §16 restraint)** — Severity: P2
  - Evidence and recommendation, ranked by what to cut:
    1. **AI notification title, cut.** The on-device model sees only the park name and picks between "A promising night at X" and "A night to consider at X" (`RootView.swift:280-284`, `OnDeviceGuide.swift:105-110`). That is a coin flip with a model inside it. It can downgrade a 96 Pristine night to "a night to consider", and it runs a model call for every new reminder on every activation. The §12 claim of "smart notification copy" is not earned. Replace it with the deterministic copy in NA-1.
    2. **Season recap (Ask Nyx `.recap`) and Year under the stars overlap.** Merge the recap into Year.
    3. **MetricKit luminance proof** appears in both Your privacy and About the data. Keep one place, About.
    4. Keep (they serve identity): field mode, sky glow, the honest forecast, the constellation. Keep sonification and haptics too (they are the Inclusivity case), but out of the visual path (PC-3).
  - Effort: S

- **[PC-5] The score saturates: about a third of a desert month is "Pristine", and reminders follow** — Severity: P1
  - Evidence: the store calendar frame (`Store/Framed/6.9-inch/06-calendar.png`) shows Joshua Tree at 90 or above on Oct 6, 7, 8, 9, 12, 13, 14, 15 and 16 (nine forecast nights), and many more at 85 to 94. Reminders fire for every night ≥90 with a forecast. There is no per-park or per-week cap, only the 60 total (`NotificationScheduler.swift:77-90`). One saved desert park can mean about nine reminders in 16 days, and three saved parks about twenty-five. Joshua Tree's Bortle is 3 (`parks.json`), which the Bortle essay itself calls "a rural sky where artificial light may be visible near the horizon", yet the band reads "Pristine".
  - Why it matters: "Pristine" stops meaning anything and the calendar stops discriminating, so the decision gets harder. Notification fatigue is the fastest route to the app being muted. It is also an honesty problem: the word overstates the sky (§17).
  - Recommendation: (a) Reminders: at most one per park per 7 nights (the best of a run, the earliest on a tie), plus the "subtle double-tap" haptic only for that one. (b) Owner decision on the band: either rename the top band for the *night* rather than the *sky* ("Exceptional"), or gate "Pristine" on Bortle ≤2. The score is unchanged either way. (c) In the calendar, mark only the single best night of each run (the river already uses triangles for the top three).
  - Effort: S (cap) / S plus owner decision (band)

**First-run experience**

- **[FR-1] First launch answers for Joshua Tree, and calls it "nearby"** — Severity: P1
  - Evidence: the default home park is `jotr` and the radius is 200 mi (`Nyx/App/PlanModel.swift:54-55`). Tonight's hero eyebrow is "Your darkest nearby sky" (`TonightView.swift:100`), with "From Joshua Tree" in a panel below it (`:229`). Onboarding never asks for a starting point (`SettingsAndLearn.swift:202-203`), by design (no permission up front). A first-time user in Chicago finishes three onboarding pages and is told their darkest nearby sky is Death Valley.
  - Why it matters: time to a true answer is several taps (find "Near me", read an explainer, grant permission) for everyone outside the Mojave. A wrong first answer is the worst first impression for an app whose brand is honesty.
  - Recommendation: on first run (until a starting point is chosen), replace the hero eyebrow with a choice card above it: "Where do you start from?" [Near me] [Choose a starting point]. Show "Example: from Joshua Tree" until then. That is no permission up front, but the question is asked. Never say "nearby" for a park-relative origin; use "Darkest within 200 mi of Joshua Tree".
  - Effort: S

- **[FR-2] Location denied, far from parks: "A starting park works just as well" is false for most Americans** — Severity: P1
  - Evidence: the starting-point picker lists only the 63 parks (`TonightView.swift:264-281`), searched by park name or state (`Park.swift:38-42`). Illinois has no national park, so searching "Illinois" returns nothing. The copy says "Location is off. A starting park works just as well." (`TonightView.swift:241`).
  - Recommendation: bundle an offline list of starting places (public-domain US Census Gazetteer: state centroids plus about 1,000 largest places, roughly 60–100 KB). "Chicago, IL" then works with no location and no network. Same file powers Ask Nyx (AN-2). Until then, change the copy to "Location is off. Choose the park closest to you."
  - Effort: M

- **[FR-3] A thin result in a small radius doesn't suggest looking farther** — Severity: P2
  - Evidence: with "Near me" in Chicago at the 200 mi default, the only candidate is Indiana Dunes (32 mi, Bortle 6). Mammoth Cave (333 mi, International Dark Sky Park, Bortle 4) and Isle Royale (428 mi, Bortle 2) are outside it (computed from `parks.json`). The "A little farther from here" state appears only when the result is *empty* (`TonightView.swift:41`), and "More skies within reach" is empty.
  - Recommendation: when fewer than three parks are in reach, or the best is Bortle ≥5, add one line under the hero: "Darker within 500 mi: Mammoth Cave, 88 tonight." Tapping it widens the radius. It is honest and teaches what the radius is for.
  - Effort: S

- **[FR-4] Onboarding copy is atmospheric, not informative, and skips the signature feature** — Severity: P2
  - Evidence: titles "Make room / for the night", "A darker sky. / A clearer plan.", "The night is yours." CTA "Begin exploring" (`SettingsAndLearn.swift:202,227`). Page 1's body ("Find the national parks and nights that give the stars their best chance.") never says *score*, *63 parks* or *which night*. Night vision, the one thing a night-adapted user needs on day one, is introduced nowhere except Settings (`SettingsAndLearn.swift:15`).
  - Recommendation, drafts:
    - P1 title "Where and when the sky is darkest". Body: "Nyx compares the 63 national parks night by night, so you know which park to drive to and which night to take off."
    - P2 unchanged (it is good), plus the band words under the example: "90 Pristine · 75 Excellent · 60 Good".
    - P3 title "Made for dark eyes". Body: "Turn the screen red at any time from Control Center. Nyx has no account, no ads, no tracking. Your journal never leaves this phone." Add a live red toggle on the page.
    - CTA: "Show me tonight".
  - Effort: S

**Copy audit (voice rules)**

- **[CP-1] Clean on the hard rules: no "!", "¡" or marketing adjectives** — (strength, evidence)
  - A scan of every en/es value, the essays, `docs/` and `Store/1.1/metadata.md` found zero exclamation marks. The only adjective hit is "perfect", used in the ZHR definition ("under a perfect sky"), which is legitimate.

- **[CP-2] The score's four parts have four names each** — Severity: P1 (comprehension and consistency are the brand)
  - Evidence:
    - Readout: "Moon / Clouds / Sky glow / Dark hours" (`ScoreReadout.swift:27-30`).
    - Its spoken values: "Moonlight / Cloud cover / Light pollution / Length of darkness".
    - Breakdown rows: "Moonlight / Cloud cover / Light pollution / Length of darkness" (`ParkViews.swift` `row(...)`).
    - Onboarding: "Moonlight / Clouds / Light pollution / Length of darkness" (`SettingsAndLearn.swift:267`).
    - Breakdown detail: "Astronomical darkness, with ten hours receiving full credit."
    - Press kit: "Moon / Clouds / Sky glow / True darkness".
    - About: "estimated light pollution … length of true darkness".
    - Darkness itself is called "true darkness" (47 strings), "dark window" ("%lld%% average cover across the dark window."), "the dark hours" ("Moon down through the dark hours"), "Darkness begins", and "Astronomical darkness". Vision Pro adds "Middle of darkness / Middle of the night / Middle of true darkness" for one control.
  - Recommendation: canonical nouns are **Moonlight, Clouds, Sky glow, True darkness** (visible and spoken alike). Use "true darkness" everywhere a user reads it, and "astronomical twilight" only in About, glossed once ("true darkness: the Sun more than 18° below the horizon"). Replace "dark window" with "true darkness".
  - Effort: S

- **[CP-3] "Moon and darkness only" is opaque, and has 28 variants** — Severity: P1
  - Evidence: 28 catalog strings carry the phrase. It is lowercased in some ("moon and darkness only", "clouds unknown, moon and darkness only"), title-cased in others, and joined with "—", "·", ";" or "," to "clouds unknown", "forecast not yet available", "Cloud forecast unavailable", "No cloud forecast for this night" and "Open Nyx on iPhone for clouds". The same state reads "Moon and darkness only. Clouds are unknown." on Tonight (`TonightView.swift:105`) and "Moon and darkness only — forecast not yet available." on detail (`ParkViews.swift:~285`). A newcomer cannot tell that it means "this score leaves clouds out". Spanish inherits the problem: "Las noches sin relleno solo tienen Luna y oscuridad" reads as "hollow nights only have the Moon and darkness".
  - Recommendation: lead with what is missing, not what remains. Short label "**No cloud forecast yet**". Long form "**Clouds not forecast yet. This score counts the Moon and darkness only.**" Keep one variant for a stale forecast ("Cloud forecast unavailable") and one for the watch. That is about 4 strings instead of 28, and fewer for the Spanish review. Keep §8's honesty intact.
  - Effort: S

- **[CP-4] Moon capitalization, hyphenation and spelling drift** — Severity: P3
  - Evidence:
    - "New moon", "Full moon", "Five nights near the new moon" sit beside "Feel a new Moon", "a full Moon is one wide swell", "Plays the Moon's phase … a new Moon".
    - Spanish has the same drift inside one paragraph: "Una luna nueva … la luna llena … Una Luna creciente".
    - "Dark-Sky designated only" and "Dark-sky parks", while DarkSky International now writes "International Dark Sky Park" (no hyphen), which the app also uses ("An International Dark Sky Park, certified by DarkSky International.").
    - British spellings in a US-English app: "colour" ×5 (About the data: "lunar colour map", "light colour"), "travelled" (`learn/milkyway.md`).
    - The meteor essay uses kilometres only, against §2's locale rule.
  - Recommendation: house style "the Moon" for the body and lowercase phases ("a new moon", "a full moon"), which matches the Spanish glossary rule. "Dark Sky" without the hyphen. US spelling. Give distances in the essays in both units ("about 60 miles (100 km) up").
  - Effort: S

- **[CP-5] Decorative eyebrows stack three headers before the answer** — Severity: P2
  - Evidence: Tonight shows the nav title "Tonight", then the eyebrow "THE NIGHT IS WAITING", then "Where the sky is darkest", then "YOUR DARKEST NEARBY SKY", then the park (`TonightView.swift:73,100`; visible in `01-tonight.png`, whose store caption repeats the same headline). Other tagline eyebrows: Calendar "MAKE TIME FOR THE NIGHT" over "Choose your night"; detail "A NIGHT BENEATH THE STARS"; Learn "A little knowledge. A wider sky."; Journal "Keep a little of the night". These are slogans, the closest thing in the app to marketing copy.
  - Recommendation: eyebrows should carry information: the date and starting point on Tonight ("TUE, OCT 6 · WITHIN 200 MI OF CHICAGO"), the park's state and Dark Sky status on detail, the chosen park on Calendar. Drop the duplicated serif "Where the sky is darkest" on iPhone; the nav title plus the park pill already say it.
  - Effort: S

- **[CP-6] Jargon without a gloss in user-facing (non-About) copy** — Severity: P2
  - Evidence: "Rods taking over" (field clock; glossed only in a long paragraph); "Totality", "Penumbral lunar eclipse", "In Earth's shadow" (What's up); "%@ radiant" (glossed in only one string); "Bortle %lld" in rows and filters with no gloss (the breakdown has one); "Astronomical twilight / Nautical twilight / Civil twilight" and "R↑" in Vision Pro (`NyxVision/Resources/Localizable.xcstrings`). In About: "IANA time zone", "Sagittarius A*", "Aerosol optical depth at 550 nm", "ERA5 reanalysis". About can stay technical, but each paragraph should open with a plain sentence. Today "Park-local time" opens with "Each park has an IANA time zone."
  - Recommendation: one-line glosses ("Penumbral: the Moon dims slightly; easy to miss"; "Rods taking over: your faint-light vision is waking up"). Vision: rename "R↑" and gloss the twilight names. About: lead each block with the plain sentence, then the citation.
  - Effort: S

- **[CP-7] Duplicate near-identical strings** — Severity: P3
  - Evidence:
    - "No national parks fall inside this radius. Widen it or choose a different starting park." / "…Widen it or start from another park."
    - "Distances are straight lines, not driving routes. …" / "Distances are straight lines, not roads. …"
    - "Opens score breakdown." / "Opens the score breakdown."
    - "Hollow nights are moon and darkness only." / "Hollow nights have no cloud forecast yet."
    - Eleven variants of "forecast included" ("Cached forecast included", "Includes a cached cloud forecast.", "Includes cloud forecast.", "Cloud forecast included.", …).
    - "%@ from the night before" with and without a period.
  - Recommendation: consolidate. Each duplicate is another string in the Spanish review.
  - Effort: S

- **[CP-8] No plural variations anywhere; hand-rolled plurals already wrong** — Severity: P2
  - Evidence: zero `plural` variations in either language (scan of `Localizable.xcstrings`). `YourSkyViews.swift:91` branches on the *night* count but interpolates the *park* count, so 3 nights at 1 park prints "3 nights under the stars at 1 national parks". `NightCharts.swift:66` "1 of 30 nights have no cloud forecast yet." `TripPlannerView.swift:110` and `YourSky.swift:270-271` hand-branch for 1. Spanish inherits each one.
  - Recommendation: move every count string to String Catalog plural variations (`%lld nights`, `%lld national parks`, `%lld nights after the peak`, `Nights logged: %lld`, `%lld of %lld nights have…`) and delete the `==1 ?` branches.
  - Effort: S

- **[CP-9] Debug and preview strings ship in the catalog and go to translators** — Severity: P3
  - Evidence: "Extra-large widget review", "Large widget review", "Widget content review" (`TonightWidgetView.swift:368`); "Snippet review", "Voice only (iOS 27):" (`DebugPlatform.swift:26,30`); "Debug fixture, not a measurement." (`LuminanceProof.swift:32`); "StandBy at night (vibrant rendering, red tint, simulated)", "Tinted Home Screen (vibrant rendering, simulated)", "Content preview. …". "The forecast is resting" and "Moon and darkness calculations still work offline." are used only in a `#Preview` (`NyxTheme.swift:125`). The DEBUG notification explainer shows different copy from the shipping one (`RootView.swift:166` vs `SettingsAndLearn.swift:33`), so captures of it are not the real text.
  - Recommendation: use `Text(verbatim:)` in DEBUG and preview code and prune the catalog. Make the DEBUG explainer reuse the shipping strings.
  - Effort: S

- **[CP-10] Small word choices** — Severity: P3
  - "Unsave" / "Unsave park" is not iOS vocabulary; use "Remove from Saved".
  - "Ask using these records" (`GuideView.swift`) is jargon on a button; use "Ask".
  - "Darker skies shine brighter." (`YourSkyViews.swift:42`) reads as a paradox; "Brighter stars mark darker skies." is clearer.
  - "Am. Samoa", "Virgin Is." need fuller forms where space allows.
  - "63" is hard-coded in at least five strings ("63 places to look up", "%lld of 63 parks", "Nyx knows the 63 US national parks"). Interpolate the count so a 64th park is a data change, not a string change.

**Spanish (triage for the native review; tú register is consistent, nothing untranslated)**

- **[ES-1] Highest-risk items, in review order** — Severity: P1 for the store-facing items, P2 for in-app
  1. **Store and marketing calques** (`Store/1.1/metadata-es.md`): "Dale tiempo a un cielo más oscuro" and the caption "Dale tiempo a la noche" mean "give the night (some) time / be patient with it", not "make time for". Suggest "Hazle espacio a la noche" or "Date tiempo para un cielo oscuro".
  2. **Spanish metadata is stale against 1.1.** It describes 1.0-era widgets ("la semana que viene"), says forecasts don't include telescope seeing, omits Watch, Vision Pro, trip planner and sky glow, uses a different promo message, and its caption table doesn't match `spanishFrames` in `make_store_frames.swift`.
  3. **Times at 1 o'clock**: "Sale a las %@" prints "Sale a las 1:14 a.m.", which is ungrammatical. The glossary calls this "rare at night", but 1 a.m. moonrises and planet rises are common; the English frame 03 shows "Mars rises at 1:14 AM". Fix with "a la(s)" chosen in code by hour, or rephrase as "Sale: 1:14 a.m.".
  4. **"Solo Luna y oscuridad" and "Las noches sin relleno solo tienen Luna y oscuridad"** lose the meaning (see CP-3). Rewrite as "Sin pronóstico de nubes".
  5. **Band words**: "Mala" (Poor) reads as a harsh verdict, and "Prístina" is unusual for a night (the glossary already flags both). In spoken strings like "Índice de oscuridad: 94 de 100. Prístina." the feminine band doesn't agree with masculine *índice*. Consider "Excepcional / Excelente / Buena / Regular / Baja", which mostly avoids gender.
  6. "Probable rocío en las lentes": in Mexico, *el lente / los lentes*. Suggest "Puede formarse rocío en los lentes".
  7. "Ráfagas de %@" should be "Ráfagas de hasta %@". "sube alto antes del amanecer" is awkward; suggest "gana altura antes del amanecer".
  8. "Resplandor" alone (the score part "Sky glow") is ambiguous; use "Brillo del cielo". "Noches afuera" should be "Noches de observación". "Entran los bastones" is jargon. "Samoa Am." should be "Samoa (EE. UU.)".
  9. Moon capitalization drift inside the haptics paragraph (CP-4).
  10. No plural variations (CP-8).
  - Effort: S (code fixes) + the owner's paid review

**Learn essays**

- **[LE-1] Six good, accurate essays, but they are typeset as plain paragraphs, with gaps where the app's own concepts should be** — Severity: P1 (Visuals & Graphics, Inclusivity)
  - Evidence: 363–452 words each (`wc -w Nyx/Resources/learn/*.md`). `EssayView` renders the paragraphs under an SF Symbol (`SettingsAndLearn.swift:187-192`): no subheads, figures, pull quotes or links into the app. Accuracy spot checks pass: meteors burn about 100 km up; ZHR is defined correctly; the best hours are after midnight; the core's seasonal timing and the American Samoa inversion are right. The disclaimers repeat: the Bortle-estimate caveat appears in both the darkness and Bortle essays, and "a score never confirms that a road is open" in etiquette. The Bortle essay gives no observable cues, so a journal user can't actually pick a class. Five essays have a `.md` source (`Nyx/Resources/learn/`); `access` exists only in the catalog, so there are two sources of truth.
  - Missing essays that matter, in priority order:
    1. **Reading the Darkness Score.** The app's own concept is explained only in onboarding page 2 and About's dense paragraph.
    2. **Safe in the dark.** Night driving and wildlife, cold, no signal, telling someone your plan, headlamp etiquette, how to read a park alert. Some of this is in etiquette.
    3. **Your first Milky Way photo.** Core audience: a tripod, f/2.8, about 20 s, ISO 3200, focus on a bright star, the core's timing from What's up.
    4. **What a forecast can't tell you.** Model agreement, high cloud, smoke, why the score leaves them out.
    5. **Why red light.** Rods, cones and 20–30 minutes. This is in field strings and the access essay, but deserves its own page.
    6. Optionally: **The Moon's month** and **Leave No Trace after dark**.
  - Recommendation: give each essay one live figure from Nyx's own renderers:
    - Milky Way: the real sky at the core's best time for the home park.
    - Bortle: a 1–9 strip drawn with RealSky's brightness model, plus a cue list (Milky Way casts structure ≤3; zodiacal light ≤2…).
    - Meteors: the radiant on the compass sky.
    - Score: an annotated gauge.
    End each essay with one deep link into the app ("Tonight's best night for the core →"). Keep one `.md` source per essay. Use US spelling and dual units.
  - Effort: M (figures and links) / M per new essay with Spanish

**Notifications and Ask Nyx**

- **[NA-1] Reminder copy buries the news and spends the preview on boilerplate** — Severity: P2
  - Evidence: title "A promising night at %@". Body "%@: %lld/100, %@. Forecasts can change. Confirm park access before traveling." (`NotificationScheduler.swift:90`). The band ("Pristine") and the day sit in the body, and half the body is a caveat. the product brief's own example puts them in the title. The AI retitle (PC-4) can make the title vaguer still.
  - Recommendation, drafts:
    - Title: "**Pristine night at Joshua Tree, Friday**". Body: "**94 out of 100. Moon down all night; all three forecast models clear. Check park alerts before you go.**" Use the agreement or Moon clause only when it is true; it comes from the same `NightOutlook`.
    - Shower: "**Geminids at Big Bend tonight**". Body: "About 60 an hour after 11 PM, Moon down. A rough guide; check clouds and park alerts."
    - Use `UNMutableNotificationContent.appEntityIdentifiers` on iOS 27 (already in the roadmap).
  - Effort: S

- **[AN-1] Ask Nyx validates citation IDs but not the numbers in the answer** — Severity: P2 (honesty)
  - Evidence: `OnDeviceGuide.answer` accepts any text whose `sourceIDs` are valid (`OnDeviceGuide.swift:44-50`). The numeric check `grounded(_:facts:)` exists but is used only by `yearReflection` (`:95-99`). The model could cite record 2 and misquote "94" as "97". Ask Nyx's instructions also lack the "No exclamation marks" line the recap has, and don't pin the reply language, so a Spanish user may get English or mixed answers (unverified on device).
  - Recommendation: apply `grounded` to the answer against the cited records and tool results, falling back to the existing "could not ground" message. Add "Answer in the language of the question. No exclamation marks." to the instructions.
  - Effort: S

- **[AN-2] Ask Nyx can't answer the question people will actually ask** — Severity: P2
  - Evidence: `parksNear` takes "The starting national park" (`GuideTools.swift:123-128`). The roadmap's own example ("Which weekend in November is best within 4 hours of Denver?") needs a city, and drive time, which is out of scope. The model will refuse or improvise.
  - Recommendation: with the FR-2 places file, accept a city as the origin. Seed the empty text field with three tappable example questions that the tools can answer ("Best night at Arches this month", "Darkest park within 300 mi of Denver this weekend", "When does the core rise at Big Bend tonight?").
  - Effort: S once FR-2 lands

- **[AN-3] Raw records are shown to users in machine form** — Severity: P3
  - Evidence: "The original records" prints strings like "Joshua Tree; Fri, Oct 9 (2026-10-09); score 94/100 Pristine; cloud forecast included, 3% cloud; Waxing crescent 8% lit; 9.4 hours of true darkness" (`GuideTools.swift:34`, `GuideView.swift`). "Sources: 1, 3" is bare.
  - Recommendation: render records as small cards (park, date, score chip, one line) and make each citation number tap-scroll to its card.
  - Effort: S

**Share card**

- **[SC-1] The share sends a bare image: no words, no link, no story size** — Severity: P2 (Delight; organic reach)
  - Evidence: `ShareLink(item: rendered.image, …)` (`ShareCard.swift:38`) carries no message. The card is 420×580 pt (`:21`), neither 9:16 nor 1:1. It shows only the gauge, park, date and a caveat: no "Moon down from 9:40 PM", no core time.
  - Recommendation: add a message ("94/100, Pristine night at Death Valley, Fri Oct 9. Planned with Nyx." plus the App Store link once live), a 9:16 variant for Stories, and one "why" line (Moon-free hours or core window).
  - Effort: S

**App Store product page**

- **[ST-1] The page is written as an update to a 1.0 that never shipped** — Severity: P1
  - Evidence: 1.0 was never released (the audit brief). `metadata.md` drafts What's New ("Nyx 1.1 follows the night…", "Nyx still collects no data", "A third network service"), which a first release doesn't show. The press kit lists 1.1 features as "Planned" (`docs/press/index.html`). `INPUT_NEEDED.md` step 11 schedules an **App Enhancements** nomination by Oct 28, yet says "App Launch only if 1.0 never shipped", which is the case.
  - Recommendation: treat 1.1 as the launch. Drop What's New. File an **App Launch** nomination. Rewrite the press kit's fact sheet for the shipped feature set (see WP-1).
  - Effort: S

- **[ST-2] First screenshot: the right question, a weak answer frame** — Severity: P1
  - Evidence: `Store/Framed/6.9-inch/01-tonight.png`. The caption "Where is the sky darkest tonight?" is followed by the in-app headline "Where the sky is darkest" (a duplicate) and three stacked eyebrows. The most prominent amber line under the 96 is "Gas Pumps at Panamint Springs Resort are Closed at Night", an over-flagged amenity notice (a known limit in PHASE_STATUS). It answers *where* but not *when*, and only for a park-relative origin ("From Joshua Tree").
  - Recommendation: frame 1 should show where *and* when. Capture Tonight with the "Darker on Sat: 97 at Great Basin" capsule and no amenity alert (fix PC-2/ST-2 alert ranking, or pick a capture without one). Caption drafts:
    - 1. **"The darkest park. The darkest night."** (eyebrow: "63 NATIONAL PARKS")
    - 2. "One score. Four reasons, shown."
    - 3. "The Milky Way, timed for each park."
    - 6. "Choose the night worth the drive." (keep)
    - 4/5 (red, mostly black thumbnails) belong after the calendar. Search results show only frames 1–3, so the red field frames shouldn't sit in positions 4–5 ahead of the calendar.
  - Effort: S

- **[ST-3] Description, subtitle and keywords: thorough, but no hook, and weak search terms** — Severity: P2
  - Evidence: the description opens "Make time for a darker sky." and then runs ten all-caps sections (3,946 of 4,000 characters). The first three lines (what shows before "more") are mechanics. Subtitle choice "The night sky, park by park". Keywords `stargazing,milky way,meteor shower,moon phase,national park,astronomy,bortle,planet,eclipse,star`: "light pollution" and "astrophotography" are absent, while "bortle" (low volume) and "star" (generic) take space.
  - Recommendation, drafts:
    - Subtitle: **"Stargazing in national parks"** (28). It puts the highest-intent word in a weighted field and frees "stargazing" and "national park" from the keywords.
    - Keywords: `milky way,meteor shower,moon phase,astronomy,light pollution,astrophotography,dark sky park,planet,eclipse` (99; verify the count in ASC).
    - Description opening (keep the rest, cut a section to fit): "Which park, and which night? Nyx compares the 63 US national parks night by night and gives each a Darkness Score from 0 to 100, from the Moon, the clouds, the sky glow and the hours of true darkness. It tells you what it doesn't know. Free. No account, no ads, no tracking."
    - Merge "SKY GLOW" into "PLAN", and "WORKS OFFLINE" into "PRIVATE BY DESIGN".
  - Effort: S

- **[ST-4] App Preview script: sound, but it ends on privacy, not on the night** — Severity: P3
  - Evidence: `Store/1.1/app-preview-script.md`. Seven shots in 28 s; shot 6 is two cuts in four seconds; the end card is "No account. No tracking."
  - Recommendation: drop shot 5 (models disagree, which is hard to read muted), give field mode four seconds, and end on "Where. When. Then look up." over the Moon and the name. Privacy belongs in the description and the label.
  - Effort: S

**Website and press kit**

- **[WP-1] The site is a 130-word stub and the press kit is stale; there is no case study** — Severity: P1 (every award entry and nomination points here)
  - Evidence: `docs/index.html` has 130 words, no image, no App Store link, no link to `/press/`, and no `og:image` (grep of hrefs and srcs). `docs/press/index.html` (last edited Oct 6) still says "Platforms: iPhone… Version 1.1 is planned to add iPad, Apple Watch and Apple Vision Pro", "Spanish is planned for 1.1", "Launch date To be announced", and shows six 1.0 screenshots. It offers "the app icon … on request", with no icon download, no video, no developer photo or bio. The story's "Millions of people drive for hours into a national park to see the Milky Way" is unsourced. The roadmap promised "a case study … the shader Moon, the real sky, the score formula, the accessibility audit". None exists.
  - Recommendation: (1) Homepage: hero frame, App Store badge, three sentences, links to Press and Case study. (2) Press kit: current fact sheet, a downloadable zip (icon at 1024, the ten frames in en/es, Watch/Vision/iPad sets, the 30 s preview, the developer's photo), a 50/100/200-word boilerplate, and a source for every number (cite NPS astrotourism figures or remove "millions"). (3) **A 3-minute case study** page, "Designing for night-adapted eyes": the problem in one paragraph with a real park; the score and why 40/25/20/15, with one annotated night; how honesty is drawn (hollow nights, model bands, "estimate" labels); the red palette, with the measured contrast ratios; the Moon shader (before/after); inclusivity (audio graph, haptic Moon, step-free spots) with a short screen recording of VoiceOver on the gauge; what was cut and why; the numbers (63 parks, 0 data collected, 166 tests, USNO error 0.5/3.7 min).
  - Effort: M

### The pitch, as it stands

> Nyx answers one question for the millions who drive into America's national parks to see the Milky Way: where should I go, and on which night? It folds the Moon, the clouds, the sky glow and the hours of true darkness into one honest score for each of the 63 parks, then follows you into the night itself with a red field mode that counts down to true darkness, guards your dark adaptation and turns the real sky to wherever you point the phone, on your wrist and in Vision Pro. Its Moon is drawn from NASA's map and lit as the park sees it; its forecast says when three weather models disagree; it collects nothing. It is built for night-adapted eyes and for people who navigate by VoiceOver, sound and touch: you can hear a month of darkness and feel the Moon's phase. One person made it.

What is missing for that pitch to be undeniable:
1. **Evidence from the dark.** Not one night with a real device, a real park, or a real person (AUDIT.md "Physical review procedure" is entirely open). A juror's first question is "did it work out there?". Get two or three park visits with field mode, ideally one with a VoiceOver user, plus photos and quotes.
2. **A sourced problem.** Replace "millions" with an NPS or academic number, and add one concrete story ("drove four hours to Joshua Tree under a full Moon").
3. **A single signature moment that fits in one clip.** Right now there are a dozen. Pick one (the score reveal into the river scrub, or field mode's countdown turning red) and make every artifact (preview, case study, nomination) open with it.
4. **Restraint you can point to.** A "what we left out" paragraph (AR, accounts, aurora, ISS) is more persuasive than another feature. Today the 1.1 list reads as everything at once.
5. **Coherent public surfaces.** Store, press kit, nominations and website must agree on version, platforms and language (ST-1, WP-1).
6. **Inclusivity proof, not features.** A recorded VoiceOver walkthrough and one quote from a blind or low-vision stargazer. The Inclusivity story rests on it, and none exists.
7. **Impact beyond the user.** The roadmap's DarkSky International resource listing, or a ranger program that uses Nyx. Social Impact needs a partner, not an essay.

### Strengths worth protecting
- The voice: calm, short, honest, with zero exclamation marks or hype across 1,152 strings, the essays and the store copy. Copy such as "Nyx can't see what you looked at while you were away. Bright light resets dark adaptation." and "My screen stayed dark" is award-grade.
- Uncertainty is designed in: hollow nights, model ranges, "estimate" everywhere, closures retained when offline.
- Spanish infrastructure: a glossary with reasoning, a consistent tú register, everything translated, device variations for iPad ("this iPad").
- Permission explainers in context, and offline-first fallbacks with calm copy.
- The essays are accurate and well judged in tone. The access essay ("that is a flaw to fix, not a limit of the sky") is the best paragraph in the app.

### Open questions for the owner
1. Rename the top band ("Pristine" → "Exceptional") or gate it on Bortle ≤2 (PC-5)?
2. Allow a user-initiated "Open in Maps" hand-off for viewing spots (PC-1)? It is not a Nyx network call, but §13 says "including Apple routing services".
3. Bundle an offline US places list (about 100 KB, Census, public domain) so people far from parks can start from their city (FR-2, AN-2)?
4. Tab IA: rename Calendar to "Plan" and fold the trip planner into it (PC-3)?
5. Cut the AI notification-title feature (PC-4)?
6. Spend on the native Spanish review now, or ship 1.1 store metadata in English only and keep the Spanish UI (ES-1 items 1–2 are store-facing)?
