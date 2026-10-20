import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

@main struct NyxWatchWidgetsBundle: WidgetBundle {
    var body: some Widget { TonightComplication(); MoonComplication(); NextDarkComplication(); AdaptationComplication(); DuskWidget(); RedLightControl(); AdaptationControl() }
}

/// Complications and Smart Stack: tonight's score at a park, the Moon, and the next moment of the
/// night. Built on the watch from the snapshot the watch app wrote. The park is a setting:
/// "Same as Tonight" (the default: the place kept on the watch, else the darkest saved place, else
/// Tonight's pick or the starting park on iPhone, `WatchSky.choice`) or one place.
struct TonightComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NyxTonight", intent: TonightParkIntent.self, provider: TonightComplicationProvider()) { entry in WatchComplicationView(entry: entry) }
            .configurationDisplayName("Tonight's sky")
            .description("The darkness score, the Moon and the next moment of the night.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
struct TonightComplicationProvider: AppIntentTimelineProvider {
    /// What Tonight shows first (today's behaviour), then each park saved on iPhone.
    func recommendations() -> [AppIntentRecommendation<TonightParkIntent>] {
        let saved = WristParkQuery.savedParks().prefix(8)
        return [AppIntentRecommendation(intent: TonightParkIntent(), description: Text("Same as Tonight"))]
            + saved.map { AppIntentRecommendation(intent: TonightParkIntent(park: WristParkEntity($0)), description: Text(verbatim: $0.wristName)) }
    }
    /// The gallery's sample sky, so the system's redacted placeholder has the complication's real shape.
    func placeholder(in context: Context) -> WatchSkyEntry {
        var cache: [String: SkyConditions] = [:]
        return WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache)
    }
    func snapshot(for configuration: TonightParkIntent, in context: Context) async -> WatchSkyEntry {
        let choice = Self.snapshot(for: configuration, at: .now)
        if choice.unsaved { return WatchSkyEntry(date: .now, night: nil, next: nil, nightVision: WristLook.current.nightVision(park: nil, at: .now), unsaved: true) }
        var snapshot = choice.snapshot
        // The face gallery shows a real sky (Joshua Tree tonight, with its usual clouds), not an empty state.
        if context.isPreview, snapshot?.parks.isEmpty ?? true { snapshot = WatchTimeline.sample }
        var cache: [String: SkyConditions] = [:]
        return WatchTimeline.entry(at: .now, snapshot: snapshot, look: .current, dataDiffers: WatchSky.dataDiffers, cache: &cache)
    }
    func timeline(for configuration: TonightParkIntent, in context: Context) async -> Timeline<WatchSkyEntry> {
        await Self.noteFacePlaces()
        let now = Date.now, choice = Self.snapshot(for: configuration, at: now)
        if choice.unsaved {
            // Until the face is set to another place (or the place is saved again, which reloads every timeline).
            return Timeline(entries: [WatchSkyEntry(date: now, night: nil, next: nil, nightVision: WristLook.current.nightVision(park: nil, at: now), unsaved: true)], policy: .never)
        }
        return WatchTimeline.timeline(WatchTimeline.entries(from: now, snapshot: choice.snapshot, look: .current, dataDiffers: WatchSky.dataDiffers), now: now, until: choice.until)
    }
    /// Notes the places the Tonight complications on the faces are set to (`WatchSky.facePlaces`), so
    /// the watch names them the next time it asks the iPhone for clouds. Left as it was when the
    /// system cannot say.
    static func noteFacePlaces() async {
        guard let faces = try? await WidgetCenter.shared.currentConfigurations() else { return }
        var seen = Set<String>()
        WatchSky.facePlaces = faces.compactMap { $0.widgetConfigurationIntent(of: TonightParkIntent.self)?.park?.id }
            .filter { $0 != WristParkEntity.darkestID && seen.insert($0).inserted }
    }
    /// The parks this complication weighs: the watch app's choice, or the one place set (a park, or a
    /// saved spot or world place the iPhone sent whole), with the clouds, the usual clouds and the
    /// closure the iPhone last sent for it. `unsaved`: the place set is no longer among those the
    /// iPhone sends, so the face says so rather than quietly showing another place. `until`: when
    /// what Tonight follows changes on its own (`WatchSky.faces`).
    static func snapshot(for configuration: TonightParkIntent, at now: Date) -> (snapshot: SavedSkySnapshot?, unsaved: Bool, until: Date?) {
        guard let id = configuration.park?.id, id != WristParkEntity.darkestID else { let faces = WatchSky.faces(at: now); return (faces.snapshot, false, faces.until) }
        let context = WatchSky.readContext()
        // Before anything has come from the iPhone, nothing is known about what is saved: the default holds.
        guard let park = WatchSky.place(id, in: (try? ParkData.load()) ?? [], context: context) else {
            if context == nil { let faces = WatchSky.faces(at: now); return (faces.snapshot, false, faces.until) }
            return (nil, true, nil)
        }
        return (WatchSky.snapshot(parks: [park], context: context), false, nil)
    }
}

