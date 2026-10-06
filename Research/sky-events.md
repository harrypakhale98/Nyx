# sky-events.json: sources, method, caveats

Retrieved 2026-10-05. Output: `Nyx/Resources/sky-events.json` (13 meteor showers, 17 lunar eclipses 2026-2032, 5 solar eclipses 2026-2032). Everything is reference data only. The app computes visibility itself.

## 1. Meteor showers

**Primary source.** International Meteor Organization, *2026 Meteor Shower Calendar* (IMO INFO 3-25, ed. J. Rendtel), https://www.imo.net/files/meteor-shower/cal2026.pdf. Table 5 (Working List of Visual Meteor Showers) supplies activity dates, peak lambda-sun (J2000), radiant RA/Dec at peak, V-infinity, population index r and ZHR. The shower sections supply stated peak times and ZHR ranges. The 2025 edition (cal2025.pdf) was used only for text the 2026 edition dropped (ETA, SDA, CAP, URS, QUA descriptions).

**Access caveat.** On 2026-10-05 the live imo.net is a "we're rebuilding" placeholder: every PDF URL returns that HTML page, including the linked 2027 calendar (`ShCal27s.pdf`). The 2026 and 2025 PDFs were read from the Internet Archive copies (`web.archive.org/web/<2026 date>id_/https://www.imo.net/files/meteor-shower/cal2026.pdf`), text-extracted with PDFKit.

**Radiant drift.** The IMO calendar gives drift only graphically/as Table 6 (positions every 5 days, whole degrees). `driftRA` and `driftDec` (deg/day) were fitted from the Table 6 rows bracketing each peak, so expect about +/-0.1 deg/day. DRA drift is "negligible" per IMO (set to 0). URS rests on two table points (Dec 20 and 25) and is low confidence. The radiant at peak in the JSON is the Table 5 value (whole degrees).

