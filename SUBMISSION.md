# Nyx 1.0 submission package

**Release gates remain open.** Complete `INPUT_NEEDED.md` and the physical-device review before submitting. Unsigned and development-signed Release archives succeed; neither is an App Store validation result.

## Product metadata draft

- Name: **Nyx** (use until App Store Connect reports a conflict; approved fallback **Noctis**).
- Subtitle: **Plan a darker night**
- Primary category: Travel. Secondary: Weather.
- Price: Free; no subscriptions, ads or in-app purchases. This is required by the chosen Open-Meteo free/non-commercial service.
- Language: English. iPhone only, portrait, iOS 26.0 and later.
- Keywords: `stargazing,national parks,moon,dark sky,astronomy,Milky Way,night,calendar,travel`
- Copyright: 2026, publisher's legal name (owner confirms before entry).
- Privacy policy URL: https://harrypakhale98.github.io/Nyx/privacy.html · Support URL: https://harrypakhale98.github.io/Nyx/support.html · Marketing URL (optional): https://harrypakhale98.github.io/Nyx/ — served by GitHub Pages from `docs/`. Contact: harry.pakhale98@gmail.com. These pages are submission metadata, not app network endpoints.

### Description

Make time for a darker sky.

Nyx compares nights across the 63 US national parks. Moonlight, cloud cover, estimated artificial light and the length of true darkness become one Darkness Score, with a breakdown that explains it.

Find nearby parks using a straight-line radius or choose a starting park yourself. Explore the calendar and five-night moon window. Follow changing conditions along a thirty-night timeline. Park-local times help you plan the evening without converting time zones.

Save parks, receive optional local reminders for promising nights, and keep a private journal with notes and selected photos. Home and Lock Screen widgets show the best sky among your saved parks. Night-vision mode uses a red palette; Learn offers short essays on skyglow and sharing the night.

Moon and twilight calculations, the park library, calendar, journal and saved parks work offline. Cloud forecasts extend roughly sixteen days. When clouds are unknown, Nyx says so and recalculates the estimate without them. Bortle classes are conservative estimates, not measurements. Lunar rise and set times are approximate and can vary with terrain.

Nyx has no account, advertising or tracking. Device location stays on your iPhone. Optional weather and park updates contact their respective data providers; see the privacy policy for those requests and provider processing.

Scores do not confirm clear skies or safe access. Check current road and park conditions before traveling. Forecasts do not include smoke, haze or telescope seeing. Live park alerts and ranger programs depend on data availability and publisher NPS configuration.

Weather data: Open-Meteo, CC BY 4.0. Park data: National Park Service. Nyx is not affiliated with or endorsed by the National Park Service.

### Promotional text

Compare parks and nights, understand what is still uncertain, and keep a little of the night in a private journal.

### Review notes

No account or reviewer login. Onboarding requests no permissions and can be skipped. Manual starting-park selection works with location denied. Data updates are independently switchable in Tonight → Settings → Your privacy. Core astronomy and the bundled park library work offline. Unknown cloud forecasts have hollow calendar/timeline marks and a caveat beside the score; a polar summer night has no true darkness and is capped below 40.

Notifications are local, opt-in, and scheduled only for saved parks with complete recent cloud forecasts and scores of at least 90. They are recalculated on activation. PhotosPicker accesses only selected photos. SwiftData stores observations on-device; there is no CloudKit synchronization.

Widgets/Control Center share `group.com.harrypakhale.nyx`. Save a park to populate the widget; opening Nyx refreshes its cached data. Siri/Shortcuts can answer a park's score without network. Optional AI explanations appear only when Apple's Foundation Models is actually available; absence is expected on unsupported/unconfigured devices. AI uses supplied source records and does not calculate astronomy.

The build includes the publisher's NPS key (from git-ignored `Config/Secrets.xcconfig`), so live park alerts and ranger programs load; if they are unavailable the app says access was not checked. No developer screenshot launch arguments exist in the Release experience.

## Screenshot plan

Use actual app renders, not fabricated scores or clouds. Retain visible forecast/access caveats. `Research/Screenshots` is the QA matrix, not automatically store-ready artwork. `Store/Screenshots` contains raw large-device captures when generated; the owner can submit the raw frames or compose restrained captions around them. Recapture after the final icon and any content/privacy changes.

