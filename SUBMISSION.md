# Nyx 1.1 submission package (first public release)

**Build 1.1 (8)** is Nyx's **first public release**: 1.0 was never released, and 1.1 (7) was uploaded but never submitted. App Store Connect therefore shows no What's New field, and the featuring nomination is an **App Launch** (`Store/1.1/featuring-nominations.md`). Release is **manual** after approval.

Archive both builds from the integrated `main` after the integrator bumps `CURRENT_PROJECT_VERSION` to 8: the iOS archive (iPhone and iPad app with the widgets and the Apple Watch app inside) and the visionOS archive (`NyxVision`, same bundle ID). Before uploading, run `python3 Scripts/verify_release.py --require-key <ios archive> <vision archive>`; it must pass, including the new checks for the age-range entitlement and the Safari link hosts. A development-signed archive is not an App Store validation result: distribute from Xcode's Organizer, which re-signs for the App Store.

**Release gates** (owner, `INPUT_NEEDED.md`): the device pass, the Spanish decision, the privacy page push, the Declared Age Range capability on the App ID, counsel on age assurance, the trademark search and the storefront decision below.

## The record

- **Name:** Nyx: Dark Sky Planner ("Nyx" alone is taken). Home Screen name **Nyx**. Fallback: **Noctis**.
- **Subtitle:** **Stargazing in national parks** (28). Reasoning in `Store/1.1/metadata.md` § Subtitle decision.
- **Categories:** Travel (primary), Weather (secondary). **Price:** Free; no subscriptions, ads or in-app purchases. Keep it that way: Open-Meteo's free tier is for non-commercial apps without subscriptions or advertising.
- **Platforms:** iPhone, iPad, Apple Watch (inside the iOS build, companion), Apple Vision Pro (own build, same bundle ID `com.harrypakhale.nyx`, universal purchase). iOS/iPadOS 26.0+, watchOS 26.0+, visionOS 26.0+. Vision Pro may be submitted a week after iOS if it threatens the date.
- **Languages:** English (U.S.). Spanish (Mexico) store metadata only after native review (`Store/1.1/metadata-es.md`); the in-app Spanish is the owner's AM-12 decision.
- **Copyright:** `2026 Hardik Pakhale`. **URLs:** privacy https://harrypakhale98.github.io/Nyx/privacy.html · support https://harrypakhale98.github.io/Nyx/support.html · marketing https://harrypakhale98.github.io/Nyx/ (GitHub Pages from `docs/`; not app endpoints). Contact harry.pakhale98@gmail.com.

## Metadata (paste from the files, not from memory)

- English: `Store/1.1/metadata.md` (promotional text, description, keywords, subtitle; counts verified by script). Confirm the feature table at its top against build 8 first.
- visionOS version page: `Store/1.1/metadata-visionos.md`.
- Spanish: `Store/1.1/metadata-es.md`, only after the native review.
- App Preview (optional): `Store/1.1/app-preview-script.md`.

## Review notes (paste into App Review Information → Notes)

```
Nyx has no account and no login; nothing needs a demo account. Onboarding asks for no permissions and can be skipped. Choosing a starting park by hand works with location denied.

Data and network: the app contacts exactly three public services, each with its own switch in Settings → Your privacy: developer.nps.gov (park alerts and ranger programs), api.open-meteo.com (cloud forecasts) and air-quality-api.open-meteo.com (smoke and haze). Alert requests always name all 63 parks in one request; forecast requests always carry the public coordinates of all 63 parks. No request depends on the person's location. The Apple Watch app makes no network requests. The Apple Vision Pro app makes one: the same cloud forecast request to api.open-meteo.com for the 63 parks' public coordinates, behind its own switch in its Your privacy sheet; it cannot reach the other two hosts.

Background App Refresh (one background mode, fetch): about every six hours, when iOS allows, Nyx refreshes saved parks' cloud forecasts and park alerts from the same two public services (api.open-meteo.com, developer.nps.gov), so local reminders and the widget never rely on an old forecast. No user data is sent.

Field mode: on any park's detail screen, "I'm here tonight" opens a red, dimmed screen with a countdown to true darkness, a dark-adaptation clock, a Live Activity started on the device (no push) and "Where to look", which reads Core Motion attitude only while open. Best tried in the evening. Alarms use AlarmKit (iOS 26.1 and later); permission is requested in context, after an in-app explainer, when the person sets the first alarm.

Age assurance: where iOS reports that the account is subject to an age-assurance law (Declared Age Range: requiredRegulatoryFeatures contains declaredAgeRangeRequired, or isEligibleForAgeFeatures on iOS 26.2–26.3), Nyx requests an age range once per launch with gates 13, 16 and 18. Nyx has no age-restricted content: the response is not stored and changes nothing, and errors or a refusal leave the app unchanged. Elsewhere nothing is shown.

Links: park pages on nps.gov, Globe at Night, Open-Meteo and the Creative Commons licence open in Safari only when tapped; Nyx itself never requests them.

Reminders are local notifications, opt-in, for saved parks only: nights scoring 90 or more, up to five days ahead, with a recent full cloud forecast, at most one a week per park. Photos come only through PhotosPicker. The journal lives in SwiftData on the device (no CloudKit) and can be exported as a file the person saves. Siri, Shortcuts, widgets and Spotlight answer from data already on the device. Apple Intelligence features appear only where Apple's on-device model is available. The build includes the publisher's National Park Service API key. Developer screenshot launch arguments are compiled out of Release.
```

Add these sentences only if the feature is in build 8 (integrator to confirm):

