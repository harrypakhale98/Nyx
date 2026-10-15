import AppIntents
import Foundation

// Siri and Shortcuts on Apple Vision Pro: a park's darkness score tonight, a park opened in the
// planner, and tonight's sky to stand under. Everything is computed on the headset from the
// bundled parks and the cached cloud forecast, smoke and park alerts; no intent makes a request.

/// A national park, for Siri and Shortcuts. The iPhone's entity name and identifiers (the park
/// code), so a park means the same thing on every device; read from the bundled park list.
struct ParkEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "National park")
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
        case .parkNotFound: "That park could not be found in the bundled library."
        }
    }
}

/// "What's the darkness score at Joshua Tree tonight?" Answers in words and returns the score,
/// 0 to 100, so Shortcuts can use it. Reads this headset's cached forecast, smoke and park alerts
/// and never asks for new ones, so it answers the same with a switch off, and says so.
struct DarknessIntent: AppIntent {
    static let title: LocalizedStringResource = "Tonight's darkness score"
    static let description = IntentDescription("Find the on-device darkness estimate for a national park. Returns the score, 0 to 100.")
    @Parameter(title: "Park") var park: ParkEntity
    static var parameterSummary: some ParameterSummary { Summary("Darkness at \(\.$park) tonight") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        guard let selected = try ParkData.load().first(where: { $0.id == park.id }) else { throw VisionIntentError.parkNotFound }
        let forecast = await WeatherService().forecast(for: selected, network: false)
        let layers = await SummitLayerService().layers(for: [selected], network: false)[selected.id]
        let defaults = UserDefaults.standard
        let smokeOn = defaults.object(forKey: VisionModel.smokeKey) as? Bool ?? true
        let air = smokeOn ? await ForecastDetailService(extras: false).hydrate([selected])[selected.id]?.air : nil
        let inputs = ScoreInputs(smokeOn: smokeOn, smokeKnown: air == nil ? [] : [selected.id],
                                 alertsOn: defaults.object(forKey: VisionModel.alertsKey) as? Bool ?? true, alerts: ParkStore.stored([selected]))
        let answer = VisionDarknessAnswer(park: selected, forecast: forecast, layers: layers, air: air, inputs: inputs, forecastsOn: CloudForecastSwitch.isOn(), now: .now)
        return .result(value: answer.night.score.value, dialog: IntentDialog(stringLiteral: answer.dialog))
    }
}
/// Siri's answer apart from the intent: tonight scored as the planner scores it (`NightPlan`),
/// the clouds in the planner's words (`VisionModel.cloudCaption`): the forecast's cover, an early
/// look, the usual clouds beyond its reach, or the switch that is off; smoke that holds the score
/// down, or why smoke is not counted; and a closure first, as on the iPhone (`ClosureLine.first`),
/// or that closures are not checked. Every answer asks to confirm conditions and access.
nonisolated struct VisionDarknessAnswer: Sendable {
    let night: Night
    let dialog: String
    init(park: Park, forecast: Forecast?, layers: HourlySeries?, air: HourlySeries?, inputs: ScoreInputs, forecastsOn: Bool, now: Date) {
        let sky = AstronomyEngine().conditions(for: park, on: park.currentNight(at: now))
        night = NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: ForecastDetail.vision(layers: layers, air: air), now: now)
        dialog = Self.dialog(night, caption: VisionModel.cloudCaption(night, forecastsOn: forecastsOn), inputs: inputs)
    }
    static func dialog(_ night: Night, caption: String, inputs: ScoreInputs) -> String {
        let park = night.park, score = night.score
        let body: String
        if night.sky.darkHours == 0 { body = String(localized: "No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
        else if caption.isEmpty { body = String(localized: "\(park.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.") }
        else { body = String(localized: "\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
        let smoke = night.smokeSentence(tonight: true) ?? inputs.smokeNote(park, night: night) ?? ""
        let access = inputs.closure(park) == nil && inputs.unchecked(park) ? inputs.accessNote(park) ?? "" : ""
        return ClosureLine.first(Sentences.join([body, smoke, access]), closure: inputs.closure(park))
    }
}

/// What Siri or Shortcuts asked the planner window for: a park on tonight (nil keeps the chosen
/// park), and whether to stand under its sky. Each request is new, even for the same park.
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
        AppShortcut(intent: OpenParkIntent(), phrases: ["Open \(\.$target) in \(.applicationName)"], shortTitle: "Open park", systemImageName: "mountain.2")
    }
}
