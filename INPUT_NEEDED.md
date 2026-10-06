# Input needed — the only steps left, in order

Everything else is built, verified and documented. Each step below needs your Apple ID, your accounts, or your own eyes on a real iPhone.

1. **Try Nyx on your iPhone, ideally at night.** Plug it in, pick it as the run destination in Xcode, press Run. Check: VoiceOver on the gauge, time river and calendar; haptics while scrubbing the river; night vision from Control Center; the Tonight widget on the Home and Lock Screen; "Hey Siri, what is the darkness score at Joshua Tree in Nyx"; "Near me" with location allowed and denied; adding journal photos; Airplane Mode. The automated accessibility audit already passes on every screen in the simulator (`NyxUITests/AccessibilityAuditTests.swift`); this is the human pass. Note anything odd and ask for a fix.

2. **Publish on the App Store** (follow `SUBMISSION.md`, which has every field filled in):
   - App Store Connect → My Apps → + New App: iOS, name **Nyx: Dark Sky Planner** ("Nyx" is taken), bundle ID `com.harrypakhale.nyx`, SKU `nyx-ios`.
   - Paste the description, keywords, subtitle and URLs from `SUBMISSION.md`. If you entered the description before, paste it again; it gained two sentences.
   - App Privacy: "No, we do not collect data from this app". Reasoning is in `PRIVACY.md`.
   - Upload the six 6.9-inch screenshots in `Store/Screenshots/` (no alpha channel), replacing any uploaded earlier.
   - **Build 1.0 (5) is uploaded** (2026-10-05 design pass: score readout, week strip, fact-based breakdown, journal sky; builds 1–4 are superseded). When it finishes processing: test it in TestFlight, select it on the version page, then Submit for Review.
   - Upload the six captioned frames in `Store/Framed/6.9-inch/` (and `6.5-inch/`), recaptured 2026-10-05, replacing earlier ones.

3. **Ask NPS for a higher request limit for the Nyx key** (optional before launch, needed if Nyx grows). Every install shares the one key, and NPS keys default to about 1,000 requests an hour. Nyx now sends only alerts for most screens, at most one request per park every ten minutes, but a popular launch could still reach the limit; Nyx then quietly keeps the last known alerts and says when they were checked. Use the contact link on developer.nps.gov, name the key, and describe the use (a free app reading park alerts and night-sky events). Only the key's owner can ask.

4. **Enter the awards that close soon** (only the account owner can enter and pay). The full plan is in `Research/award-roadmap.md` (Tier 4). Once 1.0 is live: file an App Launch featuring nomination in App Store Connect (app → Featuring → Nominations); enter the **Webby Awards** by the early deadline **Oct 30, 2026** (Apps, Software & Immersive); register for the **iF Design Award** by **Nov 4, 2026** (UI/UX). Fees and later deadlines are in the roadmap.

5. **Publish the updated privacy page before submitting a build with the smoke forecast.** Nyx now contacts a third host, `air-quality-api.open-meteo.com` (approved 2026-10-05, behind its own "Smoke and haze" switch). `docs/privacy.html`, `docs/support.html` and `docs/index.html` already say so, but GitHub Pages serves them only after they are pushed to `main`. Merge `roadmap` and push (`git push origin main`) before the build carrying this work goes to review, so the store's privacy link matches the app. The App Store privacy answer stays "Data Not Collected".

## Done
- Build 1.0 (5) archived (zero warnings, `verify_release.py` passing) and uploaded to App Store Connect on 2026-10-05.
- Build 1.0 (4) archived (zero warnings, `verify_release.py` passing) and uploaded to App Store Connect on 2026-10-04. Future builds: bump `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen generate`, then Product → Archive → Distribute App → App Store Connect → Upload.
- Privacy page update (forecast and park-alert wording) pushed to GitHub Pages on 2026-10-04.
- App icon: native Icon Composer document `Nyx/Resources/AppIcon.icon`.
- NPS key installed in `Config/Secrets.xcconfig` (git-ignored, on this Mac only) and verified with live Joshua Tree alerts. Building on another Mac? Copy that file over first.
- Privacy label decision: Data Not Collected, reasoned in `PRIVACY.md`.
- Public pages live on GitHub Pages: https://harrypakhale98.github.io/Nyx/ (privacy.html, support.html).
- App Store screenshots recaptured with the current design: `Store/Screenshots/`.
- Automated accessibility audit passes on every screen in both palettes.
- Signing team `DUHVN68KBA` configured; Release archive builds and signs locally.
