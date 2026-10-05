# What to add: the award roadmap

*Nyx · October 5, 2026 · a ranked plan for what to build on top of build 1.0 (5), and how to put it in front of every jury that matters.*

## Verdict

Nyx already answers **"where and when is the sky darkest?"** better than anything on the App Store. The Moon, the sky and the score are at award depth, and so are accessibility and privacy. What it doesn't yet do is carry people through the night itself, show what is in the sky besides darkness, or make the case for Social Impact and Inclusivity beyond compliance. Five additions close those gaps. Each is built on the engine and rules Nyx already has: on-device, two hosts, no third-party code, honest about uncertainty.

1. **Field mode.** The night itself, from arrival to dawn, on the Lock Screen and the wrist. *(Interaction, Innovation)*
2. **What's up tonight.** A timed Milky Way core, planets and meteor showers, computed on the phone. *(Visuals, Delight)*
3. **An honest forecast.** Cloud layers, how much the weather models agree, dew and cold. *(Innovation; honesty is the brand)*
4. **The cost of light.** Measured sky glow per viewing spot, light domes on the horizon, and how each park's sky has changed since 2012. *(Social Impact)*
5. **The sky for everyone.** Hearing and feeling the night, step-free viewing spots, Spanish. *(Inclusivity)*

Ship 1.0 first. Every jury below requires the app on the App Store, and nothing here needs to block the first release.

**Ground truth from the 2026 Design Awards.**
- The **Interaction** winner was *Moonlitt*, a moon-phase tracker. Apple cited SwiftUI, "best-in-class Liquid Glass integration", easy onboarding, and that it runs on every Apple platform including Vision Pro.
- The **Visuals and Graphics** winner was *Tide Guide*, a data app whose custom animations tie into its theme.
- The finalist closest to Nyx was *The Outsiders*, from the Gentler Streak team, for its readiness-score visualization.

So Nyx's category is proven, and a moon app has already won. Nyx can't win on the Moon alone. What sets it apart is **planning (where × when), the real sky, the cost of light and inclusivity**, plus a **reach beyond the iPhone** (Watch, then Vision Pro). iPhone-only and English-only are its two visible weaknesses against the criteria: Inclusivity names "abilities, and languages".

---

## Tier 1: signature additions

### 1. Field mode: the night itself

**Gap.** Nyx plans the trip and then goes quiet. The hardest hours are the ones in the dark: when does true darkness start, where should I look, when does the Moon set, how long until my eyes adapt? A phone screen is also the biggest threat to dark adaptation.

**Build.**
- **"I'm here tonight"** on any park's detail starts field mode (and Tonight offers it after sunset when the device is in a park, with location already allowed).
- **Live Activity and Dynamic Island** (ActivityKit, iOS 16.1+): a countdown through the night's milestones: astronomical dusk, moonset, core rise, core highest, dawn. All of them are computed on the phone and scheduled at start, so no push server is needed. In StandBy's night mode, iOS already renders it red.
- **Field screen.** Night vision forced on, screen dimmed to a set level and restored on exit, black everywhere, only large type. One thing at a time: *"True darkness in 14 min · then 7 h 52 m · Moon below the horizon"*.
- **Dark-adaptation clock.** Counts the 20–30 minutes the eye needs and resets, with an explanation, if the screen was used at full brightness. It is honest physiology, it is delightful, and nothing else on the App Store does it.
- **Where to look.** The real sky (already computed) turned to the phone's compass heading: point the phone and the core, the planets and the meteor radiant are where they really are, with labels in red. The magnetic heading comes from Core Location and works offline. This is not AR: there is no camera and no overlay, just the existing star projection rotated to the device's attitude.
- **AlarmKit** (iOS 26): "Wake me when the core rises" and "Wake me 30 minutes before the Moon sets", for the pre-dawn Milky Way. The alarm breaks through Silent and Focus, which a notification can't do.
- **Focus filter**: a "Stargazing" Focus turns on night vision and field mode automatically.
- **Apple Watch** (lift the §11 exclusion in v1.2): a wrist countdown and the Moon's state, red only, readable without pulling out a phone. It shares the engine.

