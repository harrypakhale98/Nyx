# Nyx — App Store featuring nominations (paste-ready)

Where: App Store Connect → Apps → Nyx → Featuring (or Apps → Featuring → Nominations) → Create nomination. Required role: Account Holder, Admin, App Manager or Marketing.

## What Apple's form asks (verified 2026-10-05)

Source: App Store Connect Help, [Nominate your app for featuring](https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring), summarized by a page fetch. The page states no character limits, so the drafts below keep a short version (about 1,000 characters) and a long one; paste whichever fits the field, and trim if the form refuses. Apple's [getting featured](https://developer.apple.com/app-store/getting-featured/) page is the other source to reread.

| Field | Notes |
|---|---|
| Nomination type | **New Content** (new content, offers or events), **App Enhancements** (new features or significant updates), **App Launch** (launch or pre-order of a new app). Cannot be changed after submission. |
| Nomination name | Yours. Memorable. |
| Description | Detailed description of what is changing. No stated limit. |
| Publish date | One day or a custom range; uses the device's local time zone. |
| Related apps | Up to 10 apps from the same account (Nyx only). Cannot be changed after submission. |
| Platforms | Select relevant platforms. In-App Events exist for iPhone and iPad only. |
| Countries and regions | Pre-filled from availability. |
| Localizations | Pre-filled from the app's localizations (add Spanish for 1.1). |
| In-App Events | Attach approved or published events. |
| Supplemental materials | **Up to 5 URLs** (documents, art assets, TestFlight links). |
| Helpful details | Accessibility, inclusivity, priority level, unique aspects. |

**Lead time: at least 3 weeks before the publish date.** Apple asks for early submission. CSV imports are submitted at once and cannot be saved as drafts; use the form.

Nominations are editable after submission except for type and related apps. Keep every claim true on the publish date: remove any 1.1 feature that slips.

---

## Shared story (use in every nomination)

One person built Nyx. It answers a question that sends millions of people to national parks at night: where should I go, and on which night, for the darkest sky? It combines moon phase, cloud cover, estimated sky glow and the length of true darkness into one Darkness Score for each of the 63 US national parks, and explains the score in four plain parts.

- **No tracking.** No account, advertising or analytics. Data Not Collected on the App Privacy label. The location stays on the iPhone. Three optional data services, each with its own switch in the app.
- **A real sky.** The stars are the Yale Bright Star Catalogue. The Moon is drawn on the device from NASA's lunar map with a Metal shader, lit and oriented as the park sees it. Moon, sun, planets and the Milky Way core are computed on the device, so the core works offline.
- **Built for night-adapted eyes.** A red night-vision mode, and in 1.1 a dimmed field mode that counts down to true darkness and tracks how long the eye needs to adapt.
- **Honest about what it does not know.** Forecasts beyond about sixteen days are labelled "moon and darkness only"; three weather models are compared and the range is drawn when they disagree; smoke is a caveat, never points; Bortle and sky glow are called estimates.
- **Accessibility as a launch requirement, not a patch.** Automated accessibility audit on every screen in both palettes. Dynamic Type to AX5, VoiceOver summaries on every custom control, Reduce Motion, Reduce Transparency, Increase Contrast, Smart Invert.

---

## Nomination 1 — App Launch (Nyx 1.0)

- **Nomination name:** `Nyx: Dark Sky Planner launches`
- **Type:** App Launch
- **Publish date:** the planned release day. Today is 2026-10-05, so the earliest date you can ask for is 2026-10-26 if you submit this week. Leave a few days after App Review approval. Build 1.0 (5) is uploaded; release is manual.
- **Platforms:** iPhone. **Countries:** all of Nyx's availability (United States first if you prefer to start small). **Localizations:** English.
- **In-App Events:** none yet (the November new moon weekend is optional here; it runs on 1.0).

**Description (short, about 1,000 characters):**

```
Nyx is a free dark-sky planner for the 63 US national parks. It answers one question: where should I go, and on which night, for the darkest sky?

Moon phase, cloud cover, estimated sky glow and the length of true darkness become one Darkness Score from 0 to 100 for every park and night, with a four-part breakdown that explains it. A calendar shows the nights and the five-night new moon window. A thirty-night time river lets you scrub the Moon through the month. Park closures sit beside the score, because driving four hours to a closed road is the worst outcome a stargazing app can cause.

Nyx has no account, no advertising and no tracking. The App Privacy label reads Data Not Collected. It works offline: Moon, sun and twilight are computed on the iPhone. A night-vision mode renders the whole app in red. It was built by one developer, with a native Liquid Glass shell, a Metal-rendered Moon from NASA's map, and an automated accessibility audit on every screen.
```

**Description (long):** the short text plus:

```
Where Nyx is honest: forecasts reach about sixteen days; beyond that the score says "moon and darkness only" and the calendar shows hollow marks. Light-pollution classes are conservative estimates. Moonrise and moonset are approximate to about 15 minutes. Scores never confirm clear skies or open roads.

What is native: the tab bar, navigation, search, sheets, widgets (Home and Lock Screen), a Control Center control for night vision, App Intents for Siri and Shortcuts ("What's the darkness score at Joshua Tree tonight?"), Spotlight indexing, and local notifications for promising nights. Optional Apple Intelligence explanations appear only on devices where Apple's on-device Foundation Models are available.
```

**Supplemental materials (5 URLs):**

1. `https://harrypakhale98.github.io/Nyx/` (marketing page)
2. `https://harrypakhale98.github.io/Nyx/press/` (press kit; publish `docs/press/` first)
3. TestFlight public link: `[add after you enable external testing]`
4. `https://harrypakhale98.github.io/Nyx/privacy.html` (privacy policy; Data Not Collected reasoning)
5. `https://github.com/harrypakhale98/Nyx/blob/main/AUDIT.md` (accessibility audit evidence) — confirm the repository is public, otherwise upload `AUDIT.md` as a PDF to a shared link.

**Helpful details:**

```
Accessibility: automated accessibility audit passes on every screen in both palettes (standard and red night vision) on iOS 26 and 27. Dynamic Type to AX5 with layouts that reflow instead of shrinking (the 30-night river becomes a native stepper at accessibility sizes). Every custom control (celestial gauge, moon disc, time river, sky arc, calendar nights) has a VoiceOver data summary. Reduce Motion stops the starfield, orbit and reveal. Reduce Transparency and Increase Contrast switch glass panels to opaque. The Moon ignores Smart Invert. Physical-device VoiceOver testing is on the owner's list and not yet signed off; the evidence log says so.
Inclusivity: free, no purchase, no account. Plain English with glosses for jargon. A red night-vision palette checked for contrast (red on black 6.2:1; secondary text 5.3:1).
Unique aspects: honest uncertainty, no tracking, offline astronomy, the Moon shader, closures beside the score.
Priority: standard. There is no fixed date, so any week works.
```

---

## Nomination 2 — App Enhancements (Nyx 1.1)

- **Nomination name:** `Nyx 1.1: the whole night`
- **Type:** App Enhancements
- **Publish date:** 1.1's release day, at least 3 weeks after submitting. If 1.1 targets mid-to-late November, submit by about Oct 28 for Nov 18, and attach the Geminids event.
- **Platforms:** iPhone, iPad, Apple Watch, Apple Vision Pro (select those that ship in the 1.1 record). **Localizations:** English, Spanish (after review).
- **In-App Events:** attach the Geminids event once approved. A nomination can be edited after submission, so submit first and attach when the event is approved.

**Description (short, about 1,000 characters):**

```
Nyx 1.1 follows the night from the plan to the dawn. For each national park and night it now times the Milky Way core, planets and meteor showers on the device; compares three weather models and says plainly when they disagree; and adds wildfire smoke as a caveat beside the score. Field mode turns the iPhone into a red, dimmed instrument for night-adapted eyes: a Live Activity and Dynamic Island countdown to true darkness, alarms that wake you when the core rises, a dark-adaptation clock, and "Where to look", the real sky turned to the phone's direction with no camera. Nyx also arrives on Apple Watch, Apple Vision Pro (stand under the real sky for a park and a night) and iPad, in English and Spanish. Sky glow at viewing spots is now estimated from NASA Black Marble data. It stays free, with no account and no tracking: the App Privacy label still reads Data Not Collected.
```

**Description (long):** the short text plus:

```
New in accessibility: audio graphs so VoiceOver users can hear the 30-night timeline, the calendar month and the sky arc; a short sonification of tonight; haptics that follow the Moon's phase; a "Reduce bright effects" mode (iOS 26.4 and later) that dims glow, halos and the shooting star; step-free viewing spots sourced from park accessibility pages, with a filter; Spanish throughout.

What stays the same: the score formula. The Milky Way, planets, meteors, model agreement and smoke are reasons to go, shown beside the score, never points inside it. Every number states its uncertainty. A third network host (Open-Meteo's air-quality forecast, for smoke) has its own switch and receives only public park coordinates.

Platforms in use: ActivityKit and Dynamic Island, AlarmKit, App Intents and Control Center, Focus filters, Core Motion, Core Haptics, WidgetKit and Smart Stack, Foundation Models (availability-gated), watchOS, visionOS with RealityKit/immersive space, iPad layouts.
```

(Edit the platform sentence to match what actually ships.)

**Supplemental materials (5 URLs):**

