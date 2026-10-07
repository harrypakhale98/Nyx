# Depth and realism audit

*Nyx · October 3, 2026 · **Status: all items implemented in build 3** (see `DECISIONS.md`, "Depth and realism") · scope: the icon, the app's drawn objects, and everything that could gain depth or physical realism*

## Verdict

Nyx's layouts are not the problem. Its **objects** are flat: the moon is a shaded disc, the stars are same-coloured dots on one plane, the score dial is line art, and the cards are flat indigo panels. The award-level move is not "make everything 3D". It is to make the handful of real things physically real (the Moon, the sky, the instrument) and let iOS 26's glass supply depth for the interface around them. Every idea below keeps Nyx readable with night-adapted eyes, works in night vision, honours Reduce Motion and Reduce Transparency, stays offline, and adds no third-party code.

## What exists today

| Object | Today | Depth today |
|---|---|---|
| Moon (`MoonDisc`) | Vector crescent, limb darkening, soft terminator, 9 soft maria blobs, glow | Low: reads as a disc, maria are invented shapes |
| Starfield (`Starfield`) | 88 seeded dots, one colour, one plane, gentle twinkle | None |
| Score dial (`CelestialGauge`) | Arc, ticks, glow, leading star, orbiting particles | Low: line art |
| Sky arc (`SkyArc`) | Altitude-true twilight colours, paths, moon disc, horizon | Medium |
| Cards (`Panel`) | Flat indigo rounded rectangles, hairline border | None |
| Time river, calendar cells | Canvas line art | None (appropriate for charts) |
| App icon | Liquid Glass layers: flat crescent, flat disc, thin orbit | Medium: system glass only |

## Verified building blocks

Checked against the installed iOS 27.0 SDK (minimum target stays iOS 26.0):

- **SwiftUI Metal shaders**: `colorEffect`, `layerEffect`, `distortionEffect`, `ShaderLibrary`, and `Shader.Argument.image(_:)` all exist in SwiftUICore. A per-pixel shader can sample a bundled texture, so a lit 3D sphere needs no 3D engine. iOS 17+, so fully inside iOS 26.
- **Liquid Glass**: `glassEffect(_:in:)` with `Glass.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`; `GlassEffectTransition`. iOS 26+.
- **RealityKit `RealityView`**: available on iOS 18+. Real 3D scenes if ever needed; heavier than a shader.
- **SceneKit**: still present, and none of the view or node headers are marked deprecated. Apple has steered new work to RealityKit, so it isn't recommended for new work.
- **CoreMotion device motion**: present. Raw attitude is not expected to trigger the Motion & Fitness prompt (that covers activity and pedometer data); confirm on device. It stays on-device, collects nothing, and is off under Reduce Motion.

Data sources (free, offline once bundled):

- **Moon texture: NASA SVS CGI Moon Kit**, from the LRO wide-angle camera colour mosaic. Credit requested: "NASA's Scientific Visualization Studio". No commercial restriction is stated; NASA media guidelines apply (no NASA logo, no implied endorsement). The 2K map downsampled to 1024×512 JPEG is about 150 KB. A displacement map is also available for relief shading.
- **Stars: Yale Bright Star Catalogue (BSC5, 9,110 stars)**, a NASA/HEASARC-distributed government dataset. A cut at magnitude 4.5 is about 900 stars and ~30 KB of JSON. **Avoid the HYG database**: it is CC BY-SA 4.0, and share-alike is awkward inside an App Store binary. *Confirm BSC5's public-domain status at HEASARC before shipping; the fallback is ESA's Hipparcos catalogue with acknowledgement.*
- **Milky Way**: computed, not imaged. The galactic plane is a fixed great circle (north galactic pole RA 192.86°, Dec +27.13°), so the band can be placed exactly with no photo and no licence. Avoid Gaia all-sky images (CC BY-SA IGO).

Spec impact: the product brief allows "one bundled JSON dataset". A star list and a moon texture are free, offline data, but they are new bundled assets. That is a deliberate departure under Section 17, to be logged in `DECISIONS.md`.

## Findings and recommendations

Ranked by value to the app and to an Apple Design Award case (Visuals and Graphics, Interaction, Inclusivity). Effort: S under a day, M one to two days, L several days.

### 1. A physically lit Moon — highest value · M · low risk

**Gap.** The moon is the app's emblem and appears on six surfaces (Tonight header, time river, detail, calendar peek, onboarding, tab icon). It looks like a drawing.

