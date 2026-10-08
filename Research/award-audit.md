# Nyx award audit

*October 7, 2026 · build 1.1 (7) at `c7918ba` · nine review lenses, each written up in full in `Research/audit-2026-10-07/`*

## Implementation status (build 1.1 (8), October 7, 2026)

Everything below was implemented on `main` the same day, version still 1.1, decisions in `DECISIONS.md` ("Award audit implementation", waves 1–3), handoff in `PHASE_STATUS.md`. What is left needs the owner: accounts, a lawyer, a native Spanish reviewer and the device pass (`INPUT_NEEDED.md`).

| Area | Status |
|---|---|
| Ship-blockers S1–S12 | Done: score caps for clouds, sky glow and smoke; clouds fade toward each park's usual clouds by lead time (never rise offline); reminders only ≤5 days out on a fresh forecast, one per park per week; eclipse partial phases; one bulk NPS alerts request; Open-Meteo credit linked; privacy, support, credits and version in Settings; Texas age assurance through Declared Age Range (counsel review still the owner's); versioned journal store with migration; public pages and store copy as a first release |
| Also before submission | Done: state search, field countdown in minutes, closure beside the score on the park page, river activation, brighter red for colour-blind eyes, location purpose string, gated accessibility claim, archives moved out of `/tmp`. Store frames: recaptured once, after the device pass (the build 7 frames show scores the new rules no longer allow, so they must not be uploaded) |
| Score v2 and science | Done, with hard caps kept (see `DECISIONS.md`), best clear window, moonlight by phase and height, glow tie-breaks, planets and meteor ranges, aurora, satellite, zodiacal-light and limiting-magnitude notes, Haleakalā above the inversion; the false bright star T CrB removed |
| Close the loop, IA, first run | Done: four tabs with Plan, the park in three chapters, Where do you start from (with an offline US places list), Add to Calendar, Follow this night, Keep this night, one vocabulary, plural variations |
| Accessibility | Done: Assistive Access, Feel tonight, where to look by sound, action-slider alternative, Show Borders, photo descriptions, AX5 audits; device pass pending |
| Platform | Done: scheduled Live Activity, small family for Watch and CarPlay, stale face, tab accessory, glass lens and pill, widgets with a park setting, Moon widget, inline, controls, Siri values and snippet, journal by voice, Handoff, translation, Open sky alarms |
| Watch, Vision Pro, iPad | Done: Automatic palette, adaptation clock, Crown and Double Tap, Moon and Next dark complications; named stars and constellations, turn the night by hand, darker room, Moon volume, visionOS widget, forecast clouds behind a switch; new windows, drag and drop, inspector, the week across parks, field mode side by side |
| Content and reach | Done: four new Learn essays with links into Nyx, the Bortle figure, the map of tonight, campgrounds (Where to stay), from home tonight, website, press kit and case study |
| Not built, by decision | SharePlay on Vision Pro (needs the owner to relax the social and host rules); a native Mac target |

## How this audit was done

Each lens was reviewed separately against the product brief, `DECISIONS.md`, the earlier audits (`AUDIT.md`, `Research/award-roadmap.md`, `Research/depth-and-realism-audit.md`) and the installed iOS 27, watchOS 27 and visionOS 27 SDKs. Nothing already built was re-recommended. The question each time was whether what exists reaches award depth, and what is still missing.

| Lens | Method | Evidence file |
|---|---|---|
| Design and UX | App built and run on iOS 27 and iOS 26.5 simulators, iPhone 17e, iPad Pro 13, AX5, Increase Contrast; every screen captured and critiqued | `design-ux.md` |
| Astronomy and the score | Engine sources compiled unchanged into a harness, compared with live USNO and JPL Horizons, and every park scored for 60 nights at 0, 50, 100% and typical cloud | `astronomy-score.md`, `score-distribution.csv` |
| Accessibility and inclusivity | Every custom control, plus the contrast data and audit tests, checked against the SDK | `accessibility.md` |
| Platform APIs (iOS 26, 27) | Every availability guard and unused SDK symbol checked against the `.swiftinterface` files | `platform-apis.md` |
| Engineering | Concurrency, networking, persistence, launch path, tests, release | `engineering.md` |
| Compliance | Network hosts, privacy manifests, data licences, App Review Guidelines (June 8, 2026), state law | `compliance.md` |
| Beyond the iPhone | Watch, Vision Pro, iPad, widgets, Live Activity, controls, Mac, CarPlay | `multiplatform.md` |
| Product, copy, store | All 1,152 strings in both languages, essays, onboarding, notifications, Ask Nyx, store page, website | `product-copy.md` |
| Awards and market | 2025–2026 winners and citations, award calendars and fees, 17 competitors, launch strategy | `awards-market.md` |

Severity: **P0** blocks submission or makes Nyx say something false; **P1** is an award-critical gap; **P2** is a meaningful improvement; **P3** is polish.

---

## Verdict

Nyx is engineered and documented above the level of most apps Apple has honoured. The astronomy agrees with the U.S. Naval Observatory to within a minute at Alaskan, Hawaiian, Samoan and Caribbean parks. The privacy plumbing could not be broken. The voice holds across 1,152 strings with no exclamation mark and no marketing adjective, and accessibility in code is well past compliant. Every iOS 26.4 and iOS 27 API on the roadmap ships behind correct guards.

Four things stand between Nyx and an award, and none of them is a missing feature.