- **Maps hand-off:** `Viewing spots can open in Apple Maps when the person taps "Directions in Maps": the app hands the spot's public coordinates to Maps through a maps:// link. Nyx makes no request itself and uses no MapKit.`
- **Translation of park text:** `Park descriptions and alerts from the National Park Service can be translated on the device with Apple's Translation framework (translationPresentation), only when the person asks. Nyx sends nothing for this.`

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

**Recapture every set from build 8 before upload.** The build 7 frames in `Store/Framed/` show scores from before score v2 (for example Joshua Tree 93 or 94, which the Bortle 3 cap now limits to 89) and copy that has since changed ("Moon and darkness only. Clouds unknown."). Showing them would contradict the app (Guideline 2.3). Reproduce with `python3 Scripts/capture_store.py SIM DERIVED en|es` and `swift Scripts/make_store_frames.swift [es]`, then `swift Scripts/make_device_frames.swift`.

Slots (checked against Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) on 2026-10-06):

- **iPhone**, required "Dynamic Island, medium display" 1206×2622: `Store/Framed/6.3-inch/`; optional 1320×2868 `6.9-inch/` and 1284×2778 `6.5-inch/`.
- **iPad 13-inch**, 2064×2752 portrait: `Store/Framed/iPad-13-inch/`.
- **Apple Watch**, 422×514: `Store/Framed/Watch-Ultra/` (one size across localizations).
- **Apple Vision Pro**, 3840×2160: `Store/Framed/Vision-Pro/` (add a star-names frame and the Moon on your table).

Order (hero order, DX-19 and ST-2): (1) Tonight answering where *and* when, with no amenity alert in view; (2) the score and its reasons; (3) What's up tonight; (4) the calendar; then field mode and Where to look (red, mostly black thumbnails belong after the calendar, because search results show only the first three); then the trip planner, the constellation (caption footnote "Sample entries"), Listen, sky glow and access. Captions: calm, six words or fewer, no prices, no "new", no exclamation marks.

## Platform steps

- **iPad:** in the iOS build. Mac availability off (above).
- **Apple Watch:** in the iOS build (`Nyx.app/Watch/NyxWatch.app`, complications and the Red light control). Bundle IDs `com.harrypakhale.nyx.watchkitapp` and `.watchkitapp.widgets` carry the App Group. `WKRunsIndependentlyOfCompanionApp = NO`: the watch app needs the iPhone app.
- **Apple Vision Pro:** App Store Connect → + Add Platform → visionOS, upload `NyxVision` 1.1 (8) with its widget (`NyxVisionWidgets`, ID `com.harrypakhale.nyx.widgets`), add the screenshots and the visionOS page, and submit.

## Privacy

- App Privacy: **"No, we do not collect data from this app" (Data Not Collected), no tracking.** Reasoning in `PRIVACY.md`. Nothing in build 8 changes it: bulk alerts name all 63 parks, so a request says nothing about the person; background refresh repeats the same requests; age assurance stores and sends nothing; journal export is a file the person saves; diagnostics stay on the device.
- Push `docs/` (privacy page dated October 7, 2026, with the age-range and links paragraphs) before review.
- Run Xcode's "Generate Privacy Report" on the final archive.

## Accessibility Nutrition Labels

Declare only what the device pass confirms (`Store/1.1/accessibility-nutrition-labels.md`). Dark Interface can be declared now. The same gate governs the description's accessibility sentence (C11): "designed for VoiceOver and the largest text sizes" until the pass.

## In-App Events and featuring

- **Featuring:** one **App Launch** nomination for 1.1, publish window **Nov 6–8, 2026** (the new-moon weekend), filed **by Oct 16**; then a **New Content** nomination for the Geminids event (Dec 12–15), filed **by Nov 20**. No App Enhancements nomination until 1.2. Texts in `Store/1.1/featuring-nominations.md`.
- **In-App Events:** `Store/1.1/in-app-events.md` (artwork in `Store/1.1/events/`). Submit each at least 7 days before its publish date, once build 8 is approved.

## App Store Connect checklist

1. Rename the pending version to 1.1 if needed; select build 8 (iOS, with the watch inside) and the visionOS build 8.
2. Export compliance: No (above).
3. TestFlight: install on iPhone (iOS 26 and 27 if possible), iPad, Apple Watch and Vision Pro; run the device pass; enable the public TestFlight link for the nomination.
4. Version page: promotional text, description, keywords, subtitle, screenshots (build 8 captures), optional App Preview; no What's New.
5. Pricing and Availability: US, Canada, Mexico; Mac availability off.
6. App Privacy (Data Not Collected), Accessibility Nutrition Labels (only passed features), age rating (expected 4+; social media capabilities: No), review notes (above).
7. Manual release → Submit for Review. File the App Launch nomination (by Oct 16) and attach the events once approved.
8. After approval: install from the App Store, run an offline sanity check, then release; flip the website's one line to the App Store link (`docs/index.html` comment).

## Owner sign-off

| Gate | Status |
|---|---|
| Privacy label | READY: Data Not Collected (`PRIVACY.md`) |
| Privacy page with age range and links | READY in the repo; push `docs/` |
| Declared Age Range capability on the App ID | OPEN (owner) |
| Counsel on SB 2420 | RECOMMENDED (owner) |
| USPTO search for NYX | OPEN (owner) |
| Storefronts and DSA trader status | OPEN: recommendation US, Canada, Mexico |
| Open-Meteo, NPS, IMO emails | OPEN (owner) |
| Build 8 archives and `verify_release.py --require-key` | OPEN (integrator) |
| Screenshots recaptured from build 8 | OPEN |
| Physical device pass (accessibility, field mode at night, Watch, Vision Pro) | OPEN (`AUDIT.md`) |
| Spanish native review | OPEN |
