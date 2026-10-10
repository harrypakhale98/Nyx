# Nyx 1.3 submission package (update)

**Nyx 1.1 is live** (build 1.1 (7), released October 7, 2026, App Store ID 6818817800). **Version 1.2 (build 8) is approved** by App Review; the owner decides when to release it (`INPUT_NEEDED.md` step 12). Approval closed the 1.2 train, so **version 1.3** is the next update: build 10 was uploaded on October 9 (build 9 was never uploaded), and **build 11** (build 10 plus the October 10 carry-forward for Vision Pro, the Watch and iPad) is built and tested but waits for the owner's word to be archived and uploaded; it then replaces build 10 for submission. App Store Connect needs a new version (+ Version → 1.3) with build 11 selected (build 10 until 11 is uploaded), a What's New text (What's New in 1.3, `Store/1.1/metadata.md`), and the featuring nomination is **App Enhancements** (`Store/1.1/featuring-nominations.md`). Use **phased release** (seven days, pausable) after approval. Existing users' journals migrate to the new store on first launch (tested; confirm on your own phone with a TestFlight upgrade from 1.1 (7)).

Archive both builds from the integrated `main` at the version and build in `project.yml` (1.3 and 10, archived and uploaded 2026-10-09; 1.2 and 8 on 2026-10-08): the iOS archive (iPhone and iPad app with the widgets and the Apple Watch app inside) and the visionOS archive (`NyxVision`, same bundle ID). Before uploading, run `python3 Scripts/verify_release.py --require-key <ios archive> <vision archive>`; it must pass, including the new checks for the age-range entitlement and the Safari link hosts. A development-signed archive is not an App Store validation result: distribute from Xcode's Organizer, which re-signs for the App Store.

**Release gates** (owner, `INPUT_NEEDED.md`): the device pass, the Spanish decision, the privacy page check, the Declared Age Range capability on the App ID, counsel on age assurance, the trademark search and the storefront decision below.

## The record

- **Name:** Nyx: Dark Sky Planner ("Nyx" alone is taken). Home Screen name **Nyx**. Fallback: **Noctis**.
- **Subtitle:** **Stargazing in national parks** (28). Reasoning in `Store/1.1/metadata.md` § Subtitle decision.
- **Categories:** Travel (primary), Weather (secondary). **Price:** Free; no subscriptions, ads or in-app purchases. Keep it that way: Open-Meteo's free tier is for non-commercial apps without subscriptions or advertising.
- **Platforms:** iPhone, iPad, Apple Watch (inside the iOS build, companion), Apple Vision Pro (own build, same bundle ID `com.harrypakhale.nyx`, universal purchase). iOS/iPadOS 26.0+, watchOS 26.0+, visionOS 26.0+. Vision Pro may be submitted a week after iOS if it threatens the date.
- **Languages:** English (U.S.). Spanish (Mexico) store metadata only after native review (`Store/1.1/metadata-es.md`); the in-app Spanish is the owner's AM-12 decision.
- **Copyright:** `2026 Hardik Pakhale`. **URLs:** privacy https://get-nyx.com/privacy · support https://get-nyx.com/support · marketing https://get-nyx.com/ (Cloudflare Worker serving `docs/` from `main`; not app endpoints). Contact harry.pakhale98@gmail.com.

## Metadata (paste from the files, not from memory)

- English: `Store/1.1/metadata.md` (promotional text, description, keywords, subtitle; counts verified by script). Confirm the feature table at its top against build 8 first.
- visionOS version page: `Store/1.1/metadata-visionos.md`.
- Spanish: `Store/1.1/metadata-es.md`, only after the native review.
- App Preview (optional): `Store/1.1/app-preview-script.md`.

## Review notes (paste into App Review Information → Notes)

```
Nyx has no account and no login; nothing needs a demo account. Onboarding asks for no permissions and can be skipped. Choosing a starting park by hand works with location denied.

Data and network: the app contacts exactly three public services, each with its own switch in Settings → Your privacy: developer.nps.gov (park alerts, ranger programs and campgrounds), api.open-meteo.com (cloud forecasts) and air-quality-api.open-meteo.com (smoke and haze). Alert requests always name all 63 parks in one request; the campground request also names all 63 parks, is made at most once every seven days, only after a park's "Where to stay" first appears, and is held back on a Low Data Mode network; forecast requests always carry the public coordinates of all 63 parks. No request depends on the person's location. The Apple Watch app makes no network requests. The Apple Vision Pro app makes one: the same cloud forecast request to api.open-meteo.com for the 63 parks' public coordinates, behind its own switch in its Your privacy sheet; it cannot reach the other two hosts.

Background App Refresh (one background mode, fetch): about every six hours, when iOS allows, Nyx refreshes saved parks' cloud forecasts and park alerts from the same two public services (api.open-meteo.com, developer.nps.gov), so local reminders and the widget never rely on an old forecast. No user data is sent.

Field mode: on any park's detail screen, "I'm here tonight" opens a red, dimmed screen with a countdown to true darkness, a dark-adaptation clock, a Live Activity started on the device (no push) and "Where to look", which reads Core Motion attitude only while open. Its optional "Sound" switch (off by default, after an in-app explainer) places a tone in headphones; with headphones that report head motion, iOS asks once for Motion & Fitness access (NSMotionUsageDescription), and the motion never leaves the device. Best tried in the evening. Alarms use AlarmKit (iOS 26.1 and later); permission is requested in context, after an in-app explainer, when the person sets the first alarm.

Age assurance: where iOS reports that the account is subject to an age-assurance law (Declared Age Range: requiredRegulatoryFeatures contains declaredAgeRangeRequired, or isEligibleForAgeFeatures on iOS 26.2–26.3), Nyx requests an age range once per launch with gates 13, 16 and 18. Nyx has no age-restricted content: the response is not stored and changes nothing, and errors or a refusal leave the app unchanged. Elsewhere nothing is shown.

Links: park pages on nps.gov, Globe at Night, Open-Meteo and the Creative Commons licence open in Safari only when tapped; Nyx itself never requests them.

Reminders are local notifications, opt-in, for saved parks only: nights scoring 90 or more, up to five days ahead, with a recent full cloud forecast, at most one a week per park. Photos come only through PhotosPicker. The journal lives in SwiftData on the device (no CloudKit) and can be exported as a file the person saves. Siri, Shortcuts, widgets and Spotlight answer from data already on the device. Apple Intelligence features appear only where Apple's on-device model is available. The build includes the publisher's National Park Service API key. Developer screenshot launch arguments are compiled out of Release.
```

Add this sentence (shipped in build 8):

- **Translation of park text:** `When Nyx runs in a language other than English, park alerts and ranger programs from the National Park Service have a Translate button. It opens Apple's translation sheet (Translation framework, translationPresentation), only when the person taps it. iOS may download an Apple language pack on first use; Nyx itself sends nothing for this.`

Add this sentence only if the feature is in build 8 (integrator to confirm):

- **Maps hand-off:** `Viewing spots can open in Apple Maps when the person taps "Directions in Maps": the app hands the spot's public coordinates to Maps through a maps:// link. Nyx makes no request itself and uses no MapKit.`

## Age assurance (Texas SB 2420)

What Apple asks: since 2026-06-04, Apple tells developers that "in those regions, you must check the age of the people using your app" ([age assurance Q&A](https://developer.apple.com/support/age-assurance/), [Apple news](https://developer.apple.com/news/?id=sg176nne), read 2026-10-07 by the compliance audit). Nyx has no age-restricted content, accounts, messaging or purchases.

What Nyx does (`Nyx/Services/AgeAssurance.swift`, hook in `NyxApp`):

1. About 1.5 s after the first frame, once per launch, Nyx asks iOS whether this account needs an age range: on iOS 26.4 and later, `isEligibleForAgeFeatures` and then `requiredRegulatoryFeatures` containing `.declaredAgeRangeRequired`; on iOS 26.2–26.3, `isEligibleForAgeFeatures`. On iOS 26.0–26.1 the system cannot say, so Nyx never asks.
2. Only when the answer is yes, Nyx calls `requestAgeRange(ageGates: 13, 16, 18, in:)`. iOS shows its own sheet (or answers from its cache).
3. The response is dropped at once. Nothing is stored, logged or sent; no feature is gated; a refusal, an error or "not available" changes nothing.
4. Never in DEBUG screenshot scenarios; never blocks the interface.

Requirements: the **Declared Age Range** entitlement (`com.apple.developer.declared-age-range`, in `Config/Nyx.entitlements`; `verify_release.py` checks it). **Owner:** enable the Declared Age Range capability on the App ID `com.harrypakhale.nyx` in Certificates, Identifiers & Profiles (or let Xcode's automatic signing add it at archive), otherwise the request fails at runtime with a missing-entitlement error (harmless, but then Nyx does not comply). Test in the age-assurance sandbox (Settings → Developer, or App Store Connect test scenarios) before release.

Not done, and why: no `SignificantAppUpdate`/PermissionKit flow (Nyx has nothing a parent must approve; revisit if a social feature or an age-rating change ever happens), no App Store Server Notifications (Nyx has no server, so it cannot receive `RESCIND_CONSENT`; with nothing gated, a withdrawn consent changes nothing in the app). **Counsel review is still recommended** (an hour on SB 2420, and on Utah, effective 2027-05-06, and Louisiana, 2027-07-01, both from secondary sources). Keep the age rating at 4+ and answer the current questionnaire.

## Export compliance

`ITSAppUsesNonExemptEncryption = NO` on iPhone, Watch and Vision Pro (`project.yml`). Nyx uses only the encryption built into iOS for HTTPS, no CryptoKit or CommonCrypto (verified by grep, compliance audit C16). No export documentation is needed; answer "No" if App Store Connect asks.

## Storefronts and the EU Digital Services Act (C6)

**Recommendation: launch in the United States, Canada and Mexico only.** The data covers US parks only, and Spanish (Mexico) is the one other language. Leave the EU and the UK out until the owner decides whether he is a "trader" under the DSA (traders publish an address, phone and email on the EU product page; [Apple's DSA page](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements)). Leave China mainland out (it needs an ICP filing; from memory, unverified). App Store Connect → Pricing and Availability → Countries or Regions. **Mac availability:** do not make the iPad app available on Mac (field mode, compass, alarms and Live Activities are hidden there and were never tried).

## The name (C10)

Before submitting, the owner runs a **USPTO trademark search** (https://tmsearch.uspto.gov) for "NYX" in classes 9, 42, 38 and 41. Other apps named Nyx exist on the App Store, and NYX Professional Makeup is a well-known mark in cosmetics; a complaint is unlikely but would come under Guidelines 4.1(c) and 5.2.1. Keep **Noctis** as the agreed fallback. Never use the NPS arrowhead or the DarkSky logo; every public surface says Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.

## Data permissions on file (Guideline 5.2.2)

App Review may ask for proof of permission to use third-party data. Before submitting, the owner emails and keeps the replies:

- **Open-Meteo** (info@open-meteo.com): a free app with no ads, subscriptions or in-app purchases; 63-park batches about every six hours; credit as a link "Weather data by Open-Meteo.com" in About the data. Ask them to confirm non-commercial use.
- **National Park Service** (the API contact): the key ships in a public app; ask for a raised hourly limit (`INPUT_NEEDED.md` #10).
- **International Meteor Organization:** a courtesy note that Nyx shows dates, radiants and rates from the 2026 calendar, credited.

## Screenshots

**iPhone: upload the build 10 set in `Store/1.2 v10/iPhone/` (captured 2026-10-09; it shows build 10, so it serves 1.3 (10) unchanged).** `6.3-inch/` is required; `6.9-inch/` and `6.5-inch/` are optional. It supersedes the iPhone frames in `Store/1.1 v8/`, which show build 8. **iPad, Apple Watch and Apple Vision Pro: the sets in `Store/1.3 v11/`** (captured 2026-10-10 from the tree after the carry-forward commits; captions and contents in `Store/1.3 v11/README.md`). They show the watch's forecast models' range, the Vision Pro relief Moon and globe and the iPad city-light figure fix, which the uploaded 1.3 (10) lacks, so upload them with 1.3 (11); if 1.3 (10) itself is submitted, keep the build 8 sets in `Store/1.1 v8/` for these three devices. **Spanish frames wait for the native review.** Never upload the build 7 frames in `Store/Framed/`: they show scores from before score v2 (for example Joshua Tree 93 or 94, which the Bortle 3 cap now limits to 89) and copy that has since changed; showing them would contradict the app (Guideline 2.3). The owner's device pass (`INPUT_NEEDED.md` step 9) may still require a retake of any frame whose screen it changes. Reproduce the iPhone set with `python3 Scripts/capture_store.py SIM DERIVED en --out "Store/1.2 v10/raw"` on the iOS 27 iPhone 18 Pro simulator, then `swift Scripts/make_store_frames.swift`; the other devices from the raw captures in `Store/1.3 v11/raw/` with `swift Scripts/make_device_frames.swift "Store/1.3 v11"` (routes for each frame in that folder's README).

Slots (checked against Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) on 2026-10-06):

- **iPhone**, required "Dynamic Island, medium display" 1206×2622: `Store/1.2 v10/iPhone/6.3-inch/`; optional 1320×2868 `6.9-inch/` and 1284×2778 `6.5-inch/`.
- **iPad 13-inch**, 2064×2752 portrait: `Store/1.3 v11/iPad/` (8 frames).
- **Apple Watch**, 422×514: `Store/1.3 v11/Apple Watch/` (6 frames; one size across localizations).
- **Apple Vision Pro**, 3840×2160: `Store/1.3 v11/Apple Vision Pro/` (6 frames).

(The `Store/1.3 v11/` sets need 1.3 (11); with 1.3 (10) use `Store/1.1 v8/` for these three devices, as above.)

iPhone order (1.3 (10), real sky first; search results show only the first three, which hold one gauge): (1) Tonight's sky; (2) Tonight; (3) What's up tonight; (4) the score and its reasons; (5) field mode and (6) Where to look, in red; (7) the calendar; (8) what city light takes; (9) every park on the map; (10) the constellation (caption footnote "Sample entries"). Captions in `Store/1.2 v10/README.md`: calm, six words or fewer, no prices, no "new", no exclamation marks.

## Platform steps

- **iPad:** in the iOS build. Mac availability off (above).
- **Apple Watch:** in the iOS build (`Nyx.app/Watch/NyxWatch.app`, complications and the Red light control). Bundle IDs `com.harrypakhale.nyx.watchkitapp` and `.watchkitapp.widgets` carry the App Group. `WKRunsIndependentlyOfCompanionApp = NO`: the watch app needs the iPhone app.
- **Apple Vision Pro:** App Store Connect → + Add Platform → visionOS, upload `NyxVision` 1.3 (11) with its widget (`NyxVisionWidgets`, ID `com.harrypakhale.nyx.widgets`), add the screenshots and the visionOS page, and submit.

## Privacy

- App Privacy: **"No, we do not collect data from this app" (Data Not Collected), no tracking.** Reasoning in `PRIVACY.md`. Nothing in build 8 changes it: bulk alerts name all 63 parks, so a request says nothing about the person; background refresh repeats the same requests; age assurance stores and sends nothing; journal export is a file the person saves; diagnostics stay on the device.
- Confirm once, before review, that https://get-nyx.com/privacy serves the page dated October 8, 2026 (for Nyx 1.2: age range, links, campgrounds, Maps, translation, sound and Vision Pro). The site already serves it; this is a check, not a push.
- Run Xcode's "Generate Privacy Report" on the final archive.

## Accessibility Nutrition Labels

Declare only what the device pass confirms (`Store/1.1/accessibility-nutrition-labels.md`). Dark Interface can be declared now. The same gate governs the description's accessibility sentence (C11): "designed for VoiceOver and the largest text sizes" until the pass.

## In-App Events and featuring

- **Featuring:** one **App Enhancements** nomination for 1.3, publish window **Nov 6–8, 2026** (the new-moon weekend), filed **by Oct 16**; then a **New Content** nomination for the Geminids event (Dec 12–15), filed **by Nov 20**. (App Launch no longer applies: 1.1 is live.) Texts in `Store/1.1/featuring-nominations.md`.
- **In-App Events:** `Store/1.1/in-app-events.md` (artwork in `Store/1.1/events/`). Submit each at least 7 days before its publish date, once build 8 is approved.

## App Store Connect checklist

1. Release or withdraw the approved 1.2 first (`INPUT_NEEDED.md` step 12), then + Version → **1.3** (iOS and visionOS); select build 11 (iOS, with the watch inside) and the visionOS build 11 once uploaded (build 10 for each until then).
2. Export compliance: No (above).
3. TestFlight: install on iPhone (iOS 26 and 27 if possible), iPad, Apple Watch and Vision Pro; run the device pass; enable the public TestFlight link for the nomination.
4. Version page: promotional text, description, keywords, subtitle, screenshots (iPhone `Store/1.2 v10/iPhone/`; iPad, Watch and Vision Pro `Store/1.3 v11/` with 1.3 (11), or `Store/1.1 v8/` with 1.3 (10)), optional App Preview, **What's New in 1.3** (`Store/1.1/metadata.md`). The `Store/1.2 v10/` frames show build 10 and serve 1.3.
5. Pricing and Availability: US, Canada, Mexico; Mac availability off.
6. App Privacy (Data Not Collected), Accessibility Nutrition Labels (only passed features), age rating (expected 4+; social media capabilities: No), review notes (above).
7. Phased release (or manual) → Submit for Review. File the App Enhancements nomination for 1.3 (by Oct 16 for Nov 6–8) and attach the events once approved.
8. After approval: install the update from the App Store over the version it has (1.1, or 1.2 if released) with a journal entry, run an offline sanity check, then release (the website already links to the live App Store page).

## Owner sign-off

| Gate | Status |
|---|---|
| Privacy label | READY: Data Not Collected (`PRIVACY.md`) |
| Privacy page dated October 8, 2026 live at get-nyx.com/privacy | CONFIRM (owner): already served; open it once before submitting |
| Declared Age Range capability on the App ID | OPEN (owner) |
| Counsel on SB 2420 | RECOMMENDED (owner) |
| USPTO search for NYX | OPEN (owner) |
| Storefronts and DSA trader status | OPEN: recommendation US, Canada, Mexico |
| Open-Meteo, NPS, IMO emails | OPEN (owner) |
| Build 10 archives (1.3) and `verify_release.py --require-key` | DONE 2026-10-09: iOS (with the Watch app) and visionOS uploaded as 1.3 (10), processing (`INPUT_NEEDED.md` #12); confirm the processed builds in App Store Connect. Build 8 (1.2) was uploaded 2026-10-08 and is approved. Build 11 (1.3): built and tested 2026-10-10 (zero warnings, 504 tests), not archived or uploaded; waits for the owner's word |
| Screenshots | iPhone DONE from build 10 (`Store/1.2 v10/`, 2026-10-09, all three sizes); iPad, Watch and Vision Pro DONE from the carry-forward tree (`Store/1.3 v11/`, 2026-10-10) for 1.3 (11) (`Store/1.1 v8/` with 1.3 (10)); retake any frame whose screen the device pass changes |
| Physical device pass (accessibility, field mode at night, Watch, Vision Pro) | OPEN (`AUDIT.md`) |
| Spanish native review | OPEN |
