# Privacy

How Nyx handles data, for anyone reading the code. The user-facing policy is at [get-nyx.com/privacy](https://get-nyx.com/privacy).

Nyx has no account, no server, no analytics or crash SDK, no ads and no tracking. There's no App Tracking Transparency prompt and no iCloud sync. The App Store label is **Data Not Collected**.

## Network

All requests go through `SafeHTTP`. It only allows HTTPS to these four hosts and rejects redirects:

| Host | Used for | What's sent |
|---|---|---|
| `developer.nps.gov` | Alerts, ranger programs, campgrounds | Alerts and campgrounds: all 63 park codes in one request, so it says nothing about which park you care about. Programs: the code of the park page you have open. |
| `api.open-meteo.com` | Cloud forecasts | Public coordinates of all 63 parks together. For saved spots, a separate request with coordinates rounded to 0.1° (about 11 km). For world places, every place in a 10°×10° tile. |
| `air-quality-api.open-meteo.com` | Smoke and haze | Public coordinates of the 63 parks. |
| `services.swpc.noaa.gov` | Aurora forecast (NOAA's Kp index for the next three days) | Nothing: one global file, at most every three hours. |

Each host has its own switch in Settings › Your privacy, and saved-spot forecasts have a separate switch. Sessions are ephemeral with cookies and caching off. The device's location is never sent, except when you save where you're standing as a spot, and then only rounded.

Requests are cached (six hours for clouds) and paced per device to stay well inside Open-Meteo's free limits. 429 and 5xx responses back off and respect `Retry-After`. Background refresh repeats the same requests, and only when a widget, reminder, Live Activity or the watch needs the result.

The NPS key ships in the app and is sent in the `X-Api-Key` header. It's a free key for public park data. You can enter your own under Your privacy › Advanced; it's stored in the Keychain.

Links to nps.gov, recreation.gov, Wikidata, Globe at Night and similar sites open in Safari only when tapped. Nyx doesn't request them.

## On the device

- **Journal, saved parks and saved spots** – SwiftData. Photos come from `PhotosPicker` only, so Nyx sees just the ones you pick. A journal export (`.nyxjournal`) leaves the device only if you share it.
- **Location** – When In Use, asked in context with an explainer first. Used on the device for distances, and only kept if you save where you stand as a spot. The app is fully usable with location off.
- **Motion** – field mode's compass reads device attitude while it's open. "Where to look by sound" reads headphone motion and asks for Motion & Fitness access once. Neither is stored.
- **Notifications** – local only. Alarms use AlarmKit; the Live Activity is started and updated locally, with no push token.
- **Ask Nyx** – Foundation Models on the device. No Private Cloud Compute, no network.
- **MetricKit** – only the average pixel luminance is kept, to show how dark the screen stays. Nothing is sent.
- **Age range** – where the law requires it, Nyx asks iOS through Declared Age Range. The answer isn't stored or used.

## Apple Watch and Vision Pro

The watch makes no network requests; the network code isn't compiled into the watch targets. The iPhone sends it saved places, night vision, cached forecasts and the aurora forecast over WatchConnectivity.

The Vision Pro app reaches the same four hosts as the iPhone, with the same requests and pacing, each behind its own switch in its Your privacy screen: `api.open-meteo.com` (clouds), `air-quality-api.open-meteo.com` (smoke and haze), `developer.nps.gov` (park alerts, all 63 park codes in one request) and `services.swpc.noaa.gov` (the aurora forecast, one global file). They carry only the parks' public coordinates and codes, or nothing at all. It requests no permissions.

## Privacy manifests

Every target bundles `PrivacyInfo.xcprivacy`: tracking off, no tracking domains, no collected data. Required-reason APIs: UserDefaults (CA92.1, and 1C8F.1 where an App Group is shared) and, in the app only, disk space (E174.1, checked before moving journal photos).
