# Nyx

A dark-sky planner for iPhone, iPad, Apple Watch and Apple Vision Pro.

Nyx gives every night a darkness score from 0 to 100 so you can pick where to go and which night to take off. It looks at the Moon, cloud cover, sky glow and how long true darkness lasts. It covers the 63 US national parks, about 3,400 national parks and dark-sky places around the world, and any spot you save.

No account, no ads, no tracking, no backend. Everything is computed on the device and the core app works offline.

[App Store](https://apps.apple.com/app/id6818817800) · [Website](https://get-nyx.com) · [Privacy](https://get-nyx.com/privacy) · [Support](https://get-nyx.com/support)

## Features

- **Tonight** – the darkest places near you, with the score and what it's made of.
- **Parks** – every park with tonight's score, a map, alerts and closures from the NPS, viewing spots and ranger night-sky programs.
- **Plan** – a month of nights per park, with the best new-moon window marked.
- **Journal** – nights you've been out, with notes and photos. Stays on the device.
- **Field mode** – a red, full-screen view for the night itself: countdown to true darkness, moonrise and moonset, where the Milky Way core is, a dark-adaptation clock.
- **Widgets, Live Activity, Siri and Shortcuts**, Control Center controls.
- **Apple Watch** app and complications. **Vision Pro** app with an immersive sky.
- English, Spanish, German, French and Japanese.

## How the score works

| Part | Points |
|---|---|
| Moon: how much moonlight falls during true darkness (phase and height) | 40 |
| Clouds: average cover over the dark window, inverted | 25 |
| Sky darkness: Bortle class | 20 |
| Length of astronomical darkness, up to 10 hours | 15 |

90+ Pristine, 75+ Excellent, 60+ Good, 40+ Fair, below that Poor.

The weakest condition then caps the total, so a moonless night under heavy cloud or next to a city can't score well just because the other parts are good. No true darkness (Alaska in summer) caps a night at 39, and smoke caps it at Good or Fair. Past the ~16 day forecast, clouds come from each place's usual cover for the month (ERA5, 2015–2024) and the night is labelled that way. The details are in [`ScoreEngine.swift`](Nyx/Services/ScoreEngine.swift).

The astronomy runs on the device: NOAA solar equations for sunrise, sunset and twilight, and a low-precision Meeus lunar model for the Moon. Moonrise and moonset are good to about ±15 minutes, more at difficult horizons. Results were checked against USNO data, including polar and tropical cases.

## Privacy

Nyx only talks to three hosts, each with its own switch in Settings › Your privacy:

- `developer.nps.gov` – park alerts, events and campgrounds
- `api.open-meteo.com` – cloud forecasts
- `air-quality-api.open-meteo.com` – smoke and haze

Your location isn't sent anywhere. A saved spot's coordinates are rounded to 0.1° (about 11 km) before its forecast is requested. Notifications are local. The App Store privacy label is "Data Not Collected". Full details in [PRIVACY.md](PRIVACY.md).

## Building

You need Xcode 27 and an iOS 26 simulator or device.

1. Open `Nyx.xcodeproj` and run the **Nyx** scheme.
2. For a device, change the team and register the bundle IDs and the App Group `group.com.harrypakhale.nyx` under your account.

The project file is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. Source folders are synchronized, so adding files doesn't need a project change. To change targets or settings, edit `project.yml` and run `xcodegen generate`.

### NPS API key (optional)

The app works without a key using the bundled park data. To get live alerts and events, get a free key at [developer.nps.gov](https://developer.nps.gov/) and create `Config/Secrets.xcconfig` (it's git-ignored):

```
NPS_API_KEY = your_key
```

### Other targets

- **NyxWatch** – watchOS 26. It's embedded in the iOS app, so the Nyx scheme builds it too. The watch never uses the network; it gets saved parks and forecasts from the iPhone.
- **NyxVision** – visionOS 26. It makes the iPhone's optional requests (clouds, smoke, park alerts), each behind its own switch, and reads `NPS_API_KEY` from the same xcconfig.

### Tests

```sh
xcodebuild test -project Nyx.xcodeproj -scheme Nyx \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Unit tests use Swift Testing. The UI tests include Apple's accessibility audit across the main screens, in both palettes and at the largest text size.

DEBUG builds accept launch arguments that open a screen in a fixed state, e.g. `-nyx-screen detail -nyx-park deva -nyx-state offline`. See `Nyx/App/DebugScenario.swift`.

## Project layout

| Path | |
|---|---|
| `Nyx/` | iPhone and iPad app: `App`, `DesignSystem` (gauge, moon, sky arc, time river, starfield), `Models`, `Services` (astronomy, score, forecasts, notifications), `Views`, `Intents`, `Resources` |
| `NyxWidgets/` | Widgets, controls and the field-mode Live Activity |
| `NyxWatch/`, `NyxWatchWidgets/`, `NyxWatchShared/` | Apple Watch app and complications |
| `NyxVision/`, `NyxVisionWidgets/` | Vision Pro app and widget |
| `NyxTests/`, `NyxUITests/` | Unit and UI tests |
| `Config/` | Info.plists, entitlements, xcconfig |
| `docs/` | The website, get-nyx.com |

No third-party packages.

## Data sources

- Weather: [Open-Meteo](https://open-meteo.com/) (CC BY 4.0). Smoke and haze contain modified Copernicus Atmosphere Monitoring Service information, via Open-Meteo.
- Usual cloud cover: ERA5 reanalysis 2015–2024 (Hersbach et al. 2020), modified Copernicus Climate Change Service information, CC BY 4.0. Neither the European Commission nor ECMWF is responsible for any use of it.
- Sky glow: NASA Black Marble nighttime lights (VNP46A4), public domain.
- Parks, alerts, events: National Park Service.
- World parks and dark-sky places: [Wikidata](https://www.wikidata.org/) (CC0).
- Towns: [GeoNames](https://www.geonames.org/) (CC BY 4.0) and the US Census Bureau.
- World map: Natural Earth. US outline: US Census Bureau.
- Stars: Yale Bright Star Catalogue; star names from the IAU Working Group on Star Names.
- Moon: NASA LRO colour map and LOLA elevation (CGI Moon Kit).
- Meteor showers: International Meteor Organization 2026 calendar. Lunar eclipses: Fred Espenak, NASA/GSFC.
- Planets: Paul Schlyter's orbital elements. Aurora: IGRF-14 geomagnetic latitude (IAGA, via NOAA NCEI).

No endorsement by the NPS, NASA or DarkSky International is implied.

## Licence

Copyright © 2026 Hardik Pakhale. All rights reserved.

The source is public so people can see how Nyx works and what it does with data. It isn't licensed for reuse or redistribution. Bundled third-party data keeps its own licence.

Security issues: see [SECURITY.md](SECURITY.md).
