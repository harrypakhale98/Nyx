# Privacy review — 2026-10-02

## Implementation evidence

Nyx has no accounts, tracking, analytics/crash SDKs, advertising identifier, ATT prompt, CloudKit sync or server. No package dependencies. Journal notes/selected photos and saved parks live in SwiftData on-device; PhotosPicker is the only photo API. Location is requested in context, While Using only, and used for on-device distances. Local notifications contain rule-based forecast caveats. Foundation Models receives small local source records and never calls a remote model.

`SafeHTTP` is the only network transport. It accepts HTTPS and exactly `developer.nps.gov` or `api.open-meteo.com`, rejects every redirect, uses an ephemeral session with cookies/cache disabled, and checks independent privacy preferences before each request. NPS requests contain a park code and developer API key. Weather requests contain public park coordinates, not the device's location. Network servers necessarily see an IP address and ordinary request metadata. Disabling updates prevents subsequent requests; an already transmitted request cannot be recalled.

`parks.json` contains NPS source URLs for provenance. They are not opened or downloaded by the app. Research scripts/USNO fixtures are development tools, not runtime network code. Apple's location, Photos, Siri, model provisioning and device backup services are OS-managed; this review does not claim control over the operating system's network traffic.

## Manifests

App and widget each bundle `PrivacyInfo.xcprivacy`: tracking false; tracking domains empty; declared collected data empty; UserDefaults required reasons CA92.1 (own preferences) and 1C8F.1 (same developer's App Group preferences). Allowed data hosts appear in a comment, not `NSPrivacyTrackingDomains`, because they are not tracking domains and Apple defines no general host-allowlist manifest key. No custom/unrecognized manifest keys were invented.

Direct source inspection found no disk-space, file-timestamp, system-uptime or active-keyboard required-reason API usage. Ordinary file I/O and Date calculations are not those APIs. Build/Archive must include the manifests in both bundle roots. The development-signed archive validates locally with the correct App Group; this is not App Store distribution validation. Owner must generate Xcode's archive privacy report and validate the distribution export before uploading.

[Apple manifest documentation](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) and [required API reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype).

## App Store label draft — unresolved release gate

**Target: Data Not Collected. Do not publish this declaration yet.**

The code does not send identity, journal, photos, device coordinates or analytics. However, [Open-Meteo's free API policy](https://open-meteo.com/en/terms) permits IP-address collection for operation/abuse prevention and retains troubleshooting logs, potentially including requested coordinates, for 90 days. Requested coordinates here are public parks. That does not eliminate the IP-retention question. NPS/API.gov server logging also needs publisher review.

[Apple's App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) defines collection by off-device access beyond servicing a real-time request and requires accurate disclosures for applicable third-party practices. Its partner definition refers to integrated external code; Nyx uses no vendor SDK. Whether these direct API providers require disclosure must be resolved authoritatively, not inferred solely from the lack of SDKs.

Before submission, the account owner must obtain authoritative Apple/provider guidance and record the result here, or obtain a retention arrangement compatible with free data and the two allowed hosts. Do not describe retained IP logs as absent. No proxy/server, paid provider, extra host or silent change of the fixed privacy requirement has been added. The checked-in manifest is an implementation draft, not certification of the external retention policy.

Proposed answers **only after resolving the gate**: no tracking; no developer data collection; local location/photos/journal do not count as transmitted collection. If the authoritative answer requires disclosure, the current brief's Data Not Collected requirement needs an explicit owner decision before shipping.

## Device verification still required

Use iPhone Settings → Privacy & Security → App Privacy Report. Exercise all screens with network updates enabled, then disabled; confirm app-initiated weather/NPS traffic matches the two hosts and no journal/device location appears in requests. Check no permission prompt at onboarding, denied location retains manual planning, selected photo access only, local-notification removal after disabling, and no required-reason API omissions in the archive report. Device backups may include app data according to the user's OS settings; Nyx itself never uploads a journal.
