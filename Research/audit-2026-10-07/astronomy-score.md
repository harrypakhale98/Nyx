## Astronomy and Darkness Score: findings

Auditor scope: AstronomyEngine, ScoreEngine, SkyAlmanac, WhatsUp, NightPlanner, TripPlanner, ForecastDetail, SkyGlow, CloudClimate, Forecast, and the bundled data. Method: I copied the engine sources unchanged into a scratch harness (compiled with `swiftc`, no Xcode project) and compared its output with the live USNO API (`aa.usno.navy.mil/api/rstt/oneday`) and JPL Horizons. I also ran all 63 parks × 60 nights (from 2026-10-07) through the score at 0, 50 and 100% cloud and at ERA5 typical cloud. Raw output is in `score-distribution.csv` beside this file.

### Verdict
The astronomy is excellent. Rise and set times match USNO to within 1 minute at Alaskan, Hawaiian, Samoan and Caribbean parks, and planet positions match JPL Horizons to within 0.02°. That holds up to professional scrutiny. **The Darkness Score does not.** It is additive, so the 25-point cloud term cannot pull a dark, moonless night below "Good". A **100% overcast night scores "Good" (60–73) on 55% of park-nights**, and an 80% overcast night can read "Excellent". Light pollution is just as weak: **Hot Springs (Bortle 5, inside a city) can score 90 "Pristine"** and the Gateway Arch can score 83 "Excellent". On clear nights, **96% of score variance comes from the night (Moon and season) and 4% from the park**, and on average 16 parks tie for best. So the score answers "when" but barely answers "where". This is the most important thing to fix before the award push. It is the app's core claim, and right now a Bortle 5 park on a moonless night, or a 50%-cloudy desert night, gets a reassuring band that a serious stargazer would immediately say is wrong.

### Findings

- **[AS-1] Overcast and mostly cloudy nights score Good or Excellent** — Severity: **P0**
  - Evidence: `Nyx/Services/ScoreEngine.swift:17-22`. The parts are added, cloud is worth at most 25, and there is no cap for cloud (compare `cap(darkHours:)` at :27). Harness over 3,780 park-nights:
    - **100% cloud:** 0 Pristine, 0 Excellent, **2,091 Good**, 886 Fair, 803 Poor. Median 62, max 73.
    - **80% cloud:** 1,057 park-nights (28%) score **Excellent** (75–78).
    - **50% cloud:** 1,910 (50%) Excellent, max 85.
    - Worked example: Death Valley, December new Moon, 100% cloud = 40 + 0 + 17.5 + 15 = **73 "Good"**.
    - With forecast at the spec's 90 threshold, a night is "Pristine" at up to 30% average cloud.
    - `CalendarView.swift:44` only draws a cloud glyph above 75%. Nothing else says "overcast".
  - Why it matters: Honesty is a fixed constraint (§17) and Social Impact / Inclusivity. "Good" on a fully overcast night is exactly how this app could cause the worst-case four-hour drive (§4). A judge or reviewer who checks one cloudy night will distrust every number.
  - Recommendation: Make transparency gate the score instead of adding to it. The simplest change that stays inside the spec's spirit is a weakest-link cap like the existing darkness cap, for example `cap = 100 − 0.9·cloud%`: 10% → 91, 20% → 82, 30% → 73, 50% → 55, 80% → 28. Simulated with ERA5 typical clouds, bands become 366 E / 915 G / 1,593 F / 906 Poor instead of 177 P / 1,684 E. That spread is more informative and more honest.
    - Better long-term: `score = darkness potential × transparency`, where potential = (moon + glow + length)/75 and transparency = (1 − cloud) · e^(−k·AOD) (see AS-6). Show "If clear: 96" as the secondary figure.
    - Log the departure from §5 weights in DECISIONS and pin it with tests: 100% cloud is never ≥ 40, 80% is never ≥ 60.
  - Effort: S (cap) / M (multiplicative model, copy, breakdown sheet, onboarding meters)

