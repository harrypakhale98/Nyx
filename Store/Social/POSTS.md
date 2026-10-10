# Nyx — launch posts for X and Threads

Images (1080×1350, 4:5, fits both feeds uncropped), in posting order:

1. `01-sky.png` — "The night sky, before you go."
2. `02-tonight.png` — "Where is the sky darkest tonight?"
3. `03-calendar.png` — "Choose the night worth the drive."
4. `04-city-light.png` — "See the stars a city would hide."

**Media status (2026-10-09):** the four cards are built from the 1.2 (10) App Store frames in `Store/1.2 v10/iPhone/6.3-inch` (`swift Scripts/make_social.swift` from the repo root) and may be posted once 1.2 is live. If the device pass changes one of their screens, regenerate them after the frames are retaken. **The promo videos are not to be posted:** `nyx-promo-4x5.mp4`, `nyx-promo-9x16.mp4` and their covers predate 1.2 (they show the Calendar and Learn tabs and the score before its caps); they stay in the folder for reference only until a new video is cut from the App Preview.

Replace `[link]` with the App Store link: `https://apps.apple.com/us/app/nyx-dark-sky-planner/id6818817800`.

---

## X — single post (4 images attached)

> I built Nyx, a dark-sky planner for the 63 US national parks.
>
> It answers one question: where should I go, and on which night, for the darkest sky?
>
> Moon, clouds, sky glow and true darkness become one score.
>
> Free. No account. No tracking.
> [link]

(≈270 characters with the link, under 280.)

---

## X — thread (one image per post)

**1/5** · `01-sky.png`
> People drive hours into national parks to see the Milky Way, then arrive under a full moon or a cloud deck.
>
> I built Nyx to fix that. It tells you where the sky is darkest tonight, and which nights are worth the drive.

**2/5** · `02-tonight.png`
> Every park, every night, gets a Darkness Score from 0 to 100.
>
> 40 points for moonlight (and whether the moon is up during true darkness), 25 for cloud cover, 20 for sky glow, 15 for the hours of true darkness. The weakest part can cap the total, so a cloudy night never looks good.
>
> The park page shows the four parts and what limits the night.

**3/5** · `03-calendar.png`
> Plan marks the best five-night stretch around each new moon.
>
> After about three days the forecast eases toward each park's usual clouds, and those nights are drawn half-filled. Beyond ten days they are hollow: the usual clouds, not a forecast. It never pretends to know the weather a month out.

**4/5** (no image, or reuse `02-tonight.png`)
> All 63 parks, from Acadia to the National Park of American Samoa. Real astronomy for each one, including Alaska in June when there's no true darkness at all.
>
> Park closures show next to the score, so you don't drive four hours to a closed road.

**5/5** (no image, or reuse `01`)
> Nyx works offline once installed. No account, no ads, no tracking. Your stargazing journal stays on your phone.
>
> The next new-moon weekend is Nov 6–8.
>
> Free on the App Store: [link]

---

## Threads — single post (all 4 images as a carousel)

> I built an app for people who drive hours to see the Milky Way.
>
> Nyx is a dark-sky planner for the 63 US national parks. Moonlight, clouds, sky glow and the hours of true darkness become one Darkness Score for every park, every night.
>
> Plan marks the best nights around each new moon. Closures sit next to the score. It works offline. No account, no ads, no tracking.
>
> Free on iPhone, iPad, Apple Watch and Apple Vision Pro. [link]

(488 characters with the full link, under the 500 limit.) Topic tag: **Astronomy** (Threads allows one; alternatives: Stargazing, NationalParks).

## X — what city light takes (one image: `04-city-light.png`)

> In 58 of 63 national parks, Nyx names the towns lighting the horizon, from NASA Black Marble satellite data.
>
> It draws the park's sky beside the same sky at a city's class 8, labelled an illustration.
>
> Globe at Night opens in Safari. Nyx sends nothing.
> [link]

(276 characters, the link counted as 23, under 280.) Facts from `Store/1.1/award-entries.md` (social impact, checked against the bundled data on 2026-10-09). Never say that Nyx reduces light pollution.

---

## Threads — short follow-up reply

> The next new-moon weekend is Nov 6–8. If you were planning a dark-sky trip this fall, that's the window. Nyx shows which parks look best for it.

---

## Hashtags (X, use two at most)

`#stargazing` `#NationalParks` · alternates: `#MilkyWay` `#darksky` `#iOSdev` (for the build-in-public crowd)

## Alt text (paste into each image's description)

1. Nyx's full-screen sky over Death Valley for Saturday, July 3, at 12:55 AM, facing south. Headline: "The night sky, before you go." The Milky Way rises from the southern horizon with its core labelled; Altair and Antares are named, and faint lines trace their constellations.
2. Nyx's Tonight screen for Friday, October 9. Headline: "Where is the sky darkest tonight?" Death Valley is the darkest park within 200 miles, with a Darkness Score of 97, Pristine, on an amber dial. Below it: "No closures listed, check alerts before you go."
3. Nyx's Plan tab for Joshua Tree, October 2026. Headline: "Choose the night worth the drive." Each night is a dot sized by its score, with the score beneath; October 13 to 17, the nights around the new moon, are ringed, with scores of 88 and 89.
4. Nyx's Sky glow panel for Death Valley. Headline: "See the stars a city would hide." A drawn sky full of stars and the Milky Way, a switch between "Here, Class 2" and "City, Class 8", and the note "An illustration: the same sky drawn at this park's estimated class and at a city's." Below: Bortle estimate, Class 2 of 9.

## Notes

- The cards are built from the 1.2 (10) store frames, real captures with live Open-Meteo forecasts and NPS alerts from October 9, 2026, scored by the shipping engine (`Store/1.2 v10/README.md`). The sky card is a computed night (July 3, 2027) with its date on screen. No numbers were staged.
- Tone matches the app: calm, no exclamation points, honest about uncertainty.
- Nyx isn't affiliated with the National Park Service. Avoid NPS logos or arrowheads in any reposts or edits.
