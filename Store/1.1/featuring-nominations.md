# Nyx — App Store featuring nominations (paste-ready)

Updated 2026-10-08: **Nyx 1.1 is live** (released October 7, 2026, App Store ID 6818817800), so the nomination for the big update is **App Enhancements for 1.2**, then **one New Content nomination** for the Geminids event. (If you already filed an App Launch nomination for 1.1, keep it and add this one for 1.2.) The type cannot be changed after submission.

Where: App Store Connect → Apps → Nyx → Featuring → Nominations → Create nomination. Role: Account Holder, Admin, App Manager or Marketing.

## What Apple's form asks

Sources: App Store Connect Help, [Nominate your app for featuring](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring) (read 2026-10-05 and, by the awards audit, 2026-10-07), and [Getting featured](https://developer.apple.com/app-store/getting-featured/).

| Field | Notes |
|---|---|
| Nomination type | **App Launch**, **New Content** or **App Enhancements**. Cannot be changed after submission. |
| Nomination name | Yours. |
| Description | What is launching. No stated limit; keep the short version below if the form trims. |
| Publish date | One day or a custom range, in the device's local time zone. |
| Related apps | Up to 10 from the same account (Nyx only). Cannot be changed after submission. |
| Platforms | iPhone, iPad, Apple Watch, Apple Vision Pro: select those in the submitted build. |
| Countries and regions | Pre-filled from availability (see `SUBMISSION.md` § Storefronts: US, Canada and Mexico at launch). |
| Localizations | Pre-filled. Add Spanish only if the Spanish store page passed native review. |
| In-App Events | Attach approved or published events. |
| Supplemental materials | Up to 5 URLs. |
| Helpful details | Accessibility, inclusivity, priority, unique aspects. |

**Lead time.** App Store Connect asks for at least **3 weeks** before the publish date (Apple's developer page says at least 2 weeks and recommends up to 3 months). Use 3 weeks as the floor. Nominations can be edited after submission except for the type and related apps. Keep every claim true on the publish date: if a feature is not in the 1.2 build that is released, delete its sentence.

---

## Nomination 1 — App Enhancements (Nyx 1.2)

- **Nomination name:** `Nyx: which park, which night`
- **Type:** App Enhancements
- **Publish date range:** **Fri Nov 6 – Sun Nov 8, 2026**, the November new-moon weekend (the Moon about 5, 2 and 0 percent lit; `in-app-events.md`). File **by Oct 16** to keep three weeks' lead; earlier is better.
- **Release plan:** manual release. Release as soon as App Review approves (early ratings matter more than a quiet fortnight); the nomination's publish window is the "official" launch weekend, with the press emails going out the same weekend.
- **Platforms:** iPhone, iPad, Apple Watch; add Apple Vision Pro only if the visionOS build is approved by then (it may be submitted a week after iOS).
- **Localizations:** English (add Spanish only after review).
- **In-App Events:** the November new-moon weekend event, once approved.

**Description (short):** leads with what 1.2 changes, from What's New in `metadata.md`. The journal's photo descriptions are left out: they work only on iOS 27 with Apple Intelligence. "Follow this night" is in: its Live Activity fixes are in build 9, the build submitted.

```
Nyx 1.2 is a large update to a free dark-sky planner for the 63 US national parks. It answers one question: where should I go, and on which night, for the darkest sky?

A more honest score. Clouds, smoke and city light now cap a night's score instead of only subtracting from it, so an overcast desert night no longer reads Good, and a park beside a city can no longer read Pristine. Beyond the forecast, nights use each park's usual clouds for that month and say so. The park page says what limits tonight and shows the best clear window.

Plan your nights. A new Plan tab holds the month for one park and My free nights for a trip, starting from your city or from a park. Follow a night and its countdown appears on your Lock Screen at dusk. Park pages come in three parts: Tonight; The sky, with the Moon at full size and tonight's sky full screen; and The place, where the park's sky can be switched to the same sky under a city's glow, with the towns lighting its horizon, viewing spots, campgrounds and ranger programs.

For more people. Assistive Access, a brighter red for color-blind eyes, Feel tonight through the Taptic Engine, where to look by sound with AirPods, and better VoiceOver throughout. On Apple Watch, a dark-adaptation clock; on Apple Vision Pro, named stars and constellations; on iPad, parks in their own windows.

The astronomy runs on the device and works offline. There is no account, advertising or tracking; the App Privacy label reads Data Not Collected. One independent developer made it.
```

**Description (long), add after the short text:**

```
What is native: the tab bar, navigation, search and sheets; widgets on the Home and Lock Screens; a Live Activity and Dynamic Island countdown; AlarmKit alarms for true darkness and the Milky Way core's rise; Control Center controls; App Intents for Siri and Shortcuts; Spotlight; Apple Watch complications that turn red at dusk; a visionOS immersive sky and a volumetric Moon; Foundation Models for optional explanations, only on devices with Apple's on-device model.

What is made by hand: a Moon drawn by a Metal shader from NASA's lunar map, lit and oriented as each park sees it; a thirty-night time river whose Moon changes shape as you scrub; calendar nights drawn as tiny skies, filled, half-filled or hollow by how sure the forecast is; the real sky, from the Yale Bright Star Catalogue, behind every screen.
```

**Supplemental materials (5 URLs):**

1. `https://get-nyx.com/` (landing page, with the App Store link since 1.1 went live)
2. `https://get-nyx.com/press/` (press kit)
3. `https://get-nyx.com/case-study` (case study: designing for night-adapted eyes)
4. TestFlight public link: `[add after external testing is enabled]` (editors who cannot see the store page yet can try the build)
5. `https://get-nyx.com/privacy` (privacy policy; Data Not Collected reasoning)

**Helpful details:**

```
Accessibility: every custom control (the score dial, the Moon, the time river, the sky arc, calendar nights) has a VoiceOver summary; audio graphs let VoiceOver users hear a month of darkness; "Listen to tonight" plays the night as tones with a transcript; haptics can follow the Moon's phase; layouts reflow at the largest accessibility text sizes. Apple's automated accessibility audit passes on every screen in both palettes in the simulator; the physical-device pass is in progress and the labels declared in App Store Connect follow it.
Night-adapted eyes: a red mode for the whole app with measured contrast (red text on black 6.2:1, secondary red 5.3:1), and a field mode that dims the screen and tracks dark adaptation.
Inclusivity: free, no account, no purchase; step-free notes for viewing spots that quote each park's accessibility page.
Unique aspects: uncertainty drawn rather than hidden; closures beside the score; on-device astronomy that works offline; no tracking.
Social impact: each park page names the towns whose light rises on its horizon (58 of 63 parks, NASA Black Marble), switches the park's sky to the same sky at a city's class 8 (62 of 63), and links a Learn essay that quotes Falchi 2016 and Kyba 2023, plus Globe at Night in Safari; Nyx sends nothing.
Priority: High. The publish window is the November new-moon weekend, the darkest of the month.
```

---

## Nomination 2 — New Content (Geminids event)

- **Nomination name:** `Geminids under a thin Moon`
- **Type:** New Content
- **Publish date range:** **2026-12-12 to 2026-12-15**. File **by Nov 20** (three weeks before Dec 12 is Nov 21); ideally the same week as Nomination 1, attaching the event once it is approved.
- **Attach:** the Geminids In-App Event (`in-app-events.md`).

```
The Geminids peak on December 14, and in 2026 a thin crescent Moon sets in the evening. Nyx shows each of the 63 national parks' Darkness Score, moonset and cloud forecast for the nights of December 13 to 14 and 14 to 15, with the Geminid radiant on the real sky. The peak itself falls in US daylight, so the best nights are the two around it, and the app says so. Rates are shown as a range from the International Meteor Organization's calendar, a rough guide rather than a promise. Field mode keeps a red countdown on the Lock Screen at the park. Free, no account, no tracking.
```

**Supplemental (5):** landing page; press kit; App Store link (live by then); event artwork (`Store/1.1/events/geminids-2026-*.png`, shared link); `https://www.imo.net/` (source of the shower data).
**Helpful details:** Priority High. Accessibility: the event screens carry VoiceOver summaries and audio graphs. Unique: honest about the peak falling in daylight.

---

## Later (not filed now)

- **Eta Aquariids at new moon** (New Content), publish 2027-05-04 to 05-08, file by Apr 12, 2027. Copy in the git history of this file.
- Monthly new-moon weekend events are too routine to nominate one by one; mention them as a series in Nomination 2's helpful details.

## Submission order

1. By Oct 16: enable the public TestFlight link, publish `docs/` (landing page, press kit, case study), then file Nomination 1.
2. Submit the November new-moon and Geminids In-App Events once the 1.2 build is approved; attach them.
3. By Nov 20: file Nomination 2.
4. Never send the same nomination twice; edit instead. Keep the final text of each nomination here.
