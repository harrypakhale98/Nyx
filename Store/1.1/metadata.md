# Nyx 1.3 — App Store metadata (update)

Paste-ready copy for App Store Connect. Nyx 1.1 is live and **version 1.2 (8) is approved** (released when the owner chooses); **version 1.3 (10)** is the next update, uploaded on 2026-10-09, so What's New is required (below). Voice: calm, precise, plain, honest about uncertainty. No exclamation marks, no marketing adjectives, nothing says "only", "first" or "best".

Character counts were verified with a script on 2026-10-07 (`len()` of the text between the fences; App Store Connect may count a line break as two characters, so each field keeps a margin). Apple's limits: name 30, subtitle 30, promotional text 170, description 4,000, keywords 100.

## Confirm before pasting (integrator)

The description and What's New name features from main. Each row below was checked against the code on main on 2026-10-08. Before pasting, confirm the build you submit still has it, and delete its sentence if not:

| Feature | Where it appears | Status on main, 2026-10-08 |
|---|---|---|
| Plan tab with "My free nights" (trip planner) | PLAN | In build 8 (`PlanView`, `TripPlannerView`; the tabs are Tonight, Parks, Plan, Journal) |
| Starting from a town or city (Census places) | What's New | In build 8 (`StartingPointPicker`, bundled `places.json`) |
| Spanish (Mexico) in the app | Last line of FOR MORE PEOPLE | In build 8 (the String Catalogs hold `es`); cut the line if the native review is not done (AM-12) |
| Apple Vision Pro: star names, constellation figures, Moon on your table, widget | ON YOUR WRIST AND IN THE ROOM | In build 8 (`star-names.json`, `constellations.json`, `MoonVolume`, `NyxVisionWidgets`); the visionOS build is a separate upload |
| Apple Watch: Crown scrub, adaptation clock, Red light control, Moon and Next dark complications | ON YOUR WRIST AND IN THE ROOM | In build 8 (`WatchViews`, `DarkAdaptation`, `NyxWatchWidgetsBundle`) |
| Journal export and import | KEEP A LITTLE OF THE NIGHT | In build 8 (`JournalArchive`) |
| Follow this night (Live Activity), Handoff, Assistive Access | What's New | In build 8 (`BestNightIntent`, `Handoff.swift`, `AssistiveAccessViews`) |
| Where to look by sound, Feel tonight, map of every park | What's New | In build 8 (`SkyBeacon`, `MoonHaptics`, `TonightMapView`) |
| Photo descriptions in the journal | What's New | In build 8, but only on iOS 27 with Apple Intelligence; the sentence is accurate only for those devices |
| Translation of park text | not mentioned | Shipped in build 8 (`TranslateButton`); optional to add to the description |
| Open a viewing spot in Maps | not mentioned | Shipped in build 8 ("Directions in Maps", `SkyGlowViews`); optional to add to the description |

---

## The record

