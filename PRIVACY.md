# Privacy review — 2026-10-02, updated 2026-10-07 for build 1.1 (8), the first public release

## Implementation evidence

Nyx has no accounts, tracking, analytics/crash SDKs, advertising identifier, ATT prompt, CloudKit sync or server. No package dependencies. Journal notes/selected photos and saved parks live in SwiftData on-device; PhotosPicker is the only photo API. Location is requested in context, While Using only, and used for on-device distances. Local notifications contain rule-based forecast caveats. Field mode (2026-10-05) reads Core Motion's device attitude only while "Where to look" is open, to turn the sky to where the phone points; it needs no permission prompt, is not recorded and never leaves the phone (true north is used only when location is already allowed). Its alarms are AlarmKit alarms on this iPhone, set only by the person after an in-app explainer; its Live Activity is started locally and updated by the app, with no push token or server. It changes screen brightness, auto-lock and night vision only while open and restores them on exit. Foundation Models receives small local source records and never calls a remote model.

`SafeHTTP` is the only network transport. It accepts HTTPS and exactly `developer.nps.gov`, `api.open-meteo.com` or `air-quality-api.open-meteo.com` (smoke/aerosol forecast, added with the owner's approval on 2026-10-05), rejects every redirect, uses one ephemeral session per service with cookies/cache disabled, and checks independent privacy preferences before each request. NPS alert requests always contain all 63 park codes (one request, at most every six hours); a ranger-program request contains the code of the park whose page is open. The NPS key travels in the `X-Api-Key` header: the bundled key, or a key the person entered in Your privacy → Advanced (kept in the Keychain on the device). Weather and air-quality requests always contain the public coordinates of all 63 parks (each park's first named viewing spot), never the device's location or a location-dependent subset. With the one background mode (`fetch`, approved 2026-10-07), iOS may let Nyx repeat the same requests about every six hours to keep saved parks' forecasts, the widget, the watch and reminders current; nothing else is sent. Network servers necessarily see an IP address and ordinary request metadata. Disabling updates prevents subsequent requests; an already transmitted request cannot be recalled.

**Apple Watch** (added 2026-10-05): the watch app and its complications make no network requests; the network transport is not compiled into either watch target (`Scripts/verify_release.py` checks this). The iPhone hands the watch the saved park IDs, the starting park, the night-vision switch and the cached cloud forecasts through WatchConnectivity, which Apple carries directly between the paired devices (Bluetooth or local Wi-Fi), not through a Nyx server. Nothing goes from the watch to the iPhone. The watch keeps that context and its own choices (park, colours) in its App Group on the watch. No location, health or motion data is read on the watch.

`parks.json` contains NPS source URLs for provenance. They are not opened or downloaded by the app. Some links open in Safari, the system browser, only when the person taps them: a viewing spot's nps.gov accessibility page (URL from the bundled `accessible-spots.json`), Globe at Night (globeatnight.org, from a journal entry, nothing prefilled), the park's current-conditions page on www.nps.gov when NPS alerts are busy, and (since 2026-10-07, for the licence credits in About the data) open-meteo.com and the Creative Commons BY 4.0 licence page on creativecommons.org. Nyx makes no request to any of them; they are SwiftUI `Link`s handed to the system, and `verify_release.py` checks the in-code list (`BrowserLink`: globeatnight.org, www.nps.gov, open-meteo.com, creativecommons.org). If the Settings rows for the privacy policy and support pages land (harrypakhale98.github.io, apps.apple.com), they join the same list. The sky-glow and step-free data are bundled; nothing is downloaded for them. Research scripts/USNO fixtures are development tools, not runtime network code. Apple's location, Photos, Siri, model provisioning and device backup services are OS-managed; this review does not claim control over the operating system's network traffic.

**Delight (2026-10-06).** *Plan a trip* adds a night to Calendar through EventKitUI's `EKEventEditViewController`. Since iOS 17 that editor runs outside the app and needs no calendar permission: Nyx fills in a draft (title, park-local dark hours, the park's name as plain text, score notes, a `nyx://` link back to that night) and the person chooses the calendar and saves it, or cancels. Nyx never requests calendar access, never reads a calendar or event, and ships no calendar usage description. Trip plans, the journal's constellation, "skies you've seen" and the year recap are computed on the iPhone from bundled data, cached forecasts and park updates and the journal; nothing is fetched for them, and their share cards and plan text leave the phone only through the share sheet the person opens. The recap's optional wording uses the on-device model only and receives the recap's facts and up to a few short journal notes. *First light* uses location only when it was already allowed and only between 5 PM and 7 AM device time, once each time Nyx becomes active, to see whether the iPhone is at a park in true darkness; the position is used on the device and discarded, and a "first light shown" flag per park is kept in the app's preferences on this iPhone. Choosing an alternate app icon is a local system setting.

