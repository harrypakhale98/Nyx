# App Store screenshots: Nyx 1.2 (10), iPhone

English, iPhone only. File order is upload order. Every frame is flattened (no alpha) and exactly its slot's size. This set supersedes the iPhone frames in `Store/1.1 v8/`; the iPad, Apple Watch and Apple Vision Pro frames stay in `Store/1.1 v8/` until their own recapture, and the Spanish frames wait for the native review.

The screens come from the build 10 source (`c979be2`, plus this commit's DEBUG-only change that hides the status bar on the field-mode capture routes, as presented field mode does), Debug build, on the iOS 27 simulator, captured October 9, 2026 in the evening (Pacific). They use live data (`-nyx-state live`: real Open-Meteo forecasts and NPS alerts at capture time, scored by the shipping engine). The one exception is the journal, which uses the DEBUG seed (`-nyx-state populated`, sample entries, no personal photos); its caption says "Sample entries". Every launch adds `-nyx-reduce-motion`, so no reveal, count or dial is mid-flight. The status bar shows 9:41 with a full battery; field mode and Where to look have none, as on a device.

Reproduce: `python3 Scripts/capture_store.py <SIMULATOR> <DERIVED_DATA> en --out "Store/1.2 v10/raw"` (add a comma-separated name list to retake only those frames), then `swift Scripts/make_store_frames.swift`. Raw captures are in `raw/`.

Frames use the design in `Scripts/make_store_frames.swift`: an eyebrow, a serif caption, and the full uncropped screen on a starfield. Field mode and Where to look are drawn in signal red. Captions are calm, six words or fewer, with no prices, no "new" and no exclamation marks.

## Order

The real sky comes first, then the question the app answers, then what is up. Only one dial appears among the first three frames (Tonight); the score's own page follows as frame 4, so search results, which show the first three, never repeat a gauge. The red frames sit after it, then the calendar, what city light takes, the map and the constellation.

## Slots

Captured natively at 1206 × 2622 on iPhone 18 Pro (iOS 27.0), which is App Store Connect's required **"Dynamic Island, medium display" (6.3-inch)** size. The framer draws the screen scaled inside each frame, so one capture serves all three sizes.

| Folder | Size | Slot |
|---|---|---|
| `iPhone/6.3-inch/` | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/6.9-inch/` | 1320 × 2868 | iPhone 6.9" (optional) |
| `iPhone/6.5-inch/` | 1284 × 2778 | iPhone 6.5" (optional) |

## Files

| File | Caption (eyebrow / headline) | What it shows |
|---|---|---|
| `01-tonights-sky.png` | TONIGHT'S SKY / The night sky, before you go. | Full-screen "Tonight's sky over Death Valley" for Sat, Jul 3 (2027, a new-moon summer night) at 12:55 AM, facing south: the Milky Way rising from the horizon with the core labelled, Altair and Antares named, hairline constellation figures, the time slider (true darkness 8:10 PM to 5:35 AM) and the direction buttons. The date is on screen. Route: `-nyx-screen detail -nyx-park deva -nyx-state live -nyx-date 2027-07-03 -nyx-sky-view` (the default hour shows the core; no time control needed) |
| `02-tonight.png` | TONIGHT / Where is the sky darkest tonight? | Tonight, Fri, Oct 9: Death Valley 97 Pristine, darkest within 200 mi, "No closures listed · check alerts before you go", then Joshua Tree 65 Good under "More skies within reach" (with its trail closure on the row, not the hero) |
| `03-whats-up.png` | WHAT'S UP TONIGHT / The Milky Way, and when to look. | What's up tonight at Death Valley (the sheet opened by `nyx://whatsup?date=2026-10-09&park=deva`): the Milky Way core 7:45 – 8:34 PM, Jupiter, Saturn and Mars, the October Draconids, zodiacal light, satellites and the faintest stars. No gauge |
| `04-score.png` | THE DARKNESS SCORE / One number, and its reasons. | Death Valley's page, Tonight chapter: gauge 97 Pristine (band word and scale inside the dial), best window 7:50 PM – 5:30 AM, clear, with the core's hours, and the four parts (Moonlight 40/40, Clouds 25/25 with "Models agree", Sky glow 17/20, True darkness 15/15) |
| `05-field-mode.png` | FIELD MODE / Red light for dark-adapted eyes. | Field mode at Joshua Tree (65 Good), 60 minutes after sunset: "True darkness in 23 min, at 7:39 PM, then 9h 42m of it", the Draconids at their best, the core sinking, eyes adjusting 4 of about 30 minutes |
| `06-where-to-look.png` | WHERE TO LOOK / Point your iPhone. Find the core. | Where to look at Joshua Tree on July 3, 2027, about 3¾ hours after sunset: the core in the south under the reticle, Mars to the right. Beyond the forecast, so the header says the score (75 Excellent) uses the park's usual clouds |
| `07-calendar.png` | BEST NIGHTS / Choose the night worth the drive. | Plan, One park: Joshua Tree's October 2026, nights sized by score, the new-moon nights Oct 13–17 ringed (89, 89, 89, 89, 88), forecast, early-look and usual-cloud nights drawn filled, half and hollow, and the best stretch "Tue, Oct 13 – Sat, Oct 17" under the tab bar |
| `08-city-light.png` | WHAT CITY LIGHT TAKES / See the stars a city would hide. | Death Valley, The place: the Sky glow panel with the park's own drawn sky, the "Here · Class 2 / City · Class 8" switch, "An illustration: the same sky drawn at this park's estimated class and at a city's.", Bortle class 2 of 9, night lights from space, and the glow on the horizon from Las Vegas (45%), Ridgecrest and Visalia. Route: `-nyx-screen light -nyx-state live -nyx-park deva` (the default "Here" state) |
| `09-parks-map.png` | EVERY PARK TONIGHT / 63 parks, darkest first. | Parks map: all 63 parks tonight with the Alaska, Hawaiʻi, American Samoa and Virgin Islands insets, the legend, and "Darkest tonight": Lassen Volcanic, Death Valley and Guadalupe Mountains at 97 |
| `10-constellation.png` | YOUR CONSTELLATION / Every night becomes a star. Footnote: "Sample entries. Your journal stays on this iPhone." | Journal: the constellation from four sample nights in the Southwest, "4 of 63 national park skies", "Your year under the stars" |

## Notes

- **Retakes.** Three frames were retaken after the first pass. The score frame first showed the default park (Joshua Tree 65) with its "Oasis of Mara Trail partial closure" line under the title, which dominated the hero and did not match Tonight's lead park; it now shows Death Valley (`-nyx-park deva`), the park Tonight and What's up show, with the same 97. Field mode and Where to look showed the white status bar over red: the DEBUG field routes draw field mode inside the root view, whose status-bar preference won over field mode's; the routes now hide it, as presented field mode does on a device.
- **City light.** The default "Here · Class 2" state was used: the switch is legible and the "An illustration" caption is in frame, and the park's own stars are what the caption asks the reader to see. `-nyx-glow-compare city` was not needed.
- **Times.** What's up gives the core's hours to the minute (7:45 – 8:34 PM); the score page's best-window line gives them to the nearest ten minutes (7:50 – 8:30 PM). Both are the app's own rounding of the same night.
- The calendar's best-stretch card sits under the tab bar, with its dates legible; the route has no scroll control for the Plan tab, and the month is the frame's subject.
- Scores, forecasts and alerts are live as of October 9, 2026. The owner's device pass (`INPUT_NEEDED.md` step 9) may still require a retake of any frame whose screen it changes.
- Social cards (`Store/Social/`) are built from `iPhone/6.3-inch/` frames 01, 02, 07 and 08 by `Scripts/make_social.swift`.
