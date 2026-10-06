# Nyx

A calm, offline-first dark-sky planner for the 63 US national parks. Nyx compares moonlight, clouds, estimated skyglow and true darkness to help choose a park and a night. No accounts, advertising, tracking, backend or third-party runtime packages.

## Run

Requires the installed Xcode 27 (Swift 6), an iOS 26+ iPhone or simulator, and XcodeGen only when changing project settings. Open `Nyx.xcodeproj`, select the **Nyx** scheme and run. The signing team is `DUHVN68KBA`; configure the app/extension identifiers and App Group in your Apple developer account for a device.

The project is generated from `project.yml`. New source files are synchronized automatically. For targets/capabilities/settings, edit the YAML, run `xcodegen generate`, and commit the YAML and generated project. Never edit `project.pbxproj` manually.

Core planning, calendar, saved parks, Learn and the journal work on first launch without network or an API key. Cloud forecasts enhance scores when available. Without clouds, the remaining weights are renormalized and the uncertainty is visible. A score never confirms safe access.

### Optional NPS key

Register a free public-app key at [developer.nps.gov](https://developer.nps.gov/). Create `Config/Secrets.xcconfig` (git-ignored) containing one line, `NPS_API_KEY = your_key`, then build. `Config/Nyx.xcconfig` includes it and the app's Info.plist carries it as `NPS_API_KEY`. Without the file the key is empty and Nyx says plainly that park access was not checked. The key ships inside the app binary, so use a public-app key and treat it as identifiable, not secret.

The three independent network toggles (forecasts, smoke and haze, park updates) are in Tonight → Settings → Your privacy. They stop new requests without deleting cached data. Only `developer.nps.gov`, `api.open-meteo.com` and `air-quality-api.open-meteo.com` are reachable through the transport; redirects are rejected. Location remains on-device. PhotosPicker sees only selected photos. Reminders are local.

## Verify

The scheme's tests include `NyxUITests/AccessibilityAuditTests`, Apple's automated accessibility audit on 17 screens in both palettes; set `TEST_RUNNER_NYX_AUDIT_SCREENS=parks,detail` to audit a few. Run one simulator at a time; parallel simulators can overload the Mac.

```sh
xcodebuild test -project Nyx.xcodeproj -scheme Nyx \
  -destination 'platform=iOS Simulator,id=4B98F460-8228-4B8B-8626-2BE43641E876' \
  -derivedDataPath /tmp/NyxBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
xcodebuild test -project Nyx.xcodeproj -scheme Nyx \
  -destination 'platform=iOS Simulator,id=5BB44DBD-DBE4-4FA3-84C8-8E92D3B3F0B3' \
  -derivedDataPath /tmp/NyxBuild CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
```

These are this machine's iPhone 17 Pro / iOS 26.5 and iPhone 18 Pro / iOS 27.0. On another machine, substitute IDs from `xcrun simctl list devices available`. App Group simulation needs the ad-hoc signed simulator build. For an unsigned device Release archive:

```sh
xcodebuild archive -project Nyx.xcodeproj -scheme Nyx -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Nyx.xcarchive CODE_SIGNING_ALLOWED=NO
```

Unsigned and development-signed Release archives were verified locally. Development signatures have get-task-allow enabled and require App Store distribution export/re-signing. Only Organizer validation and processing through the publisher's account establish distribution readiness.

### Screenshot scenarios (DEBUG only)

Launch with `-nyx-screen detail -nyx-state offline`, or run `python3 Scripts/capture_screens.py SIMULATOR_ID 26`. Screen routes include the five tabs, detail, editor, entry, settings, privacy, data, article, breakdown, share, ask, onboarding, skyarc, river, whatsup, loader, widgets/widgets-empty content and both permission explainers. States: offline, no-forecast, agree, disagree, smoke (fixture forecast detail: models agreeing and cold with dew, models disagreeing with high cloud, smoke at AOD 0.38), no-location, loading, empty, error, polar, polar-night, populated, photo, night-vision. Flags: `-nyx-night-vision` (combine with any state), `-nyx-ax5`, `-nyx-reduce-motion`, `-nyx-contrast`, `-nyx-bottom`, `-nyx-onboarding-page 1|2`, `-nyx-date 2026-12-13` ("now" is that afternoon, 21:00 UTC, so every computed sky is real for that date) and `-nyx-park ever` (starting park). What's up examples: Geminid peak `-nyx-screen whatsup -nyx-date 2026-12-13`; total lunar eclipse `-nyx-screen whatsup -nyx-date 2029-06-25 -nyx-park ever`; core below the horizon `-nyx-screen whatsup -nyx-park dena`; Tonight's shower line `-nyx-screen tonight -nyx-date 2026-12-11`. Scenarios use an in-memory journal; sample journal content is DEBUG only. Offline scenarios may use a real cached forecast. `no-forecast` guarantees unknown clouds. Normal app behavior reads actual data; scores are never mocked.

`Scripts/sync_catalog.py /tmp/NyxBuild` merges compiler-extracted English copy into the String Catalog after a build; run another build after syncing. Capture scripts wait eight seconds for settled frames by default (`NYX_CAPTURE_WAIT` can override the QA runner). Essays are original, catalog-backed English content with Markdown sources in `Resources/learn`. Development-only USNO references and scripts contact research hosts; none are in the app's networking path.

## Implementation

SwiftUI + @Observable state; injectable astronomy/weather/park/notification protocols; SwiftData journal and saved parks; external-storage selected photos. Canvas draws seeded stars, a sphere-projected moon, gauge, solar/lunar paths, and calendar/timeline marks. Native navigation, glass controls, sheets, search and accessibility adjustments carry the rest.

On iOS 27, Save uses the pinned trailing toolbar placement; iOS 26 retains a complete native fallback. Foundation Models entry points require actual model availability and use only injected source records. AI never computes astronomy or blocks core planning/reminders. The scheme runs the Swift Testing suite and two native XCTest UI tests (offline tab navigation and launch responsiveness). Actual Simulator AX5/contrast captures use `Scripts/capture_system_accessibility.py SIMULATOR_ID 26`; that script restores the prior settings. `Scripts/capture_store.py` produces native-resolution artwork drafts. See `Research/performance.md` for measured results and their limits.

Widgets and intents compute locally from the shared cached snapshot; they do not fetch network data.

### Data and accuracy

- NOAA/Meeus solar coordinates; local-noon-to-noon nights through DST. Polar results are explicit.
- Truncated Meeus lunar position with parallax; illumination corrects the mean synodic epoch cycle with calculated elongation.
- USNO reference results in [Research/accuracy.md](Research/accuracy.md). Rise/set approximations exclude terrain/refraction variation; allow roughly ±15 minutes for lunar timing and more at difficult horizons.
- Open-Meteo hourly clouds: one request for many parks (comma-separated coordinates, plus the previous day so eastern nights stay covered), complete overlap-weighted dark-window average, six-hour refresh, 36-hour expiry, no partial coverage treated as clear.
- Forecast context, never in the score (seven days): three models' clouds (`gfs_seamless`, `ecmwf_ifs025`, `icon_seamless`) for agreement, cloud layers, coldest hour, dew risk, gusts and visibility (one request each for all parks), and the CAMS aerosol forecast from `air-quality-api.open-meteo.com` (about five days) for smoke and haze. Same overlap rules; each part has its own six-hour refresh and cache (`nyx-detail-<park>.json`).
- Bundled NPS inventory and sourced viewing spots. Bortle values are conservative planning estimates, not measurements. Some parks have no verified viewing spot and say so. Weather attribution: [Open-Meteo](https://open-meteo.com/), [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Air-quality attribution: Copernicus Atmosphere Monitoring Service (CAMS) via Open-Meteo, CC BY 4.0. Meteor shower data: International Meteor Organization (IMO) 2026 Meteor Shower Calendar. Lunar eclipse predictions: Fred Espenak, NASA/GSFC. Planet positions: Paul Schlyter's low-precision orbital elements, computed on the device. Park descriptions/data: National Park Service. No NPS endorsement is implied.

## Release handoff

Read [PHASE_STATUS.md](PHASE_STATUS.md), [AUDIT.md](AUDIT.md), [PRIVACY.md](PRIVACY.md), [SUBMISSION.md](SUBMISSION.md), and the ordered [INPUT_NEEDED.md](INPUT_NEEDED.md). The app icon is a native Icon Composer document, `Nyx/Resources/AppIcon.icon` (layers mirrored in `IconSources/`); preview it with Icon Composer's `ictool --export-image`. Physical accessibility/performance review and the provider-retention privacy decision are release gates, not completed certifications.