- **[AS-2] Light-polluted parks can be "Pristine" or "Excellent"** — Severity: **P0/P1**
  - Evidence: Bortle is worth 20·(9−B)/8, linear (`ScoreEngine.swift:19`). Harness maxima on clear moonless nights:

    | Park | Bortle | Max score | Band |
    |---|---|---|---|
    | Hot Springs (`hosp`) | 5; Black Marble glow 123× the park median | **90** | Pristine |
    | Saguaro | 4; computed 5.1 | 93 | Pristine |
    | Cuyahoga Valley | 6 | 88 | Excellent |
    | Indiana Dunes | 6 | 88 | Excellent |
    | Gateway Arch (`jeff`) | 8; glow 1500× | **83** | Excellent |

    - `NotificationScheduler.swift:80` would fire "A promising night at Hot Springs: 90/100, Pristine".
  - Why it matters: A Bortle 5 suburban sky cannot show a structured Milky Way. Calling it "Pristine" overstates the score, which §17 forbids. It is also the first thing an astronomer judge would test.
  - Recommendation: Cap by sky glow as the score already caps by darkness length, for example Bortle ≤3 → 100, 4 → 89, 5 → 74, 6 → 59, 7+ → 39. Simulated: Hot Springs max 74, Cuyahoga 59, Gateway Arch 39. Also make the glow term nonlinear (sky brightness is logarithmic).
  - Effort: S

- **[AS-3] The score barely answers "where"; dark parks tie** — Severity: P1
  - Evidence:
    - On clear nights, the night explains **96%** of score variance and the park **4%**. With ERA5 typical clouds: 87% / 12%.
    - On average **16 parks tie for the best score each clear night** (max 35).
    - Bortle is an integer: 35 of 63 parks are "2" and 20 are "3", so the 20-point term is effectively constant.
    - Black Marble already separates them: Great Basin glow 0.088 vs Grand Canyon 2.31, a 26× difference. Both are Bortle 2 and score identically.
    - The glow model is excluded from the score (DECISIONS "The score keeps the hand Bortle estimate").
  - Why it matters: Half of the app's one question ("**where** should I go") rests on a term that cannot rank the parks people actually choose between.
  - Recommendation: Use the continuous glow (or a fractional Bortle from it) as a tie-breaker in `NightPlanner.better` and the trip planner, without changing the displayed number. Then consider a continuous glow term in the score itself, with the review queue (Biscayne, Cuyahoga, Kobuk, Mammoth Cave, Saguaro) settled first.
  - Effort: S (tie-break) / M (score term)

- **[AS-4] Days 8–16 of the cloud forecast are treated as fully certain** — Severity: P1
  - Evidence: `Forecast.mean` (`Forecast.swift:10-13`) accepts any covered hour within 16 days at full weight. Model agreement is fetched for only 7 days (`DataServices.swift:249`). No code lowers confidence by lead time (grep for "lead" or "days ahead" finds nothing).
  - Effect: A single deterministic run 13 days out ("0% cloud") draws a solid dot and a "Pristine 97", and can schedule a 90+ notification (14-night window, `NotificationScheduler.swift:80`). Cloud forecast skill beyond about 7–10 days is close to climatology.
  - Why it matters: Honesty about uncertainty is a fixed constraint, and "which nights to take off work" is decided exactly at 8–16 days.
  - Recommendation:
    - Blend toward ERA5 climatology by lead time: weight w = clamp((10 − lead_days)/7, 0, 1), cloud_used = w·forecast + (1 − w)·typical.
    - Mark days 8–16 as "early look" (half-filled dot), and require lead ≤ 5 days before a score notification.
  - Effort: S–M