**Why it wins.** The Interaction category rewards apps that make a moment physical, and this is the app's signature moment, currently unbuilt. It shows off Live Activities, StandBy, AlarmKit, Focus, Control Center and the Watch, all for a real reason.

### 2. What's up tonight: core, planets, meteors

**Gap.** Milky Way guidance is a seasonal sentence (`AstronomyEngine.milkyWayGuidance`). Milky Way photographers, the app's core audience, plan around the core's **rise time, azimuth and altitude**. That is the question PhotoPills owns and Nyx can answer better, because it pairs it with the score.

**Build.**
- **Timed galactic core** per park per night: rise, highest altitude and bearing, set, and the window when it is above 10° in true darkness with the Moon down. The real-sky projection already places it, so this needs only the existing `crossings` search over a fixed RA/Dec. It replaces the heuristic, and the sky arc draws the core's path beside the Sun and Moon.
- **Planets**: positions from low-precision orbital elements (Schlyter or Meeus ch. 33), accurate to about 1°, which is plenty to say *"Saturn rises at 8:12 pm in the east"*. They appear as labelled dots in the real sky.
- **Meteor showers**: a bundled table from the IMO calendar (peak, ZHR, radiant), scored for Moon interference and radiant altitude at each park. These are real hooks: the **Geminids peak Dec 13–14, 2026 under a 23%-lit crescent** that sets early; the **Quadrantids Jan 3–4, 2027 at 11%**; the **Eta Aquariids May 6, 2027 at new moon**. The **Perseids 2027 are washed out (86% lit)**, which Nyx should say plainly.
- **Eclipses and conjunctions**: a small hand-checked table, shown when visible from a park.
- **The score stays the score.** Events are reasons to go, shown as glyphs on calendar nights, a line on the detail, and their own reminder kind.

**Why it wins.** Visuals and Graphics (the real sky gains labelled planets and a timed core) and Delight (the calendar suddenly has events). It also makes App Store In-App Events possible (Tier 4).

### 3. An honest forecast

**Gap.** Nyx reads one weather variable, total cloud cover. Thin high cirrus, haze, dew on lenses and cold all decide a night, and a single number hides how sure the forecast is.

**Build** (one request to `api.open-meteo.com`, the same host as now; verified 2026-10-05 that `models=gfs_seamless,ecmwf_ifs025,icon_seamless` returns `cloud_cover_<model>` separately):
- **Model agreement as confidence.** Three models' cloud averages over the dark window. When they agree: *"Clear in all three forecast models."* When they disagree: *"Models disagree: 0–30% cloud. Check again tomorrow."* Show it as a band on the time river and a word beside the cloud meter. It is honest uncertainty, shown visually, and no consumer stargazing app does it.
- **Cloud layers** (`cloud_cover_low/mid/high`): *"Thin high cloud; bright stars only."*
- **What to bring**: dew point against temperature for dew risk on optics, wind gusts, and the coldest hour, in locale units. This is a short "Bring" line, not a weather app.
- `visibility` as a haze hint only, labelled as such.
- **Wildfire smoke**: the Air Quality API lives on a third host (`air-quality-api.open-meteo.com`), which §13 forbids. It is the biggest honesty gap for western parks in summer. **Owner decision** (logged in INPUT_NEEDED): add it as a third disclosed host behind its own privacy toggle, or keep a static "smoke is not forecast" note in fire season. Recommended: add it, disclosed and switchable. Same provider, same no-coordinates-from-the-device rule.
- **Score impact:** keep the formula. Clouds stay the cloud term (the high-cloud fraction could earn a small penalty later, after validation). Everything else is context, never points.

### 4. The cost of light: sky glow you can see

**Gap.** "Bortle 3, estimated" is one park-wide number, and a gentle guess. Light pollution is the whole reason the app exists, and Nyx has no way to show it.

