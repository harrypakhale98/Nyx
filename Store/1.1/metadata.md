# Nyx 1.1 — App Store metadata

Paste-ready copy for App Store Connect. Voice follows the Nyx voice: calm, precise, plain, honest about uncertainty. No exclamation marks, no marketing adjectives.

**Before pasting, remove every line for a feature that does not ship in the 1.1 build you submit.** The copy below assumes the full list from the brief: honest forecast, What's up tonight, Field mode, Apple Watch, Apple Vision Pro, deep accessibility, measured sky glow, step-free viewing spots, Spanish, iPad, trip planner, personal constellation journal. Every claim is something the app does or is built to do. Nothing says "only", "first" or "best".

Character counts (verified with a script on 2026-10-05) are in brackets after each field. Apple's limits (checked in App Store Connect help on 2026-10-05): What's New 4,000; promotional text 170; description 4,000; keywords 100; subtitle 30; name 30.

---

## Version

- Version **1.1**, build number above 5 (integrator bumps `CURRENT_PROJECT_VERSION` in `project.yml`).
- Release: **manual release** after approval, so the 1.1 In-App Events (`in-app-events.md`) and featuring nomination (`featuring-nominations.md`) line up.
- Platforms in the 1.1 record: iPhone, iPad (new), Apple Watch (new, companion), Apple Vision Pro (new). visionOS has its own version page with its own description, keywords, promotional text and review notes: `metadata-visionos.md`.

---

## What's New (1.1)

```
Nyx 1.1 follows the night from the plan to the dawn.

TONIGHT'S SKY
- The Milky Way core, timed for each park: when it rises, when it is highest and where, and when the Moon is out of the way.
- Planets, with rise and set times and the direction to look.
- Meteor showers, with the Moon's interference and a rate estimate from the International Meteor Organization. Lunar eclipses are listed when the park can see them.
- None of this changes the Darkness Score. These are reasons to go, not points.

AN HONEST FORECAST
- Three weather models are compared. Nyx says when they agree and shows the range when they do not.
- Cloud layers: thin high cloud and thick low cloud are different nights.
- Dew, cold and wind for the dark hours, in your units.
- Wildfire smoke and haze appear beside the score as a caveat. This uses one new, optional data service (see Privacy below).

FIELD MODE
- "I'm here tonight" turns Nyx into a red, dimmed screen made for night-adapted eyes: a countdown to true darkness, each milestone in turn, and a dark-adaptation clock.
- Where to look: the real sky follows your iPhone, with the Moon, the core, planets and a shower's radiant marked in red. No camera.
- A Live Activity and Dynamic Island carry the countdown on the Lock Screen. Alarms can wake you when true darkness begins or the core rises (iOS 26.1 and later).
- A Stargazing Focus and a Control Center control start it for you.

ON YOUR WRIST AND IN THE ROOM
- Apple Watch: a red-first countdown, the Moon, and complications.
- Apple Vision Pro: stand under the real sky for a park and a night, and scrub the hours.
- iPad: the calendar and park detail side by side.

SKY GLOW YOU CAN READ
- Sky glow at each named viewing spot is now compared with the other national parks, from NASA's Black Marble night-lights data, and each park names the towns whose glow rises on its horizon and which way they lie. It is a comparison, not a measurement, and says so.

THE SKY FOR MORE PEOPLE
- Hear the night: audio graphs for the timeline, calendar and sky arc, and a short sonification of tonight.
- Feel the Moon: haptics that follow the phase.
- Reduce bright effects (iOS 26.4 and later) softens the glow, halos and shooting star.
- Step-free viewing spots are marked and can be filtered, sourced from park accessibility pages.
- Spanish.

PLANNING AND MEMORY
- Trip planner: give Nyx your free dates and a straight-line radius, and it suggests a park for each night.
- Your constellation: every journal night becomes a star on a map of the parks. It stays on your iPhone.

PRIVACY
- Nyx still collects no data. No account, no advertising, no tracking.
- A third network service, Open-Meteo's air-quality forecast, supplies smoke and haze. It has its own switch in Settings, Your privacy, like forecasts and park updates. It receives the public coordinates of national parks, never your location.

GOOD TO KNOW
- Scores and forecasts are estimates. They do not confirm clear skies or open roads. Check park conditions before you travel.
- Moonrise and moonset are approximate, to about 15 minutes, and vary with terrain.
- Meteor rates are a rough guide: the nominal rate assumes a perfect sky.
- Apple Intelligence features appear only on devices where Apple's on-device model is available.

Questions or problems: harry.pakhale98@gmail.com
```

