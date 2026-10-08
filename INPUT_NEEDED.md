# Input needed: the steps left for Nyx 1.1, in order

**Nyx 1.1 is live** (released October 7, 2026, App Store ID 6818817800). **Version 1.2 (build 8)** is the update. It carries the award audit's work (`Research/award-audit.md`): the score's caps, honest forecasts with usual clouds, bulk park alerts, background refresh, the four-tab app with Plan, the park in three chapters, Assistive Access, Feel tonight, the Watch's dark-adaptation clock and complications, Vision Pro's named sky and clouds, iPad windows, widgets with choices and Spanish drafts for every string. Every step below needs your Apple ID, your accounts, your money, a lawyer, or your own eyes on real hardware. Steps 1–6 can start today. The device pass (9–10) runs straight from Xcode: plug in the iPhone, choose it as the run destination and press Run (the Watch app installs with it; Vision Pro uses the NyxVision scheme). No archive is needed for it; the build you upload is archived after the device pass and its fixes.

## Start now (deadlines first)

1. **File the App Enhancements featuring nomination for 1.2 by about Oct 16.** *Why only you:* App Store Connect → Featuring → Nominations needs the account holder. *How:* `Store/1.1/featuring-nominations.md` has the text: one **App Enhancements** nomination for 1.2 (1.1 is already live; if you filed an App Launch nomination for 1.1, keep it) with the publish window **Nov 6–8** (the November new-moon weekend; Apple needs at least three weeks), supplemental links from get-nyx.com (landing page, press kit, case study, privacy) and the TestFlight public link once step 11 has one. Then the Geminids **New Content** nomination by **Nov 20**.

2. **Send three short emails and keep the replies.** *Why only you:* each is about your key or your app. App Review may ask for proof of permission (Guideline 5.2.2).
   - **Open-Meteo** (info@open-meteo.com): Nyx is free, with no ads, subscriptions or in-app purchases; it requests all 63 parks' public coordinates together, a few times a day per device; ask them to confirm this counts as non-commercial use, and give an expected volume.
   - **NPS** (contact link on developer.nps.gov): name the key, say it ships inside a free public app, that Nyx now sends one request for all parks' alerts every six hours, and ask for a higher hourly limit before launch.
   - **IMO** (optional courtesy): Nyx shows meteor shower dates and rates from the IMO calendar, credited.

3. **One hour with a lawyer on Texas SB 2420.** *Why only you:* legal advice for your situation. Nyx now asks iOS for an age range only when the system says the account requires it, stores nothing and gates nothing (`PRIVACY.md`, `SUBMISSION.md` § Age assurance). Ask whether that is enough for an all-ages app with no account and no server. Utah (2027-05-06) and Louisiana (2027-07-01) follow.

4. **Run a USPTO search for "NYX"** (tmsearch.uspto.gov, classes 9, 42, 38, 41). *Why only you:* a name decision. The App Store name is "Nyx: Dark Sky Planner"; the agreed fallback is **Noctis**.

5. **Decide EU trader status, or launch outside the EU and UK.** *Why only you:* a trader's address and phone are published on the EU product page. Recommended for launch: United States, Canada and Mexico only (App Store Connect → Pricing and Availability), EU and UK later.

6. ~~Send me Nyx's App Store ID~~ **Done 2026-10-08:** 6818817800, found on the live App Store. "Rate Nyx" in Settings and the store link on share cards use it.

## Accounts and signing

7. **Capabilities for build 8.** *Why only you:* the developer account. When you archive (step 11), Xcode's automatic signing should add these to the App ID; confirm in Certificates, Identifiers & Profiles if the archive complains:
   - **Declared Age Range** on `com.harrypakhale.nyx` (new entitlement for age assurance).
   - **Background Modes → Background fetch** is in the Info.plist (no capability needed), and **Assistive Access** support is a plist key (none needed).
   - The visionOS widget extension uses the iPhone widget's ID, `com.harrypakhale.nyx.widgets`, inside its own visionOS build; confirm the profile is created on the first visionOS archive.

8. **Xcode Cloud (optional, recommended).** *Why only you:* it runs on your account. In Xcode → Integrate → Create Workflow: a test workflow on `main` (iOS 26.5 and 27 simulators, `Nyx.xctestplan`, Default configuration) and an archive workflow named "Release" with the secret environment variable `NPS_API_KEY` (from `Config/Secrets.xcconfig`). `ci_scripts/` is already in the repo.

## The device pass (run from Xcode on your devices; at night where it says so)