**Build.**
- **Measured sky glow per viewing spot** from NASA's **Black Marble** annual night lights (VNP46A4, public domain): a downsampled radiance grid for the western and eastern US bundled offline, with artificial sky brightness at each spot from a distance-weighted sum (Walker's law or Garstang-style falloff). This replaces the hand-estimated Bortle with a computed, documented one, and still says "estimate". *Avoid the Falchi 2016 atlas: CC BY-NC.*
- **Light domes on the horizon.** The same grid gives the bearing and strength of each city glow: *"Las Vegas glow, east, about 15° high."* It is drawn in the real sky and on the sky arc ridge, and tells people which way not to set up a camera. It is novel and useful.
- **"Your sky over time."** Black Marble yearly composites from 2012 onward give a per-park trend: *"Night lights within 100 miles of Arches rose 9% since 2012."* Measured, sourced and calm. It is the Social Impact headline.
- **Protect this sky**, a short per-park card: the park's International Dark Sky Park certification year where it has one, what the park has done, and three things anyone can do at home (shielded, warm, motion-sensing lights). It links to the existing Learn essays.
- **Citizen science, user-initiated.** A journal entry offers *"Share your observation with Globe at Night"*. It opens their page in Safari with nothing prefilled (no data leaves through Nyx, and no third host). Journal entries gain an optional limiting-magnitude estimate using the Globe at Night star charts, rendered from Nyx's real sky.

**Why it wins.** Social Impact is the category judges reward for a cause, and disappearing night skies is a cause with a measurable, local, emotional story. Today Nyx makes that case only in an essay. With these additions it makes it in data.

### 5. The sky for everyone

Nyx already passes Apple's accessibility audit on every screen. To win Inclusivity, it has to do something no one asked for.