/// The score complication's setting: which park it shows.
struct TonightParkIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Tonight's sky"
    static let description = IntentDescription("The darkness score at a place you choose, or at the place Tonight shows.")
    @Parameter(title: "Place") var park: WristParkEntity?
    init() {}
    init(park: WristParkEntity) { self.park = park }
}
/// A park as the watch's settings list it. "Same as Tonight" is an entry of its own, the default
/// (its id stays "darkest", so faces set before keep their setting).
struct WristParkEntity: AppEntity {
    static let darkestID = "darkest"
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static let defaultQuery = WristParkQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name)) }
    init(_ park: Park) { id = park.id; name = park.wristName }
    init(id: String, name: String) { self.id = id; self.name = name }
    static var darkest: WristParkEntity { WristParkEntity(id: darkestID, name: String(localized: "Same as Tonight")) }
}
struct WristParkQuery: EntityQuery {
    static func allParks() -> [Park] { ((try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    /// The saved parks, and the saved spots and world catalogue places the iPhone sent with them.
    static func savedParks() -> [Park] {
        let parks = allParks(), context = WatchSky.readContext()
        return (context?.savedParkIDs ?? []).compactMap { id in WatchSky.place(id, in: parks, context: context) }
    }
    /// A spot or world place the iPhone no longer sends stays the face's setting, named "No longer
    /// saved", so the face can say so instead of falling back to what Tonight shows unnoticed.
    func entities(for identifiers: [String]) async throws -> [WristParkEntity] {
        let parks = Self.allParks(), context = WatchSky.readContext()
        return identifiers.compactMap { id in
            if id == WristParkEntity.darkestID { return .darkest }
            if let place = WatchSky.place(id, in: parks, context: context) { return WristParkEntity(place) }
            return PlaceIDText.validated(id) == id && id.contains(":") ? WristParkEntity(id: id, name: String(localized: "No longer saved")) : nil
        }
    }
    /// What Tonight shows, then the saved parks, then every park.
    func suggestedEntities() async throws -> [WristParkEntity] {
        let saved = Self.savedParks()
        return [.darkest] + saved.map(WristParkEntity.init) + Self.allParks().filter { park in !saved.contains { $0.id == park.id } }.map(WristParkEntity.init)
    }
    func defaultResult() async -> WristParkEntity? { .darkest }
}

/// The Moon right now at the park Tonight follows: phase, light, and its next rise or set.
struct MoonComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NyxMoon", provider: MoonProvider()) { entry in MoonComplicationView(entry: entry) }
            .configurationDisplayName("Moon")
            .description("The Moon's phase and light, and when it next rises or sets at your park.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
struct MoonProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoonEntry {
        MoonEntry(date: .now, park: WatchTimeline.sample?.parks.first, moon: MoonNow(at: .now, park: WatchTimeline.sample?.parks.first), nightVision: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (MoonEntry) -> Void) {
        var snapshot = WatchSky.faces(at: .now).snapshot
        if context.isPreview, snapshot?.parks.isEmpty ?? true { snapshot = WatchTimeline.sample }
        completion(WristTimeline.moonEntries(from: .now, snapshot: snapshot, look: .current).first ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MoonEntry>) -> Void) {
        let now = Date.now, faces = WatchSky.faces(at: now)
        completion(WatchTimeline.timeline(WristTimeline.moonEntries(from: now, snapshot: faces.snapshot, look: .current), now: now, until: faces.until))
    }
}

/// When the sky is next truly dark at the park Tonight follows: true darkness, or the Moon setting.
struct NextDarkComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NyxNextDark", provider: NextDarkProvider()) { entry in NextDarkComplicationView(entry: entry) }
            .configurationDisplayName("Next dark")
            .description("A countdown to truly dark sky: the Sun far below the horizon and the Moon down.")
            .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}
struct NextDarkProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextDarkEntry {
        let park = WatchTimeline.sample?.parks.first
        return NextDarkEntry(date: .now, park: park, moment: park.map { DarkMoment.next(at: $0, now: .now) } ?? .none, nightVision: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (NextDarkEntry) -> Void) {
        var snapshot = WatchSky.faces(at: .now).snapshot
        if context.isPreview, snapshot?.parks.isEmpty ?? true { snapshot = WatchTimeline.sample }
        completion(WristTimeline.nextDarkEntries(from: .now, snapshot: snapshot, look: .current).first ?? placeholder(in: context))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextDarkEntry>) -> Void) {
        let now = Date.now, faces = WatchSky.faces(at: now)
        completion(WatchTimeline.timeline(WristTimeline.nextDarkEntries(from: now, snapshot: faces.snapshot, look: .current), now: now, until: faces.until))
    }
}

/// A park and night worth stepping outside for. The watch's Smart Stack offers it from 45 minutes
/// before sunset until true darkness ends on Good nights or better, and whenever the wearer is
/// near a saved park's main viewing spot.
struct DuskNight: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Dark night"
    static let description = IntentDescription("A dark night at a park Nyx follows.")
    @Parameter(title: "Park") var park: String?
    /// Nil: whichever night is current when the card is shown (the at-the-park card).
    @Parameter(title: "Evening") var evening: Date?
    init() {}
    init(park: String, evening: Date?) { self.park = park; self.evening = evening }
}
struct DuskEntry: RelevanceEntry {
    let entry: WatchSkyEntry
}
struct DuskProvider: RelevanceEntriesProvider {
    /// Around this far from a park's main viewing spot counts as being at the park.
    static let parkRadius: CLLocationDistance = 25_000
    func relevance() async -> WidgetRelevance<DuskNight> {
        let now = Date.now
        guard let snapshot = WatchSky.faces(at: now).snapshot else { return WidgetRelevance([]) }
        let climate = snapshot.climate
        var attributes: [WidgetRelevanceAttribute<DuskNight>] = []
        for park in snapshot.parks {
            for offset in 0..<7 {
                let evening = park.date(park.currentNight(at: now), addingDays: offset)
                let night = WatchSky.night(park, evening: evening, forecast: snapshot.forecasts[park.id], detail: snapshot.details?[park.id], now: now, climate: climate)
                guard NightPlanner.worthSurfacing(night), let window = WatchTimeline.duskWindow(sky: night.sky), window.end > now else { continue }
                attributes.append(WidgetRelevanceAttribute(configuration: DuskNight(park: park.id, evening: evening), context: .date(interval: window, kind: .informational)))
            }
            // At the park, the card is the point of the trip, whatever the score. The system matches
            // the region itself; Nyx asks for no location.
            let spot = park.viewingSpots.first.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                ?? CLLocationCoordinate2D(latitude: park.latitude, longitude: park.longitude)
            let region = CLCircularRegion(center: spot, radius: Self.parkRadius, identifier: "nyx.park.\(park.id)")
            attributes.append(WidgetRelevanceAttribute(configuration: DuskNight(park: park.id, evening: nil), context: .location(region)))
        }
        return WidgetRelevance(attributes)
    }
    func entry(configuration: DuskNight, context: Context) async throws -> DuskEntry {
        let now = Date.now
        let snapshot = SharedSettings.read(), context = WatchSky.readContext()
        let parks = snapshot?.parks ?? []
        let look = WristLook.current
        guard let id = configuration.park, let park = parks.first(where: { $0.id == id }) ?? WatchSky.place(id, in: (try? ParkData.load()) ?? [], context: context) else {
            return DuskEntry(entry: WatchSkyEntry(date: now, night: nil, next: nil, nightVision: look.nightVision(park: nil, at: now)))
        }
        let evening = configuration.evening ?? park.currentNight(at: now)
        // The usual clouds the snapshot carries, else those the iPhone sent for a place it no longer weighs.
        let climate = (snapshot?.climate ?? .shared).carrying((context?.usualClouds ?? [:]).filter { $0.key == id && snapshot?.usualClouds?[id] == nil })
        // Clouds and detail the same way: the snapshot's, else those the iPhone sent for a place it no longer weighs.
        let forecast = snapshot?.forecasts[park.id] ?? context?.cloudForecasts[id]
        let detail = snapshot?.details?[park.id] ?? context?.forecastDetails[id]
        let night = WatchSky.night(park, evening: evening, forecast: forecast, detail: detail, now: now, climate: climate)
        // The closure from the snapshot, or from the iPhone's context for a park the snapshot no longer weighs.
        let closure = parks.contains { $0.id == id } ? snapshot?.closures[id] : context?.closures[id]
        return DuskEntry(entry: WatchSkyEntry(date: now, night: night, next: NightMilestone.next(after: now, in: night.sky), nightVision: look.nightVision(park: park, at: now),
                                              closure: closure, cloudsOld: WatchTimeline.cloudsOld(park, forecast: forecast, detail: detail, at: now),
                                              dataDiffers: context?.dataDiffers ?? false))
    }
    func placeholder(context: Context) -> DuskEntry {
        var cache: [String: SkyConditions] = [:]
        return DuskEntry(entry: WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache))
    }
}
struct DuskWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: "NyxDusk", provider: DuskProvider()) { entry in
            // The card is built once and may sit in the stack for hours: clock times, never a relative countdown.
            WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry.entry, clockTimes: true)
        }
        .configurationDisplayName("Dark night ahead")
        .description("Appears in the Smart Stack at dusk on Good nights or better, and at your saved parks.")
    }
}