1. **Nobody can see it.** Apple's editors choose Design Award finalists from live apps, and finalists are named around May 18–20, 2027. Moonlitt won Interaction in 2026 with about 930 ratings and version 2.9 behind it. Nyx has no ratings, no release history and no live product page. Every week unreleased is a week of record the jury will not see.
2. **The score is not yet honest enough to defend.** The astronomy underneath is excellent, but the Darkness Score is a sum, so a fully overcast night scores "Good" on 55% of park-nights. Hot Springs, a Bortle 5 park inside a city, can read 90 "Pristine". A stale forecast makes the score go *up* when the phone goes offline. A juror who checks one cloudy night will distrust every number, and honesty is the brand.
3. **No evidence from the dark.** Nothing has run on a physical device, at a park, at night, or with a disabled person. The Inclusivity, Interaction and Social Impact cases all rest on simulator captures.
4. **The product has outgrown its question.** Roughly twenty features arrived in five days. The answer to "where and when" is fast, but the loop breaks after "decide": saving, going and remembering are not connected, and the first-run answer for anyone outside Southern California is about Joshua Tree.

Fix the score, close the loop, ship within about two weeks, gather real nights and real testers, then release a visible update every month until May. That is the path. The rest of this report is the detail.

---

## Ship-blockers (P0)

Each of these either makes Nyx state something false, breaks a licence or law, or fails on the first busy day. All are small. Together they are about a week of work.

| ID | Finding | Fix | Effort |
|---|---|---|---|
| **S1** | **Clouds cannot pull a night below "Good".** Clouds are 25 additive points (`ScoreEngine.swift:17-22`). At 100% cloud: median 62, max 73, 2,091 of 3,780 park-nights "Good". At 80% cloud, 28% read "Excellent". Death Valley at new moon under total overcast scores 73. | Make transparency a gate, like the existing darkness cap. See "The score, version 2" below. Pin with tests: 100% cloud never ≥ 40, 80% never ≥ 60. | S |
| **S2** | **Light-polluted parks reach the top bands.** Hot Springs (Bortle 5) max 90 "Pristine" and would trigger a "Pristine" reminder; Gateway Arch (Bortle 8) max 83 "Excellent"; Cuyahoga and Indiana Dunes (6) 88. | Cap the score by sky glow: Bortle ≤3 → 100, 4 → 89, 5 → 74, 6 → 59, 7+ → 39. | S |
| **S3** | **Going offline raises the score.** A forecast older than 36 h is dropped (`Forecast.swift:11`) and the remaining terms are divided by 0.75. A 65 night under 90% cloud becomes 83 "Estimate" at the park. Flagged "fix before release" in `Research/behavior-audit.md` A4; still open. | Keep the last forecast past 36 h, labelled with its age ("Clouds as of Fri 8 AM"). Never show a no-cloud score above the last known with-cloud score. | S |
| **S4** | **Smoke never touches the score.** A clear night in heavy smoke (AOD 1.0) shows 97 "Pristine" beside "faint stars hidden". | Cap the band: AOD ≥ 0.5 → at most Fair; 0.25–0.5 → at most Good. | S |
| **S5** | **Reminders fire on forecasts the app itself calls expired.** A "94/100 Pristine" reminder for a night 13 days out fires 12 days after its forecast; nothing refreshes it (`NotificationScheduler.swift:80-91`, no background task). | Schedule a score reminder only if the forecast will be ≤ 36 h old when it fires, and only ≤ 5 days out. Background refresh (P1, below) then extends it honestly. | S |
| **S6** | **Eclipse called "not visible" when the partial phase is up.** Virgin Islands 2026-03-03 (partial 05:50–06:36) and Badlands 2029-12-20 (Moon rises eclipsed, 16:13–17:28) both read "Not visible" (`SkyAlmanac.swift:338-351`). | Fall back through stages: totality, umbral, penumbral. "Rises already in Earth's shadow; partial phase visible 4:13–5:28 PM." Add both as tests. | S |
| **S7** | **The shared NPS key runs out at about 1,000 daily users.** One alerts request per park (`DataServices.swift:323-328`), looped (`PlanModel.swift:201-206`), up to a 1,000 mi radius. At 10k users the hourly quota is gone 6 minutes in; on a featured day, in 35 seconds. Closures, the safety signal, then go stale for everyone. The bulk call was verified and marked "fix before release" in `behavior-audit.md` A1, and never built. Per-park requests also reveal a rough region to NPS. | One `alerts?parkCode=<all 63>` request per 6 h, shared by every screen; events only on park detail, kept 24 h; persist `retryAfter`; key in the `X-Api-Key` header. Ask NPS for a raised limit before submitting. | M |
| **S8** | **Open-Meteo attribution is not done the way its licence asks.** CC BY 4.0 wants "a link next to any location Open-Meteo data are displayed". Today it is a plain caption on detail and unlinked text in About; nothing on Watch, widgets or the share card. The non-commercial basis is not confirmed in writing (Guideline 5.2.2: "must be provided upon request"). | "Weather data by Open-Meteo.com" as a real link beside the cloud meter and in About; a credits screen on Watch and Vision; email Open-Meteo describing the app and expected volume, and keep the reply. | S |
| **S9** | **No in-app privacy policy, support or contact link.** Guidelines 5.1.1(i) and 1.5. | "Privacy policy", "Support and contact", "Credits" and the version in Settings. | S |
| **S10** | **Texas app-store age law (SB 2420) is not addressed anywhere.** Apple's developer news (2026-06-03) says developers "must implement age assurance" for new Texas accounts; `DeclaredAgeRange` is in the SDK (iOS 26.0). Utah and Louisiana follow in 2027 (secondary sources). | One hour with counsel. Likely outcome: read `requiredRegulatoryFeatures` at launch, request an age range only when the system requires it, store nothing, gate nothing, document it in `PRIVACY.md`. | S–M |
| **S11** | **No versioned SwiftData schema, and a store failure replaces the whole app with an error.** The first shipped store defines V1. A 1.2 migration mistake would take out Tonight, Parks and Calendar too. | `NyxSchemaV1: VersionedSchema` plus an empty migration plan before the first public build. On failure, run the planner with an in-memory store and a journal-only banner. Test opening a V1 store on disk. | S–M |
| **S12** | **Public surfaces describe a product that does not exist.** The website reads as available now with no store link; the press kit says "1.1 is planned to add iPad, Watch and Vision Pro", "Spanish is planned" and "launch date TBA"; the featuring nominations assume 1.0 shipped; `metadata.md` writes a What's New for an update. | Treat 1.1 as the launch. One App Launch nomination. Website says "Coming to the App Store". One feature list in the press kit. Drop What's New. | S |

