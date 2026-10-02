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