- **Name (≤30):** `Nyx: Dark Sky Planner` (21). Home Screen name Nyx. Fallback name: Noctis.
- **Subtitle (≤30):** `Stargazing in national parks` (28). See "Subtitle decision" below.
- **Categories:** Travel (primary), Weather (secondary).
- **Price:** Free. No subscriptions, advertising or in-app purchases (a standing condition of Open-Meteo's free, non-commercial terms).
- **Copyright:** `2026 Hardik Pakhale`.
- **Version / build:** 1.3 (10) (1.2 (8) is approved; App Store Connect closed the 1.2 train, so build 10 ships as 1.3). **Phased release** (seven days, pausable), as in `SUBMISSION.md`; release the version by hand after approval, once the offline check on the App Store build passes (checklist steps 7 and 8).
- **Platforms:** iPhone, iPad, Apple Watch (inside the iOS build), Apple Vision Pro (its own build and version page: `metadata-visionos.md`).

---

## What's New in 1.3 (≤4000)

Paste one of these on the 1.3 version page. It describes what changed since build 8, the approved 1.2: the October 8 team review and the October 9 award panel and round two (`DECISIONS.md`, `PHASE_STATUS.md`). If 1.2 is never released, 1.3 also carries everything in 1.2's text below; then paste 1.2's short text first (without its last sentence) and this full text after it (about 3,300 characters together; 1.2's full text and this one come to about 4,520, over the limit). Each claim was checked against the code on main on 2026-10-09 (table below).

**Full (2,804 characters; 2,822 if each line break counts twice):**

```
Nyx 1.3 looks more closely at the sky itself, and at how the app tells you what it knows.

A Moon you could print. On the large Moons, craters now catch the light along the terminator, drawn from NASA's LOLA elevation data, and a small Moon near new keeps a faint edge instead of reading as a hole. The share card leads with the night: the Moon, the score, the park, the date and the reason. It is always sent in full color, even from night vision.

An honest dial. The score counts up with no word beside it, and the band word arrives only when the number lands in its band, so the two never disagree. When the forecast models disagree, the dial draws their range and says it in words. The four parts of a score's breakdown now always add up to the score it names.

Tonight's sky, named. The full-screen sky arrives as your eyes would adapt, brightest stars first, then names up to six of the brightest stars in view and draws faint constellation figures. Fling it and it coasts to a stop. On a night without true darkness, the sky behind the app shows that night's twilight, with no stars under the midnight sun.

What city light takes. A park's Sky glow panel can switch its own sky to the same sky seen from a city, as an illustration. The line naming the towns on its horizon now says how much of the city light around the park lies in each direction. The essay "A sky worth protecting" quotes its sources and links to Globe at Night.

Under your finger. Touch and hold the shape of the night on a park's page to read any hour; on iPhone, feel it hum through the night under your finger. With VoiceOver, double-tap it and slide a finger to feel the same night. The time river's loupe shows the night and score under your finger, and Plan's month follows your finger as you swipe. A Directions row opens Maps at a step-free viewing spot first, where the park has one.

Tonight, in order. The answer comes first, then other skies within reach, then your starting point. The tab bar shrinks as you scroll. The night vision switch is now a flashlight, and the screen dips to black before it turns red.

A followed night follows the forecast. Its Live Activity updates the score and any closure, and says when the score is old.

Also new: a night you record arrives in your journal's constellation as a new star; field mode says each fact once; outlines and marks grow heavier with Bold Text and Increase Contrast; Assistive Access gains a Red light switch; pull to refresh says what happened; widgets and Apple Watch show closures for any park; watch complications open their own park and night. On devices with Apple Intelligence, Ask Nyx shows only words whose numbers appear in its records, lists each lookup as it happens and shows the records it cites first.

Still no account, no ads, no tracking.
```

**Short (493 characters):**

```
A Moon with craters along its terminator, from NASA elevation data, and a share card that leads with the night. An honest dial: the band word arrives only with its number, and the forecast models' range is drawn when they disagree. Tonight's sky names its brightest stars and coasts when flung. Switch a park's sky to the same sky from a city. Touch and hold the shape of the night to read any hour. A followed night's Live Activity follows the forecast. Still no account, no ads, no tracking.
```

| Claim | Where it is on main, 2026-10-09 |
|---|---|
| Crater relief from LOLA on large Moons; faint edge on small Moons | `Moon.metal` (`nyxMoonRelief`), `MoonView.swift`, `MoonRelief.xcassets` |
| Share card leads with the night, always in full color | `ShareCard.swift` ("Shares a full-color image.") |
| Band word only with its number; models' range on the dial in words | `CelestialGauge.swift` ("Forecast models: …") |
| Breakdown parts add up to the sum | `DarknessScore.displayedParts` (`SkyConditions.swift`), `ScoreReadout.swift` |
| Eyes-adapting sky, up to six star names, constellation figures, coasting | `TonightSkyView.swift` ("As your eyes adapt"), `SkyLore.swift`, `PanoramaSky.swift` |
| Twilight sky on nights without true darkness, no stars under the midnight sun | `RealSky.swift` (`Visibility(sunAltitude:)`) |
| City-sky switch; light-dome share by direction; essay sources and Globe at Night | `CityLight.swift` ("City · Class 8"), `SkyGlow.swift` ("Glow on the horizon"), `learn/darkness.md` |
| Touch and hold the sky arc; VoiceOver direct touch | `SkyArc.swift` ("Touch and hold to read any hour", `accessibilityDirectTouch`), `ArcTouch.swift` |
| River loupe, paging month, Directions row | `TimeRiver.swift`, `CalendarView.swift`, `NightActions.swift` ("Directions to …") |
| Tonight's order, shrinking tab bar, flashlight lamp | `TonightView.swift`, `RootView.swift` (`tabBarMinimizeBehavior`), `TabRoot.swift` |
| Live Activity follows the forecast ("as of") | `FieldActivity.swift`, `FieldServices.swift` |
| New star in the constellation; field mode once; heavier strokes; Red light in Assistive Access | `YourSkyViews.swift` ("A new star at …"), `FieldNight.swift`, `NyxTheme.swift` (`stroke`), `AssistiveAccessViews.swift` |
| Pull to refresh; closures on widgets and watch; complications open their night | `TonightView.swift`, `SavedSkySync.swift`, `WatchViews.swift` (`WatchLink`) |
| Ask Nyx's checked words, lookups, cited records first | `GuideView.swift` ("Numbers checked against the records", "other records") |

## What's New in 1.2 (≤4000) — the approved 1.2 copy

This is the 1.2 text kept for the record; 1.2 (build 8) is approved, and App Store Connect holds whatever was pasted at its submission. One clause is restored to its October 8 wording: on October 9 The place's sentence gained "where the park's sky can be switched to the same sky under a city's glow, with the towns lighting its horizon", which describes build 10 (now 1.3), not build 8. Do not paste this on the 1.3 page except as described above.

Nyx 1.1 is live (App Store ID 6818817800, released October 7, 2026), so 1.2 is an update and App Store Connect asks for What's New.

**Full (about 1,900 characters):**

```
Nyx 1.2 is a large update, shaped by a careful look at every part of the app.

A more honest score. Clouds, smoke and city light now cap a night's score instead of only subtracting from it, so an overcast desert night no longer reads Good, and a park beside a city can no longer read Pristine. Beyond the forecast, nights use each park's usual clouds for that month, and a score never rises when you go offline. The park page says what limits tonight and shows the best clear window.

Plan your nights. A new Plan tab holds the month for one park and My free nights for a trip. Start from your city, not only from a park. Follow a night and its countdown appears on your Lock Screen at dusk by itself. Add any night to Calendar, and keep it in your journal at dawn.

Park pages in three parts: Tonight; The sky, with the Moon at full size and tonight's sky full screen; and The place, with sky glow, viewing spots, campgrounds and ranger programs.

For more people. Assistive Access, a brighter red for color-blind eyes, Feel tonight through the Taptic Engine, where to look by sound with AirPods, photo descriptions in your journal, and better VoiceOver throughout.

On every device. Widgets you can set to a park, a Moon widget, an inline Lock Screen widget, Siri answers with the gauge, and Handoff. On Apple Watch, a dark-adaptation clock, Moon and Next dark complications, and the Crown through the week. On Apple Vision Pro, named stars and constellations, turning the night by hand, the Moon on your table, and tonight's clouds. On iPad, parks in their own windows and drag and drop.

Also new: a map of every park tonight, four Learn essays, and From home tonight.

Still no account, no ads, no tracking.
```

**Short (about 500 characters):**

```
A more honest score: clouds, smoke and city light now cap each night, and beyond the forecast nights use each park's usual clouds. A new Plan tab, starting from your city, and Follow this night on your Lock Screen. Park pages in three parts, with the Moon at full size. Assistive Access, Feel tonight and a brighter red. Widgets set to a park, a dark-adaptation clock on Apple Watch, named stars on Apple Vision Pro, windows on iPad. Still no account, no ads, no tracking.
```

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
Which park, and which night? Nyx compares the 63 US national parks night by night and gives each a darkness score from 0 to 100, from the Moon, the clouds, the sky glow and the hours of true darkness. It tells you what it doesn't know. Free. No account, no ads, no tracking.

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
- **Screenshots:** `SUBMISSION.md` § Screenshots. iPhone: upload the build 10 set in `Store/1.2 v10/iPhone/` on the 1.3 page (captured 2026-10-09 from build 10, so valid for 1.3 (10); real sky first; order and captions in `Store/1.2 v10/README.md`). iPad, Apple Watch and Apple Vision Pro: the build 8 set in `Store/1.1 v8/` until their own recapture. The build 7 frames in `Store/Framed/` show scores computed before score v2 (for example Joshua Tree 93).
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
