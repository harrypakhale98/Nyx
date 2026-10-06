# Nyx handoff — 2026-10-06 (Vision Pro polish: the immersive sky)

Branch `vision-polish`; only `NyxVision/` changed. Logged under "Vision Pro polish — 2026-10-06" in `DECISIONS.md`.

- **Done:** near-black night with faint airglow and Bortle glow; twilight colours, Earth's shadow and Belt of Venus from the Sun's real altitude; moonlight as glare (blue sky, aureole, Milky Way and faint stars washed out in proportion); GPU-drawn Milky Way model (`SkyShaders.metal`, 4096×512, warm core, star clouds, Great Rift and dust lanes); star atlas with a perceptual brightness curve, glare and blackbody colours; seeded two-range skyline (labelled illustrative) with compass letters on the land; label depth fix; Reduce Transparency in window and sky cards.
- **Verified:** NyxVision builds with zero warnings (Debug, visionOS simulator). Captures on "Nyx Vision Pro" (visionOS 27): `Research/Screenshots/vision-polish-core-july.png`, `-core-overhead`, `-moonlit`, `-twilight`, `-belt-of-venus`, `-night-vision` (compare `vision-sky-*` from before). iOS suite not run (no shared file changed).
- **Review fix:** the Milky Way's hard edge (faint alpha un-premultiplied on texture upload) is gone: additive textures are opaque, the band is ±30° with a 12° fade. Core, overhead, moonlit and night-vision captures retaken.
- **Known issues:** on device (≈3× the pixel density) the 0.088°/px texture is softer than the stars. A second, higher-resolution texture for the summer core is the next step if it shows. No scintillation (by decision).
- **Next:** try on a device for brightness calibration (the levels were tuned on simulator captures); consider a core-region detail texture.

# Nyx handoff — 2026-10-06 (roadmap: platform showcase, each for a reason)

Roadmap Tier 3, on branch `platform`. Logged under "Platform — 2026-10-06" in `DECISIONS.md`. The score is unchanged. Every API was checked in the installed iPhoneOS 27.0 SDK.