### Also before submission (P1, small)

- **State search is broken.** "Park or state" returns nothing for "utah"; only codes are searched (`Park.swift:38-43`). *(DX-03)*
- **The field countdown reads as a clock.** "22:39" sits next to "7:42 PM". Write "23 min". *(DX-02)*
- **Store frames.** The field frames show a white status bar and green battery over the red screen; recapture them through the production presenter. *(DX-19)*
- **Closure beside the score on park detail.** Tonight has it; detail shows it below the 30-night river (`ParkViews.swift:273-297`). The press kit's "closures beside the score" is false there. Rank alerts so a road closure leads and "gas pumps closed at night" folds into "All park alerts"; the gas-pump notice is currently the most prominent line in store screenshot 1. *(PC-2)*
- **Time river activation bug.** A VoiceOver double-tap, "Tap River" in Voice Control or a Switch Control tap probably selects the middle night, because the tap gesture (`TimeRiver.swift:96`) sits on the single accessibility element (`:105`). Give it an explicit default action. *(AX-03, verify on device)*
- **Red night mode for colour-blind eyes.** Under a protanopia simulation, red text falls to 4.30:1 and secondary text to 4.02:1. Field mode forces red and 12% brightness with no way out. Multiply by about (1, 0.36, 0.31) under Increase Contrast and as a "Brighter red" choice: 6.9:1 normally, 5.1:1 protan, still red. *(AX-02)*
- **Location purpose string** covers one of four uses (also: noticing you are at a park, the trip planner start, true north). *(C7)*
- **Store accessibility sentence** claims VoiceOver and larger text before the device pass. Gate it on the pass, like the Nutrition Labels. *(C11)*
- **Archives and dSYMs are in `/tmp`.** Move them to `~/Library/Developer/Xcode/Archives` now; a reboot loses the symbols for the build under review. *(E24)*

---

## The score, version 2

The score is the app's one claim, and the audit's strongest finding. It is worth getting right before anyone outside sees it.

**What the numbers show** (63 parks × 60 nights from today, `score-distribution.csv`):

- On clear nights the *night* (Moon and season) explains 96% of score variance and the *park* 4%. On average 16 parks tie for the best score; 35 of 63 parks are Bortle 2. The score answers "when" but barely answers "where".
- Beyond the forecast horizon, 38% of all park-nights display "Pristine" under a "Moon and darkness only" caption, while the expected score with each park's usual clouds has a median of 74 and only 5% Pristine. The numeral and the band word speak louder than the caption.
- Joshua Tree (Bortle 3) shows nine "Pristine" nights in sixteen in the store calendar frame. Reminders follow every one of them.