- **[AS-5] No hour-by-hour clouds: "when does it clear?" is invisible** — Severity: P1
  - Evidence: Clouds are fetched hourly but only the dark-window mean is ever shown (`ParkViews.swift:338,418`; no hourly view exists in `Nyx/Views` or `DesignSystem`). A night clear for 5 hours and overcast for 5 averages 50% and scores about 85 under the current formula.
  - Why it matters: Interaction and Visuals categories. Every serious stargazer plans around the clear window, and the sky arc and time river are the perfect place to show it.
  - Recommendation: Add a cloud ribbon along the sky arc, plus "Best window: 11:40 PM–3:10 AM (clear, Moon down, core up)" by intersecting hourly cloud < 30%, the moon-down interval and `CoreNight.dark`. All the data is already on device. Consider scoring the best contiguous 2–3 hours rather than the whole-window mean.
  - Effort: M

- **[AS-6] Smoke and haze never touch the score, even at very high aerosol** — Severity: P1
  - Evidence: `ForecastDetail.swift:157-182`. AOD ≥ 0.5 is "Heavy smoke or haze: faint stars hidden" but is only a caveat; the score is unchanged (DECISIONS:189).
  - Effect: A 0%-cloud night in AOD 1.0 wildfire smoke shows **97 "Pristine"** beside a line saying faint stars are hidden.
  - Physics: zenith extinction is 1.086·τ magnitudes, so τ = 1 dims stars by 1.1 mag at the zenith and about 2.2 mag at 30° altitude. Smoke also scatters artificial light, which raises sky glow.
  - Why it matters: Western parks in August and September (Milky Way core season) are exactly when this happens. Those are contradictory messages on one screen.
  - Recommendation: Multiply transparency by e^(−1.5·AOD), or simply cap the band (AOD ≥ 0.5 → at most Fair, 0.25–0.5 → at most Good). CAMS only reaches about 5 days, which is fine since it is near-term.
  - Effort: S

- **[AS-7] Eclipse "not visible" when only the partial phase is visible (bug)** — Severity: P1 (correctness)
  - Evidence: `SkyAlmanac.swift:338-351` picks the "stage worth seeing" (u2–u3 for a total eclipse) and computes `visible` only for that stage. If totality is below the horizon, `visible` is nil and `WhatsUp.swift:265-267` says "Not visible from this park: the Moon is below the horizon." Harness cases:
    - **Virgin Islands, 2026-03-03** (past): totality 07:04–08:02 AST, Moon sets 06:36. The partial phase is up from **05:50 to 06:36**, yet Nyx says "Not visible".
    - **Badlands, 2029-12-20**: Moon rises eclipsed at 16:13 MST; the partial phase is visible until 17:28. Nyx: "Not visible".
    - Same for Arches, Grand Canyon, Yellowstone and Big Bend on 2029-12-20.
    - `WhatsUpTests.eclipseSeenAndUnseen` covers only fully visible and fully hidden cases.
  - Why it matters: It states something false, and "the Moon rises already eclipsed" is one of the most photogenic events there is.
  - Recommendation: Fall back through stages (totality → umbral u1–u4 → penumbral). Say "Rises already in Earth's shadow; partial phase visible 4:13–5:28 PM". Add these two cases as tests.
  - Effort: S

- **[AS-8] Displayed scores beyond the forecast are "if clear" scores labelled with bands** — Severity: P2
  - Evidence: `cloudCover: nil` divides by 0.75 (`ScoreEngine.swift:21`), which on a dark night is within a point of a clear sky. In the harness, **38% of all park-nights display "Pristine"** without a forecast (median 83), while the climatology-expected score (`rankScore`) has a median of 74 and only 5% Pristine.
  - Also: if the cached forecast is older than 36 hours (`Forecast.swift:11`), an overcast night *rises* to its clear-sky estimate when the phone is offline.
  - Both are labelled "Moon and darkness only", but the numeral and band speak louder than the caption. Rank and display can also disagree visibly in the trip planner: Olympic shows 93 above Death Valley's 92 in display, but ranks 77 vs 90.
  - Recommendation: Beyond the forecast, lead with the expected score (climatology) or label the numeral "if clear" with no band word. Show "Last forecast: 80% cloud (2 days old)" rather than discarding stale data silently.
  - Effort: S–M

