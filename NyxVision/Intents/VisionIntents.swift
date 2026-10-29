import AppIntents
import Foundation

// Siri and Shortcuts on Apple Vision Pro: a park's darkness score tonight, when it is dark and what's
// up there, a park opened in the planner, and tonight's sky to stand under. Everything is computed on
// the headset from the bundled parks and the cached cloud forecast, smoke, park alerts and aurora
// forecast; no intent makes a request.

/// A national park, for Siri and Shortcuts. The iPhone's entity name, type name and identifiers
/// (the park code), so a park means the same thing on every device; read from the bundled park list.
struct ParkEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Place")
    static let defaultQuery = ParkQuery()
    let id: String
    let name: String
    var state = ""
    var darkSky = false
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: state.isEmpty ? nil : "\(state)", image: .init(systemName: darkSky ? "moon.stars" : "mountain.2"))
    }
    init(_ park: Park) { id = park.id; name = park.shortName; state = park.region; darkSky = park.darkSkyDesignated }
}
struct ParkQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ParkEntity] { try ParkData.load().filter { identifiers.contains($0.id) }.map(ParkEntity.init) }
    /// The park chosen in the planner first (the one people ask about), then the rest by name.
    func suggestedEntities() async throws -> [ParkEntity] {
        let chosen = UserDefaults.standard.string(forKey: VisionModel.parkKey)
        return try ParkData.load().sorted { ($0.id == chosen ? 0 : 1, $0.shortName) < ($1.id == chosen ? 0 : 1, $1.shortName) }.map(ParkEntity.init)
    }
    func entities(matching string: String) async throws -> [ParkEntity] { try ParkData.load().filter { $0.matches(string) }.map(ParkEntity.init) }
}
/// What Siri and Shortcuts say when an intent cannot answer, in the iPhone's words.
enum VisionIntentError: Error, CustomLocalizedStringResourceConvertible {
    case parkNotFound
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .parkNotFound: "That place could not be found in Nyx."
        }
    }
}