- **Hear the night.** Audio Graphs (`AXChartDescriptor`) for the time river, the calendar month and the sky arc, so VoiceOver users can play a month of darkness as a rising and falling tone. Add a **"Listen to tonight"** sonification: the night as sound from dusk to dawn, a pitch for darkness, a soft pulse for moonrise. Blind astronomy is a real community (NASA's *A Universe of Sound*).
- **Feel the Moon.** Core Haptics patterns: the river's detent sharpens with score, and the Moon's phase is a texture under the finger (sharp at new moon, broad at full). Paired with VoiceOver it's a non-visual reading of the Moon.
- **Step-free viewing spots.** Flag spots with paved access, accessible parking and restrooms from NPS accessibility pages (many star parties are held at parking lots). Add a filter and say it in the spot row. This is research work, with each flag sourced as viewing spots already are.
- **Spanish** (then more): the String Catalog is ready. US national parks publish in Spanish, and over 40 million US residents speak it at home. The owner reviews the translation with a native speaker (INPUT_NEEDED).
- **Accessibility Nutrition Labels** on the product page: declare VoiceOver, Voice Control, Larger Text, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast and Reduced Motion. Nyx supports all of them; add a Voice Control pass to the audit first.
- **Rotors**: a VoiceOver rotor for "best nights" in the calendar and for "closures" in park lists.

---

## Tier 2: delight

- **Your constellation.** Each journal night becomes a star at that park's position on a map of the US drawn as a sky. Over seasons they join into the user's own constellation. Shareable. It replaces any "badges" idea and stays calm.
- **Skies you've seen: 7 of 63.** A quiet count on the journal, with observed Bortle per park. It's a reason to go again without being a game.
- **A trip planner.** *"I'm free Oct 10–17, within 300 miles."* Nyx assigns the best park to each night, weighing the drive as straight-line distance only, and highlights the single best night. *"Weekends only"* covers the brief's "which nights to take off work". It adds to Calendar through `EKEventEditViewController`, which needs no calendar permission.
- **Year under the stars**, a December recap: nights out, darkest sky, Moon phases met, new parks. It uses Foundation Models where available (already availability-gated) and a template otherwise.
- **Alternate icons**: the icon's crescent following the Moon's phase is not possible (icons are static), but offer four hand-made Liquid Glass variants (new, crescent, quarter, full) in Settings.
- **First light.** The first time someone opens Nyx at a park after dusk, the sky reveals itself once, slowly, with the real stars overhead. Skipped under Reduce Motion.

## Tier 3: platform showcase, each for a reason

- **Interactive widgets**: a large widget with the month's nights; a Button intent to cycle saved parks; relevance hints so the widget rises in the Smart Stack at dusk on a good night.
- **App Intents**: `IndexedEntity` for semantic Spotlight; a "Find the best night" intent with a date-range parameter (Shortcuts); interactive snippet results; intents exposed to Apple Intelligence.
- **Ask Nyx with tool calling**: give the model tools that call `ScoreEngine` and `AstronomyEngine` (the model still does no astronomy itself), so it can answer *"Which weekend in November is best within 4 hours of Denver?"* from computed data.
- **Control Center**: a "Field mode" control beside night vision.

### Newer-OS APIs, verified in the installed iPhoneOS 27.0 SDK

Nyx uses one iOS 27 API today (`topBarPinnedTrailing`). Each item below sits behind `if #available`, with iOS 26 unchanged.

| API | Available | Use in Nyx |
|---|---|---|
| `EnvironmentValues.accessibilityReduceHighlightingEffects` | iOS 26.4 | "Reduce bright effects": dim the gauge glow, amber halos, shooting star and Milky Way peak. A natural fit for night-adapted eyes; mention it in the Inclusivity story |
| `EnvironmentValues.accessibilityPrefersCrossFadeTransitions`, `NavigationTransition.crossFade` | 26.4 / 27 | Cross-fade instead of the zoom and calendar slide when preferred |
| `AccessibilityAttributes.accessibilitySpeechSSML` | 27 | VoiceOver says "Bortle" correctly, reads "94 out of 100", and paces sky summaries |
| `MetricKit` `PixelLuminanceMetric`, Swift `MetricManager` | 27 | On-device proof that Nyx stays dark: the real average screen luminance, shown in About ("Nyx kept your screen at x% of the brightness of a typical app"). Nothing leaves the phone, and it fits the "MetricKit only" rule |
| `EnvironmentValues.systemPrefersReducedResourceUsage` | 27 | Fewer twinkling stars and a cheaper Moon when the system asks |
| `toolbarMinimizationBehavior(.onScrollDown, for:)` | 27 | Bars recede so the park's sky runs full-bleed |
| AlarmKit `AlarmConfiguration.alarm(…appEntityIdentifier:…)` | 27 (AlarmKit itself 26) | Field-mode alarms tied to the park entity |
| `UNMutableNotificationContent.appEntityIdentifiers` | 27 | "Pristine night at Joshua Tree" becomes an object Siri understands ("open this park") |
| `IndexedEntity`, `IndexedEntityQuery.reindexEntities`, `CSSearchableItem.relatedAppEntityIdentifier` | 26 / 27 | Semantic Spotlight for parks; link the existing Spotlight items to `ParkEntity` |
| `IntentSystemContext.isVoiceOnly` | 27 | Shorter Siri answers when no screen is in view |
| FoundationModels `Attachment(cgImage:)`, `ReasoningLevel`, real `contextSize`, `tokenCount(for:)`, `SpotlightSearchTool` | 27 / 26.4 | Season recap that can look at journal photos (described, never "measured"); exact prompt trimming; Ask Nyx searches the journal through Spotlight. **Never `PrivateCloudComputeLanguageModel`**: it uses the network |
| SwiftData `@Query(sectionBy:)` | 27 | Journal grouped by season natively |
| `CMDeviceMotion.headingAccuracy` | 27 | A calibration hint in the where-to-look compass |
| AVFAudio `installAudioTap(…tapProvider:)`, throwing `connectNode` | 27 | Safer engine for the "listen to tonight" sonification |

Not usable under §13: MapKit's new ranger-station and viewpoint categories (Apple's servers), and Private Cloud Compute. ActivityKit, TipKit and CoreHaptics have no iOS 27 changes, so Live Activities and haptics are built on their iOS 26 APIs.

## Tier 2b: beyond the iPhone

Moonlitt won partly for reaching every Apple platform. Nyx's engine is pure Swift with no UIKit, so reaching other platforms is mostly layout work.

