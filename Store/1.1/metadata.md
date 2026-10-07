# Nyx 1.1 — App Store metadata (first public release)

Paste-ready copy for App Store Connect. Version 1.1 is the **first public release**: 1.0 never shipped, so there is **no What's New** field to fill (App Store Connect does not show one for an app's first version). Voice: calm, precise, plain, honest about uncertainty. No exclamation marks, no marketing adjectives, nothing says "only", "first" or "best".

Character counts were verified with a script on 2026-10-07 (`len()` of the text between the fences; App Store Connect may count a line break as two characters, so each field keeps a margin). Apple's limits: name 30, subtitle 30, promotional text 170, description 4,000, keywords 100.

## Confirm before pasting (integrator)

The description names features from main as of 2026-10-07 plus wave 2 and 3 items. Before pasting, confirm each of these is in build 8, and delete its sentence if not:

| Feature | Where it appears | Status on 2026-10-07 |
|---|---|---|
| Plan tab with "My free nights" (trip planner) | PLAN | Trip planner on main; the Plan tab is wave 2 |
| Starting from a town or city (Census places) | PLAN | Wave 2 (another lane); not on main |
| Spanish (Mexico) in the app | Last line of FOR MORE PEOPLE | On main; may be cut if the native review is not done (AM-12) |
| Apple Vision Pro: star names, constellation figures, Moon on your table, widget | ON YOUR WRIST AND IN THE ROOM | On main (vision lane); the visionOS build may be submitted separately |
| Apple Watch: Crown scrub, adaptation clock, Red light control, Moon and Next dark complications | ON YOUR WRIST AND IN THE ROOM | On main (watch lane) |
| Journal export and import | KEEP A LITTLE OF THE NIGHT | On main (data lane) |
| Translation of park text | not mentioned | Planned for wave 3; add nothing until it ships |
| Open a viewing spot in Maps | not mentioned | Planned; add nothing until it ships |

---

## The record