[3,251 of 4,000 characters]

Short fallback (about 600 characters) if the full text feels long for the release:

```
Nyx 1.1 follows the night from the plan to the dawn. The Milky Way core, planets and meteor showers are timed for each park. The forecast compares three weather models and shows smoke and haze. Field mode puts a countdown, a dark-adaptation clock and "where to look" on a red screen, the Lock Screen and your wrist. Sky glow at viewing spots is now estimated from NASA data. New: Apple Watch, Apple Vision Pro, iPad, Spanish, audio graphs, step-free viewing spots and a trip planner. Still no account, ads or tracking.
```

---

## Promotional text (≤170)

Primary:

```
Plan the night, then follow it. The Milky Way core, planets and meteor showers, honest forecasts, and a red field mode for your eyes. Free. Data Not Collected.
```

Alternates (use for seasonal swaps; promotional text can change without a new build):

- Meteor season, Dec: `Geminids peak December 13 to 14 under a 23 percent Moon that sets early. See which national park skies are darkest each night. Free, no account, no tracking.`
- Quiet/ranger tone: `Which park, which night, and when the Milky Way clears the horizon. Nyx compares the 63 national parks and says plainly what the forecast cannot know.`
- Accessibility angle: `Hear the night, feel the Moon, read it in red. Nyx plans dark-sky trips to the national parks and works with VoiceOver, larger text and night-adapted eyes.`

---

## Description (≤4000)

