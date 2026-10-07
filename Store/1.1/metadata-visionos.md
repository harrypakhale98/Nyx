# Nyx 1.1 for Apple Vision Pro — App Store metadata (English)

Paste-ready copy for the **visionOS** version page in App Store Connect (App Store tab → the visionOS platform in the sidebar → 1.1). Name, subtitle (`Stargazing in national parks`), categories, age rating, App Privacy and the privacy policy URL are shared with iPhone and set once under App Information. Description, keywords, promotional text, support and marketing URLs, screenshots and review notes belong to each platform's version page.

Updated 2026-10-07 for build 8: star names and constellation figures, turning the night by hand, the Moon on your table, the visionOS widget, and scores with each park's usual clouds (score v2). The Vision Pro app makes one optional request, the cloud forecast from Open-Meteo for the parks' public coordinates (switchable in Your privacy); nothing else leaves the headset. 1.1 is the first public release on every platform, so there is no What's New. Character counts are checked by script (in brackets).

---

## Promotional text (≤170)

```
Stand under the night sky of any national park, on any night this year, with the stars named and the Moon on your table. Computed on Apple Vision Pro. No tracking.
```

[163 of 170 characters]

---

## Description (≤4000)

```
Stand under a darker sky.

Nyx on Apple Vision Pro shows the night sky over any of the 63 US national parks, on any night in the coming year, computed on the device from the positions of the Sun, the Moon, the planets and the stars.

PLAN THE NIGHT
Browse the parks with each night's Darkness Score, from 0 to 100. Open a park to see its night: the Moon's phase and its times, the hours of true darkness, the park's estimated sky glow, and what is up, from the Milky Way core to the planets. Step through the nights ahead, scrub from sunset to sunrise, or jump to the middle of true darkness. Times are park-local.

STAND UNDER THIS SKY
Open the sky and the night surrounds you, with the room still at the edges until you turn the Digital Crown. The brightest stars are placed from the Yale Bright Star Catalogue, in their true colors, and the best known carry their names. Constellation figures can be shown or hidden. The Milky Way is a model drawn from the shape of our galaxy. Planets glow, sized by their brightness; tap a star, a planet, the Moon or the Milky Way core to see its name, its height and its direction. Drag across the sky to turn the night by hand.

THE MOON ON YOUR TABLE
Place the Moon in your room as a globe, lit by the Sun at that night's true phase and turned as the park sees it. Drag it to turn it, and it turns back to the face we always see.

THE NIGHT AS IT FALLS
Scrub the hours and the sky follows: twilight deepens through blue to black, the faintest stars appear only as twilight ends, and a bright Moon washes out the Milky Way. Each park's estimated sky glow brightens its horizon.

HONEST ABOUT WHAT IT SHOWS
The sky is computed, not a live view. South is ahead of you, where the Milky Way, the Moon and the planets cross, rather than your room's real south. Clouds are not shown. The skyline is illustrative. Nyx on Vision Pro downloads no forecasts, so each score uses the park's usual clouds for that month, and says so. For cloud forecasts, park alerts and field mode, use Nyx on iPhone.

COMFORTABLE AT NIGHT
Night vision turns the window and the sky red. The sky moves only when you move it: no twinkling and no autoplay. VoiceOver describes the whole sky and names the Moon, each planet, the bright stars and the core, and the window lists the same sky in words. Reduce Motion, Reduce Transparency and Increase Contrast are respected.

A WIDGET FOR THE WALL
Tonight's Moon: its phase, how much is lit and the next new moon, on a wall or a desk.

PRIVATE BY DESIGN
No account, no advertising, no tracking. The sky is computed on the device; the one thing Nyx fetches is the cloud forecast for the parks' public coordinates, never anything about you, and a switch in Your privacy turns it off.

PLEASE NOTE
Scores are estimates and do not confirm clear skies or safe access. Check current park conditions before traveling.

Stars: Yale Bright Star Catalogue (via NASA HEASARC). Star names: IAU Working Group on Star Names. Moon imagery: NASA's Scientific Visualization Studio; LRO LROC and LOLA teams. Usual clouds: generated using Copernicus Climate Change Service information. Park data: National Park Service. Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.
```

[3,161 of 4,000 characters; 3,192 if each line break counts twice]

Note on "Reduce Motion … respected": the vision lane built the Reduce Motion paths (the sky moves once on release; the Moon turns back instantly). Keep the sentence only if the Vision Pro device pass confirms it; otherwise cut "Reduce Motion, " (C11).

---

## Keywords (≤100)

The name and the shared subtitle are indexed with these, so no repeats of "Nyx", "Dark", "Sky", "Planner", "Stargazing", "national" or "parks". Singular matches plural.

```
milky way,planetarium,immersive,astronomy,moon phase,planet,constellation,star names,moon globe
```

[95 of 100 characters]

---

## Review notes (visionOS)

```
Nyx for Apple Vision Pro asks for no permissions and has no login. Its only network request is the cloud forecast from api.open-meteo.com for the 63 parks' public coordinates (Your privacy → Cloud forecasts switches it off). Choose a park in the window, then "Stand under this sky" to open the immersive sky (it opens with the room still visible at the edges; turn the Digital Crown for more). "Leave the sky" closes it. The clock ornament steps nights and scrubs the hours; dragging across the sky also turns the night. Tap a planet, a bright star, the Moon or the Milky Way core for its name card. "The Moon on your table" in the window toolbar opens a volumetric Moon. The sky is computed for the chosen park and night and is not aligned to the room's real north (a plaque at your feet says so). Scores use the cloud forecast for nights it covers, eased toward each park's usual clouds farther out, and say which. Credits are under the info button in the sidebar.
```

---

## Screenshots

`Store/Framed/Vision-Pro/` (four, 3840×2160, captioned, from build 7): the planner window, the core setting in the west at Joshua Tree, a moonlit Great Basin night, Jupiter's name card above the rising crescent Moon. The window frame shows a score labeled "moon and darkness only", which build 8 no longer shows; recapture it (and add a star-names frame and the Moon on your table) from build 8 before upload.

## Support and marketing URLs

Same as iPhone (`SUBMISSION.md`). The support and privacy pages cover Apple Vision Pro (updated 2026-10-07).