- **Name (≤30):** `Nyx: Dark Sky Planner` (21). Home Screen name Nyx. Fallback name: Noctis.
- **Subtitle (≤30):** `Stargazing in national parks` (28). See "Subtitle decision" below.
- **Categories:** Travel (primary), Weather (secondary).
- **Price:** Free. No subscriptions, advertising or in-app purchases (a standing condition of Open-Meteo's free, non-commercial terms).
- **Copyright:** `2026 Hardik Pakhale`.
- **Version / build:** 1.1 (8). **Manual release** after approval.
- **Platforms:** iPhone, iPad, Apple Watch (inside the iOS build), Apple Vision Pro (its own build and version page: `metadata-visionos.md`).

---

## Promotional text (≤170)

Primary:

```
Which park, and which night, for the darkest sky. The Milky Way timed for each park, an honest forecast, and a red field mode for your eyes. Free, with no tracking.
```

[164 characters]

Alternates (promotional text changes without a new build):

- New moon weekend: `The Moon is new this weekend. See which national parks have the darkest skies each night, and when the Milky Way clears the horizon. Free, no account, no tracking.` [163]
- Geminids, December 2026: `The Geminids peak December 13 to 14 under a thin evening Moon that sets early. See which national park skies are darkest each night. Free, no account, no tracking.` [163]

---

## Description (≤4000)

```
Which park, and which night? Nyx compares the 63 US national parks night by night and gives each a Darkness Score from 0 to 100, from the Moon, the clouds, the sky glow and the hours of true darkness. It tells you what it doesn't know. Free. No account, no ads, no tracking.

ONE SCORE, WITH ITS REASONS
Four parts add up, and the weakest can cap the total, so a cloudy night never looks good. The line under the score names the cap. Park closures from the National Park Service sit beside the number.

PLAN
See tonight's darkest parks within a straight-line radius, or sort every park by darkness. Choose a park and see its month as a calendar, with the best stretch of nights marked. Scrub thirty nights on a timeline and watch the Moon change shape. Give Nyx your free nights and it suggests a park for each. Times are always park-local.

AN HONEST FORECAST
For the next few days the cloud forecast counts in full. Further out it is eased toward each park's usual clouds for the month, and beyond the forecast the usual clouds count alone; those nights say so. Three weather models are compared, with the range drawn when they disagree. Cloud layers, dew, cold and wind are shown for the dark hours, and heavy smoke can cap the score.

WHAT'S UP TONIGHT
Each park's night lists the Milky Way core with its rise, highest point and Moon-free hours; the planets; meteor showers with a rate range; and lunar eclipses the park can see. These are reasons to go. They never change the score.

FIELD MODE
At the park, "I'm here tonight" opens a red, dimmed screen for night-adapted eyes: a countdown to true darkness, each milestone of the night, and a dark-adaptation clock. "Where to look" turns the real sky to wherever you point your iPhone, with no camera. A Live Activity keeps the countdown on the Lock Screen, and alarms can wake you for true darkness or the core's rise.

ON YOUR WRIST AND IN THE ROOM
On Apple Watch: tonight's score, the Digital Crown to look ahead, a dark-adaptation clock that taps your wrist, and complications that turn red at dusk. On Apple Vision Pro: stand under a park's computed sky on a chosen night, with star names and constellation figures, and place the Moon on your table, lit at its true phase. On iPad: the calendar and a park side by side.

SKY GLOW AND ACCESS
Each viewing spot shows how its sky glow compares with the other parks, from NASA's Black Marble night-lights data, and which towns light its horizon. It compares places; it is not a measurement. Step-free notes quote the park's own accessibility pages.

KEEP A LITTLE OF THE NIGHT
Save parks and get optional local reminders for promising nights. Keep a private journal with notes and selected photos; each night becomes a star in your own constellation. Export it as a file you keep. Widgets show the best sky among your saved parks.

FOR MORE PEOPLE
Nyx is designed for VoiceOver and the largest text sizes. Audio graphs let you hear a month of darkness, haptics can follow the Moon's phase, and a red mode keeps the whole app readable to night-adapted eyes. Spanish is included.

PRIVATE AND OFFLINE
Your location, journal and photos stay on your device. Three public services supply data, each with its own switch under Your privacy: park alerts from the National Park Service, and forecasts and smoke from Open-Meteo. They never receive your location. The Moon, twilight, the Milky Way, the park library, the calendar and your journal work without a connection.

PLEASE NOTE
Scores are planning estimates. They do not confirm clear skies or open roads. Check current park conditions before you travel.

Weather data by Open-Meteo.com (CC BY 4.0). Smoke and usual clouds: Copernicus (CAMS, C3S). Night lights and Moon imagery: NASA. Meteor showers: IMO. Lunar eclipses: Fred Espenak, NASA's GSFC. Park data: National Park Service. Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.
```

[3,936 of 4,000 characters; 3,971 if each line break counts twice]

Notes:
- The opening three lines are what shows before "more" on the product page; they carry the question, the answer and the promise (ST-3).
- **Accessibility sentence (C11).** "Designed for VoiceOver and the largest text sizes" says what the simulator audit and the design work support. Do not list Reduce Motion, Reduce Transparency, Increase Contrast, Bold Text or Voice Control as supported in the description until the device pass in `accessibility-nutrition-labels.md` confirms them; then the sentence may become "Nyx works with VoiceOver, larger text, …".
- Smoke is described as a cap (score v2), not as "a caveat, never points", which is no longer true.
- "Nyx is not affiliated with or endorsed by … DarkSky International" is added (C10); no DarkSky logo is used anywhere.
- Alarms need iOS 26.1 or later on device (AlarmKit); the description does not promise a version, and the app hides the alarm rows where they cannot work.

---

## Keywords (≤100)

```
milky way,meteor shower,moon phase,astronomy,light pollution,astrophotography,planet,eclipse,night
```

[98 characters]

Rules: App Store indexes the name, subtitle and keywords together, so no word repeats across them. The name already holds "Nyx", "Dark", "Sky", "Planner"; the subtitle holds "Stargazing", "national", "parks". Singular matches plural.

Changes from the draft of 2026-10-05 (`stargazing,milky way,meteor shower,moon phase,national park,astronomy,bortle,planet,eclipse,star`):
- `stargazing` and `national park` moved into the subtitle, where they weigh more.
- Added `light pollution` and `astrophotography` (the Milky Way photographers are a core audience, ST-3) and `night` (pairs with "sky" from the name for "night sky").
- Dropped `bortle` (low search volume) and `star` (generic).
- `aurora` stays out: Nyx does not forecast aurora.

Spanish keywords: `metadata-es.md`.

---

## Subtitle decision

**`Stargazing in national parks` (28).** Logged reasoning: the name already says "Dark Sky Planner", so the subtitle's job is the two highest-intent search words the name lacks, "stargazing" and "national parks", in the field the store weighs above keywords (ST-3). It also tells people who remember Apple's discontinued Dark Sky weather app that this is a stargazing planner, not a weather app (AM-11). AM-11's preference for `The night sky, park by park` rested on avoiding a repeat of "dark" and "sky", which this subtitle also avoids. The calmer line survives as the website's and press kit's tagline. A subtitle changes only with a new version, so revisit with 1.2 using App Store Connect's search-term data.

Spanish subtitle: `metadata-es.md`.

---

## Other fields

- **Age rating:** answer the current questionnaire. Expected result 4+: no user-generated content feed, no unrestricted web access (links open in Safari), no social features, no gambling or mature themes. New question (September 2026), social media capabilities: **No**. Age assurance (Texas SB 2420) is handled in the app by Declared Age Range; see `SUBMISSION.md`.
- **App Privacy:** Data Not Collected (`PRIVACY.md`).
- **Review notes:** `SUBMISSION.md` § Review notes (paste from there).
- **Screenshots:** `SUBMISSION.md` § Screenshots. The build 7 frames show scores computed before score v2 (for example Joshua Tree 93); they must be recaptured from build 8 before upload.
- **App Preview (optional):** `app-preview-script.md`.
- **Accessibility Nutrition Labels:** declare only what the device pass confirms (`accessibility-nutrition-labels.md`).
- **Creative assets (optional):** product page header (21:9) and search result asset (3:2) can wait for 1.2.

## Count table

| Field | Limit | Characters |
|---|---|---|
| Name | 30 | 21 |
| Subtitle | 30 | 28 |
| Promotional text (primary) | 170 | 164 |
| Description | 4,000 | 3,936 |
| Keywords | 100 | 98 |