/// Control Center (and the Action button): red light on the wrist, or back to Automatic.
struct RedLightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WatchSky.redLightKind, provider: RedLightProvider()) { isOn in
            // The state reads in word and symbol: "On" with a filled flashlight, "Automatic" with an
            // outline: the iPhone's night-vision glyph (the eye stays dark adaptation's).
            ControlWidgetToggle(isOn: isOn, action: RedLightIntent()) { Text("Red light") } valueLabel: { isOn in
                if isOn { Label("On", systemImage: "flashlight.on.circle.fill") } else { Label("Automatic", systemImage: "flashlight.off.circle") }
            }
        }
        .displayName("Red light")
        .description("Keep Nyx red on the wrist, day or night, to protect dark-adapted eyes.")
    }
}
struct RedLightProvider: ControlValueProvider {
    var previewValue: Bool { true }
    func currentValue() async throws -> Bool { WatchSky.palette == .red }
}
/// On: the Red light palette. Off: back to Automatic (red from dusk to dawn at the park on Tonight).
struct RedLightIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set red light"
    static let isDiscoverable = false
    @Parameter(title: "Red light") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult {
        WatchSky.setPalette(value ? .red : .automatic)
        return .result()
    }
}

#Preview("Tonight • rectangular", as: .accessoryRectangular) { TonightComplication() } timeline: {
    var cache: [String: SkyConditions] = [:]
    WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache)
}
#Preview("Tonight • closure, rectangular", as: .accessoryRectangular) { TonightComplication() } timeline: {
    let entry = closedSample
    entry
    WatchSkyEntry(date: entry.date, night: entry.night, next: entry.next, nightVision: false, closure: "Keys View Road and the Geology Tour Road closed for repairs through November")
}
#Preview("Tonight • closure, circular", as: .accessoryCircular) { TonightComplication() } timeline: { closedSample }
#Preview("Tonight • closure, corner", as: .accessoryCorner) { TonightComplication() } timeline: { closedSample }
#Preview("Tonight • closure, inline", as: .accessoryInline) { TonightComplication() } timeline: { closedSample }
/// Joshua Tree tonight with an illustrative closure, for the previews.
private var closedSample: WatchSkyEntry {
    var cache: [String: SkyConditions] = [:]
    let entry = WatchTimeline.entry(at: .now, snapshot: WatchTimeline.sample, look: .red, cache: &cache)
    return WatchSkyEntry(date: entry.date, night: entry.night, next: entry.next, nightVision: entry.nightVision, closure: "Keys View Road closed at night")
}
#Preview("Moon • circular", as: .accessoryCircular) { MoonComplication() } timeline: {
    MoonEntry(date: .now, park: WatchTimeline.sample?.parks.first, moon: MoonNow(at: .now, park: WatchTimeline.sample?.parks.first), nightVision: false)
}
#Preview("Moon • rectangular", as: .accessoryRectangular) { MoonComplication() } timeline: {
    MoonEntry(date: .now, park: WatchTimeline.sample?.parks.first, moon: MoonNow(at: .now, park: WatchTimeline.sample?.parks.first), nightVision: true)
    MoonEntry(date: .now, park: nil, moon: MoonNow(at: .now, park: nil), nightVision: false)
}
#Preview("Moon • corner", as: .accessoryCorner) { MoonComplication() } timeline: {
    MoonEntry(date: .now, park: WatchTimeline.sample?.parks.first, moon: MoonNow(at: .now, park: WatchTimeline.sample?.parks.first), nightVision: false)
}
#Preview("Moon • inline", as: .accessoryInline) { MoonComplication() } timeline: {
    MoonEntry(date: .now, park: WatchTimeline.sample?.parks.first, moon: MoonNow(at: .now, park: WatchTimeline.sample?.parks.first), nightVision: false)
}
#Preview("Next dark • every state", as: .accessoryRectangular) { NextDarkComplication() } timeline: {
    let park = WatchTimeline.sample?.parks.first
    NextDarkEntry(date: .now, park: park, moment: .begins(.now.addingTimeInterval(4200), moonset: false), nightVision: false)
    NextDarkEntry(date: .now, park: park, moment: .begins(.now.addingTimeInterval(7200), moonset: true), nightVision: true)
    NextDarkEntry(date: .now, park: park, moment: .darkNow(until: .now.addingTimeInterval(9000), moonrise: true), nightVision: true)
    NextDarkEntry(date: .now, park: park, moment: .moonlit(from: .now.addingTimeInterval(3600), to: .now.addingTimeInterval(30000)), nightVision: true)
    NextDarkEntry(date: .now, park: park, moment: .none, nightVision: false)
    // No park chosen yet: "Choose a place" under the empty face's mark, never a claim about the sky.
    NextDarkEntry(date: .now, park: nil, moment: .none, nightVision: false)
}
#Preview("Moon • inline, southern sky", as: .accessoryInline) { MoonComplication() } timeline: {
    // American Samoa: the phase symbol turned for the southern sky, by name, inside text.
    let samoa = try? ParkData.load().first(where: { $0.id == "npsa" })
    MoonEntry(date: .now, park: samoa, moon: MoonNow(at: .now, park: samoa), nightVision: false)
}
#Preview("Next dark • circular", as: .accessoryCircular) { NextDarkComplication() } timeline: {
    NextDarkEntry(date: .now, park: WatchTimeline.sample?.parks.first, moment: .begins(.now.addingTimeInterval(7800), moonset: true), nightVision: true)
}
#Preview("Next dark • corner", as: .accessoryCorner) { NextDarkComplication() } timeline: {
    NextDarkEntry(date: .now, park: WatchTimeline.sample?.parks.first, moment: .begins(.now.addingTimeInterval(7800), moonset: false), nightVision: false)
}
#Preview("Next dark • inline", as: .accessoryInline) { NextDarkComplication() } timeline: {
    NextDarkEntry(date: .now, park: WatchTimeline.sample?.parks.first, moment: .darkNow(until: .now.addingTimeInterval(7800), moonrise: false), nightVision: false)
}
