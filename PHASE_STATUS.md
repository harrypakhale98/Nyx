# Nyx handoff — 2026-10-04 (fresh audit, build 4)

A fresh four-part audit (astronomy math against PyEphem, services and concurrency, UI and accessibility, configuration and release). All confirmed findings are fixed and logged under "Fresh audit" in `DECISIONS.md`. Highlights: Alaska moonrise/moonset accuracy (was up to 41 minutes off), Milky Way guidance at high latitude, a privacy-preserving all-park forecast request, careful use of the shared NPS key, offline data moved out of Caches, reminder calendar and race fixes, and a set of night-vision, VoiceOver and time-river corrections.

**Verified 2026-10-04 on one dedicated simulator (iPhone 17 Pro, iOS 27.0):** zero warnings; 35 Swift Testing tests pass (7 new: PyEphem reference times, pinned formula, Milky Way latitude, polar sunrise, NPS throttling, all-park forecasts, reminder race); both UI tests and the night-vision accessibility audit (17 screens) pass; the standard-palette audit passes on all 17 screens across two runs (a heavily loaded host made one run's audit time out mid-way; every issue it logged is a documented exclusion). Touched screens were captured and reviewed (detail standard and polar, river selection, calendar, Tonight). Not re-run on iOS 26.5 this time (one simulator, at the owner's request); none of the changes touch iOS 26-specific code paths.

**Next starting point:** upload build 1.0 (4), push to publish the privacy page, optionally request a higher NPS limit (INPUT_NEEDED 3–5), then the on-device night review (INPUT_NEEDED 1).

---

# Nyx handoff — 2026-10-03 (depth and realism, build 3)

Every item in `Research/depth-and-realism-audit.md` is implemented, at the owner's request, before the first release:

- **Icon:** the Dial (score arc and leading star around a sphere-shaded, earthlit crescent), three depth groups. Earlier concepts in `IconSources/Concepts/`.
- **Moon:** a Metal shader lights NASA's lunar map on a sphere (Lommel–Seeliger), tilted as seen from the park at the Moon's highest point that night, with libration and earthshine. Test: the bright limb points at the Sun's real bearing within 3° in six parks. Share cards use it; widgets get pre-rendered pictures from the app.
- **Sky:** 904 Yale Bright Star Catalogue stars in their true colours, projected for each park and night, with the Milky Way along the galactic plane, on three tilt-parallax layers. Test: the galactic core sits low in the south on a July night at Joshua Tree.
- **Instrument and glass:** the gauge has an open-arc Liquid Glass rim, inner shadow and a tilt glint; cards are tinted Liquid Glass; hero gauges float on scroll; the sky arc has a per-park ridge. Solid fallbacks under Reduce Transparency, Increase Contrast and night vision; motion off under Reduce Motion and Low Power Mode.
- Build number **3** (`project.yml`). Builds 1 and 2 in App Store Connect predate this work.

**Verified 2026-10-03:** zero warnings; on iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5, all 28 Swift Testing tests, both accessibility audits (17 screens × standard and night vision) and both UI tests pass. Store screenshots recaptured (live data, no alpha).

---

# Earlier handoff — 2026-10-03 (award polish)

## Award polish

Two independent audits (astronomy/score, app flows) and a screen-by-screen visual critique. Everything found is fixed and logged under "Award polish" in `DECISIONS.md`. Highlights:

- **Correctness:** reminders no longer return after being tapped or cleared; "tonight" turns over at sunrise, not noon; eastern parks keep tonight's clouds (`past_days=1`); a few minutes of darkness can no longer score Excellent; fresh closures survive a failing NPS events call; the five-night window crosses month boundaries; Ask Nyx shares Tonight's location; denied location links to Settings; the reminder switch reflects iPhone Settings; safe journal deletion.
- **Product:** one Open-Meteo request now covers all 63 parks, so the Parks tab shows forecast-backed scores everywhere, with a "Darkest tonight" sort. Tonight leads with the answer.
- **Visuals:** vector moon disc (limb darkening, soft terminator, maria, glow); gauge with glowing arc, leading star and visible orbit; sky arc rebuilt with altitude-true twilight colour, moonlit-hours wash, true-darkness bracket, hour labels and Now marker; medium widget gains a seven-night strip, moon phase and a seeded sky; journal cards show a photo.
- Build number is now **2** (`project.yml`). Build 1 in App Store Connect predates these fixes.