```
Make time for a darker sky.

Nyx compares nights across the 63 US national parks. Moonlight, cloud cover, estimated sky glow and the length of true darkness become one Darkness Score from 0 to 100, with a breakdown that explains it.

PLAN
Find nearby parks within a straight-line radius, or sort every park by tonight's darkness. Explore the calendar and its five-night new moon window. Follow thirty nights on a timeline that draws in the range the forecast models allow. Give the trip planner your free dates and it suggests a park for each night. Times are park-local.

SEE WHAT IS UP
Each park's night lists the Milky Way core with its rise, highest point, direction and Moon-free hours; planets with rise and set times; meteor showers with the Moon's interference and a rate estimate from the International Meteor Organization; and lunar eclipses the park can see. These are reasons to go. They never change the score.

A FORECAST THAT SAYS WHAT IT DOES NOT KNOW
Nyx compares three weather models and tells you when they agree and when they do not. It separates thin high cloud from thick low cloud, notes dew, cold and wind for the dark hours, and shows wildfire smoke and haze beside the score. Beyond the forecast horizon Nyx scores the Moon and darkness alone, and labels those nights that way.

FIELD MODE
At the park, "I'm here tonight" opens a red, dimmed screen made for night-adapted eyes: the countdown to true darkness, each milestone of the night, and a dark-adaptation clock. "Where to look" turns the real sky to your iPhone's direction, with no camera. A Live Activity keeps the countdown on the Lock Screen, and alarms can wake you for true darkness or the core's rise (iOS 26.1 and later). On Apple Watch, the countdown and the Moon are on your wrist, in red. On Apple Vision Pro, you can stand under the real sky for a park and a night.

SKY GLOW
Each named viewing spot shows how its sky glow compares with the other national parks, from NASA Black Marble night-lights data, and each park names the direction of the city glow on its horizon. It is a comparison between places, not a measurement taken at the spot.

KEEP A LITTLE OF THE NIGHT
Save parks and receive optional local reminders for promising nights. Keep a private journal with notes and selected photos; each night becomes a star in your own constellation. Widgets show the best sky among your saved parks.

BUILT FOR MORE PEOPLE
Nyx works with VoiceOver, Voice Control, larger text, Reduce Motion, Reduce Transparency, Increase Contrast and Bold Text. Audio graphs let you hear the timeline, the calendar and the sky arc. Haptics follow the Moon's phase. Step-free viewing spots are marked and can be filtered. Night-vision mode renders everything in red. Spanish is included.

PRIVATE BY DESIGN
No account, no advertising, no tracking. Your location and your journal stay on your iPhone. Three optional services supply data, each with its own switch under Your privacy: park alerts from the National Park Service, forecasts from Open-Meteo, and smoke and haze from Open-Meteo's air-quality service. They receive the public coordinates of national parks, not yours.

WORKS OFFLINE
Moon, sun and twilight calculations, the core, planets, the park library, the calendar, the journal and saved parks work without a connection. Forecasts reach about sixteen days. Light-pollution classes are estimates. Moonrise and moonset are approximate, to about 15 minutes.

PLEASE NOTE
Scores do not confirm clear skies or safe access. Check current road and park conditions before traveling. Forecasts do not include telescope seeing. Park alerts and ranger programs come from the National Park Service and may be unavailable.

Weather data: Open-Meteo, CC BY 4.0. Air quality: Copernicus Atmosphere Monitoring Service via Open-Meteo, CC BY 4.0. Night lights and Moon imagery: NASA. Meteor showers: International Meteor Organization. Lunar eclipses: Fred Espenak, NASA/GSFC. Park data: National Park Service. Nyx is not affiliated with or endorsed by the National Park Service or NASA.
```

[3,978 of 4,000 characters. It is tight on purpose: if you add a sentence, cut one.]

Notes for the owner:
- The 1.0 description said "Forecasts do not include smoke, haze or telescope seeing." That sentence is now false for smoke and haze (the forecast adds them, as a caveat); this draft changes it. Keep that correction.
- "Voice Control" appears in the list above only after the on-device pass in `accessibility-nutrition-labels.md` is signed off. Delete the words if it is not.
- "Nyx is not affiliated with or endorsed by ... NASA" is added because the Moon map and Black Marble are NASA data; NASA's media guidelines ask that use not imply endorsement.

---

## Keywords (≤100)

Rules: App Store indexes name, subtitle and keywords together, so none of those words repeat here. "Nyx", "Dark", "Sky", "Planner" are in the name; Travel and Weather are the categories. Singular and plural both match, so use singular where possible. Commas, no spaces.

Primary (re-optimized):

```
stargazing,milky way,meteor shower,moon phase,national park,astronomy,bortle,planet,eclipse,star
```

Changes from 1.0 (`stargazing,national parks,moon phase,astronomy,milky way,night sky,bortle,camping,meteor,aurora`):
- **Dropped `aurora`.** Nyx does not forecast aurora (the roadmap lists it under "what not to add"). Keeping it would mislead and attract the wrong reviews.
- Dropped `camping` (high competition, weak intent match) and `night sky` (its words overlap the name).
- Added `meteor shower`, `planet`, `eclipse` (1.1 features) and `star`.
- `national park` singular covers both forms.
- `astrophotography` (core audience) was tried and does not fit in 100 characters with the rest. Swap it in for `star` and `planet` if the photography audience matters more than planet searches.

Alternate (97 characters), trading `star` for `photo`:

```
stargazing,milky way,meteor shower,moon phase,national park,astronomy,bortle,planet,eclipse,photo
```

