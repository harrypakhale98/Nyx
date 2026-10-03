# Input needed — the only steps left, in order

Everything else is built, verified and documented. Each step below needs your Apple ID, your accounts, or your own eyes on a real iPhone.

1. **Try Nyx on your iPhone, ideally at night.** Plug it in, pick it as the run destination in Xcode, press Run. Check: VoiceOver on the gauge, time river and calendar; haptics while scrubbing the river; night vision from Control Center; the Tonight widget on the Home and Lock Screen; "Hey Siri, what is the darkness score at Joshua Tree in Nyx"; "Near me" with location allowed and denied; adding journal photos; Airplane Mode. The automated accessibility audit already passes on every screen in the simulator (`NyxUITests/AccessibilityAuditTests.swift`); this is the human pass. Note anything odd and ask for a fix.

2. **Publish on the App Store** (follow `SUBMISSION.md`, which has every field filled in):
   - App Store Connect → My Apps → + New App: iOS, name **Nyx: Dark Sky Planner** ("Nyx" is taken), bundle ID `com.harrypakhale.nyx`, SKU `nyx-ios`.
   - Paste the description, keywords, subtitle and URLs from `SUBMISSION.md`.
   - App Privacy: "No, we do not collect data from this app". Reasoning is in `PRIVACY.md`.
   - Upload the six screenshots in `Store/Screenshots/` (6.9-inch).
   - **Build 1.0 (3) is uploaded** (2026-10-03, from this Mac, with the NPS key): the new Dial icon, the lit NASA Moon, the real star sky, the glass dial and cards. When it finishes processing, test it in TestFlight and select it on the version page instead of builds 1 or 2. The six screenshots in `Store/Screenshots/` were recaptured for build 3 (no alpha channel); replace the ones already uploaded. The description in `SUBMISSION.md` gained two sentences (sort by darkness, week-ahead widget, Milky Way essay); paste it again if you already entered it. Future builds: bump `CURRENT_PROJECT_VERSION` in `project.yml`, regenerate, then Product → Archive → Distribute App → App Store Connect → Upload.
   - When the build finishes processing: test it in TestFlight, select it on the version page, then Submit for Review.

## Done
- App icon: native Icon Composer document `Nyx/Resources/AppIcon.icon`.
- NPS key installed in `Config/Secrets.xcconfig` (git-ignored, on this Mac only) and verified with live Joshua Tree alerts. Building on another Mac? Copy that file over first.
- Privacy label decision: Data Not Collected, reasoned in `PRIVACY.md`.
- Public pages live on GitHub Pages: https://harrypakhale98.github.io/Nyx/ (privacy.html, support.html).
- App Store screenshots recaptured with the current design: `Store/Screenshots/`.
- Automated accessibility audit passes on every screen in both palettes.
- Signing team `DUHVN68KBA` configured; Release archive builds and signs locally.