1. `https://harrypakhale98.github.io/Nyx/`
2. `https://harrypakhale98.github.io/Nyx/press/`
3. TestFlight link for the 1.1 build: `[add]`
4. App Preview video (30 s): `[add a hosted or shared link once recorded; see app-preview-script.md]`
5. `https://github.com/harrypakhale98/Nyx/blob/main/DECISIONS.md` (the dated design and engineering decisions, including accessibility and privacy reasoning)

**Helpful details:**

```
Accessibility: new in 1.1 are audio graphs (AXChartDescriptor) for the time river, calendar month and sky arc; a sonification of the night; Moon-phase haptics; Reduce bright effects on iOS 26.4 and later; step-free viewing spots; Spanish; Apple Watch with red-first layouts and large type; Vision Pro with a VoiceOver-readable list alongside the immersive sky. Field mode is built for night-adapted eyes: forced night vision, dimmed brightness restored on exit, contrast checked in red. Where to look has a VoiceOver list as its default under VoiceOver and at accessibility text sizes. Captions and audio descriptions do not apply: Nyx has no video or spoken audio content.
Inclusivity: free; no account; Spanish; step-free spots; every custom control has a non-visual equivalent.
Unique aspects: dark-adaptation clock and compass sky with no camera; honest model agreement; on-device astronomy that works offline; no tracking.
Priority: High for a mid-to-late November publish date, so the Geminids event (Dec 12 to 15) lands with the update.
```

---

## Nomination 3 — New Content (In-App Events)

One nomination per event that has a clear moment. Each is **New Content**, attaches the approved event, and needs 3 weeks of lead time before the event starts. Dates and copy are in `in-app-events.md`.

### 3a. Geminids under a thin Moon

- **Nomination name:** `Geminids under a thin Moon`
- **Publish date range:** 2026-12-12 to 2026-12-15 (submit by Nov 20, ideally Oct 28 for a full month of lead).
- **Attach:** the Geminids event.

```
The Geminids peak on December 14, and in 2026 a crescent Moon, about 20 to 30 percent lit, sets in the evening. Nyx shows each of the 63 national parks' score, moonset, cloud forecast and the model agreement for the nights of December 13 to 14 and 14 to 15, with the Geminid radiant on the real sky. The peak itself falls in US daylight, so the best nights are the two around it, and the app says so. Rates are the International Meteor Organization's rough guide for a perfect sky, never a promise. Field mode keeps a red countdown on the Lock Screen at the park. Free, no account, no tracking.
```

**Supplemental (5):** marketing page; press kit; TestFlight or App Store link; event artwork (shared folder); `https://www.imo.net/` (the International Meteor Organization, source of the shower data).
**Helpful details:** Priority High. Accessibility: audio graphs and Spanish apply to the event's screens. Unique: honest about the peak falling in daylight.

### 3b. Eta Aquariids at new moon

- **Nomination name:** `Eta Aquariids at new moon`
- **Publish date range:** 2027-05-04 to 2027-05-08 (submit by Apr 12).

```
On May 6, 2027 the Moon is new, so the Eta Aquariids, debris from Halley's Comet, meet a sky with no moonlight. The radiant rises only shortly before dawn, so rates are higher in the south: Nyx lists each park's window and the Moon, clouds and smoke for it, and says plainly that northern parks see fewer. Free, no account, no tracking.
```

### 3c. Optional: Perseids 2027, honest about a bright Moon

Skip unless the owner wants to show that Nyx says when a famous event is a poor night. Submit by Jul 7 for the August 11 to 14 event. Copy: "The Perseids in 2027 peak under a Moon about 86 percent lit. Nyx says so, and shows each park's moon-free hours before dawn."

### 3d. Not nominated

The monthly "New moon weekend" events are too routine to nominate individually. Mention them in 3a's helpful details as a recurring series ("New moon weekend events every month from November").

---

## Accessibility and inclusivity block (paste into Helpful details if short on space)

```
Nyx supports VoiceOver (summaries on every custom control), Larger Text to AX5, Dark Interface (dark by design), Differentiate Without Color Alone (shape and size carry scores; hollow marks mean no forecast), Sufficient Contrast (checked in both palettes, measured ratios published), and Reduced Motion. Voice Control and physical VoiceOver testing are verified on device before the label is declared. It is free, needs no account, and collects no data.
```

## Submission order

1. Today to Oct 14: file Nomination 1 (App Launch), with publish date at least 3 weeks away.
2. By about Oct 28: file Nomination 2 (App Enhancements) with the Geminids event attached later.
3. Nov: file 3a once its event is approved; Apr 2027: 3b.
4. Do not send the same nomination twice; edit instead.
5. Keep a copy of every nomination text here; Apple's form is the only record outside App Store Connect.