**Proposed model** (a departure from the brief's additive 40/25/20/15; log it in `DECISIONS.md`):

```
potential    = (moon + glow + length) / 75                         // what the sky could be, 0...1
transparency = (1 − cloud) × e^(−1.5 × AOD)                       // what the air lets through
score        = 100 × potential × transparency, capped by
               darkness length (existing), sky glow (S2), smoke band (S4)
```

The display stays one number with four reasons, and the breakdown sheet gains "If clear: 96". Simulated with ERA5 typical clouds, the bands spread from 177 Pristine / 1,684 Excellent to 366 Excellent / 915 Good / 1,593 Fair / 906 Poor. That is more honest and more useful. If the full model is too much before launch, the weakest-link cap `100 − 0.9 × cloud%` plus S2 and S4 is an afternoon's work and removes every false band.

**Also, in order of value:**

1. **Fade days 8–16 toward climatology.** Weight the forecast by lead time, `w = clamp((10 − lead)/7, 0, 1)`, and draw days 8–16 as half-filled "early look" dots. Model agreement is fetched for only 7 days; nothing lowers confidence after that. *(AS-4)*
2. **Show the clear window hour by hour.** Hourly clouds are already fetched but only averaged. A cloud ribbon on the sky arc and one line, "Best window: 11:40 PM–3:10 AM (clear, Moon down, core up)", answer the question every serious observer actually plans around. *(AS-5)* This is also the strongest new Interaction moment.
3. **Break ties with measured glow.** Black Marble already separates Great Basin (0.088) from Grand Canyon (2.31), 26× apart, both Bortle 2. Use it as the tie-breaker in ranking without changing the displayed number, then consider a continuous glow term. Set Saguaro to Bortle 5 (computed 5.1, next to Tucson) and settle the review queue. *(AS-3, AS-13)*
4. **Beyond the forecast, lead with the expected score** (usual clouds) or show the clear-sky figure as "If clear" with no band word. *(AS-8)*
5. **Model moonlight properly.** Krisciunas–Schaefer moonlight over the dark window, weighted by altitude, instead of a 0/1 horizon test. It also gives a naked-eye limiting magnitude for free. *(AS-10)*
6. **Forecast where people look up.** Forecast at the primary viewing spot; pass `elevation=`; at Haleakalā's summit (2,966 m, above the trade-wind inversion), score from mid and high cloud only, and say why. *(AS-9)*
7. **Smaller corrections:** Mercury at +2.1 in civil twilight is listed as visible, and Mars at +1.0 is called "faint" (AS-11). Meteor rates read as the trained-observer ceiling; show a range (AS-14). The bundled solar eclipse table is unused (AS-16). Moon tolerance in tests is ±15 min where the engine is good to about 1; tighten to 180 s and add property tests for monotonicity and band calibration (AS-15). "Allow about 15 minutes" undersells the engine; "within a few minutes of the U.S. Naval Observatory" is now supportable (AS-17).

---

## Launch plan

*(Full reasoning, calendar and sources in `awards-market.md`.)* The single rule from today to release: **does this change prevent a rejection, a crash or a false claim?** If not, it waits for 1.2. The P0 list above passes that test; new features do not.

| When | What |
|---|---|
| Oct 7–9 | Fix S1–S12 in build 8. Rewrite the website and press kit as "coming soon". File one **App Launch** featuring nomination (3-week minimum lead) for **Nov 6–8, the November new-moon weekend**. Open a public TestFlight link. Email Open-Meteo and NPS. Decide Spanish. |
| **Oct 9–11** (new moon Oct 10) | **Minimal device pass at a dark site:** cold launch, Tonight with location on and off, detail, field mode start/dim/restore, Live Activity, one real AlarmKit alarm, VoiceOver on gauge/river/calendar, night vision, widget, airplane mode, Watch. Anything that fails is switched off for 1.1, not fixed in a rush. |
| Oct 12–13 | Upload build 8, submit iPhone/iPad/Watch with manual release. Vision Pro as its own submission a week later if it threatens the date. Add `AppStore.requestReview(in:)` after a positive moment (first journal entry), never in field mode. |
| ~Oct 29 | Release. Webby (Accessibility & Inclusion) at $645 if live by Oct 30, otherwise $715 in December; don't rush for $70. |
| Nov 6–8 | Press weekend: 8–10 hand-picked journalists and "best stargazing apps" authors; one post each in one or two communities. **UX Design Awards** by Nov 15 (EUR 320; accepts apps not yet live). |
| Nov–Dec | Geminids In-App Event (Dec 12–15), "New Content" nomination by Nov 20. Ship 1.1.1 from real use. Publish a static **"Darkest weekends of 2027 in every national park"** page from the engine on GitHub Pages and pitch it. |
| Jan–Mar 2027 | 1.2 and 1.3 (below), one visible update a month. Recruit blind and low-vision testers through AppleVis. Red Dot early bird (~Jan 26). Pitch the January list refreshes. 40+ honest ratings by March 31. |
| ~May 18–20 | Design Award finalists. By then: six months live, 3–5 substantive updates, press, real testers, Vision Pro live. |

**Not targets:** App Store Awards 2026 (finalists ~Nov 18, three weeks after launch; under 5%). iF (EUR 500 now, ~EUR 3,700 if it wins), D&AD, Core77, Anthem and A' Design this cycle. **Aim at** App Store Awards 2027: Vision Pro App of the Year (an individual won in 2025) and Cultural Impact.

**Positioning:** don't lead with the Moon; Moonlitt owns that story and just won with it. Lead with **which park and which night across 63 parks, closures beside the score, and uncertainty drawn on screen**, then field mode. The score alone is no longer a differentiator: ClearNight, StarTrail and Gazer all launched or relaunched in 2026.

---

## What Nyx can be: the missing pieces, ranked

Ranked by award value per unit of effort, after launch. Each stays inside the fixed constraints: three hosts, no server, offline-first, Data Not Collected.

### 1.1.x and 1.2: close the loop (Interaction, Inclusivity)

1. **The loop after "decide".** *(PC-1, P1)*
   - The first save offers reminders, in context.
   - "Add to Calendar" on any chosen night, not only in the trip planner.
   - A visible "Copy coordinates" button.
   - At dawn in field mode, and the morning after, "Keep this night" opens a prefilled journal entry.
2. **"Follow this night".** *(PA-1, MP-01/02, E11, P1)*
   - iOS 26 can schedule a Live Activity to start at a set time, even in the background (`Activity.request(…start:)`). "Follow Friday at Joshua Tree" on Wednesday puts the countdown on the Lock Screen and wrist at dusk on Friday, with no app launch and no push server.
   - Pair it with a `BGAppRefreshTask` (`fetch` mode, the same three hosts) that refreshes saved parks, the widget and the watch context, and with a stale face that lists the remaining moments as clock times instead of naming a past one "next".
   - Add the Live Activity's `.small` family, so the Watch Smart Stack and CarPlay get a designed card.
   - This is the signature moment the roadmap promised, finished.
3. **First run that answers for *you*.** *(FR-1/2/3, P1)*
   - Ask "Where do you start from?" above the hero until answered. Never call a park-relative origin "nearby".
   - Bundle a public-domain Census places list (about 100 KB) so "Chicago, IL" works with location off. It also lets Ask Nyx start from a city.
   - When fewer than three parks are in reach, offer "Darker within 500 mi: Mammoth Cave, 88 tonight."
4. **Consolidate the "when" tools.** *(PC-3, DX-01)*
   - Rename Calendar to **Plan**, with *One park* and *My free nights* (the trip planner, now buried at the bottom of Tonight).
   - Detail goes from nine panels to six: Score and closure, River, Tonight's sky, Conditions, Spots and programs, Protect this sky.
   - Settings reachable from every tab.
5. **One vocabulary.** *(CP-2/3/8)*
   - **Moonlight, Clouds, Sky glow, True darkness**, everywhere, spoken and shown.
   - Replace 28 variants of "Moon and darkness only" with "No cloud forecast yet".
   - Use plural variations for every count; "3 nights at 1 national parks" already ships.
   - Cut the AI notification title, which is a model choosing between two fixed phrases. Notification copy becomes "Pristine night at Joshua Tree, Friday" with the reason in the body.
6. **Assistive Access, "One answer".** *(AX-07, P1 for Inclusivity)*
   - The `AssistiveAccess` scene is iOS 26.0 and almost no third-party app ships one.
   - Two buttons, Tonight and Saved parks. One park, one word, one Moon, "Dark from 8:40 PM".
7. **Accessibility finishing.**
   - Read `prefersActionSliderAlternative` (26.1) to show the river's stepper at default sizes; its targets are 10.8 pt wide.
   - Honour Show Borders on 25 plain buttons.
   - Stop the gauge shrinking its own labels with `scaleEffect`: "DARKNESS / 100" draws at 6.9 pt on onboarding.
   - Put the closure first in spoken park rows, with the rest in `accessibilityCustomContent`.
   - Add alt text to share cards (`ShareLink(message:)`).
   - No auto-dismiss on First light.
   - Use phonetic "Bortle" on iOS 26 (`accessibilitySpeechPhoneticNotation`, iOS 15), not only SSML on 27.
   - Run the audit at AX5, with Increase Contrast and with Bold Text.
   - *(AX-04/05/06/08/09/10/11, PA-4)*
8. **Translate what NPS writes.** In Spanish, closure text stays English. `translationPresentation` (iOS 17.4) is a user-initiated system sheet that runs on device. *(PA-3)*
9. **Journal you can keep.** *(E9, PA-8, PA-13)*
   - Export and import a local `.nyxjournal` package; it dies with the phone today.
   - Voice logging through the iOS 18 journal intent schema, so "add to my Nyx journal: Milky Way overhead" keeps eyes dark-adapted.
   - A "Describe this photo" field, with an on-device iOS 27 vision draft, availability-gated.

### 1.3: Liquid Glass, the wrist, the room (Visuals, Interaction, multi-platform)

10. **Let the Moon and the real sky lead.** *(DX-05, DX-06)*
    - A full-bleed Moon that morphs as the river scrubs.
    - "Tonight's sky over <park>" in colour, scrubbable with the river.
    - A Bortle 1→9 slider in the essay, re-rendering the same sky.
    - These become the store's first frames instead of a third gauge.
11. **Glass as interaction, not only background.** *(PA-6/7, DX-11)*
    - Take glass off the content cards.
    - Every glass use is a static background today. Moonlitt was cited for "best-in-class Liquid Glass integration".
    - The river's scrub position becomes an interactive glass lens.
    - The Tonight park pill morphs into the picker (`glassEffectID` in a `GlassEffectContainer`).
    - A `tabViewBottomAccessory` shows "Joshua Tree · darkness in 14 min ›" while a night is followed.
    - Solid fallbacks stay for night vision, Reduce Transparency and Increase Contrast.
12. **Apple Watch as a wrist instrument, not a port.** *(MP-03/04/07/08, AX-12)*
    - Digital Crown scrubs the week with detent haptics.
    - Double Tap starts the dark-adaptation ring.
    - A real 30-minute adaptation clock with a wrist tap at "eyes adapted".
    - Moon and "Next dark" complications that never go stale.
    - An "Automatic" palette that is red only after twilight, not at noon.
    - Compile the cloud climate into the watch so the week stops tying five nights at 96.
    - Show forecast age, and lift line limits at accessibility sizes.
13. **Vision Pro worth a category.** *(MP-10–13, PA-11)*
    - `preferredSurroundingsEffect(.ultraDark)`, so the room darkens under the sky.
    - Drag the dome to turn the night, rate-limited by the existing 20°/s comfort rule.
    - Name the 60 brightest stars and draw about 30 constellation figures, authored in-house rather than imported from GPL data.
    - A volumetric "Moon on your table", lit at today's true phase from the NASA map.
    - A recessed visionOS widget.
    - Hide the core label when moonlight has washed it out.
    - Owner decisions: clouds over the Vision sky (the existing Open-Meteo host), and SharePlay.
14. **iPad as an iPad.** *(MP-16/17)*
    - Open a park in a new window, with `@SceneStorage` per window.
    - Drag parks onto Calendar and Journal.
    - An inspector for the breakdown.
    - Use the empty space: Tonight's columns end at 75% height on a 13-inch screen, and field mode in landscape is one 680 pt column.
    - A landscape store set.
15. **Widgets with choices.** *(MP-18/19, PA-15/16)*
    - Pin a widget to a park.
    - A Moon widget that is never stale.
    - Lock Screen inline, "☾ 94 Joshua Tree".
    - Location relevance (`RelevantContext.location`) so the card rises when you are at the park.
    - A value control, "Tonight 93".
    - Pre-render seven nights of Moon images so the widget never falls back to the vector Moon.
    - Capture the real clear and tinted Home Screen looks on device.
16. **Handoff** between iPhone, iPad, Watch and Vision with one `NSUserActivity` carrying park and night, plus `appEntityIdentifier` so Siri knows the park on screen. This is the privacy-compatible stand-in for sync. *(MP-23, PA-14)*

### 1.4 and beyond: the case for Social Impact and Delight

17. **The night without a screen.** *(Accessibility award angle 1)*
    - A haptic-only rendering of the night, played on the watch and phone: intensity is darkness, a sharp tap is moonrise, a swell is the core rising.
    - A spatial-audio cue in AirPods, placed toward the core or a planet from `SkyCompass`.
    - It serves blind, low-vision and deafblind people, and everyone protecting dark adaptation. Judges can feel it in a demo.
18. **A map of tonight.** A Canvas map of the 63 parks coloured by tonight's score, from the US outline already bundled; MapKit stays out. It is the "where" answer in one picture, and the frame the App Preview needs. *(AM-10)*
19. **Where to stay.** Campgrounds from the NPS API (same host), with a Recreation.gov link out. It answers the next question after "where and when". *(AM-10)*
20. **From home tonight.** An offline Moon-and-darkness view for the device location, with no network and no privacy change, for people who cannot travel to a park: wheelchair users without transport, people who cannot drive, older users. Owner decision: it stretches the parks identity. *(Accessibility award angle 4, AM-10)*
21. **Missing science observers expect**, all offline. *(AS-12)*
    - An aurora season note for the eight Alaska parks, with a link out rather than a forecast.
    - Hours when satellites are sunlit.
    - Zodiacal light windows.
    - A limiting-magnitude estimate.
    - "The core rises into the glow of Las Vegas", from data already bundled.
22. **Learn with live figures.** *(LE-1)*
    - Four missing essays, in order: **Reading the Darkness Score**, **Safe in the dark**, **Your first Milky Way photo**, **What a forecast can't tell you**.
    - Give each essay one live figure from Nyx's own renderers and one deep link into the app.
23. **Share cards that travel.** A message with the image (alt text and the store link), a 9:16 story size, and one "why" line. *(SC-1)*
24. **Directions in Maps.** A user-initiated `maps://` hand-off from a viewing spot makes no request from Nyx's process, the same class as the Safari links already shipped. It reverses one `DECISIONS.md` line, so it needs the owner's call. *(PA-10, PC-1)*
25. **Mac, after 1.1.** Test "Designed for iPad" once field mode, alarms and the compass are hidden behind `isiOSAppOnMac`. Skip Catalyst and a native Mac target. *(MP-22)*

### What not to build

Unchanged from the roadmap, and confirmed again:

- AR camera overlays, a 3D globe or a full planetarium.
- Aurora and ISS forecasts (new hosts).
- Accounts, feeds, streaks.
- WeatherKit and in-app MapKit (Apple servers).
- Private Cloud Compute.
- App Clips and Universal Links (need a hosted domain).
- A Wallet pass.
- `Chart3D`, Image Playground, Visual Intelligence.

Each is rejected with a reason in `platform-apis.md`.

---

## Engineering before scale

*(Full detail in `engineering.md`.)*

| ID | Finding | Sev |
|---|---|---|
| E15 | **The real launch has never been measured.** The 2.2–3.8 s figure is a Debug run of a test-only mode that skips production work: 189 cache reads, star projection and an `ImageRenderer` moon icon before the first frame. The caches are then read a second time. Add signposts, measure Release on the oldest supported iPhone, and hydrate caches off the main actor. | P1 |
| E3 | **Open-Meteo per-IP limits.** One full refresh is about 265 weighted calls. Three fresh launches behind one campground Wi-Fi exceed 600/min. Refresh model, layer and air detail every 12 h, after the first park detail. | P1 |
| E21 | **No CI.** Use Xcode Cloud: build and test on iOS 26.x and 27, archive on tag, fail if the NPS key is empty. `test-26/27.json` still report 17 tests; there are 166. Turn warnings-as-errors off for Release builds and on for CI, so a hotfix isn't blocked by a new deprecation. | P1 |
| E23 | The repo lives in iCloud-synced `~/Documents` with Optimize Storage on. It has already dropped stray copies into compiled folders. Move it to `~/Developer`. | P1 |
| E16 | The gauge redraws at full display rate for as long as it is visible. `CADisableMinimumFrameDurationOnPhone` is missing, so the 120 Hz scrub the product brief promises isn't delivered on iPhone. | P2 |
| E17 | Field mode keeps the screen and sensors on all night with no thermal or Low Power guard. Re-enable auto-lock after about 10 minutes idle, since the Live Activity carries the night. | P2 |
| E13 | The watch drops any context whose version differs. Decode tolerantly before the first shape change. | P2 |
| E19 | "Sky + forecast → night" is assembled in seven places across targets. Make one constructor, and add a test that compares every surface. | P2 |
| E5/E6/E7 | Tonight doesn't refresh on return. Any 3xx (a captive portal) blocks forecasts for 15 min. Low Data Mode is ignored. | P2 |
| E18 | Three latent races: the ParkStore in-flight waiter, heavy planners on the main actor, and presenting into the key window on multi-window iPad. | P3 |

---

## Award scorecard

| Category | Today | What makes it a winner | Key items |
|---|---|---|---|
| **Interaction** (Moonlitt 2026) | Strong custom controls; the night's signature moment is unfinished, glass is static, and the park page is five screens long | Follow-this-night on Lock Screen, wrist and CarPlay; glass river lens; Crown scrub; hour-by-hour clear window; a four-tab IA with Plan | S1–S5, 2, 4, 11, 12, DX-01 |
| **Visuals and Graphics** (Tide Guide 2026) | Moon shader and real sky at award depth, but hidden as thumbnails and wallpaper | Moon and real sky as heroes, a Bortle slider, glass reserved for controls, iPad that uses its canvas, Vision volumetric Moon and named sky, store frames that lead with them | 10, 11, 13, 14, DX-19 |
| **Inclusivity** (Guitar Wiz 2026: Dynamic Type, Increased Contrast, Differentiate Without Color) | Far above compliant in code; zero real-world evidence | Device pass, 3–5 disabled testers, Assistive Access, red for colour-blind eyes, the night without a screen | AX-01, AX-02, 6, 7, 17 |
| **Innovation** | Honest uncertainty drawn on screen is genuinely new | A score that survives scrutiny, model agreement, the clear window, light domes against targets | Score v2 |
| **Social Impact** (Watch Duty 2025, Primary 2026) | An essay and sky-glow data | A partner (DarkSky chapter, a ranger program), published data stories, the from-home sky. Don't lead with this category. | 20, DX-06, AM-13 |
| **Delight and Fun** | First light, constellation, alternate icons | Fewer, sharper moments; one signature clip that opens every artifact | PC-3/4 |

**The pitch, and what it still lacks** *(product-copy.md)*: the paragraph is already strong ("one person made it"). To make it undeniable it needs:

- Evidence from the dark: real nights, real parks, a VoiceOver user's own words.
- A sourced problem: replace "millions" with an NPS figure and one real story.
- One signature clip.
- A "what we left out" paragraph.
- Public pages that agree with each other.
- A partner for impact.

---

## Design and UX

*(Added from the simulator review; full critique and every capture referenced in `design-ux.md`.)*

**Verdict.** The craft floor is high, and iOS 26.5 matches iOS 27 layout for layout. Onboarding page 1, field mode's "The night" and the calendar month would hold up next to Flighty or Gentler Streak.

The app no longer reads as one calm answer, though:

- Park detail is about five iPhone screens of a dozen similar indigo cards.
- Every tab spends its first 100–150 pt on an ornamental eyebrow and a serif title that repeats the nav title.
- The most beautiful assets are thumbnails or wallpaper: the textured, correctly tilted Moon (70 pt, five panels down) and the real sky (background only).
- The gauge, the most repeated asset, fills three of the first four store frames.

The award case now depends more on subtraction and staging than on any new feature.

**Strongest screens:** onboarding page 1 (`audit-2026-10-07/shots/27-coldlaunch-onboarding1.jpg`), field mode "The night" (`audit-2026-10-07/shots/27-field-night.jpg`), and the calendar month with its long-press peek (`audit-2026-10-07/shots/27-calendar-live.jpg`).
**Weakest:** park detail below the river, Ask Nyx (a rounded text field and semicolon-joined records), and Where to look at AX5 and in its store frame.

| ID | Finding | Sev | Effort |
|---|---|---|---|
| DX-03 | **"Park or state" search returns nothing for "utah".** Only state codes are searched (`Park.swift:38-43`), and multi-state rows print "CA,NV". This is a broken core flow on a P0 screen. | **P1, fix before submission** | S |
| DX-02 | **The field countdown "22:39" reads as a clock time** beside the "7:42 PM" times below it (`FieldView.swift:188`). Write "23 min" and keep `mm:ss` only for the last two minutes. | **P1, fix before submission** | S |
| DX-19 | **The first three store frames would not get Nyx featured.** Frame 1 leads with the gas-pump notice, frame 2 repeats the gauge, and frame 3 is a wall of text. Field frames show a white status bar and green battery over the red screen, an artifact of the DEBUG capture route; the real presenter hides it. The iPad set is uncaptioned and portrait, though the docs say landscape. There is no App Preview. Re-sequence as: real sky in colour, river mid-scrub with the Moon morphing, the Moon at size, field mode, calendar. | P1 | M |
| DX-01 | **The information architecture has outgrown "calm".** Five tabs. The trip planner is reachable only below Tonight's footnote. There are two overlapping year recaps, and Ask Nyx floats alone. Proposed:<br>• Four tabs, with **Plan** = month plus "I'm free…".<br>• Learn moves out of the tab bar.<br>• Park detail becomes three chapters: **Tonight / The sky / The place**.<br>• One Year card.<br>• Ask Nyx becomes "Explain this plan". | P1 | L |
| DX-05 | **The Moon deserves a hero moment.** A full-bleed Moon that morphs as the river scrubs, used as a store frame. | P1 | M |
| DX-06 | **The real sky deserves to be a view.** Add "Tonight's sky over <park>" in colour, scrubbable with the river; Vision Pro already does this. In the Bortle essay, add a 1→9 slider that re-renders the same sky. It is the most explanatory and shareable image the app could have, and it carries the Social Impact story. | P1 | M–L |
| DX-07 | Trivia in warning amber; NPS Title Case and "Come explore for yourself!" set in Nyx's own type without attribution. Use sentence case and label the source as "From the National Park Service". | P2 | S |
| DX-08 | **The calendar's new-moon ring contradicts the scores beside it** (it rings Oct 8–12 while Oct 13–15 score higher). Past nights use the hollow "no forecast" glyph. Ring the best stretch by rank while forecasts exist, and fall back to the moon window beyond them. | P2 | S |
| DX-09 | **Night vision is two taps deep, behind a sliders icon that reads as "filters".** Add a one-tap toggle on every root (or long-press the Tonight tab moon), and give Settings a gear icon. | P2 | S |
| DX-10 | **At AX5 the numeral shrinks from 108 to 82 pt, smaller than "DARKNESS / 100".** The compass header truncates to "Excell…", and the AX calendar list opens on past nights. | P2 | S |
| DX-11 | **Glass is on every content card,** where it's invisible and costs compositing. Settings and Privacy are stock grey forms, a second surface language. Make panels solid, keep glass for floating controls, and give Settings the night background. | P2 | S |
| DX-12 | **Viewing spots show raw coordinates and repeat the disclaimer under every spot.** The glow wording ("among the brightest national parks") contradicts a 94 Pristine score. | P2 | M |
| DX-13 | **The time river needs a legend paragraph,** and its model bars read as text cursors. Use a one-time TipKit tip and a soft spread glow instead. | P2 | S |
| DX-14 | **"Darkest tonight" is a five-way tie at 97, listed alphabetically.** Break ties visibly; see the score section. | P2 | S |
| DX-15 | **iPad.** The trip planner is one phone column. The sky arc flattens to a line at 670 pt wide. Tonight in portrait leaves a third of the screen empty. | P2 | M |
| DX-16 | **Ask Nyx looks like a debug console** next to a showcase API. Show records as Nyx's own rows and night cells, citations as tappable chips, and a glass input bar with suggested prompts. | P2 | M |
| DX-17 | The count-up is a linear ramp (steps of 2 every 12 ms), but the product brief says "nothing linear". Use an odometer-style decaying spring, with the arc leading the numeral. | P3 | S |
| DX-18 | Polish:<br>• "DARK HOURS" wraps on narrow phones.<br>• The compass "S" is clipped, and its reticle reads as the core marker.<br>• What's up leads with the Draconids at 2 an hour.<br>• Onboarding page 2 draws the weights like a perfect score, and page 3 ends on an invisible new moon.<br>• Parks sorts by Name by default.<br>• Ranger cards are unclamped.<br>• The trip planner lists consecutive nights at one park as separate rows. | P3 | S |

Motion (the count-up, river scrub and night-vision toggle) was judged from code only; frame-by-frame capture wasn't possible on this machine. 120 Hz smoothness needs the device pass.

---

## Questions for the owner

Only genuine decisions. Each has a recommendation; the evidence files hold the reasoning.

1. **Score model.** May clouds and smoke gate the score (a cap or multiplicative transparency), and sky glow cap the band, departing from the brief's additive 40/25/20/15? *Recommended: yes. It is the biggest credibility fix.*
2. **Beyond the forecast.** Should the big number be the expected score with usual clouds, or "If clear" with no band word? *Recommended: the expected score.*
3. **Top band.** Keep "Pristine" but reserve it for Bortle ≤2 skies, or rename it "Exceptional"? *Recommended: gate on Bortle ≤2 once S2 lands.*
4. **Launch scope.** Spanish only if a native reviewer signs off by Oct 13? Vision Pro in the first submission or a week later? Release when approved, or hold for Nov 6–8? *Recommended: English-only unless reviewed; Vision a week later if needed; release when approved.*
5. **Background refresh.** Approve one background mode (`fetch`) for saved-park forecasts on the existing hosts? *Recommended: yes. It makes reminders and the watch honest.*
6. **Hand-offs.** Allow a user-tapped "Directions in Maps" (`maps://`) from viewing spots? Allow on-device translation of NPS text (may download an Apple language pack)? *Recommended: yes to both, each noted in `PRIVACY.md`.*
7. **Places list.** Bundle a public-domain Census places file so people can start from their city? *Recommended: yes.*
8. **Information architecture.** Rename Calendar to Plan and fold the trip planner in? Cut the AI notification title? *Recommended: yes to both.*
9. **Field mode opt-outs.** Allow a brighter red and a higher brightness floor under Increase Contrast and larger text? *Recommended: yes.*
10. **Platforms.** May Vision Pro read clouds from the existing Open-Meteo host? SharePlay on Vision Pro (relaxes §11 and §13)? Watch default "Automatic" instead of always red? Mac after 1.1? *Recommended: clouds yes, SharePlay not yet, Automatic yes, Mac test after 1.2.*
11. **Legal and accounts.**
    - Counsel on Texas SB 2420.
    - EU trader status, or launch in the US, Canada and Mexico only.
    - Email Open-Meteo, NPS and the IMO now for written permission.
    - A USPTO search for NYX in classes 9 and 42.
    - *Recommended: all four before submitting; launch outside the EU until trader status is decided.*
12. **Paid awards.** *Recommended: Webby and the UX Design Awards now; Red Dot in January if reviews and press exist; skip iF this cycle.*
13. **Design calls.** Accept the four-tab IA (Plan = Calendar + trip planner; Learn out of the tab bar; park detail in three chapters)? Should the calendar ring mean "best stretch by score" while forecasts exist? Keep the NPS park description on detail? Which hero leads the product page: the real sky, the Moon, or the score? *Recommended: yes; yes; cut it or label it "From the National Park Service"; the real sky.*
14. **"From home tonight".** An offline Moon-and-darkness view for the device location, or stay strictly parks? *Recommended: build it in 1.4, after launch feedback.*

---

## Strengths to protect

- The astronomy:
  - Within 1 minute of USNO at every polar, tropical and island park checked.
  - Planets within 0.02° of JPL Horizons.
  - DST nights of 23 and 25 hours.
  - Explicit polar states, never NaN.
- Privacy enforced in code:
  - The `SafeHTTP` allowlist, refused redirects and per-host switches.
  - No network code in the Watch or Vision targets.
  - A release script that checks all of it.
- The voice: calm, short and honest, with uncertainty designed in (hollow nights, model ranges, "estimate").
- Accessibility architecture:
  - Every Canvas control speaks a data summary.
  - Audio Graphs, rotors and Voice Control labels.
  - Layouts that reflow at accessibility sizes.
  - Correctly guarded iOS 26.4 and 27 settings.
- Swift 6 with MainActor default isolation; no `try!`, no `fatalError`; `#if DEBUG` hygiene.
- Data provenance and attribution, and the restraint shown in the "what not to add" lists.