/// "What's the darkness score at Joshua Tree tonight?" Answers in words and returns the score,
/// 0 to 100, so Shortcuts can use it. Reads this headset's cached forecast, smoke and park alerts
/// and never asks for new ones, so it answers the same with a switch off, and says so.
struct DarknessIntent: AppIntent {
    static let title: LocalizedStringResource = "Tonight's darkness score"
    static let description = IntentDescription("Find the on-device darkness score for a national park. Returns the score, 0 to 100.")
    @Parameter(title: "Park") var park: ParkEntity
    static var parameterSummary: some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let selected = try ParkData.load().first(where: { $0.id == park.id }) else { throw VisionIntentError.parkNotFound }
        let forecast = await WeatherService().forecast(for: selected, network: false)
        let layers = await SummitLayerService().layers(for: [selected], network: false)[selected.id]
        let smokeOn = NetworkService.smoke.isOn()
        let air = smokeOn ? await ForecastDetailService(extras: false).hydrate([selected])[selected.id]?.air : nil
        let inputs = ScoreInputs(smokeOn: smokeOn, smokeKnown: air == nil ? [] : [selected.id], alertsOn: NetworkService.alerts.isOn(), alerts: ParkStore.stored([selected]))
        let now = Date.now
        // Tonight scored as the planner scores it (`NightPlan`), said in every device's words (`TonightAnswer`).
        let night = NightPlanner.night(park: selected, sky: AstronomyEngine().conditions(for: selected, on: selected.currentNight(at: now)),
                                       forecast: forecast, detail: ForecastDetail.vision(layers: layers, air: air), now: now)
        let dialog = inputs.answer(night, closure: inputs.closure(selected), forecastsOn: NetworkService.forecasts.isOn()).dialog()
        return .result(value: night.score.value, dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// The park a question names, else the one chosen in the planner (Joshua Tree before any), as
/// Stand under tonight's sky chooses; and its closure from this headset's last park update, which
/// the darkness score says too (a known closure is never hidden).
nonisolated enum VisionIntentPark {
    static func resolve(_ entity: ParkEntity?) throws -> Park {
        let parks = try ParkData.load()
        let id = entity?.id ?? VisionModel.rememberedPark(in: parks)
        guard let park = parks.first(where: { $0.id == id }) else { throw VisionIntentError.parkNotFound }
        return park
    }
    static func closure(_ park: Park) -> String? { ParkStore.stored([park])?.closure(for: park) }
}
private extension AppIntent {
    /// visionOS 27: Siri answers with no window in view, so the answer keeps only what matters.
    nonisolated var voiceOnly: Bool {
        if #available(visionOS 27.0, *) { return systemContext.isVoiceOnly }
        return false
    }
}

/// "When is it dark at Arches tonight?" True darkness, start to end, in the park's own time, or
/// plainly that there is none at this latitude, in the iPhone's words (`DarkWindowAnswer`). A closure
/// is said first. Returns when true darkness begins (sunset, or the evening, where there is none).
struct DarkTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "When true darkness falls tonight"
    static let description = IntentDescription("Says when true darkness begins and ends tonight at a national park, in the park's own time, worked out on this device. Leave the park empty for the park chosen in Nyx.")
    @Parameter(title: "Park", description: "Leave empty for the park chosen in Nyx.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("When true darkness falls at \(\.$park) tonight") }
    init() {}
    func perform() async throws -> some IntentResult & ReturnsValue<Date> & ProvidesDialog {
        let selected = try VisionIntentPark.resolve(park)
        let sky = AstronomyEngine().conditions(for: selected, on: selected.currentNight(at: .now))
        let dialog = DarkWindowAnswer.dialog(park: selected, sky: sky, closure: VisionIntentPark.closure(selected), voiceOnly: voiceOnly)
        return .result(value: sky.darkStart ?? sky.sunset ?? sky.evening, dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// "What's up tonight at Arches?" The first three things in What's up (an eclipse or a shower first,
/// then the Milky Way core and the brightest planets), in the iPhone's words (`WhatsUpAnswer`).
struct WhatsUpTonightIntent: AppIntent {
    static let title: LocalizedStringResource = "What's up tonight"
    static let description = IntentDescription("Names what is worth seeing tonight at a national park: the Milky Way core, bright planets, a meteor shower or an eclipse, with times in the park's own time. Leave the park empty for the park chosen in Nyx.")
    @Parameter(title: "Park", description: "Leave empty for the park chosen in Nyx.") var park: ParkEntity?
    static var parameterSummary: some ParameterSummary { Summary("What's up tonight at \(\.$park)") }
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let selected = try VisionIntentPark.resolve(park)
        let now = Date.now
        let sky = AstronomyEngine().conditions(for: selected, on: selected.currentNight(at: now))
        // NOAA's aurora forecast as the window last kept it (no request from Siri), unless switched off.
        let outlook = NetworkService.aurora.isOn() ? await AuroraService().cached() : nil
        let whatsUp = WhatsUp(park: selected, sky: sky, isTonight: true, aurora: AuroraForecast.item(outlook, park: selected, sky: sky, now: now))
        let dialog = WhatsUpAnswer.dialog(whatsUp, park: selected, closure: VisionIntentPark.closure(selected), voiceOnly: voiceOnly)
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

/// What Siri or Shortcuts asked the planner window for: a park on tonight (nil keeps the chosen
/// park), and whether to stand under its sky. Each request is new, even for the same park. With
/// only the Moon volume open, the volume opens a planner window to answer it (`MoonVolume`).
nonisolated struct VisionIntentRequest: Equatable, Sendable {
    let parkID: String?
    let sky: Bool
    let id = UUID()
}

/// Opens a park in the planner on tonight: a Shortcuts action, or "Open Arches in Nyx".
struct OpenParkIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open park"
    static let description = IntentDescription("Opens a national park in Nyx for tonight: its darkness score, Moon and sky.")
    @Parameter(title: "Park") var target: ParkEntity
    @Dependency private var model: VisionModel
    init() {}
    init(target: ParkEntity) { self.target = target }
    // The model lives on the main actor, as the window that answers the request does.
    @MainActor func perform() async throws -> some IntentResult {
        model.intentRequest = VisionIntentRequest(parkID: target.id, sky: false)
        return .result()
    }
}

/// "Stand under tonight's sky in Nyx": opens the planner on tonight at the park and surrounds
/// you with its computed sky, as the window's own button does. Without a park, the one chosen.
struct StandUnderSkyIntent: AppIntent {
    static let title: LocalizedStringResource = "Stand under tonight's sky"
    static let description = IntentDescription("Surrounds you with tonight's computed sky at a national park: the stars, the Moon and planets in their places for the park's own night.")
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "Park", description: "Leave empty for the park chosen in Nyx.") var park: ParkEntity?
    @Dependency private var model: VisionModel
    static var parameterSummary: some ParameterSummary { Summary("Stand under tonight's sky at \(\.$park)") }
    init() {}
    init(park: ParkEntity?) { self.park = park }
    // The model lives on the main actor, as the window that answers the request does.
    @MainActor func perform() async throws -> some IntentResult {
        model.intentRequest = VisionIntentRequest(parkID: park?.id, sky: true)
        return .result()
    }
}

struct NyxVisionShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StandUnderSkyIntent(), phrases: ["Stand under tonight's sky at \(\.$park) in \(.applicationName)", "Show me tonight's sky at \(\.$park) in \(.applicationName)", "Stand under tonight's sky in \(.applicationName)"],
                    shortTitle: "Stand under the sky", systemImageName: "sparkles")
        AppShortcut(intent: DarknessIntent(), phrases: ["What is the darkness score at \(\.$park) in \(.applicationName)", "Check tonight's sky at \(\.$park) with \(.applicationName)"],
                    shortTitle: "Tonight's sky", systemImageName: "moon.stars")
        AppShortcut(intent: DarkTonightIntent(), phrases: ["When is it dark tonight in \(.applicationName)", "When is it dark at \(\.$park) in \(.applicationName)", "When does true darkness start at \(\.$park) in \(.applicationName)"],
                    shortTitle: "True darkness", systemImageName: "moon.haze")
        AppShortcut(intent: WhatsUpTonightIntent(), phrases: ["What's up tonight in \(.applicationName)", "What's up tonight at \(\.$park) in \(.applicationName)", "What can I see tonight at \(\.$park) with \(.applicationName)"],
                    shortTitle: "What's up", systemImageName: "sparkles")
        AppShortcut(intent: OpenParkIntent(), phrases: ["Open \(\.$target) in \(.applicationName)"], shortTitle: "Open park", systemImageName: "mountain.2")
    }
}
