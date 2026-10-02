# Nyx handoff — 2026-10-02

## Integrated checkpoint: Phases 0–6b

Implemented the 63-park inventory, offline astronomy and score engines, native five-tab app, celestial components, calendar/time river, saved parks, local reminders, SwiftData journal/photos, onboarding, settings/privacy/data screens, Learn essays, share cards, App Intents/Spotlight, widgets/Control Center, and availability-gated Foundation Models enhancements. XcodeGen remains the project source of truth. App and extension use only Apple frameworks.

Both requested simulator test runs pass: iOS 26.5 / iPhone 17 Pro and iOS 27.0 / iPhone 18 Pro, 12 Swift Testing tests, zero compiler warnings. Independent USNO fixtures: solar/civil twilight maximum error 0.47 minutes; moonrise/set maximum error 3.72 minutes. See `Research/accuracy.md` for individual cases and limits.

Initial screenshot critique fixed three weaknesses: Tonight's park identity appeared below its score; the phase tab icon had an opaque full-disc silhouette; calendar cells were too compact at AX5. Further fixes cover the radius picker, red native controls and calendar sheet theme, reduced-transparency panels, and park-local calendar headings.

## Deliberate limitations / human gates

- No NPS key committed. Alerts/programs use an honest unchecked state until the owner supplies a free key; cached data survives failures.
- Verified viewing spots are present only where the checked NPS sources support them. Other parks offer honest ranger guidance rather than invented coordinates.
- A working raster app icon and layered SVG sources exist. Final Icon Composer export needs the owner.
- VoiceOver interaction, actual system Reduce Motion/Transparency/Bold Text/Smart Invert, hardware haptics/ProMotion, and available Foundation Models require device review. Screenshot overrides are not evidence of those interactions.
- Privacy label target is “Data Not Collected,” but Open-Meteo's published 90-day API logs require publisher review against Apple's collection definition before submission. This is not certified resolved.

## Exact next step

Proceed directly to Phase 7: finish the whole-app critique (access warning placement, park-local journal dates, notification-setting races), final screenshot matrix on both simulators, Instruments/Release checks, `AUDIT.md`, `PRIVACY.md`, `SUBMISSION.md`, README, and an ordered owner-only `INPUT_NEEDED.md`. Do not mark submission ready while the device and privacy gates remain open.