**Implement.**
- A `colorEffect` Metal shader draws a sphere per pixel: surface normal from disc coordinates; Sun direction from the real phase angle; lunar-style reflectance (Lommel–Seeliger, so the full moon looks flat-bright as it really does, not like a shiny ball); the bundled NASA albedo map sampled by latitude and longitude; optional relief from the displacement map near the terminator, where craters cast long shadows.
- **True tilt for the park and hour (signature detail).** Rotate the lit limb by the bright-limb position angle minus the parallactic angle: a crescent over Florida in spring lies on its back, the same crescent from Alaska stands upright. `AstronomyEngine` already computes the Moon's and Sun's right ascension and declination inside `lunarAltitude` and `solarAltitude`, so this means exposing them plus two standard formulas (Meeus ch. 14 and 48). Honest, computed, and almost no consumer app does it.
- **Earthshine** on the dark side, scaled by Earth's phase as seen from the Moon (about 1 − lunar illumination): bright near new moon, gone near full.
- The southern hemisphere rotates for free with the tilt; the current `southern` flag becomes a special case.
- Keep the vector `MoonDisc` as the fallback for the tab icon (template image), widgets and the share card until the shader is verified there. `ImageRenderer` and widget hosts may not run SwiftUI shaders. **Verify before switching.**

**Guardrails.** Night vision converts the shader output to the red ramp. `accessibilityIgnoresInvertColors` stays. The VoiceOver label gains the orientation ("lit from the lower right"). The pixel cost of a 300 pt disc at 3× is about 0.8 M pixels: trivial on an iPhone 12. Add the NASA credit to "About the data".

**Test.** Compare renders against actual phase photographs for five dates (new, crescent, quarter, gibbous, full). Unit-test the tilt angle against Meeus worked examples. Snapshot the southern hemisphere (American Samoa).

### 2. The real sky behind every screen — high value · M–L · medium risk

**Gap.** The starfield is seeded noise. A planetarium-in-your-pocket app showing invented stars is a missed opportunity, and a quiet honesty gap.