- **Engine for every surface:** `NightPlanner` (`Nyx/Services/NightPlanner.swift`, also in the widget extension): nights from parks + cached forecasts, ranking, the large widget's month, dusk windows and relevance.
- **Widgets:** medium gains "2 of 3 ›" (`Button(intent: CycleWidgetParkIntent())`, `Nyx/Intents/WidgetParkIntent.swift`; the choice lapses at the park's next sunrise); new **large** family (35-cell month: dot for score, hollow without forecast, ring on the best, meteor/eclipse glyph, Moon phase and percent lit); `TimelineEntryRelevance` per entry plus `relevance()` → `WidgetRelevance` from `RelevantContext.date(interval:kind:)` for dusk on Good+ nights; white-only drawing outside `.fullColor` (StandBy at night, tinted, Lock Screen).
- **App Intents & Spotlight:** `ParkEntity` is an `IndexedEntity`; Spotlight items associate their entity (and `relatedAppEntityIdentifier` on 27); `ParkQuery` is an `IndexedEntityQuery` on 27; `OpenParkIntent` (OpenIntent) opens a park via `ParkOpenRequest`. **Find the best night** (`Nyx/Intents/BestNightIntent.swift`): park or saved parks, 1–30 nights, honest dialog (shorter when `isVoiceOnly` on 27), interactive snippet with "Next best" and "Open in Nyx". App Shortcut phrases added; `updateAppShortcutParameters()` after saved parks change. No assistant schema fits.
- **Reminders (27):** `appEntityIdentifiers` = the park's entity.
- **Ask Nyx with tools** (`Nyx/Services/GuideTools.swift`): `bestNights`, `whatsUp`, `parksNear` return computed records numbered by `GuideLedger`; citations still validated; "What Nyx looked up" under the answer. Real `contextSize` + `tokenCount(for:)` (26.4) to trim; `ContextOptions(reasoningLevel:)` on 27.
- **iOS 27 polish:** park detail `toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar, .tabBar)`. **MetricKit** (`Nyx/Services/LuminanceProof.swift`): last average pixel luminance, shown in About the data and Your privacy only after a real report (no "typical app" comparison: no reference exists).
- **visionOS:** links `AppIntents.framework`; the "Metadata extraction skipped" warning is gone.
- **Tests:** `NyxTests/PlatformTests.swift` (12): dusk windows/relevance (incl. Denali June), month layout/best/forecast edge/Geminids glyph + timing, cycling order/wrap/lapse, best-night ranking/clamps/tie rule, dialog wording incl. voice and polar, snippet browsing, Spotlight items ↔ entities (27 identifier), ParkQuery, open request expiry, the three tools' records, ledger numbering, luminance reading validity.
- DEBUG: `-nyx-screen widgets | widgets-large | snippet | metric` (`-nyx-state privacy` for Your privacy), best with `-nyx-state agree`.

**Verified 2026-10-06:** zero warnings (app, widgets, tests; visionOS build clean). iPhone Air / iOS 27.0: 120 Swift Testing tests (12 new), both UI tests, both accessibility audits limited to `detail,data,privacy,ask` (standard and night vision) — all pass. iPhone 17e / iOS 26.5: 120 Swift Testing tests pass. Large-widget month with events: 25 ms. Reviewed captures (kept as `Research/Screenshots/platform-*`): widgets (small, medium with "3 of 3", Lock Screen, StandBy night simulated), large (full colour, night vision, tinted), snippet and voice-only wording, About the data with the DEBUG luminance fixture, park detail; on 26.5 large widget and snippet. Review fixes: button crowding the weekday row, invisible shower glyph, buried brightness line.

**Known limits:** Smart Stack rise, StandBy night tint, interactive buttons in real widget/snippet hosts, Spotlight semantic results and the tools with a live model cannot be exercised in the simulator (INPUT_NEEDED 1). MetricKit reports arrive about daily on devices only. The month's clouds are frozen per night/forecast-freshness within a timeline. New strings (56) need Spanish drafts.

**Next starting point:** integrator merges `platform` (expect small conflicts in `RootView.swift` with the delight lane: new `.onReceive(ParkOpenRequest…)`, debug routes, `updateSaved`), runs the full both-runtime suite, adds Spanish drafts.

---

# Nyx handoff — 2026-10-06 (roadmap: every sky — the cost of light, step-free spots)

Roadmap §4 and the step-free part of §5, on branch `glow`. Logged under "Every sky — 2026-10-06" in `DECISIONS.md`. The score is unchanged and still uses the hand Bortle estimate.

- **Data:** `SkyGlow` and `AccessData` (`Nyx/Models/SkyGlow.swift`) load the bundled `skyglow.json` (NASA Black Marble) and `accessible-spots.json` (moved from `Research/` into `Nyx/Resources/`). Joined by park id and exact spot name; all 63 parks and 85 spots resolve.
- **Park detail:** "Night lights from space" (a five-step rank among the 63 parks, meter + words), light domes in words ("Glow on the horizon: Las Vegas, east (45% of this park's light pollution)."; "a town to the west" when unnamed; a town named once), an honest source line; breakdown's light-pollution row gets the same rank as context. New **Protect this sky** card: Dark Sky Park designation (no year), the 2013→2025 growth *rank* (outer thirds only, artifact parks excluded), three home habits, a link to "A sky worth protecting".
- **Viewing spots** (`ViewingSpots`, `ViewingSpotRow`): sky glow here (rank, and darker/brighter than the park's center), step-free status with icon and words (unknown omitted), "Access source" disclosure with the nps.gov sentence, note, Safari link and "Conditions change; check with the park."
- **Parks filter** "Step-free viewing" (41 parks), rows say so, eyebrow counts matches.
- **Real sky:** light domes glow warm at their true bearings above the horizon (`SkyProjection.lightSources`, injected by the app; widget/watch draw none and ship no glow data). No sky-arc tick (its axis is time).
- **Journal entry:** "Share your observation with Globe at Night" (Safari, nothing prefilled). Limiting magnitude not built (logged).
- **About the data:** "Night lights from space" (credit line, method, limits) and "Step-free viewing". Your privacy and PRIVACY.md: Safari links, Nyx sends nothing. `verify_release.py` checks the browser-link list (`BrowserLink`).
- **Tests:** `NyxTests/SkyGlowTests.swift` (7): every park/spot joins (glow and access), access claims always sourced, levels span the parks, dome wording incl. null city and duplicate town, trend rank exclusions/tiny base/thirds, step-free filter, domes in the real sky (and none without a source).
- DEBUG: `-nyx-screen light -nyx-park deva | grca | sequ` (added to the accessibility audit list), `-nyx-screen parks -nyx-state step-free`.

**Verified 2026-10-06:** zero warnings. Audit iPhone 17 / iOS 27.0: 96 Swift Testing tests, both UI tests, both accessibility audits limited to `light,detail,parks,entry,data,privacy` (standard and night vision) — all pass. iPhone Air / iOS 26.5: 96 Swift Testing tests pass. Reviewed captures (kept as `Research/Screenshots/glow-*`): light domes on detail (Grand Canyon, July), light/spots/protect for Death Valley, Grand Canyon (and night vision), Sequoia (Moro Rock "Steps or trail"; AX5), Parks step-free filter, journal entry with Globe at Night; 26.5: Sequoia light, Parks filter. Review fixes in DECISIONS.

**Known limits:** glow is a rank, not a sky-brightness measurement; domes east/west of the south-facing view are off screen (named in words). Five parks where the hand and computed Bortle disagree by ≥1 class are queued in `Research/skyglow.md`. New strings (about 50) need Spanish drafts in `Research/localization/es-strings.json`. `Scripts/sync_catalog.py` after a `build-for-testing` build tried to prune App Intents keys; only additions were merged.

**Next starting point:** integrator merges `glow`, runs the full both-runtime suite, adds the Spanish drafts for the new keys; owner checks the five review-queue parks against NPS Night Skies data when available.

---

# Nyx handoff — 2026-10-06 (roadmap: the sky for everyone)

Roadmap Tier 1 §5, on branch `a11y`. Logged under "Accessibility depth — 2026-10-06" in `DECISIONS.md`. The score is unchanged; this slice makes the night reachable by sound, touch and shape.

- **Hear the night:** Audio Graphs (`AXChartDescriptor`, built lazily) on the time river (scores, estimates labelled, model spread as two series), the calendar month (on its title) and the sky arc (Sun, Moon, core in degrees). "Listen to tonight" (`NightSonification`, `NightListener`, `Nyx/Services/NightSound.swift`; UI in `Nyx/Views/ListenView.swift`): twelve seconds, sunset to sunrise, rendered offline and played through `AVAudioPlayerNode` (`connectNode` on iOS 27); pitch for darkness, volume for moonlight, pulses at moonrise/set, a chime for the core; transcript with live highlight, VoiceOver captions. On park detail under the shape of the night, and in field mode's options menu.
- **Feel the Moon:** `MoonTexture`/`MoonHaptics` (Core Haptics): phase as texture, river detents sharpening with score, texture after a scrub rests, a button in the Moonlight card, a river action; `sensoryFeedback` kept where there is no Taptic Engine or the switch is off.
- **Settings:** `nyxAccessibility()` reads Differentiate Without Color, Reduce Highlighting Effects and Prefer Cross-Fade (26.4) and reduced resource usage (27). Shapes for colour (`NightMark` stars, river carets, hatched moonlight, Sun label, struck-through past nights), dimmed glows, no shooting star, cross-fade navigation (`NavigationTransition.crossFade` on 27), still skies. SSML pronunciations on iOS 27 (`accessibilitySpeechSSML`).
- **Navigation by voice and rotor:** rotors "Best nights" and "Moon window" (calendar), "Closures" and "Pristine nights" (Parks), "Milestones" (field); river actions "Best night", "Next of the best nights", "Feel the Moon"; `accessibilityInputLabels` on every custom control and icon-only button touched.
- **Learn and Settings:** essay "Stargazing for everyone"; Tonight → Settings → Accessibility → "Sound and touch" with a test for each feature.
- DEBUG: `-nyx-screen listen | accessibility`, `-nyx-screen article -nyx-state access`, flags `-nyx-differentiate`, `-nyx-reduce-highlighting`, `-nyx-crossfade`, `-nyx-reduced-resources`, `-nyx-bold`. `listen` and `accessibility` joined the accessibility audit.

**Verified 2026-10-06:** zero warnings. iPhone Air / iOS 27.0: 100 Swift Testing tests (11 new in `AccessibilityDepthTests`: sonification timeline and pitch at Joshua Tree, moonrise pulse and quieter tone, rendered buffer length/range/chime, Denali midnight sun; river chart scores, estimates, model spread and axis wording; sky chart in degrees; Moon texture and river detents; `NightMark` shapes; "Best nights" rotor; SSML annotations), both UI tests, and the accessibility audit on detail, calendar, river, skyarc, field, listen, accessibility, settings, learn and parks in both palettes (the first run timed out under a load average near 500; a second run passed every screen but "Sound and touch", whose clipped "Play tonight" label was fixed and re-audited with field: pass). iPhone 17e / iOS 26.5: unit tests (100) pass. Reviewed captures (`Research/Screenshots/a11y-*`): listen (27, 26.5), Sound and touch (27; 26.5 night vision), Differentiate Without Color on calendar (27, 26.5), river, sky arc and Parks week strips, detail with and without Reduce Highlighting, field mode at AX5 with bold, What's up and breakdown at AX5 with bold, the new essay, Settings. Review fixes: the river's best-night rings overlapped on neighbouring nights (now small triangles beneath); Sound and touch used bold rows as headings and a plain-looking play button (now section headers and an amber action); the transcript's grey bullet dots were heavy and meaningless (now each moment's own symbol, brightening as it plays) and "Listen" read as text (now a capsule button); field mode's header icons overflowed their 44 pt frames at AX5 with bold (now grow); the Learn icon read as wheelchair-only (now the accessibility symbol).

**Known limits:** the sound, haptics, Audio Graphs, rotors, Voice Control names and SSML pronunciations can only be judged on a device with VoiceOver and Voice Control (INPUT_NEEDED 1); the simulator has no Taptic Engine, so "Feel the Moon" shows its explanation instead. There is no public API for the System Haptics switch; Nyx's own switch governs Core Haptics. A cross-fade cannot be captured in a still. Planets and showers are not sonified (by design). The week strip has no Audio Graph (seven points inside a combined row). New strings have no Spanish draft yet.

**Next starting point:** the device pass in INPUT_NEEDED 1; then the Accessibility Nutrition Labels per `Store/1.1/accessibility-nutrition-labels.md`; integrator bumps the build number.

# Nyx handoff — 2026-10-05 (roadmap: field mode)

Roadmap §1, on branch `roadmap`. Logged under "Field mode — 2026-10-05" in `DECISIONS.md`. The score is unchanged; field mode says what happens tonight and when, on a screen made for dark-adapted eyes.

- **Engine:** `FieldNight` (`Nyx/Services/FieldNight.swift`): the night's milestones from `AstronomyEngine` and `SkyAlmanac` only (sunset, true darkness, moonrise/set ≥ 5% lit, core up/highest/sinking, a shower's best moment, planets rising/setting, dawn, sunrise), the one leading line for any moment (incl. midnight sun and polar night), alarm options, and `DarkAdaptation` (30-minute clock, reset after ≥ 5 s away, undoable).
- **Field screen:** `FieldView` presented full-screen from the top of UIKit's stack (`FieldPresenter`, `FieldSession`): forced red, brightness via `windowScene.screen` lowered and restored (also on background), auto-lock off, night vision written and restored; milestones snap one at a time with live `Text(timerInterval:)`; haptics and VoiceOver announcements per milestone; eye clock with an honest explanation.
- **Where to look:** `SkyCompass` (pure geometry, tested) + `FieldMotion` (Core Motion, true north when location is already allowed, magnetic otherwise and said so; iOS 27 `headingAccuracy` calibration hint) + `FieldCompassView` (red Canvas sky, labels that never collide, edge arrows, Hold still, a VoiceOver list).
- **Live Activity:** `FieldActivityAttributes` (shared with the widget) + `FieldLiveActivity` (Lock Screen, Dynamic Island compact/minimal/expanded, StandBy): no push; milestones in attributes, `staleDate` at each, a self-advancing dusk-to-dawn line, red with night vision, ended at dawn when Nyx next opens.
- **AlarmKit:** `FieldAlarms` (iOS 26.1+): true darkness, the core, 30 minutes before a moonset in darkness; explainer first; park `EntityIdentifier` on iOS 27; snooze Live Activity in the widget.
- **Entry points:** "I'm here tonight" on tonight's detail (+ "Follow tonight on the Lock Screen"), Tonight after sunset when location is already known near a park or a Stargazing Focus asks, Control Center "Field mode" (`OpenFieldModeIntent`), Siri/Shortcuts "Start field mode at <park>" (`StartFieldModeIntent`), the Live Activity (`nyx://field/<park>`), Focus filter `StargazingFocusFilter`.
- DEBUG: `-nyx-screen field | field-compass | live-activity | alarm-explainer`, states `adapting | adapted | reset | alarms | stargazing`, `-nyx-field-minutes N`; `field`, `field-compass` and `alarm-explainer` are in the accessibility audit.

