# Nyx

A calm, offline-first dark-sky planner for the 63 US national parks. Nyx weighs moonlight, clouds, estimated skyglow and the length of true darkness into one Darkness Score (0–100) per park per night, so you can choose where to go and which night to take off. No accounts, advertising, tracking, backend or third-party runtime packages.

Website, support and privacy pages: [get-nyx.com](https://get-nyx.com/), served from `docs/` by a Cloudflare Worker that deploys on every push to `main` (`wrangler.jsonc`: 404 page and clean URLs; `docs/_headers`: security headers) (GitHub Pages still serves the same folder at harrypakhale98.github.io/Nyx for links in older builds).

## Version

**1.1 (7)**, archived 2026-10-06. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` live in `project.yml` and every target inherits them. 1.1 adds What's up tonight, an honest forecast (three models, cloud layers, dew, smoke and haze from a third optional host), field mode, Apple Watch, Apple Vision Pro, iPad, measured sky glow and step-free spots, audio graphs and Listen to tonight, Spanish, the trip planner and your constellation. 1.0 (5) was the last build on the store before it.

Release steps: [SUBMISSION.md](SUBMISSION.md) and [INPUT_NEEDED.md](INPUT_NEEDED.md). Archive checks: `python3 Scripts/verify_release.py IOS_ARCHIVE [VISION_ARCHIVE]` (writes `Research/release-verification.json` and never prints the NPS key).

## Repository

| Path | What it holds |
|---|---|
| `Nyx/` | The iPhone and iPad app: `App` (entry, tab shell, deep links, DEBUG scenarios), `DesignSystem` (gauge, moon disc and shader, sky arc, time river, starfield, theme), `Models`, `Services` (astronomy, score, forecasts, notifications, watch bridge), `Views`, `Intents`, `Resources` (bundled data, String Catalogs, Learn essays, app icons) |
| `NyxWidgets/` | Home Screen, Lock Screen and StandBy widgets, Control Center controls, the field-mode Live Activity |
| `NyxWatch/`, `NyxWatchWidgets/`, `NyxWatchShared/` | Apple Watch app and complications |
| `NyxVision/` | Apple Vision Pro planner window and immersive sky |
| `NyxTests/`, `NyxUITests/` | Swift Testing suite; XCTest UI, launch and accessibility-audit tests |
| `Config/` | Info.plists, entitlements, `Nyx.xcconfig` (and your git-ignored `Secrets.xcconfig`) |
| `Scripts/` | Data builders, catalog sync, translation merge, screenshot capture, store frames, release verification, the promo video |
| `Research/` | Sources and evidence behind the bundled data: accuracy against USNO, sky glow, cloud climate, contrast, performance, localization memory, review screenshots |
| `Store/` | App Store metadata, screenshots (raw and captioned), In-App Event media, social posts |
| `docs/` | The public support, privacy and press pages (GitHub Pages) |
| `project.yml` | XcodeGen spec for every target; `Nyx.xcodeproj` is generated from it |

Project documents: [DECISIONS.md](DECISIONS.md) (every decision with its reason), [PHASE_STATUS.md](PHASE_STATUS.md) (latest handoff), [AUDIT.md](AUDIT.md) (design, accessibility and device-gate evidence), [PRIVACY.md](PRIVACY.md) (privacy review), [SUBMISSION.md](SUBMISSION.md) and [INPUT_NEEDED.md](INPUT_NEEDED.md) (release checklist and the owner's tasks).

## Run

Requires the installed Xcode 27 (Swift 6), an iOS 26+ iPhone or iPad (or simulator), and [XcodeGen](https://github.com/yonaskolb/XcodeGen) only when changing project settings. Open `Nyx.xcodeproj`, select the **Nyx** scheme and run. The signing team is `DUHVN68KBA`; for a device, register the app and extension identifiers and the App Group `group.com.harrypakhale.nyx` in your Apple developer account.

The project is generated from `project.yml`. Source folders are synchronized, so new files need no project change. For targets, capabilities or settings, edit the YAML, run `xcodegen generate`, and commit the YAML and the generated project together. Never edit `project.pbxproj` by hand.

Core planning, the calendar, saved parks, Learn and the journal work on first launch without a network or an API key. Cloud forecasts improve scores when they are available; without them the remaining weights are renormalized and the uncertainty is shown. A score never confirms safe access.

### Optional NPS key

Register a free public-app key at [developer.nps.gov](https://developer.nps.gov/). Create `Config/Secrets.xcconfig` (git-ignored) with one line, `NPS_API_KEY = your_key`, then build. `Config/Nyx.xcconfig` includes it, and the app's Info.plist carries it as `NPS_API_KEY`. Without the file the key is empty and Nyx says plainly that park access was not checked. The key ships inside the app binary, so use a public-app key and treat it as identifiable, not secret.

### iPad

The same app target runs on iPad (iPadOS 26+, every orientation, resizable windows). Wide windows (≥ 900 pt) get two-column pages: Parks as a list beside the park, park detail with the gauge and river beside the sky's detail, Tonight with the answer beside the choices, Calendar with the chosen night's breakdown beside a larger month, Journal with the constellation beside the entries. Narrow windows and Slide Over use the iPhone layout. Keyboard: ⌘1–⌘5 tabs, ⌘F find a park, ⌘← ⌘→ previous and next night. An extra-large Tonight's sky widget is iPad only. See DECISIONS.md "iPad".

### Apple Watch

`NyxWatch` (watchOS 26+, single-target app) and its complications, `NyxWatchWidgets`, are embedded in the iOS app, so the **Nyx** scheme builds them for the matching watch simulator or device. Run the watch alone with the **NyxWatch** scheme on a watch simulator (`Nyx Watch S11 42`, `Nyx Watch Ultra 3`). The watch makes no network requests: it computes the sky itself and receives saved parks, night vision and cloud forecasts from the iPhone over WatchConnectivity (`WatchBridge` → `WatchContext`). Without a paired iPhone it asks for a park and scores moon and darkness only.

### Apple Vision Pro

The **NyxVision** scheme builds the visionOS 26+ app: a planner window (every park's moon-and-darkness score for a night, one park's night in full, a night stepper and a sunset-to-sunrise clock in the ornament) and an immersive space, "Stand under this sky", that places the 903 catalogue stars, the Milky Way, the Moon (the iPhone's shader), the planets and the galactic core around you for that park and moment. South is ahead (north in American Samoa); it is not aligned to your room's real north. Its only network request is the optional cloud forecast from `api.open-meteo.com` (shared `CloudForecastClient`, its own switch); `-nyx-vision-clouds <percent>`, `-nyx-vision-night <n>` and `-nyx-vision-privacy` are its DEBUG routes for clouds, a night offset and the privacy sheet.

```sh
xcodebuild build -project Nyx.xcodeproj -scheme NyxVision \
  -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/NyxVisionBuild
python3 Scripts/sync_vision_catalog.py /tmp/NyxVisionBuild
```

The second command merges the build's strings into `NyxVision/Resources/Localizable.xcstrings`.

## Features in brief

**Privacy.** Three independent network toggles (forecasts, smoke and haze, park updates) live in Tonight → Settings → Your privacy. They stop new requests without deleting cached data. Only `developer.nps.gov`, `api.open-meteo.com` and `air-quality-api.open-meteo.com` are reachable through the transport (`SafeHTTP`), and redirects are rejected. Location stays on the device, PhotosPicker sees only the photos you pick, and reminders are local. Details: [PRIVACY.md](PRIVACY.md).

**Field mode.** "I'm here tonight" on a park's detail (tonight only), Tonight after sunset when the iPhone is already known to be in or near a park, the Control Center "Field mode" control, the "Start field mode at <park>" shortcut, the night's Live Activity, or a Stargazing Focus opens a full-screen red view of the night. It shows a live countdown to true darkness and each milestone in turn: moonrise and moonset, the core clearing 10°, its highest and sinking, a shower's best hour, planets rising and setting, dawn. It also has a dark-adaptation clock that restarts (undoably) when you leave Nyx, and "Where to look", the real sky turned to the phone's attitude (Core Motion; true north when location is already allowed, magnetic otherwise, and it says which), with a VoiceOver list. Night vision, a dim screen and no auto-lock last only while field mode is open. The Live Activity carries the night's milestones in its attributes, so it needs no push; it refreshes when Nyx is open and ends at dawn the next time Nyx opens. Alarms (AlarmKit, iOS 26.1+) wake you for true darkness, the core, or 30 minutes before a moonset in true darkness. The Stargazing Focus filter does nothing until its switches (night vision, offer field mode) are on in the Focus's settings; with both off it counts as no Focus, which is how the system reports a Focus ending.

**Sound, touch and accessibility.** A park's detail can play the night as twelve seconds of sound ("Listen to tonight", under the shape of the night): a tone that falls as the sky darkens, quiets while the Moon is up, pulses at moonrise and moonset, and chimes when the Milky Way's core rises, with a transcript beside it. "Feel the Moon" plays the Moon's phase as a Core Haptics texture, and the time river's ticks sharpen with each night's score. VoiceOver gets audio graphs on the time river, calendar month and sky arc, and rotors for best nights, closures, Pristine nights and field milestones. Nyx also follows Differentiate Without Color, Reduce Highlighting Effects and Prefer Cross-Fade Transitions (iOS 26.4) and reduced resource usage (iOS 27). Tonight → Settings → Accessibility → Sound and touch explains each one and lets you try it.

**Widgets, Siri and Spotlight.** Widgets and intents compute locally from the shared cached snapshot and never fetch. The Tonight's sky widget comes in small, medium (with a "next saved park" button), large (the coming month as small skies with shower and eclipse marks) and two Lock Screen sizes. It rises in the Smart Stack around dusk on Good or better nights, and it draws in white only in StandBy at night and in tinted modes. Siri and Shortcuts offer "Find the best night" (one park or the saved parks, up to 30 nights, an interactive snippet). Parks are semantic Spotlight entities. Ask Nyx's on-device model can call the engine through three tools (best nights, what's up, parks nearby) and cites what they return. MetricKit's average pixel luminance, once iOS delivers a report, appears in About the data; it never leaves the phone.

**Links** (`DeepLink`, tested): `nyx://park/<id>`, `nyx://tonight`, `nyx://field/<id>`, `nyx://whatsup?date=YYYY-MM-DD&park=<id>` (that night at the park, scrolled to What's up; App Store In-App Events and the calendar events Nyx drafts use it) and `nyx://calendar/<id>?month=YYYY-MM` (the park's month in Calendar).

**Delight.** A trip planner (Tonight → Plan a trip; `TripPlanner`, dynamic programming over nights × parks with a straight-line hop limit), your constellation and "skies you've seen" in the Journal (`SkyMap`, `ConstellationLayout`, `SkiesSeen`), a year recap (`YearRecap`, Journal menu), four Liquid Glass app icons (`AppIcon*.icon`, Settings → App icon), and first light (`FirstLightView`).

## Implementation

SwiftUI with `@Observable` state; injectable astronomy, weather, park and notification services; SwiftData for the journal and saved parks, with selected photos in external storage. Canvas draws the seeded stars, gauge, solar and lunar paths, and calendar and timeline marks; a Metal shader draws the Moon from NASA's lunar map. Native navigation, glass controls, sheets, search and the system accessibility adjustments carry the rest.

On iOS 27, Save uses the pinned trailing toolbar placement; iOS 26 keeps a complete native fallback. Foundation Models entry points appear only when the model is actually available and use only injected source records. AI never computes astronomy and never blocks core planning or reminders.

### App icon

The shipping icon is the Icon Composer document `Nyx/Resources/AppIcon.icon` (Xcode compiles it; `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`). Its layers, front to back: the leading star, the score arc (not glass, so its amber stays luminous), and the sphere-shaded crescent over an earthshine disc (glass), on a nebula-violet-to-black gradient. `AppIconFull`, `AppIconNew` and `AppIconQuarter` are the alternate Moon-phase icons. Edit any of them in Icon Composer (Xcode → Open Developer Tool → Icon Composer) and save in place. To preview from the command line:

```sh
"/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  Nyx/Resources/AppIcon.icon --export-image --output-file /tmp/nyx-icon.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`. Check that the crescent stays recognizable at 60 px.

## Verify

The scheme runs the Swift Testing suite and the XCTest UI tests, including `NyxUITests/AccessibilityAuditTests`, Apple's automated accessibility audit on 17 screens in both palettes (set `TEST_RUNNER_NYX_AUDIT_SCREENS=parks,detail` to audit a few). Run one simulator at a time; parallel simulators can overload the Mac.

```sh
xcodebuild test -project Nyx.xcodeproj -scheme Nyx \
  -destination 'platform=iOS Simulator,id=4B98F460-8228-4B8B-8626-2BE43641E876' \
  -derivedDataPath /tmp/NyxBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

```sh
xcodebuild test -project Nyx.xcodeproj -scheme Nyx \
  -destination 'platform=iOS Simulator,id=5BB44DBD-DBE4-4FA3-84C8-8E92D3B3F0B3' \
  -derivedDataPath /tmp/NyxBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

These are this machine's iPhone 17 Pro / iOS 26.5 and iPhone 18 Pro / iOS 27.0. On another machine, substitute IDs from `xcrun simctl list devices available`. App Group simulation needs the ad-hoc signed simulator build. For an unsigned device Release archive:

```sh
xcodebuild archive -project Nyx.xcodeproj -scheme Nyx -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Nyx.xcarchive CODE_SIGNING_ALLOWED=NO
```

Development signatures have get-task-allow enabled and need App Store distribution export or re-signing. Only Organizer validation and processing through the publisher's account establish distribution readiness. Real-device accessibility and performance review are release gates, not completed certifications ([AUDIT.md](AUDIT.md), [Research/performance.md](Research/performance.md)).

`Scripts/capture_system_accessibility.py SIMULATOR_ID 26` captures real Simulator AX5 and contrast settings and restores the previous ones afterwards. `Scripts/capture_store.py` produces the store artwork (see `Store/Screenshots/README.md`).

### Screenshot scenarios (DEBUG only)

Launch with arguments such as `-nyx-screen detail -nyx-state offline`, or run `python3 Scripts/capture_screens.py SIMULATOR_ID 26`. Nothing on the simulator is changed by these routes. Scenarios use an in-memory journal, and sample journal content is DEBUG only. Offline scenarios may use a real cached forecast; `no-forecast` guarantees unknown clouds. Normal app behavior reads actual data, and scores are never mocked.

- **Screens** (`-nyx-screen`): the four tabs (`tonight`, `parks`, `plan` (`calendar` still works), `journal`), `learn` (the Learn index), `trip` (My free nights alone), `credits`, `places` (the starting-point picker; `-nyx-place <text>` prefills), `detail`, `editor`, `entry`, `settings`, `privacy`, `data`, `article`, `breakdown`, `share`, `ask`, `onboarding`, `skyarc`, `river`, `whatsup`, `light` (light pollution, viewing spots with sky glow and step-free access, Protect this sky; for example with `-nyx-park deva | grca | sequ`), `loader`, `widgets` (small, medium with "2 of 3", Lock Screen, StandBy at night simulated), `widgets-empty`, `widgets-large` (full colour, night vision, tinted), `widgets-xl` (iPad), `snippet` (the "Find the best night" dialog and snippet, voice-only wording), `metric` (About the data with the labelled DEBUG luminance fixture), `listen` (the sonification panel and its transcript), `accessibility` (Sound and touch), and both permission explainers.
- **States** (`-nyx-state`): `live`, `offline`, `no-forecast`, `agree`, `disagree`, `smoke` (fixture forecast detail: models agreeing and cold with dew, models disagreeing with high cloud, smoke at AOD 0.38), `no-location`, `loading`, `empty`, `error`, `polar`, `polar-night`, `populated`, `photo`, `night-vision`, `step-free` (Parks with the "Step-free viewing" filter on), `privacy` (with `metric`), `access` (with `article`, a named essay), `first-run` (Tonight before a starting point is chosen).
- **Flags:** `-nyx-night-vision` (combines with any state), `-nyx-ax5`, `-nyx-bold` (Bold Text, which the simulator cannot switch from the command line), `-nyx-reduce-motion`, `-nyx-contrast`, `-nyx-differentiate`, `-nyx-reduce-highlighting`, `-nyx-crossfade`, `-nyx-reduced-resources`, `-nyx-bottom`, `-nyx-onboarding-page 1|2`, `-nyx-date 2026-12-13` ("now" is that afternoon, 21:00 UTC, so every computed sky is real for that date), `-nyx-park ever` (starting park), `-nyx-place "Chicago, IL"` (a city as the starting point), `-nyx-plan-trip` (Plan opens on My free nights), `-nyx-narrow` (iPad: the app in a 390 pt compact column), `-nyx-link <nyx:// URL>` (opens a link once the app is up, for example `-nyx-screen tonight -nyx-link "nyx://whatsup?date=2026-12-13&park=grba"`).
- **Field mode:** `-nyx-screen field` (states `adapting`, `adapted`, `reset`, `alarms`; `-nyx-field-minutes N` after sunset), `field-compass` (fixed pose 10° above the core, or south; under `-nyx-state live` both field routes refresh the forecast as detail does and re-read the score, so the two match), `live-activity` (Lock Screen and Dynamic Island), `alarm-explainer`; Tonight's Focus offer is `-nyx-screen tonight -nyx-state stargazing`.
- **Delight:** `-nyx-screen trip` (states `agree` for fixture forecasts, `weekends`, `boats` for boat-and-plane parks within 100 mi, for example with `-nyx-park chis`), `constellation` (`-nyx-state empty` for the first-star state, `skies` to open the list), `recap`, `icons`, `first-light`.
- **What's up:** Geminid peak `-nyx-screen whatsup -nyx-date 2026-12-13`; total lunar eclipse `-nyx-screen whatsup -nyx-date 2029-06-25 -nyx-park ever`; core below the horizon `-nyx-screen whatsup -nyx-park dena`; Tonight's shower line `-nyx-screen tonight -nyx-date 2026-12-11`.
- **Landscape (iPad):** `TEST_RUNNER_NYX_SHOTS_DIR=/tmp/shots TEST_RUNNER_NYX_SHOTS="parks:landscape:-nyx-screen parks -nyx-state live" xcodebuild test-without-building … -only-testing:NyxUITests/ScreenshotTests` (each item `name:portrait|landscape:arguments`, separated by `;`).
- **Apple Watch:** `-nyx-watch-screen tonight | milestones | week | dark | parks | chooser | complications`, `-nyx-watch-state synced | unsynced | polar | samoa`, `-nyx-watch-palette red | phone | standard`, `-nyx-watch-ax`.
- **Vision Pro:** `-nyx-vision-immersive`, `-nyx-vision-skyonly`, `-nyx-vision-look yaw,pitch`, `-nyx-vision-time 0…1`, `-nyx-vision-body saturn`, with `-nyx-date`, `-nyx-park`, `-nyx-night-vision` and `-nyx-ax5`.

Capture scripts wait eight seconds for settled frames by default (`NYX_CAPTURE_WAIT` overrides it for the QA runner).

## Localization

Nyx ships in English and Spanish (`es`, written for US and Mexican Spanish; tú, calm ranger voice). The String Catalogs (`Nyx/Resources/Localizable.xcstrings`, shared by the app, widgets and watch; `InfoPlist.xcstrings`; `NyxVision/Resources/Localizable.xcstrings`) are generated. English comes from the code via `python3 Scripts/sync_catalog.py /tmp/NyxBuild` (after a build; build again after syncing) or `sync_vision_catalog.py`. Spanish comes from the translation memory in `Research/localization/` via `python3 Scripts/apply_translations.py` (both sync scripts run it at the end; `--check` reports any key without Spanish and exits 1). Edit Spanish there, never in the catalogs.

The Learn essays are the catalog keys `essay.*` (English Markdown sources in `Nyx/Resources/learn`, Spanish in `Research/localization/learn-es/`). Meteor shower names are `shower.<IMO code>` and park access notes `access.<park id>`, whose English comes from `sky-events.json` and `parks.json`. Park names, viewing-spot names, and NPS alerts and programs stay in English, as nps.gov's own Spanish pages keep park names. Try it with `-AppleLanguages "(es)" -AppleLocale es_MX`. XcodeGen 2.46 cannot list `es` in the project's known regions with synchronized folders, so the project still shows `en`; the build compiles `es.lproj` from the catalogs and iOS offers Spanish from that. Native-speaker review is pending (`INPUT_NEEDED.md`).

## Data and accuracy

- NOAA/Meeus solar coordinates; nights run local noon to noon through DST. Polar results are explicit.
- Truncated Meeus lunar position with parallax; illumination corrects the mean synodic epoch cycle with calculated elongation.
- USNO reference results are in [Research/accuracy.md](Research/accuracy.md). Rise and set approximations exclude terrain and refraction variation; allow roughly ±15 minutes for lunar timing and more at difficult horizons.
- Open-Meteo hourly clouds: one request for many parks (comma-separated coordinates, plus the previous day so eastern nights stay covered), a complete overlap-weighted dark-window average, six-hour refresh, 36-hour expiry, and partial coverage is never treated as clear. Beyond the forecast, nights are ranked with each park's usual clouds from ERA5 (2015–2024, `cloud-climate.json`).
- Forecast context, never in the score (seven days): three models' clouds (`gfs_seamless`, `ecmwf_ifs025`, `icon_seamless`) for agreement, cloud layers, coldest hour, dew risk, gusts and visibility (one request each for all parks), and the CAMS aerosol forecast from `air-quality-api.open-meteo.com` (about five days) for smoke and haze. Same overlap rules; each part has its own six-hour refresh and cache (`nyx-detail-<park>.json`).
- Light pollution context: NASA Black Marble nighttime lights (VNP46A4, Román et al. 2018), public domain, reduced offline to `Nyx/Resources/skyglow.json` (method and limits in [Research/skyglow.md](Research/skyglow.md)). Shown as a rank among parks, light domes and a growth rank; never in the score.
- Step-free notes per viewing spot from nps.gov accessibility pages, retrieved 2026-10-05 (`Nyx/Resources/accessible-spots.json`, [Research/accessible-spots.md](Research/accessible-spots.md)). Access notes for 17 parks a car cannot simply reach (boat, plane or a limited road) from nps.gov directions pages, retrieved 2026-10-06 (`access` in `parks.json`, [Research/park-access.md](Research/park-access.md)).
- Bundled NPS inventory and sourced viewing spots. Bortle values are conservative planning estimates, not measurements. Some parks have no verified viewing spot and say so.
- Development-only scripts (`Scripts/fetch_references.py` and the data builders) contact research hosts; none of them are in the app's networking path.

### Attribution

Weather: [Open-Meteo](https://open-meteo.com/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Air quality: Copernicus Atmosphere Monitoring Service (CAMS) via Open-Meteo, CC BY 4.0. Usual clouds: ERA5 reanalysis, Copernicus Climate Change Service, CC BY 4.0. Stars: the Yale Bright Star Catalogue (Hoffleit and Warren, via NASA HEASARC). Moon: NASA's LRO colour map (CGI Moon Kit). Meteor showers: International Meteor Organization (IMO) 2026 Meteor Shower Calendar. Lunar eclipse predictions: Fred Espenak, NASA/GSFC. Planet positions: Paul Schlyter's low-precision orbital elements, computed on the device. US outline: US Census Bureau cb_2023_us_nation_20m (public domain), simplified. Park descriptions and data: National Park Service. No NPS endorsement is implied.