**Implement.**
- Bundle BSC5 down to magnitude 4.5. For the park and time on screen, compute altitude and azimuth with the existing sidereal-time code, then project the southern sky (or the zenith on high-score nights) to the screen.
- Star colour from B−V colour index (Ballesteros' formula: about 3,000 K orange to 10,000 K blue-white), size and brightness from magnitude. Real stars are subtly coloured; that alone reads as "real".
- **The Milky Way band**, placed from the galactic plane, rendered as a soft procedural glow (a shader, not a photo), stronger on nights with high scores and true darkness. It appears where it really is, so on a summer night at Joshua Tree the core sits low in the south.
- **Depth:** three parallax planes by magnitude (bright stars nearest) that drift slightly with scroll (`visualEffect`/`scrollTransition`). Optional device tilt on the detail hero only.
- **Performance:** draw the ~900 static stars once into a cached layer (`drawingGroup` or a pre-rendered `Image`); only the ~40 brightest twinkle per frame. That is lighter than today's 88 animated dots.
- Seeded noise stays as the fallback for the polar day and the onboarding art.

**Guardrails.** Brightness stays capped behind text (contrast audit must keep passing). Static under Reduce Motion. Red in night vision. The sky is never claimed as a visibility forecast: it is the geometry of the sky, and clouds are still in the score.

**Test.** Spot-check Orion, the Big Dipper and Scorpius positions against a planetarium reference for three parks and seasons.

### 3. The score dial as a glass instrument — medium-high value · S · low risk

**Gap.** The hero numeral sits in line art; the most-viewed object in the app has no material.

**Implement.**
- A `Glass.clear` bezel ring under the arc (falls back to solid under Reduce Transparency and night vision, exactly as the Tonight pill does now).
- A specular highlight along the arc that slides a few degrees with device tilt (CoreMotion, about 30 Hz while visible, off under Reduce Motion and Low Power Mode).
- A faint inner shadow so the numeral sits inside the dial.
- Keep the amber arc, leading star and orbit; they are the brand.

### 4. Cards in real glass — medium value · S · medium risk (contrast)

**Implement.** `Panel` uses `glassEffect(.regular.tint(panel colour), in: RoundedRectangle(cornerRadius:24))` over the starfield, so stars glint through the edges. Keep the current solid panel for Reduce Transparency, Increase Contrast and night vision.

**Risk.** Text contrast over a moving sky. The accessibility audit (17 screens × 2 palettes) is the gate; tint the glass dark enough to pass.

### 5. Depth in motion — medium value · S · low risk

- Detail hero: the gauge and moon sit on separate planes; on scroll the sky moves slower than the gauge (`scrollTransition`).
- Cold launch: the starfield resolves from the far plane forward (already short; just add the layers).
- Calendar month change: stars drift opposite to the swipe direction.
- All of it is skipped under Reduce Motion, and none of it blocks input.

### 6. Sky arc as a real horizon — medium value · M · low risk

- Replace the flat ground band with the park's silhouette, from a simple generic ridge profile (no terrain data needed; never claim it is the real skyline).
- The sun and moon glyphs become the shader moon (item 1) and a soft sun glow below the horizon.
- Keep it a chart first. No 3D dome: it would be harder to read and doesn't serve "when is it darkest?"

### 7. The icon (Dial concept) — high visibility · S · low risk

- **Moon:** sphere shading via SVG radial gradient (limb darkening), a soft terminator band, faint earthshine. Icon Composer renders these into its glass layers.
- **Layer depth:** arc and leading star as the front group (glass highlight on the arc), moon in the middle group, stars and background at the back. Liquid Glass then adds real specular movement on the Home Screen.
- **Check:** the Default, Dark, Tinted and Clear renditions, and 60 px legibility (a comparison sheet of the concepts, `IconSources/Concepts/comparison.png`, is in git history).

### 8. Widgets, share card, notifications — follow-through · S

- Widgets: use the improved vector moon (and later a pre-rendered texture-lit moon image saved by the app into the App Group), plus real star positions in `WidgetSky` instead of seeded dots.
- Share card: the texture-lit moon rendered to an image beside the score, so shared cards carry the realism.
- No change to notification content.

## What not to do

- **No 3D sky dome, AR overlay or spinning globe.** These are out of scope (product brief §11), costly in battery, and don't answer "where and when is it darkest?".
- **No photographic Milky Way or star photos** standing in for a computed sky. It would be misleading when it doesn't match tonight.
- **No RealityKit scene for the moon.** A shader does the same work at a fraction of the cost and composes with SwiftUI layout and accessibility.
- **No motion effects that run under Reduce Motion or Low Power Mode**, and no glass under Reduce Transparency.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Shaders not rendered in `ImageRenderer` or widget hosts | Keep the vector `MoonDisc` fallback; pre-render images in the app |
| Contrast regressions from glass and a brighter sky | The accessibility audit on 17 screens in both palettes is a release gate; cap sky brightness behind text |
| Frame rate on iPhone 12 | Shader moon is cheap; stars cached with only ~40 animated; Instruments pass on the oldest supported simulator plus your device |
| Licence of the star catalogue | Confirm BSC5 status; fallback to Hipparcos; never HYG (share-alike) |
| Asset size | Moon map ~150 KB, star JSON ~30 KB: negligible |
| Spec deviation (extra bundled data) | Log in `DECISIONS.md` under Section 17; credit NASA and the catalogue in "About the data" |

## Proposed sequence

| Build | Contents | Why this order |
|---|---|---|
| **3** | Dial icon with sphere-shaded moon and layer depth (7) · glass instrument dial (3) | Low risk, visible immediately, and the icon must be final for the first release |
| **4** | Physically lit Moon with true tilt and earthshine (1) · shader moon in the sky arc (6, part) | The signature piece; needs careful visual verification against photos |
| **5** | Real sky with star colours, Milky Way band and parallax planes (2) · depth in motion (5) | Biggest change to every screen's background; contrast re-audit |
| **6** | Glass cards (4) · widgets, share card and horizon polish (6, 8) | Depends on the sky's final brightness |

Each build keeps the standing gates: zero warnings, unit plus UI plus accessibility-audit suites green on iOS 26.5 and 27.0, screenshots reviewed in both palettes and at AX5, and `DECISIONS.md` updated.

## Sources

- NASA SVS, [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720) (credit line and map resolutions)
- NASA, [Goddard's CGI Moon Kit as visual storytelling](https://www.nasa.gov/missions/nasa-goddard-creates-cgi-moon-kit-as-a-form-of-visual-storytelling/)
- Astronexus, [HYG Database](https://astronexus.com/hyg) (CC BY-SA 4.0, so avoided)
- Data.gov listing, [Bright Star Catalog](https://catalog-old.data.gov/dataset/bright-star-catalog) (government-distributed; confirm terms at HEASARC)
- Installed SDK: `iPhoneOS27.0.sdk` SwiftUICore, `_RealityKit_SwiftUI`, SceneKit and CoreMotion headers, inspected October 3, 2026