- **[AS-9] Forecast point is the park centroid, not where people look up; summits are penalised** — Severity: P2
  - Evidence: Requests use `park.latitude/longitude` (`DataServices.swift:141`).
    - **Haleakalā:** centroid at 1,926 m (Open-Meteo elevation API) vs the summit visitor centre at 2,966 m, 9 km away. ERA5 typical cloud for `hale` is 41–57% every month, with only 16–40% of nights "mostly clear". The summit is famous for sitting above the trade-wind inversion, so total cloud cover (which counts low cloud *below* the observer) is systematically pessimistic there.
    - **Denali:** centroid is 118 km from the park entrance.
  - Recommendation:
    - Forecast at the primary viewing spot where one exists.
    - Pass `elevation=` to Open-Meteo.
    - For sites above about 2,500 m (Haleakalā summit; Mauna Loa if added), score from mid and high cloud only, using the layers already fetched, and say why.
    - Rebuild climatology at the spot coordinate.
  - Effort: M

- **[AS-10] Moon term: altitude ignored, crescents slightly over-penalised** — Severity: P2
  - Evidence: The Moon term is 40·(1 − illum·fractionUp), using the Moon's illuminated fraction at 22:00 (`AstronomyEngine.swift:83`). A Moon at 2° counts as fully "up".
  - Krisciunas–Schaefer (1991) Moon brightness relative to full: 75% lit = 0.23, 50% = 0.09, 25% = 0.026. Expressed as sky-brightening in magnitudes over a 21.7 mag/arcsec² sky, that is roughly 60%, 38% and 17% of the full-Moon penalty. Nyx charges 75%, 50% and 25%. Linear illumination is a defensible log-space proxy, but a low Moon near the horizon (high airmass) is charged like a high one.
  - Recommendation: Integrate a K&S-style moonlight sky brightness over the dark window (phase-angle law × altitude/extinction factor) instead of a 0/1 horizon test. That also gives AS-12's limiting magnitude for free.
  - Effort: M

- **[AS-11] Planets listed when not realistically visible; Mars at +1.0 called "faint"** — Severity: P2/P3
  - Evidence: `SkyAlmanac.swift:102`: visible = Sun ≤ −6° and altitude ≥ 5°, regardless of magnitude.
    - Harness, American Samoa 2027-07-04: **Mercury, magnitude +2.1, best altitude 10.5°, Sun at −6.0°** is listed ("Rises 5:32 AM"). At +2.1 in civil twilight at 10° it is not visible to the naked eye.
    - `WhatsUp.brightness`: magnitude > 1 → "faint", so Mars at +1.04 (Joshua Tree, 2026-10-15) is called faint while it is as bright as Spica.
  - Positional accuracy is superb. JPL Horizons, 2026-10-15 06:00 UT:

    | Planet | Nyx RA / Dec | Horizons RA / Dec |
    |---|---|---|
    | Mercury | 223.289 / −19.769 | 223.288 / −19.770 |
    | Venus | 210.742 / −20.466 | 210.753 / −20.471 |
    | Jupiter | 144.567 / 14.780 | 144.566 / 14.782 |
    | Saturn | 10.666 / 1.644 | 10.683 / 1.649 |

    Magnitudes are 0.1–0.25 off (Venus −4.03 vs −4.28).
  - Recommendation: Use a twilight and extinction threshold. For example, require the Sun at or below −6° for magnitude below −3, −9° for magnitude below 0, and −12° otherwise. Require altitude ≥ 8°, and drop Mercury fainter than +1.5. Use "faint" only above about +1.5.
  - Effort: S

