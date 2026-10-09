# Nyx — launch posts for X and Threads

Images (1080×1350, 4:5, fits both feeds uncropped), in posting order:

1. `01-tonight.png` — "Where is the sky darkest tonight?"
2. `02-score.png` — "Follow the moon. Find the darker nights."
3. `03-calendar.png` — "Choose the night worth the drive."
4. `04-parks.png` — "Every park, scored every night."

**Media status (2026-10-09): pre-1.2, do not post; regenerate after the store recapture.** This covers the four 4:5 cards above and the promo video (`nyx-promo-4x5.mp4`, `nyx-promo-9x16.mp4` and their covers): they show the tabs before 1.2 (Calendar, Learn) and the score before its caps. `swift Scripts/make_social.swift` (from the repo root) now builds the cards from the 1.2 App Store frames in `Store/1.1 v8/iPhone`; run it after the 1.2 store recapture, then rewrite the alt text below to match.

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

**1/5** · `01-tonight.png`
> People drive hours into national parks to see the Milky Way, then arrive under a full moon or a cloud deck.
>
> I built Nyx to fix that. It tells you where the sky is darkest tonight, and which nights are worth the drive.

**2/5** · `02-score.png`
> Every park, every night, gets a Darkness Score from 0 to 100.
>
> 40 points for moonlight (and whether the moon is up during true darkness), 25 for cloud cover, 20 for sky glow, 15 for the hours of true darkness. The weakest part can cap the total, so a cloudy night never looks good.
>
> The park page shows the four parts and what limits the night.

**3/5** · `03-calendar.png`
> Plan marks the best five-night stretch around each new moon.
>
> After about three days the forecast eases toward each park's usual clouds, and those nights are drawn half-filled. Beyond ten days they are hollow: the usual clouds, not a forecast. It never pretends to know the weather a month out.

**4/5** · `04-parks.png`
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
> Nyx is a dark-sky planner for the 63 US national parks. It combines moonlight, cloud cover, sky glow and the hours of true darkness into one Darkness Score for every park, every night.
>
> Plan highlights the best nights around each new moon. Park closures sit next to the score. It works offline, and there's no account, no ads and no tracking.
>
> Free on iPhone. [link]

(≈450 characters with the link, under the 500 limit.) Topic tag: **Astronomy** (Threads allows one; alternatives: Stargazing, NationalParks).

## Threads — short follow-up reply

> The next new-moon weekend is Nov 6–8. If you were planning a dark-sky trip this fall, that's the window. Nyx shows which parks look best for it.

---

## Hashtags (X, use two at most)

`#stargazing` `#NationalParks` · alternates: `#MilkyWay` `#darksky` `#iOSdev` (for the build-in-public crowd)

## Alt text (paste into each image's description)

These describe the pre-1.2 cards. Rewrite them when the cards are regenerated.

1. Nyx's Tonight screen over a dark starfield. Headline: "Where is the sky darkest tonight?" Joshua Tree is the darkest nearby sky, with a Darkness Score of 85, Excellent, on an amber dial. A trail closure notice sits below the score.
2. Nyx park detail for Joshua Tree. Headline: "Follow the moon. Find the darker nights." A score dial reads 85, Excellent. Below it, a 30-night timeline rises and falls with the moon; nights past the weather forecast are drawn hollow.
3. Nyx calendar for Joshua Tree, October 2026. Headline: "Choose the night worth the drive." Each night shows a dot sized by its score; October 8 to 12 are ringed as the new-moon window, with scores up to 95.
4. Nyx park list. Headline: "Every park, scored every night." Acadia 83 Excellent, Arches 71 Good, Badlands 69 Good, Big Bend 66 Good, Biscayne 58 Fair.

## Notes

- The current cards are real captures with live Open-Meteo forecasts from Oct 3, scored by the engine of that week. No numbers were staged. The 1.2 store frames they will be rebuilt from are live captures too (`Store/1.1 v8/README.md`).
- Tone matches the app: calm, no exclamation points, honest about uncertainty.
- Nyx isn't affiliated with the National Park Service. Avoid NPS logos or arrowheads in any reposts or edits.
