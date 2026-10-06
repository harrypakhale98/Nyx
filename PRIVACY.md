# Privacy review — 2026-10-02

## Implementation evidence

Nyx has no accounts, tracking, analytics/crash SDKs, advertising identifier, ATT prompt, CloudKit sync or server. No package dependencies. Journal notes/selected photos and saved parks live in SwiftData on-device; PhotosPicker is the only photo API. Location is requested in context, While Using only, and used for on-device distances. Local notifications contain rule-based forecast caveats. Foundation Models receives small local source records and never calls a remote model.

`SafeHTTP` is the only network transport. It accepts HTTPS and exactly `developer.nps.gov`, `api.open-meteo.com` or `air-quality-api.open-meteo.com` (smoke/aerosol forecast, added with the owner's approval on 2026-10-05), rejects every redirect, uses an ephemeral session with cookies/cache disabled, and checks independent privacy preferences before each request. NPS requests contain a park code and developer API key. Weather and air-quality requests always contain all 63 public park coordinates, never the device's location or a location-dependent subset. Network servers necessarily see an IP address and ordinary request metadata. Disabling updates prevents subsequent requests; an already transmitted request cannot be recalled.

`parks.json` contains NPS source URLs for provenance. They are not opened or downloaded by the app. Research scripts/USNO fixtures are development tools, not runtime network code. Apple's location, Photos, Siri, model provisioning and device backup services are OS-managed; this review does not claim control over the operating system's network traffic.

## Apple Vision Pro app (2026-10-05)

`NyxVision` compiles only the astronomy engine, the score, the bundled tables and its own views. No networking source (`SafeHTTP`, `DataServices`, `ForecastDetail`) is in the target, it requests no permissions (no location, photos, notifications or world sensing), stores nothing (no UserDefaults, no SwiftData), and its scores are labelled "moon and darkness only" because it fetches no forecast. Its manifest (`NyxVision/Resources/PrivacyInfo.xcprivacy`) declares tracking false, no collected data and no required-reason APIs. The privacy label stays "Data Not Collected".

## Manifests

App and widget each bundle `PrivacyInfo.xcprivacy`: tracking false; tracking domains empty; declared collected data empty; UserDefaults required reasons CA92.1 (own preferences) and 1C8F.1 (same developer's App Group preferences). Allowed data hosts appear in a comment, not `NSPrivacyTrackingDomains`, because they are not tracking domains and Apple defines no general host-allowlist manifest key. No custom/unrecognized manifest keys were invented.

Direct source inspection found no disk-space, file-timestamp, system-uptime or active-keyboard required-reason API usage. Ordinary file I/O and Date calculations are not those APIs. Build/Archive must include the manifests in both bundle roots. The development-signed archive validates locally with the correct App Group; this is not App Store distribution validation. Owner must generate Xcode's archive privacy report and validate the distribution export before uploading.

[Apple manifest documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) and [required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## App Store privacy label — recommendation: Data Not Collected

Reviewed October 3, 2026 against Apple's [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) definitions:

- Apple defines **collect** as transmitting data off the device so that *you and/or your third-party partners* can access it longer than needed to service the request in real time.
- Apple defines **third-party partners** as analytics tools, ad networks, third-party SDKs, or other external vendors *whose code you've added to your app*. Nyx embeds no vendor code; it calls two public web APIs with Apple's URLSession.
- Apple's own example: an IP address sent on a server call and not retained by you need not be disclosed.
- What leaves the device: public park coordinates for all 63 parks in each request (Open-Meteo forecasts and air quality, so they never reflect where the user is) and park codes (NPS). NPS requests cover parks the user opens or saves and parks within the Tonight radius, which can suggest a broad region when "Near me" is used; the in-app privacy screen says so and park updates can be switched off. No device coordinates, journal, photo, identifier or account data is ever sent. The developer runs no server and receives nothing.
- [Open-Meteo](https://open-meteo.com/en/terms) states its logs are not linked to user identities, are not shared, and are deleted after 90 days. The NPS API is a public government service.

**Recommended App Store Connect answer: "No, we do not collect data from this app"** (shown on the store as Data Not Collected), with no tracking. This matches the spec (§3, §13). The privacy policy (`docs/privacy.html`) still tells users, plainly, that the three services (two of them Open-Meteo) see their IP address and links the providers' policies, so the label and the policy are consistent and nothing is hidden.

The publisher makes the final declaration in App Store Connect; this is the reasoning to rely on. Revisit it if a vendor SDK, analytics, accounts, iCloud sync or a developer server is ever added.

## Device verification still required

Use iPhone Settings → Privacy & Security → App Privacy Report. Exercise all screens with network updates enabled, then disabled; confirm app-initiated weather/NPS traffic matches the three hosts and no journal/device location appears in requests. Check no permission prompt at onboarding, denied location retains manual planning, selected photo access only, local-notification removal after disabling, and no required-reason API omissions in the archive report. Device backups may include app data according to the user's OS settings; Nyx itself never uploads a journal.
