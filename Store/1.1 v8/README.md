# App Store screenshots: Nyx 1.2 (8)

English, one size per device. File order is upload order. Every frame is flattened (no alpha) and exactly the slot's size.

The screens come from the build 8 source (`73da980`), Debug build, on simulators, captured October 8, 2026. They use live data (`-nyx-state live`: real Open-Meteo forecasts and NPS alerts, scored by the shipping engine). The one exception is the journal, which uses the DEBUG seed (`-nyx-state populated`, sample entries, no personal photos). The status bar shows 9:41 with a full battery. Field mode and "Where to look" have no status bar, as on a device, where field mode hides it.

Frames use the design in `Scripts/make_store_frames.swift`: an eyebrow, a serif caption, and the full uncropped screen on a starfield. Field mode is drawn in signal red. Captions are calm, six words or fewer, with no prices, no "new" and no exclamation marks.

## iPhone

Slot: **iPhone, "Dynamic Island, medium display" (6.3-inch), 1206 × 2622**, the required iPhone size. Captured natively at 1206 × 2622 on iPhone 17 (iOS 27).

| File | Caption (eyebrow / headline) | What it shows | Size | Slot |
|---|---|---|---|---|
| `iPhone/01-tonight.png` | TONIGHT / Where is the sky darkest tonight? | Tonight from Las Vegas, NV: Death Valley 97 Pristine within 200 mi as the crow flies, "No closures in the last park update", and the start of "More skies within reach" | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/02-score.png` | THE DARKNESS SCORE / One number, and its reasons. | Death Valley's page, Tonight chapter: gauge 97 Pristine, best window 7:50 PM – 5:30 AM with the core's hours, and the four parts (Moonlight 40/40, Clouds 25/25, Sky glow 18/20, True darkness 14/15) | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/03-tonights-sky.png` | TONIGHT'S SKY / The night sky, before you go. | Full-screen "Tonight's sky over Death Valley" facing south at 12:55 AM on Sat, Jul 3 (2027, a new-moon summer night), with the Milky Way core, the time slider and the compass buttons. The date is shown on screen. | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/04-whats-up.png` | WHAT'S UP TONIGHT / The Milky Way, and when to look. | What's up tonight at Death Valley: the Milky Way core 7:47–8:38 PM, Jupiter, Saturn, Mars, the Draconids, zodiacal light and satellites | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/05-field-mode.png` | FIELD MODE / Red light for dark-adapted eyes. | Field mode at Joshua Tree, 60 minutes after sunset: "True darkness in 23 min", the night's moments, eyes adjusting | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/06-where-to-look.png` | WHERE TO LOOK / Point your iPhone. Find the core. | Where to look at Joshua Tree on July 3, 2027, about 3¾ hours after sunset: the core in the south and Mars. Beyond the forecast, so the header says the score uses the park's usual clouds. | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/07-plan.png` | BEST NIGHTS / Choose the night worth the drive. | Plan, One park: Joshua Tree's October 2026 month, nights sized by score, the new-moon window ringed, the best stretch (Oct 12–16) | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/08-parks-map.png` | EVERY PARK TONIGHT / 63 parks, darkest first. | Parks map: all 63 parks tonight (Alaska, Hawaiʻi, American Samoa and Virgin Islands inset), legend, "Darkest tonight" list | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/09-constellation.png` | YOUR CONSTELLATION / Every night becomes a star. Footnote: "Sample entries. Your journal stays on this iPhone." | Journal: the constellation map from four sample nights, "Your year under the stars" | 1206 × 2622 | iPhone 6.3" (required) |
| `iPhone/10-every-sky.png` | SKY GLOW AND ACCESS / City glow, named. Step-free spots, marked. | Death Valley: Bortle 2 estimate, night lights from space, glow from Las Vegas, Ridgecrest and Visalia, and step-free notes for Harmony Borax Works and Mesquite Flat Sand Dunes | 1206 × 2622 | iPhone 6.3" (required) |

## iPad

Slot: **iPad 13-inch, 2064 × 2752 portrait**. Captured natively in portrait on iPad Pro 13-inch (M5), iOS 27.