9. **iPhone, ideally at night at a dark place.** *Why only you:* the simulator has no Taptic Engine, compass, brightness, alarms, Lock Screen, widget host, AirPods or real sky. Record pass or fail with the build number in `AUDIT.md`; this pass also decides which Accessibility Nutrition Labels you may declare (`Store/1.1/accessibility-nutrition-labels.md`).
   - **Core:** first run asks "Where do you start from?"; Chicago (or your city) as the start; Near me allowed and denied; a park's three chapters; the closure beside the score; Plan in both modes; Add to Calendar and Follow this night from a night's menu; airplane mode (scores fall back to usual clouds, never rise).
   - **Score honesty:** a cloudy night reads low and says "Clouds limit tonight to …"; a night beyond the forecast says "No cloud forecast yet" with the park's usual clouds; Hot Springs never reads Pristine.
   - **Field mode at night:** "I'm here tonight"; the countdown reads "23 min", not "22:39"; the screen dims, then may lock after 10 minutes untouched while the Live Activity carries the night; "Keep this night" at dawn; Where to look; "Brighter red" and "Keep my brightness" in the options; "Where to look by sound" with AirPods (head tracking) and without.
   - **Follow this night:** follow a night a day ahead and confirm the Live Activity starts by itself about 30 minutes before sunset with the phone locked; its stale face after a few hours lists clock times and names nothing "next"; the tab bar's "night in progress" strip (iOS 26.1+).
   - **Reminders and background refresh:** turn reminders on, save a park, leave the phone a day; a reminder should cite a recent forecast and open that night when tapped.
   - **Sound and touch:** Feel tonight; Feel the Moon; Listen to tonight, with Silent on and off.
   - **Accessibility:** VoiceOver on the gauge, river (double-tap keeps the night), calendar and park rows (closure read first); Voice Control "Tap River"; Switch Control and Settings → Accessibility → Touch → "Prefer action slider alternative" (iOS 26.1+) show the river's previous/next buttons; Show Borders; Bold Text; the largest text size; Assistive Access (Settings → Accessibility → Assistive Access → add Nyx); Smart Invert leaves the sky dark.
   - **Platform:** the Tonight widget set to a park; the Moon widget; the Lock Screen inline widget; the Tonight control and Field mode control in Control Center; Siri "What's the darkness score at Joshua Tree in Nyx" (shows the gauge) and "Find the best night…"; Spotlight "dark sky park in Utah"; Translate on an alert with the phone in Spanish; "Add to my Nyx journal" by voice; Handoff from iPhone to iPad.
   - **Accessibility audit:** `AccessibilityAuditTests` passes on iOS 27 (every screen, including the Parks map) and on iOS 26.5's key screens, with no exemptions. Two simulator-only flags to confirm on the phone: the Parks **list** is sometimes measured ~67 pt off where it draws when the audit runs right after the map (test state, not seen by people), and on iOS 26.5 Plan's past-night dates were flagged for contrast although their colour measures about 9:1 (likely the audit sampling a star behind the small digits). With VoiceOver and Increase Contrast, glance at Parks (list and map) and Plan's past nights.
   - **Journal:** add a photo and a description; on iOS 27 with Apple Intelligence, "Suggest a description"; Export journal, delete, Import; upgrading from the 1.1 (7) TestFlight build keeps your entries and photos (the store migrates).

10. **Apple Watch, iPad and Vision Pro.** *Why only you:* real wrists, keyboards and headsets.
    - **Watch:** the three complications (score, Moon, Next dark) on a tinted face and a full-colour face around dusk (Automatic turns red at civil dusk); Crown through the week (tap the dial first); Double Tap starts the dark-adaptation clock; the 25 and 30 minute taps arrive wrist-down; the Red light control; the Live Activity's small card in the Smart Stack; forecast age reads "Clouds from …".
    - **iPad:** Open in New Window (⌘⇧N) and two park windows side by side; drag a park onto Plan and onto Journal; the breakdown inspector on a wide window; field mode side by side in landscape; the extra-large portrait widget (iOS 27).
    - **Vision Pro, in a dark room:** the named stars and constellation lines; drag to turn the night; the room darkening with immersion; clouds over the sky at 40, 60 and 90% cover (comfort and contrast); the Moon on your table; the wall widget (recessed and elevated); Your privacy's cloud switch off and on.
    - **CarPlay (if you have it):** the Live Activity's small card during a "Heading out" drive.
    - **Checked only in code or captures on October 8 (please look on the devices):** on the watch, the brighter red under Increase Contrast (the simulator refuses the setting) and the "Return to Clock" hint's path in Settings, in English and Spanish; on Vision Pro, the Moon volume's "Open planner" button, opening the Moon twice (one globe), and the brighter red under Increase Contrast (the visionOS simulator did not boot that day); on iPhone, the subtle double tap when Tonight first finds a reminder-worthy night, and pull to refresh offline ("Could not reach the forecast. Showing saved data.").

