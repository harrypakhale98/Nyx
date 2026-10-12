import AppIntents
import SwiftUI
import WidgetKit

/// Siri and Shortcuts on the wrist: tonight's score where Tonight shows it, the dark-adaptation
/// clock, and red light. Each answers from what is already on the watch; none touches the network.
struct NyxWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: WristTonightIntent(), phrases: ["How dark is it tonight in \(.applicationName)", "What's tonight's darkness score in \(.applicationName)"],
                    shortTitle: "Tonight's sky", systemImageName: "moon.stars")
        AppShortcut(intent: StartAdaptationIntent(), phrases: ["Start dark adaptation in \(.applicationName)", "Adapt my eyes to the dark with \(.applicationName)"],
                    shortTitle: "Dark adaptation", systemImageName: "eye")
        AppShortcut(intent: RedLightOnIntent(), phrases: ["Red light on in \(.applicationName)", "Turn on red light in \(.applicationName)"],
                    shortTitle: "Red light", systemImageName: "flashlight.on.circle.fill")
    }
}

/// "How dark is it tonight in Nyx?" on the wrist: the park Tonight shows (kept on the watch, else
/// the darkest saved park, else the iPhone's starting park), scored on the watch from the context the
/// iPhone last sent. Read only; a closure comes first.
struct WristTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "Tonight's darkness score"
    static let description = IntentDescription("The darkness score tonight at the park Nyx follows on the wrist, from the last forecast your phone sent.")
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: WristTonightAnswer.dialog(now: .now)))
    }
}

/// The spoken answer apart from the intent: the same park and night as Tonight (`WatchStore.featured`).
nonisolated enum WristTonightAnswer {
    static func dialog(now: Date) -> String {
        let context = WatchSky.readContext()
        let parks = (try? ParkData.load()) ?? []
        let nights = WatchSky.candidates(in: parks, context: context, pinned: WatchSky.pinnedPark).map { park in
            WatchSky.night(park, evening: park.currentNight(at: now), forecast: context?.cloudForecasts[park.id], detail: context?.forecastDetails[park.id], now: now,
                           climate: context?.climate ?? .shared)
        }
        guard let night = NightPlanner.best(nights) else {
            return String(localized: "No place chosen yet. Save one in Nyx on iPhone, or choose one in Nyx on this watch.")
        }
        return dialog(night, context: context, now: now)
    }
    /// A closure first, as on the iPhone: a long drive to a closed road is the worst outcome Nyx can cause.
    static func dialog(_ night: Night, context: WatchContext?, now: Date) -> String {
        let park = night.park, score = night.score
        let body = night.sky.darkHours == 0
            ? String(localized: "No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.")
            : String(localized: "\(park.shortName), \(score.value) out of 100, \(score.band.label). \(clouds(night, context: context, now: now))")
        guard let closure = context?.closures[park.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !closure.isEmpty else { return body }
        let alert = WristClosure.spoken(closure)
        return (alert.last.map { ".!?…".contains($0) } == true ? alert : alert + ".") + " " + body
    }
    /// What the clouds rest on, honestly: the forecast and when the iPhone sent it, or why there is none.
    static func clouds(_ night: Night, context: WatchContext?, now: Date) -> String {
        guard let context else { return String(localized: "No cloud forecast yet. Open Nyx on iPhone for clouds.") }
        let source = CloudSource.of(context: context, park: night.park, now: now)
        if night.score.hasForecast {
            // The iPhone resends a context unchanged (offline, forecasts off, "Update from iPhone"), so a
            // recent send can carry an old forecast: then the forecast's own age is said too.
            let time = context.sent.formatted(date: .omitted, time: .shortened)
            let sent = Calendar.current.isDate(context.sent, inSameDayAs: now)
                ? String(localized: "From the cloud forecast your iPhone sent at \(time).")
                : String(localized: "From the cloud forecast your iPhone sent on \(context.sent.formatted(.dateTime.weekday(.wide))) at \(time).")
            return [sent, source.isStale ? source.line(for: night.park) : nil].compactMap { $0 }.joined(separator: " ")
        }
        let fix = source.isStale || source == .missing(followed: false) ? source.line(for: night.park) : nil
        return [night.basisCaption(), fix].compactMap { $0 }.joined(separator: " ")
    }
}

/// "Red light on in Nyx": the Red light palette, as the Control Center control's On. Its own intent,
/// in the app, because the control's (`RedLightIntent`) lives in the widget extension.
struct RedLightOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn on red light"
    static let description = IntentDescription("Keep Nyx red on the wrist, day or night, to protect dark-adapted eyes.")
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WatchSky.palette = .red
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: WatchSky.redLightKind)
        return .result(dialog: IntentDialog(stringLiteral: String(localized: "Red light is on. Nyx stays red, day or night, until you change Colors in Parks.")))
    }
}

/// Takes the requests the dark-adaptation intent leaves (`AdaptationRequest`): starts the app's own
/// clock (the reminders, and the permission question the first time) and opens the red screen for
/// the park on Tonight. Also keeps the clock's complication in step when the clock starts or stops.
struct AdaptationRequests: ViewModifier {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var shown: AdaptationCover?
    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $shown) { cover in DarkAdaptationView(park: cover.park).environment(store) }
            .onAppear { take() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { take() } }
            .onReceive(NotificationCenter.default.publisher(for: AdaptationRequest.notification)) { _ in take() }
            .onChange(of: store.adaptation) { WidgetCenter.shared.reloadTimelines(ofKind: AdaptationRequest.complicationKind) }
    }
    private func take() {
        guard WatchDebug.screen == nil, let start = AdaptationRequest.take() else { return }
        // The same start the intent stored, so a clock already running keeps its minutes.
        Task { await store.startAdaptation(at: start) }
        // Before any park is followed there are no moments to show; the clock and its complication still run.
        if let park = store.featured(at: .now) { shown = AdaptationCover(park: park) }
    }
}
private struct AdaptationCover: Identifiable {
    let park: Park
    var id: String { park.id }
}
