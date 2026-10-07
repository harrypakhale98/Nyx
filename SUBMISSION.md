# Nyx 1.1 submission package

**Build 1.1 (7), archived 2026-10-06.** `/tmp/Nyx-1.1-7.xcarchive` (iPhone and iPad app with the Tonight's sky widget and the Apple Watch app inside) and `/tmp/NyxVision-1.1-7.xcarchive` (Apple Vision Pro), both Release, development-signed with team `DUHVN68KBA`, zero warnings, `python3 Scripts/verify_release.py` passing (`Research/release-verification.json`). Nothing is uploaded. A development-signed archive is not an App Store validation result: distribute from Xcode's Organizer, which re-signs for the App Store. `/tmp` does not survive a restart, so if the archives are gone, archive again in Xcode (Product → Archive) after checking `project.yml` still says 1.1 / 6.

**Release gates remain open** until the owner finishes the ordered steps in `INPUT_NEEDED.md` (device pass, Spanish review, privacy page push).

## The record

- App Store name: **Nyx: Dark Sky Planner** ("Nyx" alone is taken; owner's choice 2026-10-03). Home Screen name **Nyx**. Fallback: **Noctis**.
- Subtitle (≤30): **The night sky, park by park** (27). Recommended in `Store/1.1/metadata.md`; the 1.0 subtitle "Plan a darker night" stays valid if you prefer continuity. A subtitle changes only with a new version.
- Categories: Travel (primary), Weather (secondary). Price: Free; no subscriptions, ads or in-app purchases (required by Open-Meteo's free, non-commercial terms).
- Platforms in this version: **iPhone, iPad (new), Apple Watch (new, inside the iOS build), Apple Vision Pro (new, its own build, same bundle ID `com.harrypakhale.nyx`, universal purchase).** iOS/iPadOS 26.0+, watchOS 26.0+, visionOS 26.0+.
- Languages: English (U.S.) and **Spanish (Mexico)** (the app ships an `es` localization; see below).
- Copyright `2026 Hardik Pakhale`. Privacy policy https://harrypakhale98.github.io/Nyx/privacy.html · Support https://harrypakhale98.github.io/Nyx/support.html · Marketing https://harrypakhale98.github.io/Nyx/ (GitHub Pages from `docs/`, submission metadata, not app endpoints). Contact harry.pakhale98@gmail.com.
- Release: **manual** after approval, so the In-App Events and the featuring nomination line up.

## English metadata (paste from `Store/1.1/metadata.md`)

Every field below is in `Store/1.1/metadata.md` with character counts verified by script. Paste from there, not from memory.

- **What's New:** the full text in `metadata.md` (3,251 of 4,000) or its 518-character fallback. It describes only features in build 7: What's up tonight, the honest forecast (three models, layers, dew, smoke and haze), field mode with Live Activity and alarms, Apple Watch, Apple Vision Pro, iPad, sky glow from NASA Black Marble, audio graphs and Listen to tonight, Feel the Moon, Reduce bright effects, step-free spots, Spanish, trip planner, your constellation, and the third optional data service.
- **Promotional text (≤170):** `Plan the night, then follow it. The Milky Way core, planets and meteor showers, honest forecasts, and a red field mode for your eyes. Free. Data Not Collected.` (159). Seasonal alternates are in `metadata.md`; promotional text can change without a build.
- **Description:** `metadata.md` § Description (3,978 of 4,000). It corrects the 1.0 sentence about smoke and haze. Delete "Voice Control" from the accessibility paragraph unless the Voice Control device pass is signed off.
- **Keywords (≤100):** `stargazing,milky way,meteor shower,moon phase,national park,astronomy,bortle,planet,eclipse,star` (96). "aurora" is dropped on purpose: Nyx does not forecast aurora.
- **Review notes:** the 1.0 notes below, plus: "1.1 adds a third provider host, `air-quality-api.open-meteo.com`, behind its own switch in Tonight → Settings → Your privacy, listed in `PrivacyInfo.xcprivacy`. Field mode (Live Activity, AlarmKit alarms, Core Motion for 'Where to look') starts from 'I'm here tonight' on any park's detail screen; best tried in the evening. AlarmKit asks for permission in context after an explainer. The Apple Watch and Apple Vision Pro apps share the engine and make no network requests of their own. No login."
  - 1.0 notes, still true: no account or reviewer login; onboarding requests no permissions and can be skipped; manual starting-park selection works with location denied; each data service is switchable in Tonight → Settings → Your privacy; core astronomy and the bundled park library work offline; unknown cloud forecasts have hollow calendar and timeline marks and a caveat beside the score; a polar summer night has no true darkness and is capped below 40; notifications are local, opt-in, for saved parks with complete recent forecasts and scores of at least 90; PhotosPicker accesses only selected photos; SwiftData stores observations on the device, no CloudKit; widgets and Control Center share `group.com.harrypakhale.nyx`; Siri and Shortcuts answer without network; Apple Intelligence features appear only when the on-device model is available; the build includes the publisher's NPS key (from git-ignored `Config/Secrets.xcconfig`); no developer screenshot launch arguments exist in Release.
- **Age rating:** re-answer the questionnaire; nothing in 1.1 changes the answers (no public UGC, no web browsing beyond the providers, no account).

## Spanish (Mexico) localization

- App: Spanish ships in the app, widgets, watch and Vision Pro catalogs. Machine-drafted, marked translated, **native-speaker review pending** (`INPUT_NEEDED.md`). Do not submit Spanish metadata before that review.
- Metadata: `Store/1.1/metadata-es.md`. Name: keep **Nyx: Dark Sky Planner**. Subtitle: `Planea una noche más oscura` (27). Keywords: the list in that file (95 bytes). Description: the Spanish text **plus** its "Optional paragraph" (What's up and field mode now ship). What's New: the Spanish draft with the field-mode paragraph. The Spanish description covers fewer 1.1 features than the English one (no Watch, Vision Pro, trip planner); extending it is part of the native review.
- Screenshots: `Store/Framed/es/6.9-inch` and `es/6.5-inch` (ten captioned frames, Spanish captions in `Scripts/make_store_frames.swift`). Raw captures in `Store/Screenshots/es/`.
- Spanish (Mexico) is offered on the US storefront as an additional metadata language; confirm in App Store Connect → App Information → Localizable Information.

## Screenshots per device

All captures are real renders, no alpha channel, verified sizes. Live = `-nyx-state live`: real Open-Meteo forecasts and NPS alerts at capture time (2026-10-06, around 12:15 PM Pacific), scored by the shipping engine. Nothing is mocked. Sizes checked against Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) on 2026-10-06.

**iPhone 6.9-inch (required), 1320×2868: `Store/Framed/6.9-inch/`** (captioned; raw in `Store/Screenshots/`). iPhone 18 Pro Max, iOS 27.0. **6.5-inch, 1284×2778: `Store/Framed/6.5-inch/`** (optional when 6.9-inch is supplied). Upload in this order:

| # | File | Eyebrow / caption | Screen (all Joshua Tree unless named) |
|---|---|---|---|
| 1 | `01-tonight.png` | TONIGHT / Where is the sky darkest tonight? | Tonight: Death Valley 96, closure line beside the score (live) |
| 2 | `02-score.png` | THE DARKNESS SCORE / One number, and its reasons. | Park detail: gauge 93, four meters, "Models agree", I'm here tonight (live) |
| 3 | `03-whats-up.png` | WHAT'S UP TONIGHT / The Milky Way, and when to look. | What's up: core 7:43–8:54 PM, Jupiter, Mercury, Saturn, Mars, Wake me (live, via `nyx://whatsup`) |
| 4 | `04-field-mode.png` | FIELD MODE / Red light for dark-adapted eyes. | Field mode in red: 93 like the detail frame, "True darkness in 22:37", milestones, eye clock (tonight, live refresh, clock moved to 60 min after sunset) |
| 5 | `05-where-to-look.png` | WHERE TO LOOK / Point your iPhone. Find the core. | Compass sky: the Milky Way band rising from the core, 27° up in the south, Antares, Mars marked at the edge (computed for Sat 3 July 2027, new Moon, 11:40 PM; fixed pose 10° above the core; header 86 with "Moon and darkness only. Clouds unknown.", as that night is beyond the forecast) |
| 6 | `06-calendar.png` | BEST NIGHTS / Choose the night worth the drive. | October 2026: new-moon window halos, cloud glyphs, Orionids mark on the 20th, hollow nights past the forecast (live) |
| 7 | `07-trip.png` | PLAN A TRIP / A park for every free night. | The route and the first nights, best night Wed Oct 7 Death Valley 97 (live) |
| 8 | `08-constellation.png` | YOUR CONSTELLATION / Every night becomes a star. + privacy line | Journal: constellation, "4 of 63", an entry (illustrative DEBUG journal, no personal photos) |
| 9 | `09-listen.png` | SOUND AND TOUCH / Hear the shape of the night. | Shape of the night, Listen to tonight, transcript (live) |
| 10 | `10-every-sky.png` | SKY GLOW AND ACCESS / City glow, named. Step-free spots, marked. | Death Valley: NASA night-lights rank, glow from Las Vegas, Ridgecrest, Visalia; partly step-free spot |

Captions: calm, six words or fewer, no prices, no "new", no exclamation marks. Frames 4–5 use signal red. Reproduce: `python3 Scripts/capture_store.py SIM DERIVED en|es` (frames 7 and 9 need one scroll each; the script says where), then `swift Scripts/make_store_frames.swift [es]`.

**iPad 13-inch (required now that Nyx runs on iPad), 2752×2064 landscape: `Store/Screenshots/iPad/`**, six raw captures (iPad Pro 13-inch (M5), iOS 27.0, live data except the journal): Tonight with the river, Parks split view, two-column detail, Calendar with the night beside the month, Journal constellation, field mode "Where to look". Raw is acceptable; the frame script lays out portrait iPhone canvases only, so iPad frames were not made.

**Apple Watch, 422×514 (Ultra 3 / Ultra 4 class): `Store/Screenshots/Watch/`**, six captures from the NyxWatch scheme on Apple Watch Ultra 3 (watchOS 27): Tonight gauge, milestones, the week, Parks, dark-adaptation cover (red), Tonight in night vision. Apple requires **one** watch size used consistently across localizations; this set is it. The Series 11 42 mm simulator captures at 374×446, which App Store Connect does not accept (accepted: 422×514, 410×502, 416×496, 396×484, 368×448, 312×390), so it was not used. The watch simulator has no paired iPhone, so its scores are moon and darkness only and say "clouds unknown" (honest, not mocked); the clock shows the capture time because the watch simulator ignores status-bar overrides.

**Apple Vision Pro, 3840×2160: `Store/Screenshots/Vision/`**, four captures from NyxVision on the Vision Pro simulator (visionOS 27): `01-window` (the planner window in a room, tonight, Joshua Tree 91, moon and darkness only), `02-immersive-core` (Joshua Tree tonight, the Milky Way setting in the west), `03-moonlit` (Great Basin, 2027-07-15, the Moon beside the core), `04-name-card` (the 11%-lit Moon rising in the east before dawn at Joshua Tree, name card). Sky scenes are computed by the engine for the stated park and date.

**App Preview video (optional):** storyboard and specs in `Store/1.1/app-preview-script.md`.

**History:** 1.0 sets are kept in `Store/1.0/`.

## Platform steps

- **iPad:** included in the iOS build. Upload the iPad 13-inch set. **Mac availability:** App Store Connect → Pricing and Availability → Mac Availability → do not make the app available on Mac (field mode, compass, alarms and Live Activities were never tried there).
- **Apple Watch:** included in the iOS build (`Nyx.app/Watch/NyxWatch.app` with its complications). The bundle IDs `com.harrypakhale.nyx.watchkitapp` and `.watchkitapp.widgets` are registered and carry the App Group (Xcode's automatic signing produced their profiles during the archive). Upload the watch set under the version's Apple Watch section. The watch app needs the iPhone app (companion).
- **Apple Vision Pro:** App Store Connect → the app → **+ Add Platform → visionOS**, then upload `NyxVision-1.1-7` from Organizer (archive scheme NyxVision, destination Any visionOS Device), add the four 3840×2160 screenshots, and submit the visionOS version with iOS 1.1. Same bundle ID, so it is one universal purchase.

## Privacy

- App Privacy: **"No, we do not collect data from this app" (Data Not Collected), no tracking.** Reasoning in `PRIVACY.md`.
- The third host, `air-quality-api.open-meteo.com` (smoke and haze, approved by the owner 2026-10-05), receives only the public coordinates of national parks, as the forecast host does; it has its own switch under Your privacy, is named in `PrivacyInfo.xcprivacy` and the privacy policy, and does not change the label. `verify_release.py` checks that the code contacts exactly `developer.nps.gov`, `api.open-meteo.com` and `air-quality-api.open-meteo.com`, that the watch and Vision Pro targets contain no network code, and that all five bundled manifests declare no tracking and no collected data.
- The published privacy page must already mention the third host before review: push `docs/` to `main` (`INPUT_NEEDED.md`).

## Accessibility Nutrition Labels

App Store Connect → App Information → Accessibility, per device. Full reasoning and the device pass in `Store/1.1/accessibility-nutrition-labels.md`.

| Feature | iPhone | iPad | Apple Watch | Vision Pro | Declare when |
|---|---|---|---|---|---|
| VoiceOver | Yes | Yes | Yes | Yes | after the device pass on each |
| Voice Control | Yes | Yes | n/a | Yes | only after the Voice Control pass |
| Larger Text | Yes | Yes | Yes | Yes | after checking Live Activity, watch and Vision Pro |
| Dark Interface | Yes | Yes | Yes | Yes | now |
| Differentiate Without Color Alone | Yes | Yes | Yes | Yes | after a grayscale pass |
| Sufficient Contrast | Yes | Yes | Yes | Yes | after device sampling |
| Reduced Motion | Yes | Yes | Yes | Yes | after the device check |
| Captions / Audio Descriptions | No (no video or speech) | No | n/a | No | — |

## In-App Events and featuring

- **In-App Events:** eleven paste-ready events in `Store/1.1/in-app-events.md` (Geminids under a thin Moon, Quadrantids, seven new-moon weekends, Eta Aquariids, Perseids 2027), badge Special Event, deep links `nyx://whatsup?date=…&park=…` (supported in build 6). Submit each at least 7 days before its publish date; publish up to 14 days before start. Event media (16:9 card, 9:16 details) still has to be produced (`in-app-events.md` § Media).
- **Featuring:** `Store/1.1/featuring-nominations.md`. Nomination 2, **App Enhancements (Nyx 1.1)**, needs at least three weeks' lead: for a mid-November release, file by about **Oct 28**. Nomination 3a (Geminids event) by Nov 20. File Nomination 1 (App Launch) only if 1.0 has not shipped yet.

## App Store Connect checklist (1.1)

1. If 1.0 (5) was never submitted, rename the pending version to 1.1 and use build 7; otherwise create version 1.1.
2. Upload build 1.1 (7) (iOS, with watch inside) and the visionOS build from Organizer → Distribute App → App Store Connect. Wait for processing; complete export compliance (`ITSAppUsesNonExemptEncryption = NO`: standard HTTPS only).
3. TestFlight: install on iPhone (iOS 26 and 27 if possible), iPad, Apple Watch and Vision Pro; run the device pass in `INPUT_NEEDED.md`.
4. Version page: What's New, promotional text, description, keywords, subtitle (English, then Spanish after review); screenshots for iPhone 6.9", iPad 13", Apple Watch, Vision Pro, in both languages for iPhone.
5. Mac Availability off; add the visionOS platform.
6. App Privacy (Data Not Collected), Accessibility Nutrition Labels (only the features the device pass confirmed), age rating, review notes.
7. Select builds, manual release, Submit for Review. Attach In-App Events and file the featuring nomination per the dates above.
8. After approval: install from the App Store, offline sanity check, then release.

## Owner sign-off

| Gate | Status / evidence |
|---|---|
| Privacy label | READY: Data Not Collected, `PRIVACY.md`; third host explained above |
| Privacy page with the third host live | OPEN: push `docs/` to `main` |
| Release archives | PASS locally: 1.1 (7) iOS + watch + widgets and visionOS, development-signed, `verify_release.py` passing; distribution export pending |
| Physical accessibility, field mode at night, haptics, ProMotion | OPEN: `INPUT_NEEDED.md` step 1, `AUDIT.md` |
| Widgets, Live Activity, alarms, Siri, Spotlight, Smart Stack, available AI on device | OPEN: the simulator cannot host these |
| Apple Watch and Vision Pro on hardware | OPEN |
| Spanish native review | OPEN |
| Screenshots | READY: iPhone 6.9"/6.5" English and Spanish, iPad 13", Watch, Vision Pro |
| App Store export and account metadata | OPEN: publisher account workflow |