**Verified 2026-10-06:** zero warnings. iPhone 18 Pro / iOS 27.0: full suite, 81 tests (77 Swift Testing, 13 new in `FieldModeTests`: milestones incl. Denali midnight sun, Gates of the Arctic polar night and American Samoa, status lines, dark-adaptation reset and undo, a month of alarm times, compass projection and Core Motion attitude both ways, Live Activity payload < 4 KB and coding, Focus restore incl. the system's launch-time default call, intent hand-over, nearby park) plus both UI tests and both accessibility audits (21 screens incl. `field`, `field-compass`, `alarm-explainer`, × standard and night vision). iPhone 17 Pro / iOS 26.5: unit tests (77) only, per the integrator's instruction for this overloaded checkpoint; the integrator runs the full 26.5 audit. Reviewed captures (kept as `Research/Screenshots/field-*`): waiting, dark-adapted, reset notice, AX5, midnight sun, polar night, compass (26.5), AX5 compass list, alarms sheet (26.5), Live Activity faces, detail entry (26.5). Review fixes: at AX5 the eye's clock pushed the countdown off screen and the picker stayed segmented; the reset notice covered the countdown; compass labels collided; the "Wake me" sheet was white in field mode (palette applied inside the presentation style); "Follow tonight on the Lock Screen" had a 16 pt hit area. Found while verifying: the system calls the Focus filter at every launch and `current` then returns a default instance, so the old code switched night vision on with no Focus; fixed (defaults are off).

**Known limits:** the compass, brightness, AlarmKit, Live Activity and Focus behaviour can only be judged on a device under a sky (INPUT_NEEDED 1). The Live Activity cannot end itself at dawn without a push or the app; it goes stale with clock times and Nyx ends it when next opened (the system retires it after its own limit regardless). Alarms are absent on iOS 26.0 (the alert without a stop button is 26.1+). Dark adaptation is a clock, not a measurement, and says so. Lock Screen clock times use the iPhone's time zone (the person is at the park), not the park's.

**Next starting point:** the night review on a device (INPUT_NEEDED 1); integrator bumps the build number.

# Nyx handoff — 2026-10-05 (roadmap: Vision Pro, "stand under tonight's sky")

Roadmap Tier 2b, on branch `vision`. Logged under "Vision Pro" in `DECISIONS.md`. The iPhone app is unchanged apart from one shared, tested math file (`Nyx/Services/SkyDome.swift`).

- **New target `NyxVision`** (visionOS 26.0, scheme NyxVision, bundle `com.harrypakhale.nyx.vision`): shares the engine and bundled data by listing files; no network code is compiled in. Own String Catalog (`NyxVision/Resources/Localizable.xcstrings`, `Scripts/sync_vision_catalog.py`), privacy manifest and layered icon.
- **Window:** searchable park list with each park's moon-and-darkness score for the chosen night; one park's night (score, shader Moon, true darkness, Moon times, Bortle, What's up, the sky at the clock's moment written out); bottom ornament with night stepper, sunset→sunrise clock and "Middle of darkness". Night vision toggle in the toolbar.
- **Immersive "Stand under this sky":** catalogue stars (three additive meshes, B−V colours), a modelled Milky Way, the shader Moon at its true place (drawn 3× size), planets with tap cards, core label, compass on the horizon, twilight and moonlit dome, plaque with the honesty line. The celestial sphere turns by one rotation per moment.
- **Tests:** `NyxTests/SkyDomeTests.swift` (7): rotation vs `AstronomyEngine.horizontal` in four parks (< 0.001°), facing and inverse, southern facing, galactic centre, scrub mapping and clamps, polar spans, twilight ordering.

**Verified 2026-10-05/06:** NyxVision builds with zero warnings (visionOS simulator SDK, Xcode 27.0). iOS `Nyx` scheme on iPhone Air / iOS 27.0, with the Mac heavily loaded by parallel builds (load average ~580): 70 of 71 Swift Testing tests passed; the one failure (`SkyDome.skyColor` at exactly −18° returned 0.004000000000000001 instead of 0.004) is fixed by clamping and checked with a standalone build of the same file; a re-run was blocked by the host ("test runner hung", simulator boot timeout). Both UI tests passed. Both accessibility audits failed only by timeout ("Audit failed to complete in time", "main thread busy for 30 s"), with no audit issues recorded; no iPhone screen changed in this slice. Re-run the full suite on a quiet machine before merging. Reviewed captures (simulator "Nyx Vision Pro", visionOS 27.0, kept as `Research/Screenshots/vision-*`): window (room, immersive, night vision, accessibility size), Milky Way core in July, moonlit sky, Moon card, Saturn card, night-vision sky, plaque. Review fixes: the Milky Way's texture seam ran through the core (moved to the anticentre, noise made periodic), view attachments far out in the sky appeared late or not at all (labels are now SwiftUI rendered into textures), tone mapping bleached the night-vision red to white (sky materials now untone-mapped), the Milky Way was upside down in galactic latitude (texture rows flipped, checked with an orientation card), the Moon's night side punched a black hole in the twilight sky (now light over a sky-coloured disc), night-vision stars rendered white (grey textures, red tint), planets were fainter than bright stars, night-vision window text was filtered twice into a dim red.

**Known limits:** the sky is not aligned to real north (by design, said in the sky). Below magnitude 4.5 there are no stars (no invented filler). The Milky Way is a model, not a photograph. The simulator cannot judge true angular sizes; a device pass is in INPUT_NEEDED 6. Shipping in the iPhone record needs the bundle ID switch described there.

**Next starting point:** owner decides the bundle ID (INPUT_NEEDED 6) and tries it on a device; consider meteor radiants and the eclipse Moon in the immersive sky, and a "tonight" Spotlight/App Intent on visionOS.

---

# Nyx handoff — 2026-10-05 (roadmap: what's up tonight)

Roadmap §2, on branch `roadmap`. Logged under "What's up tonight" in `DECISIONS.md`. The score formula is unchanged; everything new is a reason to go.

- **Engine:** `SkyAlmanac` (core, planets via Schlyter elements, IMO meteor model, lunar eclipse visibility) and `SkyEvents` (bundled `sky-events.json`, sources in `Research/sky-events.md`). Wording and selection in `WhatsUp` (`Nyx/Services/WhatsUp.swift`), cached per park and night in `PlanModel`.
- **Park detail:** a "What's up tonight" card after the sky arc: eclipse and shower first, then the timed Milky Way core ("9:38 PM – 2:41 AM · Highest at 11:13 PM, 27° up in the south. Moon-free from 12:12 AM."), then planets brightest first. Links to the Milky Way and new meteor essays. The seasonal Milky Way sentence is gone from "What the sky may hold".
- **Sky arc:** the core's path (soft band, dotted spine, "Core" label, legend, VoiceOver). **Real sky:** planets as warm labelled points, the radiant as faint rays on shower nights.
- **Calendar, river, peek, breakdown:** one mark per night (visible eclipse > notable shower peak) with names in VoiceOver and the peek; breakdown says "Not part of the score."
- **Tonight:** one capsule at most: eclipse, then a major shower peak (≥ 20/h, Moon down), then "Darker on …".
- **Reminders:** major shower peaks at saved parks, one per night, own "Meteor shower peaks" switch, same ledger and budget.
- **Learn / About the data / README / site:** "Watching a meteor shower"; IMO and NASA/Espenak credits and accuracy.
- DEBUG: `-nyx-date yyyy-MM-dd`, `-nyx-park <id>`, `-nyx-screen whatsup` (also audited).

**Verified 2026-10-05:** zero warnings; iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5 — 64 Swift Testing tests (18 new: 6 engine references against PyEphem in `SkyAlmanacTests`, 12 in `WhatsUpTests` for table loading, core and planet wording, shower selection, peak notes, eclipse visibility, shower reminders, budget, ledger and no retitling) plus both UI tests and both accessibility audits (18 screens incl. the new `whatsup` × standard and night vision) pass on both runtimes. Reviewed captures (kept as `Research/Screenshots/whatsup-*`): detail and card on a Geminid peak, a total eclipse (and night vision), Alaska, a July core night, AX5, sky arc with the core, calendar, river, Tonight (shower and eclipse lines), Learn. Review fixes: planets took a glyph and a repeated time each (now one grouped list), the eclipse sentence repeated its own times, the calendar mark was lost in the halo (now beside the date), the river mark sat under the selected Moon, background planet names read as UI and failed the audit (removed; the card names them), essay links had an 18 pt hit area.

**Known limits:** shower radiants are drawn at their J2000 peak position (drift under a degree a day); the activity profile uses IMO's default steepness where the table has none, so plateau showers (Taurids) are underestimated away from their peak; the 2027 IMO calendar was read only from excerpts (see `Research/sky-events.md`). The eclipse table ends in 2032; shower peaks without a published time come from the Sun's longitude (within about 20 minutes of IMO's, ±12 h for the five showers IMO dates only to a degree). Planets are not named in the background sky (audit: unreachable text); the card names them. xcodebuild sometimes stays alive after all tests report; results are read from the log.

**Next starting point:** integrator bumps the build number; consider App Store In-App Events for the Geminids (Dec 13–14, 2026) now that the app names them.

# Nyx handoff — 2026-10-05 (roadmap: Apple Watch)

Roadmap Tier 2b with Tier 1 §1's wrist countdown, on a worktree branch from `roadmap`. Logged under "Apple Watch" in `DECISIONS.md`. The product brief's §11 no longer excludes the watch.

- **Targets:** `NyxWatch` (watchOS 26+, `com.harrypakhale.nyx.watchkitapp`) embedded in the iOS app, with `NyxWatchWidgets` (complications and Smart Stack). A `NyxWatch` scheme runs it alone. Shared engine files are listed in `project.yml`; the network transport is deliberately not compiled for the watch (`verify_release.py` asserts it). `Forecast` moved to `Nyx/Models/Forecast.swift` for that reason.
- **Sync:** `WatchBridge` (iOS, one new file, called where the widget snapshot is written and when night vision changes) sends a compact, versioned `WatchContext` (saved parks, starting park, night vision, cloud forecasts under 48 KB) over WatchConnectivity. No-op without a paired watch.
- **Watch:** red-first palette (Red light / Match iPhone / Starlight). Tonight is a Digital Crown pager: gauge + Moon + next moment; tonight's milestones; the next seven nights. Parks list with tonight's scores; "Show on Tonight" pins any park; a park chooser before the first sync (moon and darkness only, said plainly). Dark adaptation: a red full-screen countdown.
- **Complications:** circular, rectangular, corner, inline; relevance at dusk on Good+ nights, plus a watchOS 26 `RelevanceConfiguration` "Dark night ahead" Smart Stack widget.
- **Tests:** `NyxTests/WatchTests.swift` (5): context round trip and equal cloud means, gaps/version/size rejection, milestone ordering inside the night for five parks × five months, polar edges (Denali June, Gates of the Arctic December), red contrast ≥ 4.5:1.
- DEBUG: `-nyx-watch-screen`, `-nyx-watch-state`, `-nyx-watch-palette`, `-nyx-watch-ax` (README → Apple Watch).

**Verified 2026-10-05:** unsigned Release archive of the Nyx scheme (iOS app, widgets, watch app, watch widgets) builds with zero warnings and `verify_release.py` passes (4 privacy manifests); NyxWatch Debug builds clean; `NyxTests` 51/51 pass on iOS 27 (Audit iPhone 17). **Not verified:** `NyxUITests` (accessibility audit) did not complete — on a host loaded by parallel builds XCUITest failed with "Audit failed to complete in time", "Failed to get matching snapshot" and "Failed to terminate" (4,951 s for one test) and the run was stopped at the 2-hour limit; this slice changes no iPhone screen, but rerun the full suite on an idle machine before merging (watchOS 27.0 simulators only: no watchOS 26 runtime is installed, so the 26.0 floor is compile-checked, not run). Watch screens captured on Nyx Watch S11 42 and Nyx Watch Ultra 3 (watchOS 27.0) and reviewed in `Research/Screenshots/watch/`: Tonight (red, Starlight, with a real Open-Meteo forecast and without), milestones, week, dark adaptation, parks, chooser, Denali, American Samoa, complications, accessibility text size. Review fixes: toolbar buttons filled bright red (now dark), the title fell to ~2.4:1 in red (now ink), the gauge's glow was clipped into a box and the Moon covered the band word (re-proportioned), the dark-adaptation close button was white (own dark Done), and self-updating countdown text looped layout so the app never launched (now written per minute). Second review (S11 + Ultra 3): Tonight never said whether it is dark *now* (added "Truly dark now" / "Twilight now", with "clouds unknown" folded onto the clock-time line so the gauge keeps its size); the circular complication's Moon glyph rendered white on a red face (now coloured); the week named one "darkest" night when five tied (every tied night ringed, "and 4 more"). Also "Then Dawn twilight at" became "Next: Dawn twilight, 6:30 AM", and `WatchBridge` remembers a context only once WatchConnectivity accepted it. The `s11-*-clouds-*` captures predate the second review's layout.

**Known limits:** the watchOS status clock stays white; complications on a real face, the Smart Stack and real iPhone↔watch delivery need the on-device review (INPUT_NEEDED 6). The App Group and watch bundle IDs must be registered by the account holder at the first device build.

**Next starting point:** merge this branch into `roadmap`; on-device watch review; watch screenshots for App Store Connect when 1.2 ships.

---

# Nyx handoff — 2026-10-05 (roadmap: an honest forecast)

Roadmap §3, on branch `roadmap`. Logged under "An honest forecast" in `DECISIONS.md`. The score formula is unchanged; everything new is context.

- **Model agreement:** GFS, ECMWF and ICON clouds over each dark window (7 days). A word under the Clouds meter ("Models agree / Roughly agree / Models differ"), a sentence on detail and in the breakdown ("Models disagree: 4–46% cloud. Check again before you leave."), and a pale whisker on the time river spanning the scores the clearest and cloudiest model would give, with the range beside the selected night and in VoiceOver.
- **Layers and the night itself:** layer note ("Thin high cloud; bright stars only."), coldest hour, dew on lenses, gusts, in locale units; visibility as a haze hint only.
- **Smoke:** CAMS aerosol optical depth from `air-quality-api.open-meteo.com` (third host, owner-approved, own "Smoke and haze" switch). "Air" row on detail, amber caveat under the score on detail and Tonight from AOD 0.25.
- **Data:** `ForecastDetailService` + `ForecastDetail` (`Nyx/Services/ForecastDetail.swift`), cached per park with per-part six-hour freshness; `Forecast` and its caches unchanged. Three extra requests per refresh cover all 63 parks.
- **Docs:** the product brief §13, PRIVACY.md, docs/privacy|support|index.html, Store/PrivacyPolicy.md, README, both privacy manifests' host comments, `Scripts/verify_release.py` host assertion.
- DEBUG: `-nyx-state agree | disagree | smoke`, `-nyx-night-vision` flag.

**Verified 2026-10-05:** zero warnings; iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5 — 46 Swift Testing tests (11 new in `NyxTests/ForecastDetailTests.swift`: single and multi-coordinate payloads, rejected payloads, agreement and AOD bands, cold/dew/gust windows, old caches, smoke switch at the transport, per-switch requests, failure keeps last data, score unchanged with range) plus both UI tests and both accessibility audits (17 screens × standard and night vision) pass on both runtimes. Captured and reviewed: detail (agree, disagree, smoke, night vision, AX5, iOS 26.5), river (disagree, AX5 stepper), breakdown (disagree, smoke), Tonight (smoke), Your privacy; kept as `Research/Screenshots/forecast-*`. Review fixes: whiskers were too faint to read (wider, capped, range printed beside the selected night), breakdown context was as loud as the scored fact (now symbol-led callout lines), "The night itself" sentence broke mid-phrase (now three labelled lines), VoiceOver joined two sentences without a full stop.

**Known limits:** agreement needs all three models (by design). The layer note's thresholds and the AOD bands are first estimates and deserve a check against real nights (INPUT_NEEDED 1). The updated privacy page must be pushed before a build with the smoke host is submitted (INPUT_NEEDED 5).

**Next starting point:** integrator bumps the build number; push the docs with the merge; on-device night review including a smoky western night if one comes.

---

# Nyx handoff — 2026-10-05 (design pass, build 5)

A design pass aimed at the Apple Design Award bar: every screen now answers "when" as well as "where", and every number arrives with its reason. Logged under "Design pass" in `DECISIONS.md`.

- **Park detail:** a four-part score readout (Moon, Clouds, Sky glow, Dark hours) sits under the gauge and glides as nights are scrubbed; it opens the breakdown.
- **Score breakdown:** each part states the fact it was scored from, over that park's real sky for that night; unknown clouds stay visible as a dashed row.
- **Parks and Tonight lists:** a seven-night strip per park names its best night ("Best Fri · 94").
- **Tonight:** "Darker on Wed, Oct 7: 97 at Death Valley" names the best night ahead in reach and opens it.
- **Journal:** cards show the Moon's phase that night; an entry shows the lit Moon and stands under that park's real stars that night.
- Store screenshots and captioned frames recaptured with live data. Build number is **5** (`project.yml`); build 4 in App Store Connect predates this pass.

**Verified 2026-10-05:** zero warnings; iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5 — all 39 tests including both accessibility audits pass (the audit caught a fixed-size numeral in the new breakdown, now Dynamic Type-scaled). Touched screens captured and reviewed: detail (live, no forecast, night vision, AX5), Parks (live, AX5), Tonight, journal list and entry, breakdown (standard and polar), store frames.

**Next starting point:** build 1.0 (5) is uploaded (2026-10-05). Test it in TestFlight and submit it (INPUT_NEEDED 2), with the new frames in `Store/Framed/`; then the on-device night review (INPUT_NEEDED 1).

---

# Nyx handoff — 2026-10-04 (fresh audit, build 4)

A fresh four-part audit (astronomy math against PyEphem, services and concurrency, UI and accessibility, configuration and release). All confirmed findings are fixed and logged under "Fresh audit" in `DECISIONS.md`. Highlights: Alaska moonrise/moonset accuracy (was up to 41 minutes off), Milky Way guidance at high latitude, a privacy-preserving all-park forecast request, careful use of the shared NPS key, offline data moved out of Caches, reminder calendar and race fixes, and a set of night-vision, VoiceOver and time-river corrections.

**Verified 2026-10-04 on one dedicated simulator (iPhone 17 Pro, iOS 27.0):** zero warnings; 35 Swift Testing tests pass (7 new: PyEphem reference times, pinned formula, Milky Way latitude, polar sunrise, NPS throttling, all-park forecasts, reminder race); both UI tests and the night-vision accessibility audit (17 screens) pass; the standard-palette audit passes on all 17 screens across two runs (a heavily loaded host made one run's audit time out mid-way; every issue it logged is a documented exclusion). Touched screens were captured and reviewed (detail standard and polar, river selection, calendar, Tonight). Not re-run on iOS 26.5 this time (one simulator, at the owner's request); none of the changes touch iOS 26-specific code paths.

**Next starting point:** build 1.0 (4) is uploaded and the privacy page is pushed. Test build 4 in TestFlight and submit it (INPUT_NEEDED 2), optionally request a higher NPS limit (INPUT_NEEDED 3), and do the on-device night review (INPUT_NEEDED 1).

---

# Nyx handoff — 2026-10-03 (depth and realism, build 3)

Every item in `Research/depth-and-realism-audit.md` is implemented, at the owner's request, before the first release:

- **Icon:** the Dial (score arc and leading star around a sphere-shaded, earthlit crescent), three depth groups. Earlier concepts in `IconSources/Concepts/`.
- **Moon:** a Metal shader lights NASA's lunar map on a sphere (Lommel–Seeliger), tilted as seen from the park at the Moon's highest point that night, with libration and earthshine. Test: the bright limb points at the Sun's real bearing within 3° in six parks. Share cards use it; widgets get pre-rendered pictures from the app.
- **Sky:** 904 Yale Bright Star Catalogue stars in their true colours, projected for each park and night, with the Milky Way along the galactic plane, on three tilt-parallax layers. Test: the galactic core sits low in the south on a July night at Joshua Tree.
- **Instrument and glass:** the gauge has an open-arc Liquid Glass rim, inner shadow and a tilt glint; cards are tinted Liquid Glass; hero gauges float on scroll; the sky arc has a per-park ridge. Solid fallbacks under Reduce Transparency, Increase Contrast and night vision; motion off under Reduce Motion and Low Power Mode.
- Build number **3** (`project.yml`). Builds 1 and 2 in App Store Connect predate this work.

**Verified 2026-10-03:** zero warnings; on iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5, all 28 Swift Testing tests, both accessibility audits (17 screens × standard and night vision) and both UI tests pass. Store screenshots recaptured (live data, no alpha).

---

# Earlier handoff — 2026-10-03 (award polish)

## Award polish

Two independent audits (astronomy/score, app flows) and a screen-by-screen visual critique. Everything found is fixed and logged under "Award polish" in `DECISIONS.md`. Highlights:

- **Correctness:** reminders no longer return after being tapped or cleared; "tonight" turns over at sunrise, not noon; eastern parks keep tonight's clouds (`past_days=1`); a few minutes of darkness can no longer score Excellent; fresh closures survive a failing NPS events call; the five-night window crosses month boundaries; Ask Nyx shares Tonight's location; denied location links to Settings; the reminder switch reflects iPhone Settings; safe journal deletion.
- **Product:** one Open-Meteo request now covers all 63 parks, so the Parks tab shows forecast-backed scores everywhere, with a "Darkest tonight" sort. Tonight leads with the answer.
- **Visuals:** vector moon disc (limb darkening, soft terminator, maria, glow); gauge with glowing arc, leading star and visible orbit; sky arc rebuilt with altitude-true twilight colour, moonlit-hours wash, true-darkness bracket, hour labels and Now marker; medium widget gains a seven-night strip, moon phase and a seeded sky; journal cards show a photo.
- Build number is now **2** (`project.yml`). Build 1 in App Store Connect predates these fixes.

**Verified 2026-10-03 (final):** app, widget and tests build with zero warnings; on iPhone 18 Pro / iOS 27.0 and iPhone 17 Pro / iOS 26.5, all 24 Swift Testing tests, both accessibility audits (17 screens × standard and night vision) and both UI tests pass. Three independent code audits and one self-review were run; every confirmed finding is fixed and logged in `DECISIONS.md`. Touched screens were captured and reviewed, including night vision, AX5 and polar states; river scrubbing and park links over an open sheet were exercised in the simulator. Store screenshots recaptured with live data and flattened (no alpha).

**Known limits:** Ask Nyx's source records are English data, not catalog strings. Hardware haptics, real widgets, Siri, VoiceOver by ear and dark-adapted readability still need the on-device night review.

**Next starting point:** upload build 1.0 (2) (INPUT_NEEDED 2), then the on-device night review (INPUT_NEEDED 1).

---

# Earlier handoff — 2026-10-02 (completion review)

## Completion review (after the first build)

A full code, design and accessibility review of the first build found and fixed the issues listed under "Completion review" in `DECISIONS.md`. The most important:

- **Live park alerts and ranger programs could never load**: the NPS key was dropped from Info.plist. Fixed via `Config/Nyx.xcconfig` + git-ignored `Config/Secrets.xcconfig`; only the key itself is still needed (INPUT_NEEDED 3).
- **"Tonight" after midnight showed the next night** in the app, widget and Siri. Fixed (`Park.currentNight(at:)`).
- **Reminders for tonight were never sent**; tapping a reminder did nothing. Fixed, with a delivered-once guarantee.
- **Share cards exported with invisible text.** Fixed.
- **Signature motion and interaction** finished to the spec: rebuilt time river under the gauge, calendar peek and directional months, self-drawing constellation loader, score-reactive starfield and gauge orbit, onboarding that builds the score, cold-launch reveal.
- **App icon** is now a native Icon Composer document (`Nyx/Resources/AppIcon.icon`).
- **Viewing spots** researched from NPS pages for the parks that had none (see `Research/viewing-spots.json` for sources and evidence).

Verified: app + tests build with zero warnings (warnings are errors) on iOS 26.5 (iPhone 17 Pro) and iOS 27.0 (iPhone 18 Pro); unit and UI suites pass on both. Screens touched were re-captured and reviewed, including night vision and AX5.

### Release completion — 2026-10-03

- **Accessibility:** Apple's automated audit (`AccessibilityAuditTests`) passes on all 17 screens in both palettes after fixes; exclusions are documented in the test.
- **Live NPS data verified:** the owner's key lives in git-ignored `Config/Secrets.xcconfig`; real Joshua Tree alerts loaded in the app. Closure detection now also catches closures NPS files under "Caution" or "Danger".
- **Privacy label decided:** Data Not Collected (`PRIVACY.md`). Public privacy, support and landing pages are in `docs/` for GitHub Pages, contact harry.pakhale98@gmail.com.
- **App Store assets current:** screenshots recaptured (`Store/Screenshots`, 1320×2868); String Catalog synced (331 keys).
- **Owner steps left:** see `INPUT_NEEDED.md` — make the repo public and turn on Pages, try it on an iPhone, then create the App Store Connect record and upload.

---

## Engineering checkpoint: Phases 0–7 implemented

The source app and widget extension are complete for release review. The integrated feature checkpoint is `5b94bfe`; audit commit `778b3fb` contains final repairs, test evidence, screenshot artwork and submission documentation. This is not yet authorization to submit: the publisher and physical-device gates below remain open.

Implemented: all 63 national parks; offline astronomy and Darkness Score; native five-tab navigation; celestial gauge, moon, sky arc, calendar and time river; manual/location-based Tonight planning; saved parks and local reminders; SwiftData journal with selected photos; onboarding; privacy/data/settings; three Learn essays; share cards; widgets and Control Center control; App Intents/Spotlight; availability-gated on-device Foundation Models. XcodeGen remains the project source of truth. There are no third-party runtime dependencies or remote AI calls.

## Final verification

| Gate | Evidence |
|---|---|
| iPhone 17 Pro / iOS 26.5 | 15 Swift Testing + 2 native UI tests pass; zero failures and build/analyzer warnings |
| iPhone 18 Pro / iOS 27.0 | Same 17 tests pass; zero failures and build/analyzer warnings |
| Release | Development-signed archive succeeds; signatures validate; app and widget contain the correct App Group and privacy manifests; iPhone portrait only |
| Astronomy | 27 solar/civil-twilight samples: max 0.47 min error; 18 lunar rise/set samples: max 3.72 min; explicit polar/tropical/DST tests. Astronomical twilight has no separate independent published fixture |
| Visual review | 182 QA captures across both runtimes; actual Simulator AX5 and Increase Contrast; loading, empty, error, offline, unknown clouds, polar, red and reduced-motion review states |
| Store artwork | Six visually reviewed native 1320×2868 drafts; illustrative journal and real computed scores with uncertainty retained |
| Performance | Native launch means 2.179 s / 3.756 s in the documented Debug review scenario; 15.794 s active-animation profiler reports zero >250 ms hangs; allocations recording retained locally. These do not establish hardware frame rates or absence of leaks |
| Privacy | Exact two-host transport allowlist and independent network toggles verified. Provider retention / App Store label remains unresolved |

See `AUDIT.md`, `Research/accuracy.md`, `Research/performance.md`, `Research/test-26.json`, `Research/test-27.json`, and `Research/release-verification.json` for measured limits. The final development archive is `/tmp/NyxSigned.xcarchive`; rebuild/export instructions are in README and SUBMISSION. Raw Instruments traces are local and Git-ignored.

The final critique repaired access guidance placement, red native-control contrast, park-local journal/program dates, reminder preference races, malformed forecast coverage, AX5 gauge/arc/river/calendar layouts, widget text fitting and settled screenshot timing. These choices are recorded in `DECISIONS.md`.

## Deliberate limitations and release gates

- Current privacy label is a draft. Open-Meteo's published API-log retention and NPS/API.gov processing need authoritative publisher review; do not claim “Data Not Collected” until resolved. See `PRIVACY.md`.
- No NPS key is committed. Core planning works without it; live closures/programs show an honest unchecked state. Add one in `Config/Secrets.xcconfig` (INPUT_NEEDED 3); it is strongly recommended for release because closures are the app's most important safety signal.
- Named viewing spots (50 of 63 parks) appear only where nps.gov pages support them; see `Research/viewing-spots.json`. The other 13 parks give ranger guidance instead of invented coordinates. Bortle values remain clearly labeled estimates.
- VoiceOver interaction, actual system Reduce Motion/Transparency/Bold Text/Smart Invert, PhotosPicker/system permissions, actual widget/control/Siri integration, available-model behavior, hardware haptics/performance and dark-field usability require physical review. Screenshot overrides and widget content previews do not certify these gates.
- The Release archive uses development signing. App Store distribution export, hosted privacy/support pages, account metadata, TestFlight and final submission require the owner.

## Exact next starting point

Start with **item 1 in INPUT_NEEDED.md** (repo public + GitHub Pages), then the on-device review and App Store Connect steps. Do not add features before those release gates close. If review finds a defect, fix it, rerun both simulator suites, recapture affected states, archive again and update this handoff before submission.