- **[AS-12] Missing science a serious observer expects (all offline, all within the constraints)** — Severity: P2
  - Evidence: grep finds none of these in `Nyx/` or the learn essays.
  - (a) **Aurora note for the 8 Alaska parks**, about Aug 20 to Apr 20. Aurora is the main reason to be there on a dark night, and it also brightens the sky. Use a static seasonal statement (no Kp; that would need a fourth host).
  - (b) **Satellite-lit hours.** A 550 km Starlink shell is sunlit overhead while the Sun is less than about 23° below the horizon (arccos(R/(R+h))). At 45°N in June the Sun only reaches −21.6°, so satellites cross all night. This is computable from existing solar math, and astrophotographers care about it.
  - (c) **Zodiacal light windows**: evening Feb–Apr and morning Sep–Nov, from the ecliptic's angle to the horizon at the end of twilight.
  - (d) **Estimated naked-eye limiting magnitude tonight** from Bortle (`SkyAlmanac.limitingMagnitude`), Moon, twilight and AOD. This is the figure observers actually use, worded as an estimate.
  - (e) **Light dome vs target**: warn when the core's azimuth at its peak falls within ±30° of the strongest dome, for example "The core rises into the glow of Las Vegas". Both pieces of data already exist (`SkyGlow.Dome`, `CoreNight.highestAzimuth`).
  - (f) A one-line airglow note in the Bortle essay. It cannot be predicted, so state it as context.
  - Effort: M in total. Each is S–M.

- **[AS-13] Bortle labels: two not conservative; calibration is circular** — Severity: P2
  - Evidence:
    - The computed Bortle is a least-squares fit *to the hand labels* (`Research/skyglow.md` method step 6), so the agreement is not independent validation (Spearman 0.47).
    - **Saguaro:** hand 4, computed 5.1. It sits beside Tucson, so 4 contradicts the spec's "conservative where unsure" (§4).
    - **Mammoth Cave:** hand 4, computed 2.9. It has been an International Dark Sky Park since 2021, so 4 is likely too pessimistic.
    - No park is rated 1, so the maximum score anywhere is 98.
  - Recommendation: Settle the review queue against independent measurements (NPS Night Skies Program all-sky photometry / SQM summaries from published park reports; unverified which are public per park). Set Saguaro to 5. Record a source per park in `parks.json`.
  - Effort: S–M

- **[AS-14] Meteor rates read optimistic for casual observers** — Severity: P3
  - Evidence: `SkyAlmanac.swift:245-255` uses HR = ZHR·sin h / r^(6.5−LM), with LM capped at 6.5 and no field-obstruction or perception factor.
    - Harness, Death Valley Geminids 2026: **"about 130 an hour"**; Denali: 120.
    - That is the trained-observer upper bound under ideal conditions. Casual groups typically see about half that.
    - Copy says "a rough guide", which is good.
  - Recommendation: Show a range ("60–130 an hour") or apply about 0.6 for a casual observer, and keep the footnote.
  - Effort: S

- **[AS-15] Test gaps and loose reference tolerances** — Severity: P2
  - Evidence:
    - `publishedRiseSet` allows **±15 min** for the Moon (`NyxTests.swift:327`), and `referenceRiseSetAndDarkness` allows ±5 min. Measured error is ≤3.7 min (Research/accuracy.md), and ≤1 min in my Alaska, Samoa, Hawaii and Virgin Islands checks below. A regression of 10 minutes would pass.
    - USNO fixtures cover only 3 parks at 34–39°N.
    - Missing tests:
      - score monotonicity (property test over cloud, illumination, Bortle and dark hours);
      - band calibration (overcast never ≥ Good; Bortle ≥5 never Pristine; once AS-1 and AS-2 land);
      - eclipse partial-phase visibility (AS-7);
      - planet magnitude visibility;
      - no-DST zones (Honolulu, Pago Pago, St Thomas; night window always 24 h);
      - forecast lead-time behaviour;
      - smoke caveat beside a high score.
  - Recommendation: Tighten the Moon tolerance to 180 s and the Sun to 60 s. Add the USNO cases below as fixtures (`NyxTests/usno-reference.json`). Add the property and calibration tests.
  - Effort: S

