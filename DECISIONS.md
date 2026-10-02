# Decisions

One line per decision, with reasoning. Newest at the bottom.

- Project shell generated with XcodeGen (`project.yml`) instead of the Xcode wizard — the build runs from the command line (`xcodebuild`), which cannot drive Xcode's GUI; generated, not hand-written, so the "never hand-write a .pbxproj" intent holds.
- Source folders use Xcode synchronized folders — new files need no project-file change.
- Bundle ID prefix `com.harrypakhale`, App Group `group.com.harrypakhale.nyx` — matches the owner's GitHub handle; change in `project.yml` and both entitlements files if a different prefix is registered.
- Widget extension lives in top-level `NyxWidgets/` (not `Nyx/Widgets/`) — keeps extension sources out of the app target's synchronized folder.
- Entitlements and the widget Info.plist live in `Config/` — files there are not swept into a synchronized source folder as resources.
- App target uses Swift 6, default actor isolation MainActor, approachable concurrency — matches the current Xcode app template.
- `ITSAppUsesNonExemptEncryption = NO` — the app only uses HTTPS via URLSession, which is exempt.
- SwiftData container not created in the shell — Phase-owned models add it; avoids the template's throwaway `Item` model.
- Built with the installed Xcode 27.0 against an iOS 26.0 deployment target — the brief names Xcode 26; the deployment target, not the Xcode version, is what matters. iOS 27+ APIs are allowed behind availability checks with a first-class iOS 26 fallback.
- Spec updated by the owner: support iOS 26 and every later release, aim for an Apple Design Award (product brief §16), and give the builder broad creative freedom with a short list of fixed guardrails (§17).
- 2026-10-02: Merge Phase 0 with the engine portions of Phase 3 first; every visual score should be backed by tested astronomy from its first appearance.
- 2026-10-02: Split the NPS `seki` inventory record into Sequoia and Kings Canyon, retaining the shared API code; this makes the 63-park inventory correct.
- 2026-10-02: Only include viewing spots explicitly supported by an NPS night-sky page; show a ranger-guidance empty state elsewhere rather than invent a recommendation. Broader spot coverage is a content enhancement, not a requirement for safe planning.
- 2026-10-02: Cap zero-astronomical-darkness nights at 39/Poor; an otherwise high renormalized score would mislead Alaska summer visitors.
- 2026-10-02: Validate NOAA solar math against independently published USNO rise/set data (nine park/date fixtures); USNO is also the independent lunar reference.
- 2026-10-02: Use a local-noon-to-noon night and UTC instants, with NOAA/Meeus coordinates and bracketed horizon crossings; this handles polar nights and DST without invalid inverse trigonometry.
- 2026-10-02: Free, non-commercial, no ads or subscriptions for v1; Open-Meteo's free service permits this model. Preserve attribution and check terms again before distribution.
- 2026-10-02: Integrate the screen portions of Phases 1–5 with 6a/6b before the first UI checkpoint; one coherent working tab shell is easier to assess than placeholder screens. Keep Phase 7 as a separate final audit.
- 2026-10-02: Correct the epoch-based mean moon phase using Meeus ecliptic elongation; the uncorrected mean misses the October 2026 new moon by 17.4 hours. Three USNO phase fixtures now pass the 12-hour gate.
- 2026-10-02: On iOS 27 use `topBarPinnedTrailing` for Save; verified in the installed SwiftUI interface. iOS 26 uses `topBarTrailing`.
- 2026-10-02: Limit pristine reminders to complete, recent cloud forecasts; unknown clouds never produce a clear-sky notification. Respect other pending local notifications and the global limit of 64.
- 2026-10-02: First design critique fixes: move Tonight's winning park above the gauge; render a real phase silhouette for the tab icon; use an accessible list instead of the calendar grid at accessibility text sizes.
- 2026-10-02: DEBUG screen scenarios use an in-memory SwiftData container and do not write planning preferences; screenshots must not contaminate a user's saved parks or journal.
- 2026-10-02: No physical device or interactive Icon Composer pass was available. Produce original SVG icon layers and a working 1024px raster icon; leave final Icon Composer export and assistive-technology interaction checks as explicit owner gates.
- 2026-10-02: Disable unused String Catalog symbol generation; automatic compiler-extracted sentence keys and format-only keys are valid localization keys but can collide as Swift symbols. All English app copy is preserved in the catalog.
- 2026-10-02: Apply a stable monochrome red filter to the app's night-vision rendering, including native controls and separate sheet hosts; hide the bright status bar in this mode and raise secondary copy contrast.
- 2026-10-02: AI reminder copy selects between vetted templates after rule-based notifications are already scheduled; the model never writes condition claims or blocks scheduling.

- 2026-10-02: Final accessibility fixes capture motion state before Sendable scroll transitions, make panels opaque under Reduce Transparency/Increase Contrast, and carry the red theme into calendar sheets.
- 2026-10-02: Format calendar headings and NPS event dates in the park's zone; UTC dates can silently omit a local evening program or show the previous month.
- 2026-10-02: Milky Way core guidance names southern winter correctly without shifting visibility six months; the core has the same right ascension in both hemispheres (ESO southern-winter reference).
- 2026-10-02: Enforce network privacy toggles at the transport boundary as well as in view state; disabling an endpoint stops subsequent requests in a multi-page refresh.
