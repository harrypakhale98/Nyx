# Installed SDK verification

Build environment: Xcode 27.0, build 27A266a. Minimum iOS 26.0. Apple framework arm64e Swift interfaces were inspected under the installed iPhoneOS SDK; compiler builds cover both the iOS 26 fallback and iOS 27 simulator. Availability is also enforced by the 26.0 deployment target.

| API | Verification / use |
|---|---|
| SwiftUI `ToolbarItemPlacement.topBarPinnedTrailing` | Installed interface marks iOS 27; ParkDetail uses `if #available(iOS 27.0, *)`, native topBarTrailing fallback on 26. |
| `Tab`, `glassEffect`, `matchedTransitionSource`, `navigationTransition(.zoom)` | Installed SwiftUI interfaces / successful builds; deployment is already 26, no older workarounds. |
| `sensoryFeedback`, `scrollTransition` | SwiftUI interfaces/compiler; motion state captured outside the Sendable transition closure. |
| `ImageRenderer`, `ShareLink`, `PhotosPicker`, SwiftData `@Model` / external storage | Installed interfaces/compiler. Shared image uses a static gauge so the actual score is rendered. |
| WidgetKit `ControlWidgetToggle`, `StaticControlConfiguration`, `ControlValueProvider` | Installed WidgetKit interfaces/compiler; exact SetValueIntent signature checked in AppIntents. |
| `widgetFamily` | Read-only in the installed WidgetKit interface; DEBUG content review uses an explicit view parameter, not an invalid environment override. Actual system hosting remains a device gate. |
| Foundation Models `SystemLanguageModel.default.availability`, `LanguageModelSession`, `streamResponse(generating:)`, `@Generable`, `GenerationOptions` | Installed FoundationModels interface and compiled implementation. Structured partial snapshots are optional until generated. Only available models expose production entry points. |
| `accessibilityReduceMotion` | Read-only; actual system environment plus a separate DEBUG-only override used for screenshot review. |

All app runtime dependencies are Apple frameworks. There is no Package.resolved, SPM package, remote LLM or third-party SDK. SDK inspection verifies signatures/availability, not real device behavior or future OS compatibility.

## Native UI verification

The installed Simulator Developer frameworks expose `XCUIApplication`, `XCTMeasureOptions.iterationCount`, and `XCTApplicationLaunchMetric.initWithWaitUntilResponsive:` (iOS 14+). These test-only Apple APIs measure first frame plus main-thread responsiveness. UI automation uses XCTest; the unit suites continue to use Swift Testing. Importing AppIntents in both test bundles satisfies Xcode 27's metadata-extraction dependency check without adding any third-party framework.

Fixed widget fallbacks use the installed SwiftUICore `dynamicTypeSize<T: RangeExpression>` API. The compact widget host bounds its visual labels while preserving a complete spoken summary; the main app reflows fully at AX5. Native hosting requires physical sign-off.