11. **Have a native Spanish speaker review Nyx in Spanish.** *Why only you:* a machine draft needs a fluent human before it carries the app's voice, and only you can find and pay a reviewer (ideally a Mexican or US-Hispanic stargazer or park worker). Every string has a draft; the uncertain ones are listed in `Research/localization/README.md`. Edit only `Research/localization/` and run `python3 Scripts/apply_translations.py` (never the `.xcstrings` by hand). The store metadata in `Store/1.1/metadata-es.md` must be rewritten in the review. **If the review isn't done in time, submit 1.1 in English only and add Spanish later** (the app's Spanish UI still ships, marked as a draft in this list).

## Upload, store page and submission

12. **Upload 1.2 (9) before you submit (build 8 lacks the October 8 review fixes).** *Why only you:* uploading publishes a build to your App Store Connect account; say the word and I archive and upload it the same way as build 8. Build 8 (uploaded October 8) predates a full team review that fixed, among others: journal writes silently lost when the store cannot open, the watch scoring smoky nights higher than the iPhone, closures missing from widgets set to an unsaved park, Assistive Access reminders never scheduled, and journal import dropping same-night entries (`DECISIONS.md`, "Team review — 2026-10-08"). `project.yml` is at build 9. Run the device pass on build 9 from TestFlight, and select build 9 in step 17. Earlier note, kept for reference: 1.2 (8) was archived and uploaded on October 8 (iOS with the Watch app, and visionOS; "Upload succeeded" for both).

13. **Set up version 1.2 in App Store Connect.**
    - + Version → **1.2** for iOS (and for visionOS). Paste **What's New** from `Store/1.1/metadata.md` (required for an update).
    - **Mac Availability:** Pricing and Availability → uncheck "Make this app available on Mac" (field mode, alarms and the compass are hidden on Mac, but Nyx has not been tried there).
    - **Territories:** United States, Canada, Mexico (step 5).
    - **visionOS:** + Add Platform → visionOS (same bundle ID, universal purchase).
    - **Spanish (Mexico):** after step 11.
    - **Website URLs:** Privacy Policy `https://get-nyx.com/privacy`, Support `https://get-nyx.com/support`, Marketing `https://get-nyx.com/`.

14. **Enter the metadata and screenshots.** Paste from `Store/1.1/metadata.md` (subtitle "Stargazing in national parks", keywords, description) and `metadata-visionos.md`. Screenshots, replacing every earlier upload: **do not upload the build 7 frames now in `Store/` (they show scores the new rules no longer allow)**. They are recaptured once after the device pass (step 9) and its fixes, into the same folders: iPhone `Store/Framed/6.9-inch/` (and `6.3-inch/`, `6.5-inch/`), iPad `Store/Framed/iPad-13-inch/`, Watch `Store/Framed/Watch-Ultra/`, Vision Pro `Store/Framed/Vision-Pro/`. Optional App Preview: `Store/1.1/app-preview-script.md`.

15. **Answer App Privacy, age rating and Accessibility.** App Privacy: "Data Not Collected", no tracking (`PRIVACY.md`). Age rating: re-answer (unchanged). Accessibility Nutrition Labels: declare per device only what step 9 confirmed. **Review notes:** paste `SUBMISSION.md` § Review notes, including the background refresh sentence: "Background App Refresh updates saved parks' cloud forecasts and park alerts from the same public services (api.open-meteo.com, developer.nps.gov) about every six hours, so local reminders and the widget never rely on an old forecast. No user data is sent."

16. **Awards you enter yourself** (`Store/1.1/award-entries.md`): **UX Design Awards** by **Nov 15** (EUR 320; accepts apps launching within a year); **Webby** (Accessibility & Inclusion) once live (early deadline Oct 30 at $645, then about $715 in December). Skip iF, D&AD and A' Design this cycle.

17. **Submit for review, then release.** Select build 9 of version 1.2 (and the visionOS build), choose **phased release** (rolls out over seven days to people with automatic updates; you can pause it), and Submit for Review once the gate table in `SUBMISSION.md` is signed. After approval: install the update over 1.1 from the App Store with a journal entry already in place (the journal moves to the new store on first launch), try it offline, release, and publish the In-App Events. The website already links to the live App Store page.

## Housekeeping

18. **Take the repository out of iCloud Drive.** `~/Documents` syncs to iCloud, which has dropped "name 2" copies of edited files into source folders and can evict files under Optimize Storage. Quit Xcode, move the folder to `~/Developer/Nyx` (or rename it `Nyx.nosync`), and reopen `Nyx.xcodeproj` from there. Copy `Config/Secrets.xcconfig` along (it is git-ignored).

19. **Optional data reviews.** The Bortle review queue (only Saguaro changed, to 5): Biscayne, Cuyahoga Valley, Kobuk Valley, Mammoth Cave (an International Dark Sky Park computed near 2.9), Indiana Dunes, Hot Springs, Gateway Arch. Usual clouds could be rebuilt at viewing-spot coordinates with your Copernicus account (`Scripts/build_cloud_climate.py`).

20. **Push `main`** when you are happy with it. Pushing deploys the website (`docs/`) to get-nyx.com through the Cloudflare Worker.

## Done
- Build 1.1 (8): every lane from the award audit merged and verified (see `PHASE_STATUS.md`); the build 7 archives and their symbols are kept in `~/Library/Developer/Xcode/Archives/2026-10-06/`.
- Website on get-nyx.com (Cloudflare Worker from `docs/`); GitHub Pages kept for older builds. Privacy page names all three hosts, bulk alerts, campgrounds, Maps and translation hand-offs, and Vision Pro's cloud request.
- Builds 1.0 (4), 1.0 (5), 1.1 (6) and 1.1 (7) uploaded to App Store Connect. NPS key in `Config/Secrets.xcconfig` (git-ignored, this Mac only). Icon Composer icons. Privacy label decision.