[Apple's screenshot specification](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) checked October 2, 2026: the 6.9-inch iPhone class uses portrait 1260×2736, 1290×2796 or 1320×2868. The 6.3-inch class includes 1206×2622. Use the actual current simulator output that matches App Store Connect, do not stretch a smaller capture. iPad/landscape sets are not relevant to this iPhone-only app.

| Order | Screen | Optional caption | Truth to preserve |
|---|---|---|---|
| 1 | Tonight | Where the sky is darkest | Park name, score, forecast state and access guidance |
| 2 | Park detail | A number with a reason | Real computed local date; approximate/unknown data visible |
| 3 | Calendar | Make time for the night | Hollow forecast horizon and new-moon window explanation |
| 4 | Parks | Find your park | Actual inventory, honest forecast and access status |
| 5 | Journal | Keep a little of the night | Clearly illustrative observation; no personal photos without consent |
| 6 | Night vision / Learn | Room for your eyes to adjust | Actual readable red UI; no unsupported physiological guarantee |

Capture 6.9-inch on iPhone 18 Pro Max / iOS 27.0 and verify the accepted resolution. Supply 6.3-inch originals from both tested Pro simulators as useful secondary evidence. Native frames need no marketing adjectives, badges, NPS logos or implied endorsement. Optional widget artwork must show a real populated saved-park widget; DEBUG content review alone does not establish system hosting. Save source captions separately and keep status bars consistent.

## App Store Connect checklist

1. App Privacy: answer "No, we do not collect data from this app" (Data Not Collected), no tracking. Reasoning against Apple's definitions is in `PRIVACY.md`; the published policy discloses the providers' IP logs.
2. Complete every device gate in `AUDIT.md`, including VoiceOver, all accessibility settings, hardware motion/haptics, widgets/control, Siri, available-model AI, denied permissions, selected photos and airplane mode. Fix failures and rerun both simulator suites.
3. The Icon Composer icon (`Nyx/Resources/AppIcon.icon`) ships in the build. Optionally open it in Icon Composer to fine-tune glass and lighting, then rebuild and recapture artwork.
4. In the developer account, confirm the existing `com.harrypakhale.nyx`, `com.harrypakhale.nyx.widgets`, and App Group `group.com.harrypakhale.nyx` records and App Groups for both targets. Signing team is already `DUHVN68KBA`; local development signing validates. Configure distribution provisioning/certificates for export.
5. Configure the optional public NPS key locally; test live alert and recurring-program decoding plus failure/cached states. Never commit credentials. If distributing without the key, keep the unchecked UX and remove unsupported live-data marketing promises.
6. Create the App Store Connect app record under the owner's legal account. Verify Nyx name availability, SKU/bundle ID, agreements and regional availability. If Nyx conflicts, apply Noctis coherently through `project.yml`, catalogs, metadata and icon sources and rebuild.
7. Confirm version/build numbers in `project.yml` (current 1.0 / 1). Increment build number for each upload; regenerate with XcodeGen if changed.
8. Archive **Nyx / Release / Any iOS Device**, signed for distribution. In Organizer validate, generate/review the privacy report, check both manifests/entitlements and extension embedding, then upload. The development-signed archive must be exported/re-signed for App Store distribution; it cannot be uploaded as-is.
9. Complete TestFlight processing and export compliance. `ITSAppUsesNonExemptEncryption=NO`: only standard HTTPS through Apple's framework; owner verifies no other encryption was added. Exercise the distributed build on iOS 26 and 27 devices.
10. Enter reviewed metadata, screenshots, privacy/support HTTPS URLs and owner contact details. Complete the current age-rating questionnaire accurately (no public UGC feed, gambling, medical claims or account system). Private journal storage is not a public social feed; answer the exact current questionnaire, not a guessed rating.
11. Enter the resolved App Privacy answers and review notes, including actual NPS configuration and optional model availability. Keep release notes/support accurate; do not claim device gates that remain unchecked.
12. Select the processed build and manual release. Submit for review only after the owner signs the gate table. After approval, perform a final install/offline sanity check before releasing.

## Owner sign-off

| Gate | Status / evidence |
|---|---|
| Privacy label | READY — Data Not Collected recommended with reasoning in `PRIVACY.md`; publisher confirms in App Store Connect |
| Physical accessibility and dark-field testing | OPEN — use AUDIT.md device procedure |
| Hardware performance, haptics, ProMotion | OPEN — simulator timing is not certification |
| Actual widgets/control/Siri/available AI | OPEN — content compiles/previews; device integration review required |
| Icon Composer native icon | DONE — `AppIcon.icon` compiled by actool; Default, Dark, Tinted and Clear renditions checked |
| Development-signed archive | PASS locally — signatures/App Group verified; distribution export pending |
| Hosted privacy/support pages | LIVE — https://harrypakhale98.github.io/Nyx/privacy.html and /support.html |
| App Store export and account metadata | OPEN — publisher account workflow |

The strongest current work is honest offline astronomy presented with native glass navigation and a coherent moon/score language. A further week would be best spent in real parks with VoiceOver users and two or three stargazers, expanding verified viewing spots and tuning scrub/motion/haptics from observation. Those evaluations cannot be replaced by simulator screenshots.