Spanish keywords (draft; the owner's native-speaker review in `INPUT_NEEDED.md` covers these too):

```
estrellas,vía láctea,lluvia de meteoros,fases lunares,parque nacional,astronomía,planeta,eclipse
```

---

## Subtitle options (≤30)

| # | Subtitle | Count | Note |
|---|---|---|---|
| 1 | `Plan a darker night` | 19 | Current 1.0 subtitle; keeps continuity. |
| 2 | `Where the sky is darkest` | 24 | Answers the one question. Plain. |
| 3 | `The night sky, park by park` | 27 | Says the scope; 63 parks. |
| 4 | `Plan the night. Then see it.` | 28 | Covers planning plus field mode. |
| 5 | `Dark skies in national parks` | 28 | Strongest for search because "national parks" is not in the name. If chosen, remove `national park` from keywords and add `camping`. |

Recommendation: **#3, `The night sky, park by park`.** It states the scope, adds "park" and "night" to the indexed words, and is the calmest of the five. #5 is the strongest for search ("national parks" is not in the name) but repeats "dark" and "sky" from the name; if you choose it, drop `national park` from the keywords and add `camping` in its place. A subtitle changes only with a new version.

Spanish subtitle drafts (≤30, native review): `Planifica una noche oscura` (25), `Dónde el cielo es más oscuro` (28).

---

## Other fields to revisit with 1.1

- **Category:** keep Travel (primary), Weather (secondary). Do not move to Education or Reference.
- **Age rating:** re-answer the questionnaire; nothing in 1.1 changes the answers (no UGC feed, no web access beyond providers).
- **Review notes (add to the existing text in `SUBMISSION.md`):** "1.1 adds a third provider host, `air-quality-api.open-meteo.com`, behind its own switch in Tonight, Settings, Your privacy, listed in `PrivacyInfo.xcprivacy`. Field mode (Live Activity, AlarmKit alarms, Core Motion for 'Where to look') is started by a person at a park's detail screen; on a simulator, `-nyx-screen field` is DEBUG only, so reviewers should use 'I'm here tonight' on any park's detail screen after sunset or in the evening. AlarmKit asks for permission in context after an explainer. The Apple Watch and visionOS targets share the same engine and make no network requests of their own. No login."
- **App Privacy:** still "Data Not Collected". The new host receives only public park coordinates, as the forecast host does. Re-read `PRIVACY.md` before answering, because ASC asks again at each submission.
- **Screenshots (done 2026-10-06, build 7):** iPhone required slot `Store/Framed/6.3-inch/` (1206×2622), optional `6.9-inch/` and `6.5-inch/`; iPad `Store/Framed/iPad-13-inch/`; Apple Watch `Store/Framed/Watch-Ultra/`; Vision Pro `Store/Framed/Vision-Pro/`. iPhone Duo screenshots become required in April 2027 (needs Xcode 27.1).
- **Copyright:** `2026 Hardik Pakhale` (unchanged).
- **Age rating (new question, September 2026):** App Store Connect now asks whether the app has social media capabilities (for the new Time Allowances). Answer **No**: Nyx has no accounts, feeds, messaging or sharing beyond the system share sheet.
- **Creative assets (new, optional, October 2026):** product page header (21:9, 3840×1646 image or 5–30 s video) and search result asset (3:2, 1920×1280 to 3840×2560). Not required to submit. Check the page in App Store Connect's new preview tool before submitting, in each device and orientation.
- **Accessibility Nutrition Labels:** answered per device, now including Apple Vision Pro (`accessibility-nutrition-labels.md`); declare only what the device pass confirms.

## Count table

| Field | Limit | Characters |
|---|---|---|
| What's New | 4,000 | 3,251 |
| What's New short | 4,000 | 518 |
| Promotional text (primary) | 170 | 159 |
| Description | 4,000 | 3,978 |
| Keywords (primary) | 100 | 96 |
| Keywords (alternate) | 100 | 97 |
| Keywords (Spanish draft) | 100 | 96 |