## Apple Vision Pro app (2026-10-05)

`NyxVision` compiles only the astronomy engine, the score, the bundled tables and its own views. No networking source (`SafeHTTP`, `DataServices`, `ForecastDetail`) is in the target, it requests no permissions (no location, photos, notifications or world sensing), stores nothing (no UserDefaults, no SwiftData), and because it fetches no forecast its scores use each park's bundled usual clouds and are labelled that way (score v2, 2026-10-07). Its star names, constellation figures, volumetric Moon and visionOS widget (`NyxVisionWidgets`, its own empty manifest) are bundled data and add no network, permission or storage. Its manifest (`NyxVision/Resources/PrivacyInfo.xcprivacy`) declares tracking false, no collected data and no required-reason APIs. The privacy label stays "Data Not Collected".

## Platform surfaces (2026-10-06)

- **MetricKit, on device only.** Nyx subscribes to iOS's daily MetricKit reports (`MetricManager` on iOS 27, `MXMetricManager` on iOS 26) and keeps one number from them: the last average pixel luminance, with the date it covers, in the app's own UserDefaults. It is shown in About the data and Your privacy so people can see how dark Nyx keeps the screen. Nothing else from the report is read or stored, and nothing is sent: Nyx has no server or analytics. MetricKit is Apple's framework, not vendor code, and is not a required-reason API. Before a real report arrives the line is simply absent (DEBUG builds have a fixture labelled "Debug fixture, not a measurement").
- **Widgets, Spotlight, Siri and Shortcuts** compute from the bundled parks and the cached forecasts already on the phone. The medium widget's "next park" button stores the chosen park ID and night in the App Group defaults. Spotlight items for the 63 parks are public facts (name, state, Dark Sky designation), indexed into the device's own index.
- **Ask Nyx's tools** run the engine on the phone over the bundled parks and cached forecasts; the on-device model (Foundation Models' `SystemLanguageModel`) never uses Private Cloud Compute or any network service.
- **Reminders on iOS 27** carry the park's App Intents entity identifier (`appEntityIdentifiers`), so Siri can open the park from the notification. It is the park's public ID, local to the phone.

## Manifests