| File | Caption (eyebrow / headline) | What it shows | Size | Slot |
|---|---|---|---|---|
| `iPad/01-tonight.png` | TONIGHT / Where is the sky darkest tonight? | Tonight from Joshua Tree: Death Valley 97 Pristine, the next 30 nights, the sky over the starting point, and "The next 7 nights in reach" across parks with the week's best night ringed | 2064 × 2752 | iPad 13" |
| `iPad/02-score.png` | THE DARKNESS SCORE / One number, and its reasons. | Death Valley's page in two columns: gauge 97, best window, four parts, the 30-night river, and the full breakdown beside it | 2064 × 2752 | iPad 13" |
| `iPad/03-plan.png` | BEST NIGHTS / Choose the night worth the drive. | Plan: Death Valley's October 2026 month with tonight's breakdown beside it, best stretch Oct 13–17 | 2064 × 2752 | iPad 13" |
| `iPad/04-field-mode.png` | FIELD MODE / Red light for dark-adapted eyes. | Field mode at Joshua Tree: "True darkness in 23 min" and the night's moments through Jupiter rising | 2064 × 2752 | iPad 13" |
| `iPad/05-parks-map.png` | EVERY PARK TONIGHT / 63 parks, darkest first. | Parks map across the full width, legend, the five darkest parks tonight | 2064 × 2752 | iPad 13" |
| `iPad/06-constellation.png` | YOUR CONSTELLATION / Every night becomes a star. Footnote: "Sample entries. Your journal stays on this iPad." | Journal: the constellation beside four sample entries | 2064 × 2752 | iPad 13" |

### Notes

- The iPhone Moon frame ("The sky" chapter, the Moon at size) was captured but not used. The page's `-nyx-chapter moon` route stops with the "Wake me" panel cut under the chapter index, on iOS 26.5 and iOS 27 alike. The full-screen sky view is clean, so it takes slot 3. To use the Moon later, the route needs to land with the Moonlight panel at the top.
- iPad Tonight shows a small closure line ("Oasis of Mara Trail partial closure") on Joshua Tree's row in "More skies within reach". It is a park alert in a list row, not the hero line. The hero reads "No closures in the last park update".
- Scores, forecasts and alerts are live as of October 8, 2026. Recapture if the build changes what any screen shows.

## Apple Watch

Slot: **Apple Watch, 422 × 514** (Ultra class; one size covers every localization). Captured natively at 422 × 514 on Apple Watch Ultra 3 (watchOS 27), Debug build of `NyxWatch`, October 8, 2026 about 7:10 AM Pacific. The watch has no paired iPhone in the simulator, so it was handed the iPhone's context the way the iPhone sends it: saved parks Joshua Tree, Death Valley, Great Basin and Big Bend with real Open-Meteo cloud forecasts fetched at capture time, written to the watch's App Group as `watch-context.json`. Every score is computed by the watch's own engine. Routes: `-nyx-watch-screen tonight | week | dark | parks | complications`, `-nyx-watch-palette standard | red`, `-nyx-watch-night 1`, `-nyx-watch-adaptation 18`.

Framed in the design of `Scripts/make_device_frames.swift` (same Watch-Ultra layout, a copy pointed at these captures and this folder).

| File | Caption (eyebrow / headline) | What it shows | Size | Slot |
|---|---|---|---|---|
| `Apple Watch/01-tonight.png` | TONIGHT / Tonight's sky, on your wrist. | Tonight: Death Valley 97 Pristine in amber, the Moon disc, "Sunset in 11 hr, 14 min at 6:21 PM" | 422 × 514 | Apple Watch |
| `Apple Watch/02-week.png` | NEXT SEVEN NIGHTS / The darkest night this week. | The next seven nights at Death Valley (97, 97, 10, 83, 34, 45, 91), darkest Thu, Oct 8, hollow nights beyond the full forecast | 422 × 514 | Apple Watch |
| `Apple Watch/03-dark-adaptation.png` | DARK ADAPTATION / Give your eyes thirty minutes. (red) | The dark-adaptation clock running in red light, 18 of 30 minutes | 422 × 514 | Apple Watch |
| `Apple Watch/04-complications.png` | COMPLICATIONS / The whole night, at a glance. | The real complication renders (score 97, Moon 5%, Next dark 7:47 PM) in circular, corner and inline families, arranged on one black screen | 422 × 514 | Apple Watch |
| `Apple Watch/05-parks.png` | SAVED PARKS / Your parks, from your iPhone. | Parks: "Saved on iPhone" Joshua Tree 89, Death Valley 97, Great Basin 90 | 422 × 514 | Apple Watch |
| `Apple Watch/06-night-vision.png` | NIGHT VISION / The whole watch, in red light. (red) | Tonight in red, turned with the Crown to Fri, Oct 9: Death Valley 97 Pristine, "Dark 7:45 PM to 5:25 AM" | 422 × 514 | Apple Watch |