- **[AS-16] Solar eclipse table is bundled but unused** — Severity: P3
  - Evidence: `sky-events.json` has 5 `solarEclipses`, but `SkyEvents` decodes only showers and lunar eclipses (`SkyAlmanac.swift:433-439`; no Swift reference). Either use it (2029-01-14 partial over the northern US, 74%) or drop it from the bundle.
  - Effort: S

- **[AS-17] Accuracy copy undersells the engine** — Severity: P3
  - Evidence: About the data says Moon times are good to "allow about 15 minutes, and more near the poles". Measured error is ≤3.7 min at mid-latitudes and ≤1 min in Alaska (below). Honest, but a claim of "within a few minutes of the U.S. Naval Observatory" is now supportable.

### Numeric evidence: engine vs USNO (park-local times)

| Park, night | Event | Nyx | USNO |
|---|---|---|---|
| Denali 2026-10-15 | sunset / Moon | 18:45 / below all night | 18:46 / "continuously below" |
| Gates of the Arctic 2026-10-15 | sunset / Moon | 18:38 / below all night | 18:39 / "continuously below" |
| Kobuk Valley 2026-11-15 | moonrise / moonset | 16:37 / 21:04 | 16:38 / 21:05 |
| American Samoa 2026-10-15 | moonset / next moonrise | 23:03 / 10:26 | 23:04 / 10:27 |
| Haleakalā 2026-10-15 | moonset / next moonrise | 21:47 / 11:48 | 21:47 / 11:48 |
| Virgin Islands 2026-10-15 | moonset / next moonrise | 21:34 / 11:24 | 21:34 / 11:24 |
| Glacier Bay 2026-12-01 | moonset / next moonrise | 12:54 / 01:00 | 12:55 / 01:00 |
| Katmai 2026-10-20 | moonrise / next moonset | 17:44 / 03:05 | 17:44 / 03:06 |
| Wrangell–St. Elias 2027-01-20 | moonrise / next moonset | 12:37 / 09:41 | 12:37 / 09:42 |
| Denali 2027-03-20 | moonrise / next moonset | 18:24 / 07:38 | 18:24 / 07:39 |

- Polar and tropical cases behave correctly: Gates 2026-12-21 is `polarNight` with 13.3 h of true dark; Denali 2026-06-21 has 0 h with the score capped at 39; American Samoa has 9–10 h year-round.
- DST nights are 23 h and 25 h (Joshua Tree, Acadia), and Arizona stays at 24 h.

### Strengths worth protecting
- The solar, lunar, twilight and planet math is professional-grade. Keep the truncated Meeus and Schlyter code; it is correct and fast.
- Park-local noon-to-noon nights through DST, explicit polar states (never NaN), and the sunrise-after-noon handling for Kobuk are all right.
- Data provenance and attribution are exemplary: IMO 2026 with the archive caveat, NASA/Espenak eclipse contacts, Black Marble, ERA5 and CAMS credited CC BY 4.0 in About the data, Yale BSC via HEASARC (public).
- Restraint in copy: Mercury's brightness in words, "a rough guide", satellite glow labelled "not part of the score", model agreement shown in score units.

### Open questions for the owner
1. Are you willing to depart from the §5 additive weights so that clouds, and optionally smoke, act as a gate (cap or multiplicative transparency)? This is the single biggest credibility fix, and it changes the onboarding meters and the breakdown.
2. Should sky glow cap the band (no "Pristine" at Bortle 5+), and should Black Marble glow break ties among the 35 "Bortle 2" parks?
3. Beyond the forecast, should the hero numeral be the expected score (with typical clouds), or a clear-sky "if clear" figure with no band word?
4. Should days 8–16 be blended toward climatology and kept out of notifications?