**Verified 2026-10-03 (final):** app, widget and tests build with zero warnings; on iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5, all 24 Swift Testing tests, both accessibility audits (17 screens × standard and night vision) and both UI tests pass. Three independent code audits and one self-review were run; every confirmed finding is fixed and logged in `DECISIONS.md`. Touched screens were captured and reviewed, including night vision, AX5 and polar states; river scrubbing and park links over an open sheet were exercised in the simulator. Store screenshots recaptured with live data and flattened (no alpha).

**Known limits:** Ask Nyx's source records are English data, not catalog strings. Hardware haptics, real widgets, Siri, VoiceOver by ear and dark-adapted readability still need the on-device night review.

**Next starting point:** upload build 1.0 (2) (INPUT_NEEDED 2), then the on-device night review (INPUT_NEEDED 1).

---

# Earlier handoff — 2026-10-02 (completion review)

## Completion review (after the first build)

A full code, design and accessibility review of the first build found and fixed the issues listed under "Completion review" in `DECISIONS.md`. The most important:

- **Live park alerts and ranger programs could never load**: the NPS key was dropped from Info.plist. Fixed via `Config/Nyx.xcconfig` + git-ignored `Config/Secrets.xcconfig`; only the key itself is still needed (INPUT_NEEDED 3).
- **"Tonight" after midnight showed the next night** in the app, widget and Siri. Fixed (`Park.currentNight(at:)`).
- **Reminders for tonight were never sent**; tapping a reminder did nothing. Fixed, with a delivered-once guarantee.
- **Share cards exported with invisible text.** Fixed.
- **Signature motion and interaction** finished to the spec: rebuilt time river under the gauge, calendar peek and directional months, self-drawing constellation loader, score-reactive starfield and gauge orbit, onboarding that builds the score, cold-launch reveal.
- **App icon** is now a native Icon Composer document (`Nyx/Resources/AppIcon.icon`).
- **Viewing spots** researched from NPS pages for the parks that had none (see `Research/viewing-spots.json` for sources and evidence).

Verified: app + tests build with zero warnings (warnings are errors) on iOS 26.5 (iPhone 17 Pro) and iOS 27.0 (iPhone 18 Pro); unit and UI suites pass on both. Screens touched were re-captured and reviewed, including night vision and AX5.

### Release completion — 2026-10-03

- **Accessibility:** Apple's automated audit (`AccessibilityAuditTests`) passes on all 17 screens in both palettes after fixes; exclusions are documented in the test.
- **Live NPS data verified:** the owner's key lives in git-ignored `Config/Secrets.xcconfig`; real Joshua Tree alerts loaded in the app. Closure detection now also catches closures NPS files under "Caution" or "Danger".
- **Privacy label decided:** Data Not Collected (`PRIVACY.md`). Public privacy, support and landing pages are in `docs/` for GitHub Pages, contact harry.pakhale98@gmail.com.
- **App Store assets current:** screenshots recaptured (`Store/Screenshots`, 1320×2868); String Catalog synced (331 keys).
- **Owner steps left:** see `INPUT_NEEDED.md` — make the repo public and turn on Pages, try it on an iPhone, then create the App Store Connect record and upload.

---

## Engineering checkpoint: Phases 0–7 implemented

The source app and widget extension are complete for release review. The integrated feature checkpoint is `5b94bfe`; audit commit `778b3fb` contains final repairs, test evidence, screenshot artwork and submission documentation. This is not yet authorization to submit: the publisher and physical-device gates below remain open.