App, widget, watch app and watch widget each bundle `PrivacyInfo.xcprivacy`: tracking false; tracking domains empty; declared collected data empty; UserDefaults required reasons CA92.1 (own preferences) and 1C8F.1 (same developer's App Group preferences). Allowed data hosts appear in a comment, not `NSPrivacyTrackingDomains`, because they are not tracking domains and Apple defines no general host-allowlist manifest key. No custom/unrecognized manifest keys were invented.

Direct source inspection found no disk-space, file-timestamp, system-uptime or active-keyboard required-reason API usage. Ordinary file I/O and Date calculations are not those APIs. Build/Archive must include the manifests in both bundle roots. The development-signed archive validates locally with the correct App Group; this is not App Store distribution validation. Owner must generate Xcode's archive privacy report and validate the distribution export before uploading.

[Apple manifest documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) and [required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## App Store privacy label — recommendation: Data Not Collected

Reviewed October 3, 2026 against Apple's [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) definitions:

- Apple defines **collect** as transmitting data off the device so that *you and/or your third-party partners* can access it longer than needed to service the request in real time.
- Apple defines **third-party partners** as analytics tools, ad networks, third-party SDKs, or other external vendors *whose code you've added to your app*. Nyx embeds no vendor code; it calls two public web APIs with Apple's URLSession.
- Apple's own example: an IP address sent on a server call and not retained by you need not be disclosed.
- What leaves the device (build 8): public coordinates for all 63 parks in each request (Open-Meteo forecasts and air quality, so they never reflect where the user is) and park codes (NPS). Alert requests always name all 63 parks, so they reveal nothing about where the user is; a program request names only the park whose page is open. Park updates can be switched off. A journal export (`.nyxjournal`) is a file the person saves or shares themselves; Nyx sends it nowhere. Crash and hang reports from MetricKit stay on the device and leave only if the person copies or shares them. No device coordinates, journal, photo, identifier or account data is ever sent. The developer runs no server and receives nothing.
- [Open-Meteo](https://open-meteo.com/en/terms) states its logs are not linked to user identities, are not shared, and are deleted after 90 days. The NPS API is a public government service.

**Recommended App Store Connect answer: "No, we do not collect data from this app"** (shown on the store as Data Not Collected), with no tracking. This matches the spec (§3, §13). The privacy policy (`docs/privacy.html`) still tells users, plainly, that the three services (two of them Open-Meteo) see their IP address and links the providers' policies, so the label and the policy are consistent and nothing is hidden.

The publisher makes the final declaration in App Store Connect; this is the reasoning to rely on. Revisit it if a vendor SDK, analytics, accounts, iCloud sync or a developer server is ever added.

## Age assurance (2026-10-07)

Texas SB 2420 (in force since 2026-06-04, per Apple) and later Utah and Louisiana laws ask apps to check the age range of accounts in those states. Nyx uses Apple's Declared Age Range framework (`Nyx/Services/AgeAssurance.swift`, entitlement `com.apple.developer.declared-age-range`):

- Once per launch, about 1.5 s after the first frame, Nyx asks iOS whether this account requires an age range (`isEligibleForAgeFeatures`, then `requiredRegulatoryFeatures` containing `.declaredAgeRangeRequired` on iOS 26.4+; `isEligibleForAgeFeatures` alone on iOS 26.2–26.3; nothing on iOS 26.0–26.1, where the system cannot say).
- Only when it does, Nyx calls `requestAgeRange(ageGates: 13, 16, 18, in:)`. iOS presents its own sheet or answers from its own cache.
- The response is discarded when the call returns: it is not stored (no UserDefaults, file, SwiftData or Keychain), not logged, not sent, and nothing in the app depends on it. Refusal and errors are silent. A per-process flag prevents a second request in the same launch; it is never written to disk.
- Under Apple's definition of "collect", nothing leaves the device, so the label stays Data Not Collected. Apple's framework, not vendor code, handles the exchange with the system. No required-reason API is involved.
- Not used: PermissionKit significant-change consent (nothing to consent to) and App Store Server Notifications (no server). Counsel review is still recommended (owner).

## Maps hand-off and translation (planned; integrator to confirm for build 8)

- **Open in Maps** from a viewing spot, if shipped: a user-initiated `maps://` link carrying the spot's public coordinates from `parks.json`, opened by the system in Apple Maps. Nyx makes no request and uses no MapKit; what Maps does is governed by Apple's policy. The product brief's "nothing else, including Apple routing services" refers to requests Nyx makes; this is a hand-off the person chooses. Add `maps` to the documented hand-offs and to `verify_release.py` if it uses a URL literal.
- **On-device translation** of NPS descriptions and alerts, if shipped: SwiftUI's `translationPresentation` shows Apple's Translation sheet when the person asks. Translation runs through Apple's framework (on device once languages are downloaded); Nyx sends nothing. No change to the label.

## Build 8 at a glance

| Change | Leaves the device | Label effect |
|---|---|---|
| Bulk NPS alerts (all 63 park codes, one request, at most every 6 h) | Park codes only; the same request for everyone | None; removes the old "broad region" caveat |
| Background App Refresh (`fetch`, about every 6 h) | The same public requests as in the app | None |
| AlarmKit alarms | Nothing; alarms are local | None |
| Third host, air-quality-api.open-meteo.com | Public park coordinates | None |
| Journal export / import (`.nyxjournal`) | Only if the person shares the file | None |
| Diagnostics (MetricKit reports) | Only if the person copies or shares one | None |
| Age assurance (Declared Age Range) | Nothing from Nyx | None |
| Credits links (open-meteo.com, creativecommons.org) | Opened in Safari only when tapped | None |

## Device verification still required

Use iPhone Settings → Privacy & Security → App Privacy Report. Exercise all screens with network updates enabled, then disabled; confirm app-initiated weather/NPS traffic matches the three hosts and no journal/device location appears in requests. In the age-assurance sandbox (Settings → Developer), confirm the age-range sheet appears only for a regulated test account and that Nyx behaves identically after sharing, declining and an error. Check no permission prompt at onboarding, denied location retains manual planning, selected photo access only, local-notification removal after disabling, and no required-reason API omissions in the archive report. Device backups may include app data according to the user's OS settings; Nyx itself never uploads a journal.