**Peak times.**
- `peakSolarLongitude` is the IMO lambda-sun, equinox J2000. Precision varies: 0.01 deg for QUA/LYR/LEO, 0.1 deg for ETA/PER/DRA/GEM/URS, and only 1 deg for SDA, CAP, ORI, STA, NTA (see `peakSolarLongitudePrecisionDeg`). One degree is about 24 h of Sun motion, so for those five the computed instant is indicative to +/-12 h.
- `peaksComputed` (2026-2028) is my solar-longitude solve: Meeus ch. 25 apparent longitude minus general precession since J2000, root-found at each year. Check against the six times IMO states for 2026: QUA 21:18 vs "close to 21h", LYR 19:35 vs 19:40, PER 02:05 vs "02h to 04h", DRA 01:19 vs "01h", LEO 23:50 vs 23:45, GEM 13:46 vs 14h, URS 22:12 vs 22h. The app should use its own solar longitude, which should agree to the same 0-20 minutes.
- `peaks` is what IMO published. 2026 is read from the PDF. Showers with only a date in the calendar carry a date-only string (no time). Perseids are given as a window (02-04h UT, midpoint stored; full note in `peakNotes`).
- **2027:** the IMO 2027 PDF could not be retrieved. `peaks["2027"]` holds only values reported from search-index excerpts of that PDF (QUA 2027-01-04 03:25 UT, PER 2027-08-13 08-10h UT, GEM 2027-12-14 ~20h UT, and dates for LYR/DRA/LEO/URS with the same lambda-sun as 2026), and every one agrees with my computed value within 1 h (Geminids 19:53 computed vs ~20h; Perseids 08:12 vs 08-10h). Treat as unverified until the PDF is read directly. **2028:** not yet published (IMO issues each year's calendar in the preceding autumn); only computed values exist.
- Quadrantids: sharp. IMO quotes about 4 h width (radio data sometimes wider) and says video peaks in 2020-22 ran a few hours early while 2023-24 were on time. Plan for the computed instant +/- a few hours; the visual window is the nighttime hours around it. Geminids are broad (ZHR 100+ for about 10-12 h).

**Parent bodies.** From the IMO text where it names them: LYR C/1861 G1 Thatcher, ETA and ORI 1P/Halley, PER 109P/Swift-Tuttle, DRA 21P/Giacobini-Zinner, STA and NTA 2P/Encke, LEO 55P/Tempel-Tuttle, URS 8P/Tuttle. From standard literature (IAU MDC, not stated in the IMO calendar): QUA 2003 EH1, SDA 96P/Machholz (association uncertain), CAP 169P/NEAT, GEM 3200 Phaethon. Flagged in `parentSource`.

**ZHR / variable.** ZHR is the IMO Table 5 value ("based on recent observed returns"). `variable` is true where the IMO text gives a range or known outbursts: QUA (60-200), LYR (up to 90), ETA (40-85), DRA, ORI (14-70 across years), LEO (storms only near parent perihelion, next 2031), URS (up to 50). Perseid note: IMO says the 2026 background is expected below the nominal 100 until 2027.

## 2. Lunar eclipses 2026-2032

**Source.** NASA/GSFC (F. Espenak) decade tables, https://eclipse.gsfc.nasa.gov/LEdecade/LEdecade2021.html and LEdecade2031.html, plus each eclipse's figure PDF (`.../LEplot/LEplot2001/LE<yyyy><Mon><dd><T|P|N>.pdf`), which carries the UT contact table (P1, U1, U2, U3, U4, P4), greatest-eclipse UT, magnitudes and gamma. The PDFs are raster images, so the numbers were read from the rendered figures and cross-checked against the TD-of-greatest and umbral magnitude in the decade table (all 17 match).

**Notes.**
- NASA figures assume DeltaT of 75-79 s (older prediction). The current value is about 69 s, so true UT contacts are roughly 6-10 s later than listed. Irrelevant for altitude checks.
- `null` means that contact does not occur (partial eclipses have no U2/U3; penumbral have no U1-U4).
- Contacts after midnight roll the date over (2027-02-20 P4, 2029-12-20 U4/P4, 2030-12-09 P4 are on the next UT day). `date` is the UT date of greatest eclipse.
- Penumbral events (7 of 17) carry `penumbralOnly` and `barelyVisible`. By penumbral magnitude: 2027-07-18 is 0.0014 (not detectable), 2031-06-05 is 0.13, 2027-08-17 is 0.55, 2031-10-30 is 0.72, 2031-05-07 is 0.88, 2027-02-20 is 0.93, 2030-12-09 is 0.94. Shading is generally noticeable only above about 0.7.
- Very shallow partials: 2028-01-12 (umbral 0.066) is flagged in `note`.
- Visibility from a park is left to the app (Moon altitude at the listed instants). `region` is NASA's broad visibility summary only.

## 3. Solar eclipses 2026-2032

**Source.** NASA/GSFC decade tables https://eclipse.gsfc.nasa.gov/SEdecade/SEdecade2021.html and SEdecade2031.html (16 eclipses in the range), plus Besselian elements pages `.../SEbeselm/SEbeselm2001/SE<date>beselm.html`.

**Method.** NASA does not publish "30% of the Sun covered somewhere in the US", so I computed it: Besselian-element local circumstances (Espenak/Meeus) scanned over a coarse grid of the 50 states, Puerto Rico, USVI and American Samoa, then over about 100 named US places (state extremes and cities) for the candidates. Obscuration is circle-overlap area; only times with the geometric Sun above the horizon count. Validation: the 2024-04-08 eclipse reproduces published obscuration at Boston (92.5%), New York (89.9%) and Chicago (93.8%). Eleven of the 16 eclipses never reach a US area; 2029-06-12 peaks near 19% in Alaska and is excluded.

**Included (5).**

| Date | Type | US area | Approx. max obscuration |
|---|---|---|---|
| 2026-08-12 | total (Greenland/Iceland/Spain) | northern Alaska, Sun low | 57% |
| 2028-01-26 | annular (S. America/Iberia) | Puerto Rico, USVI | 35% |
| 2029-01-14 | partial | northern contiguous US | 74% |
| 2030-06-01 | annular (Europe/Asia) | western Aleutians, near sunrise | 48%, marginal |
| 2031-11-14 | hybrid (Pacific) | Hawaii | about 60% |

2030-06-01 is marked `marginal` (Sun 0-7 degrees up). The 2026-08-12 eclipse reaches only about 29% in northern Maine. South Florida sees 30-40% on 2031-11-14 only at sunset. No US central path exists in 2026-2032 (the next total eclipse in the US, 2033-03-30 over Alaska, is outside the range).

## Disagreements and judgment calls

- Where IMO and secondary calendars (AMS, timeanddate-type sites) differ, IMO values were used. The only gap is that IMO 2027 could not be read directly (above).
- IMO 2025 gave QUA "Jan 3, 15h UT" and ETA "May 6, 03h UT"; the 2026 edition gives QUA "close to 21h" and no ETA time. These shift with the leap-year cycle (same lambda-sun, different year). Not a conflict.
- "At least 30% partial phase" was read as 30% of the Sun's disk area covered (obscuration). Read as eclipse magnitude 0.30 instead (looser, since obscuration is smaller than magnitude for partials), the only addition is 2029-06-12: magnitude about 0.30 at Barter Island, Alaska (19% obscuration, Sun about 16 degrees up). It is excluded; add it if you prefer the looser rule.