## Apple Vision Pro

Slot: **Apple Vision Pro, 3840 × 2160**. Captured natively on Apple Vision Pro (visionOS 27), Debug build of `NyxVision`. Dates are pinned with `-nyx-date` (a pinned date makes no network request); everything in the sky is computed on device. Footnotes under each screen say which night it is.

| File | Caption (eyebrow / headline) | What it shows | Size | Slot |
|---|---|---|---|---|
| `Apple Vision Pro/01-immersive-core.png` | STAND UNDER TONIGHT'S SKY / The Milky Way, where it really is. Footnote: "Joshua Tree, July 15, 2026, computed on device." | The immersive sky facing south in the middle of a new-moon summer night: the Milky Way core over the horizon, constellation figures for Sagittarius, Scorpius and their neighbours, the "Milky Way core" label and the S marker. Route: `-nyx-date 2026-07-15 -nyx-park jotr -nyx-vision-time 0.5 -nyx-vision-immersive -nyx-vision-skyonly -nyx-vision-look 340,-22` | 3840 × 2160 | Apple Vision Pro |
| `Apple Vision Pro/02-star-name.png` | THE STARS / Tap a star for its name. Footnote: "Antares in Scorpius, beside the Milky Way core." | The same sky with Antares's name card: "14° up in the southwest · Scorpius · a bright star". Route as above with `-nyx-vision-look 325,-20 -nyx-vision-body star.Antares` | 3840 × 2160 | Apple Vision Pro |
| `Apple Vision Pro/03-window.png` | NYX ON APPLE VISION PRO / The darkest night, planned in your room. Footnote: "Joshua Tree, October 8, 2026, with that day's cloud forecast." | The planner window in a room, live data: Joshua Tree 89 Excellent, "Sky glow limits tonight to 89", 0% cloud forecast (Open-Meteo, Oct 8), waning crescent 2%, What's up with the October Draconids and the Milky Way core | 3840×2160 | Apple Vision Pro |
| `Apple Vision Pro/04-moon.png` | THE MOON ON YOUR TABLE / The Moon, in its true light. Footnote: "First quarter from Joshua Tree, July 20, 2026." | The Moon volume at first quarter (47% lit), lit from the true Sun direction, with its night control ("As seen from Joshua Tree at 7:52 PM, its highest that night"). Route: `-nyx-date 2026-07-15 -nyx-park jotr -nyx-vision-moon -nyx-vision-moon-night 5`. The capture is cropped to the central 2560 × 1440 around the Moon (scaled into the frame), so the Moon leads rather than the planner window behind it | 3840 × 2160 | Apple Vision Pro |

### Notes (Watch and Vision Pro)

- The watch simulator cannot set the clock, so Tonight and the adaptation clock read "Sunset in 11 hr" from a morning capture. The night-vision frame is turned to Friday with the Crown to show a dark window instead.
- Complications: the DEBUG review screen (`-nyx-watch-screen complications`) labels its rows ("Complications", "Full colour"), so the frame uses its real renders without the labels, with circular complications clipped to their circles as on a face. A capture of a real watch face would be better; the simulator cannot set up a face from the command line.
- Parks shows Death Valley's states as "CA,NV" with no space after the comma (app data formatting, not changed here).
- The Vega name card (`-nyx-vision-body star.Vega`, look 60,-55) did not appear in its capture; Antares was used.