Implemented: all 63 national parks; offline astronomy and Darkness Score; native five-tab navigation; celestial gauge, moon, sky arc, calendar and time river; manual/location-based Tonight planning; saved parks and local reminders; SwiftData journal with selected photos; onboarding; privacy/data/settings; three Learn essays; share cards; widgets and Control Center control; App Intents/Spotlight; availability-gated on-device Foundation Models. XcodeGen remains the project source of truth. There are no third-party runtime dependencies or remote AI calls.

## Final verification

| Gate | Evidence |
|---|---|
| iPhone 17 Pro / iOS 26.5 | 15 Swift Testing + 2 native UI tests pass; zero failures and build/analyzer warnings |
| iPhone 18 Pro / iOS 27.0 | Same 17 tests pass; zero failures and build/analyzer warnings |
| Release | Development-signed archive succeeds; signatures validate; app and widget contain the correct App Group and privacy manifests; iPhone portrait only |
| Astronomy | 27 solar/civil-twilight samples: max 0.47 min error; 18 lunar rise/set samples: max 3.72 min; explicit polar/tropical/DST tests. Astronomical twilight has no separate independent published fixture |
| Visual review | 182 QA captures across both runtimes; actual Simulator AX5 and Increase Contrast; loading, empty, error, offline, unknown clouds, polar, red and reduced-motion review states |
| Store artwork | Six visually reviewed native 1320×2868 drafts; illustrative journal and real computed scores with uncertainty retained |
| Performance | Native launch means 2.179 s / 3.756 s in the documented Debug review scenario; 15.794 s active-animation profiler reports zero >250 ms hangs; allocations recording retained locally. These do not establish hardware frame rates or absence of leaks |
| Privacy | Exact two-host transport allowlist and independent network toggles verified. Provider retention / App Store label remains unresolved |

See `AUDIT.md`, `Research/accuracy.md`, `Research/performance.md`, `Research/test-26.json`, `Research/test-27.json`, and `Research/release-verification.json` for measured limits. The final development archive is `/tmp/NyxSigned.xcarchive`; rebuild/export instructions are in README and SUBMISSION. Raw Instruments traces are local and Git-ignored.

The final critique repaired access guidance placement, red native-control contrast, park-local journal/program dates, reminder preference races, malformed forecast coverage, AX5 gauge/arc/river/calendar layouts, widget text fitting and settled screenshot timing. These choices are recorded in `DECISIONS.md`.

## Deliberate limitations and release gates

- Current privacy label is a draft. Open-Meteo's published API-log retention and NPS/API.gov processing need authoritative publisher review; do not claim “Data Not Collected” until resolved. See `PRIVACY.md`.
- No NPS key is committed. Core planning works without it; live closures/programs show an honest unchecked state. Add one in `Config/Secrets.xcconfig` (INPUT_NEEDED 3); it is strongly recommended for release because closures are the app's most important safety signal.
- Named viewing spots (50 of 63 parks) appear only where nps.gov pages support them; see `Research/viewing-spots.json`. The other 13 parks give ranger guidance instead of invented coordinates. Bortle values remain clearly labeled estimates.
- VoiceOver interaction, actual system Reduce Motion/Transparency/Bold Text/Smart Invert, PhotosPicker/system permissions, actual widget/control/Siri integration, available-model behavior, hardware haptics/performance and dark-field usability require physical review. Screenshot overrides and widget content previews do not certify these gates.
- The Release archive uses development signing. App Store distribution export, hosted privacy/support pages, account metadata, TestFlight and final submission require the owner.

## Exact next starting point

Start with **item 1 in INPUT_NEEDED.md** (repo public + GitHub Pages), then the on-device review and App Store Connect steps. Do not add features before those release gates close. If review finds a defect, fix it, rerun both simulator suites, recapture affected states, archive again and update this handoff before submission.