- **Apple Watch** (1.2, with field mode): red-only countdown, Moon and score complications, and Smart Stack relevance at dusk. At a dark site the wrist is the right screen, because the phone ruins dark adaptation.
- **Vision Pro** (1.4): **"Stand under tonight's sky."** An immersive space places the real catalogue stars, the Milky Way, the planets and the Moon over the chosen park on the chosen night, with the horizon ridge. Scrub the time river and the sky turns. It is literally the planetarium the brief asks for, rendered from data Nyx already computes. Vision Pro apps won Design Awards in 2025 (Interaction) and 2026 (Innovation, Social Impact).
- **iPad** (1.3): calendar and detail side by side. It's cheap once Watch and Vision have pushed the layouts apart.
- Drop "iPhone only" and "iPad layouts out of scope" from §11 at the release that adds each one, and log it in `DECISIONS.md`.

## Tier 4: store and awards

**Dated actions, with sources in the research notes:**

| When | Action |
|---|---|
| Now | Submit build 5 for review. File an **App Launch featuring nomination** in App Store Connect (Featuring → Nominations), at least 2–3 weeks before the date you want, with the TestFlight link, press kit and accessibility notes |
| **By Oct 30, 2026** | **Webby Awards** early deadline (Apps, Software & Immersive; the app must be live). About $525–645 |
| **By Nov 4, 2026** | **iF Design Award** late registration (UI / UX disciplines), €500 |
| Nov 2026 | In-App Event and nomination: *Geminids under a dark sky* (Dec 13–14) |
| Dec 2026 | In-App Event: *Quadrantids at an 11% moon* (Jan 3–4) |
| Jan–Mar 2027 | **Red Dot** Brands & Communication (Interface & UX), **D&AD** Digital Design, **Core77** (Apps & Platforms; Design for Social Impact); verify each year's dates |
| Spring 2027 | **Fast Company Innovation by Design** (Apps), **Anthem Awards** (Sustainability, Environment & Climate; judged against the entrant's resources, which suits a solo developer) |
| Mid-May 2027 | Apple Design Award finalists announced (you can't apply; editors pick from live apps). 1.3 must be out by March |
| Nov–Dec 2027 | App Store Awards, best shot at **Cultural Impact**. An October 2026 launch is too late for this year |
| Ongoing | Ask DarkSky International to list Nyx as a resource (their awards honour advocacy, not products). Pitch the NPS Natural Sounds & Night Skies Division for awareness only; never imply NPS endorsement |

**Positioning against competitors.** Their reviews complain about paywalls, ads, email-for-saving, tracking (StargazingPal's label shows tracking) and confusing interfaces (PhotoPills). Nyx is free, Data Not Collected and calm. Say so on the product page and in every nomination. Score-style apps are multiplying (ClearNight, StargazingPal), so the score alone is no longer the differentiator. The park-level where × when plan with closures, the real sky, honesty about uncertainty and accessibility are.

**Product page and launch:**
- **Release 1.0 now.** Build 5 is uploaded. Every jury and every editor needs a live App Store page.
- **App Preview video** (15–30 s): the score reveal, a river scrub with the Moon morphing, the night-vision toggle. Judges and editors watch videos.
- **In-App Events** (App Store Connect, free, shown in search and Today): *"Geminids under a dark sky"* (Dec 13–14, 2026), *"New moon weekend"* every month, *"Eta Aquariids at new moon"* (May 6, 2027). Each needs only the meteor table from Tier 1 §2.
- **Featuring nomination** in App Store Connect for each release, with the story: one person, no tracking, real sky, built for night-adapted eyes.
- **Press kit and a case study** on the GitHub Pages site: the shader Moon, the real sky, the score formula, the accessibility audit. Juries and press both need something to read.
- **Accessibility Nutrition Labels** (Tier 1 §5).

---

## Proposed sequence

| Release | Contents | Why this order |
|---|---|---|
| **1.0** (now) | Build 5 as is | Every award needs a live app |
| **1.1** "Tonight's sky", ~Nov 2026 | What's up tonight (core, planets, meteors) · honest forecast (model agreement, layers, bring) · iOS 26.4/27 accessibility APIs (reduce bright effects, cross-fade, SSML) · In-App Event for the Geminids · Accessibility Nutrition Labels · App Preview video | The data work is engine-only and testable; it makes Dec 13 a launch moment |
| **1.2** "Field", ~Jan 2027 | Field mode · Live Activity · AlarmKit · where-to-look compass · Focus filter · Field control · **Apple Watch** | The signature interaction, timed for the Quadrantids and winter's long nights |
| **1.3** "Every sky", ~Mar 2027 | Black Marble sky glow · light domes · sky-over-time · Protect this sky · hear the night · step-free spots · **Spanish** · iPad · luminance proof | The Social Impact and Inclusivity case, complete before Design Award finalists are chosen in mid-May |
| **1.4**, by WWDC 2027 | **Vision Pro "stand under tonight's sky"** · trip planner · your constellation · year recap | The showpiece, live before finalists and winners are announced; then the Milky Way season |

Each release keeps the standing gates: zero warnings, unit, UI and accessibility-audit suites green on the oldest and newest iOS, screenshots reviewed in both palettes and at AX5, and `DECISIONS.md` updated.

## What not to add

- **A camera AR overlay, a 3D globe or a full planetarium.** Sky Guide and Stellarium own that, and it doesn't answer "where and when". The compass-turned real sky gives 80% of the value at 5% of the cost.
- **Aurora forecasts.** They need NOAA SWPC, a third host, and are unreliable days out. Revisit only if Alaska users ask.
- **Social feeds, accounts, leaderboards, streaks.** These break §13 and the calm.
- **ISS passes.** They need live orbital elements, another host.
- **Ambient music.** Sound only where it carries information (Tier 1 §5).

## Sources

- Apple Design Awards: [categories](https://developer.apple.com/design/awards/), [2026 winners](https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/), [2026 finalists](https://www.macrumors.com/2026/05/18/apple-design-award-finalists-2026/), [2025 winners](https://www.apple.com/newsroom/2025/06/apple-unveils-winners-and-finalists-of-the-2025-apple-design-awards/)
- App Store Awards: [2025 winners](https://www.apple.com/newsroom/2025/12/apple-unveils-the-winners-of-the-2025-app-store-awards/); [featuring nominations](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring); [getting featured](https://developer.apple.com/app-store/getting-featured/); [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)
- Other awards: [Webby eligibility](https://webbyawards.com/eligibility-and-guidelines), [iF 2027](https://graphiccompetitions.com/multiple-disciplines/if-design-award-2027/), [Red Dot B&C](https://www.red-dot.org/bcd/participate), [D&AD](https://dandad.org/d-ad-awards), [Core77](https://designawards.core77.com/about), [Fast Company IBD](https://www.fastcompany.com/91593051/methodology-innovation-by-design-2026), [Anthem](https://www.anthemawards.com/faq), [DarkSky and Star Gazers](https://darksky.org/news/meet-star-gazers-stargazing-app/)
- Competitor reviews: [Astrospheric](https://justuseapp.com/en/app/1166046863/astrospheric/reviews), [PhotoPills review](https://www.space.com/photopills-app-review), [Good To Stargaze](https://mwm.ai/apps/good-to-stargaze/1298891559), [ClearNight](https://mwm.ai/apps/clearnight/6788958981), [StargazingPal](https://apps.apple.com/app/id6738318070)
- Data: [NASA Black Marble VNP46A4](https://catalog.data.gov/dataset/viirs-npp-lunar-brdf-adjusted-nighttime-lights-yearly-l3-global-15-arc-second-linear-lat-l) (public domain); [Falchi 2016 atlas](https://www.arxiv.org/pdf/1609.01041) (CC BY-NC, avoided); [Open-Meteo forecast variables](https://open-meteo.com/en/docs). Multi-model response shape verified with a live request on 2026-10-05.
- Meteor-shower Moon illumination and new moons: PyEphem 4.x, computed 2026-10-05.
- New APIs: installed `iPhoneOS27.0.sdk` `.swiftinterface` files, including the `anyAppleOS 27.0` availability form.

Dates for Red Dot, D&AD, Core77, Fast Company and Anthem 2027, and the exact Design Award eligibility cutoff, aren't published yet. Check them in December.
