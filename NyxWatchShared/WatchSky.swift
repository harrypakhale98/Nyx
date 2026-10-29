import Foundation
import SwiftUI
import WidgetKit

/// Everything the watch app and its complications agree on: which park the wrist follows,
/// which palette it wears, and how a night is scored. Shared through the watch's own App Group;
/// nothing here touches the network.
nonisolated enum WatchSky {
    static let contextFile = "watch-context.json"
    static let paletteKey = "watchPalette"
    static let parkKey = "watchPark"
    static var defaults: UserDefaults { SharedSettings.defaults }
    private static var contextURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.group)?.appendingPathComponent(contextFile)
    }
    /// The last context the iPhone sent; it survives relaunches so the watch works away from the phone.
    static func readContext() -> WatchContext? {
        guard let url = contextURL, let data = try? Data(contentsOf: url) else { return nil }
        return WatchContext(data: data)
    }
    static func save(_ context: WatchContext) {
        // Kept beside the context, so the complications read the red without decoding it.
        defaults.set(context.brighterRed, forKey: NightTint.key)
        guard let url = contextURL, let data = context.data else { return }
        try? data.write(to: url, options: .atomic)
    }
    /// Whether the iPhone's last context came from a Nyx whose data differs from this one's
    /// (`WatchContext.dataDiffers`), so a face can say its score may differ from the iPhone's.
    static var dataDiffers: Bool { readContext()?.dataDiffers ?? false }
    /// The iPhone's "Brighter red", from the last context it sent (`WatchContext.brighterRed`).
    static var brighterRed: Bool { defaults.bool(forKey: NightTint.key) }
    static var palette: PaletteChoice {
        get { PaletteChoice(rawValue: defaults.string(forKey: paletteKey) ?? "") ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: paletteKey) }
    }
    /// Sets the palette from outside the app (Siri, the Control Center control), then asks the
    /// complications and the control to look again; the app reads it on return (`reloadSettings`).
    static func setPalette(_ choice: PaletteChoice) {
        palette = choice
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadControls(ofKind: redLightKind)
    }
    static let adaptationKey = "watchAdaptationStart"
    /// The Control Center control's kind, reloaded whenever the palette changes.
    static let redLightKind = "NyxRedLight"
    /// When the dark-adaptation clock was started, if it is running.
    static var adaptationStart: Date? {
        get { defaults.object(forKey: adaptationKey) as? Date }
        set { defaults.set(newValue, forKey: adaptationKey) }
    }
    /// A park kept on Tonight from the watch; nil follows the iPhone.
    static var pinnedPark: String? {
        get { defaults.string(forKey: parkKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: parkKey) }
    }
    /// Why Tonight on the wrist weighs the places it does (`choice`).
    enum Rule: Sendable, Equatable {
        /// A place kept on Tonight from the watch.
        case pinned
        /// The places saved on iPhone.
        case saved
        /// Nothing saved: the place Tonight on the iPhone answered with (`WatchContext.tonightParkID`).
        case iPhoneTonight
        /// Nothing saved and no answer from Tonight on the iPhone: its starting park.
        case start
    }
    /// The parks Tonight and the complications weigh at `now`, in order: a park kept on the watch;
    /// else the parks saved on iPhone; else the place Tonight on the iPhone answered with, while the
    /// night it was picked for is still tonight there (`WatchContext.stillPicks`); else the iPhone's
    /// starting park. Empty until one of those exists. Saved spots and world catalogue places arrive
    /// whole in the context (`WatchContext.places`); a bundled park keeps its id.
    static func choice(in parks: [Park], context: WatchContext?, pinned: String?, now: Date) -> (parks: [Park], rule: Rule?) {
        let byID = Dictionary((parks + (context?.places ?? [])).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if let pinned, let park = byID[pinned] { return ([park], .pinned) }
        let saved = (context?.savedParkIDs ?? []).compactMap { byID[$0] }
        if !saved.isEmpty { return (saved, .saved) }
        if let park = context?.tonightParkID.flatMap({ byID[$0] }), context?.stillPicks(park, at: now) == true { return ([park], .iPhoneTonight) }
        if let park = context.flatMap({ byID[$0.homeParkID] }) { return ([park], .start) }
        return ([], nil)
    }
    static func candidates(in parks: [Park], context: WatchContext?, pinned: String?, now: Date) -> [Park] { choice(in: parks, context: context, pinned: pinned, now: now).parks }
    /// What the faces that follow Tonight weigh from `now`: the snapshot the watch app last wrote,
    /// unless what Tonight follows has changed since without the app running (Tonight's pick on the
    /// iPhone whose night has passed): then rebuilt from the context. `until`: when the pick the
    /// faces follow stops answering (its night turns over), so a timeline ends there and is made again.
    static func faces(at now: Date) -> (snapshot: SavedSkySnapshot?, until: Date?) {
        let written = SharedSettings.read()
        guard let context = readContext(), context.tonightParkID != nil else { return (written, nil) }
        let current = choice(in: (try? ParkData.load()) ?? [], context: context, pinned: pinnedPark, now: now)
        let until = current.rule == .iPhoneTonight ? current.parks.first?.nightTurnovers(from: now, to: now.addingTimeInterval(86400)).first : nil
        guard (written?.parks.map(\.id) ?? []) != current.parks.map(\.id) else { return (written, until) }
        return (snapshot(parks: current.parks, context: context), until)
    }
    /// One short line naming the rule where the screen does not already say it: Tonight's answer on
    /// the iPhone, or its starting park. Nil for a kept or saved place.
    static func caption(_ rule: Rule?) -> String? {
        switch rule {
        // Tonight's answer may be measured from a chosen city or park, not from where the iPhone is.
        case .iPhoneTonight: String(localized: "Tonight's pick on iPhone")
        case .start: String(localized: "Starting park on iPhone")
        case .pinned, .saved, nil: nil
        }
    }
    static let facesKey = "watchFacePlaces"
    /// The places complications on this watch's faces are set to, as they last found them
    /// (`TonightComplicationProvider` notes them).
    static var facePlaces: [String] {
        get { defaults.stringArray(forKey: facesKey) ?? [] }
        set { defaults.set(newValue, forKey: facesKey) }
    }
    static let toldKey = "watchToldPlaces", toldAtKey = "watchToldAt"
    /// The places last told to the iPhone and when it answered (`WatchStore.tellIPhoneIfNeeded`).
    static var told: (places: [String], at: Date)? {
        get {
            guard let places = defaults.stringArray(forKey: toldKey), let at = defaults.object(forKey: toldAtKey) as? Date else { return nil }
            return (places, at)
        }
        set {
            defaults.set(newValue?.places, forKey: toldKey)
            defaults.set(newValue?.at, forKey: toldAtKey)
        }
    }
    /// The places this watch asks the iPhone to carry clouds for, once each: the one kept on Tonight,
    /// then those its complications are set to, no more than the iPhone follows (`WatchContext.wanted`).
    static func wantedPlaces(pinned: String?) -> [String] { WatchContext.wanted(pinned: pinned, faces: facePlaces) }
    /// Where a place's clouds came from (`CloudSource.of`), counting the places this watch asks the
    /// iPhone for, so a place kept or on a face that it does not follow yet offers to ask.
    static func cloudSource(_ park: Park, context: WatchContext?, now: Date) -> CloudSource {
        CloudSource.of(context: context, park: park, now: now, wanted: wantedPlaces(pinned: pinnedPark))
    }
    /// A place by id on the wrist: a bundled park, else a saved spot or catalogue place the iPhone
    /// sent whole (`WatchContext.places`). Nil for an id neither knows.
    static func place(_ id: String, in parks: [Park], context: WatchContext?) -> Park? {
        parks.first { $0.id == id } ?? context?.places.first { $0.id == id }
    }
    /// One night at one park, scored on the watch from the bundled park, the astronomy engine and,
    /// when the iPhone sent them, the cached cloud forecast and the smoke and summit layers, by the
    /// iPhone's own rule (`NightPlanner.night`): without a forecast, the park's usual clouds for the month.
    /// `climate` carries the usual clouds the iPhone sent for spots and world places (`WatchContext.climate`,
    /// `SavedSkySnapshot.climate`); the bundled climate alone knows only the 63 parks.
    static func night(_ park: Park, evening: Date, forecast: Forecast?, detail: ForecastDetail?, now: Date, sky cached: SkyConditions? = nil,
                      climate: CloudClimate = .shared) -> Night {
        NightPlanner.night(park: park, sky: cached ?? AstronomyEngine().conditions(for: park, on: evening), forecast: forecast, detail: detail, now: now, climate: climate)
    }
    /// Write what the complications read: the candidate parks, their forecasts, smoke and layers,
    /// and the usual clouds the iPhone sent for spots and world places.
    /// True when the snapshot on disk changed.
    @discardableResult static func publish(parks: [Park], context: WatchContext?) -> Bool {
        SharedSettings.write(snapshot(parks: parks, context: context))
    }
    /// The candidate parks with what the iPhone sent for them, as the complications read it.
    static func snapshot(parks: [Park], context: WatchContext?) -> SavedSkySnapshot {
        let ids = Set(parks.map(\.id))
        let usual = (context?.usualClouds ?? [:]).filter { ids.contains($0.key) }
        return SavedSkySnapshot(parks: parks, forecasts: (context?.cloudForecasts ?? [:]).filter { ids.contains($0.key) },
                                details: (context?.forecastDetails ?? [:]).filter { ids.contains($0.key) },
                                closures: (context?.closures ?? [:]).filter { ids.contains($0.key) }, usualClouds: usual.isEmpty ? nil : usual)
    }
    /// Red or not at that moment: At dusk reads the Sun at the iPhone's starting point, else at the
    /// park Tonight follows (worked out only then).
    static func nightVision(_ choice: PaletteChoice, context: WatchContext?, park: @autoclosure () -> Park?, at now: Date) -> Bool {
        choice.nightVision(phone: context?.nightVision, park: park(), dusk: context?.duskPlace, at: now)
    }
    /// What a score's clouds rest on when there is no full forecast, in one short honest line, in
    /// the iPhone's words (`Night.basisCaption`).
    static func forecastNote(_ night: Night, context: WatchContext?, short: Bool = false) -> String? {
        guard let label = night.basisLabel else { return nil }
        if short { return label }
        return Sentences.join([night.basisCaption() ?? "", unsyncedNote(night, context: context) ?? ""])
    }
    /// Before the iPhone has sent anything, a night a forecast should reach says where its clouds
    /// come from; one beyond every forecast's reach needs no such line.
    static func unsyncedNote(_ night: Night, context: WatchContext?) -> String? {
        context == nil && night.basis == .usual && !night.beyondForecast ? String(localized: "Open Nyx on iPhone for clouds.") : nil
    }
}

/// A complication's or the Smart Stack card's tap: the park and night it shows, opened in the
/// watch app. The iPhone's park link with the park-local evening added
/// (`nyx://park/<id>?date=YYYY-MM-DD`, the date as the iPhone's What's up link writes it). A
/// widget's URL goes straight to its own app, so no URL scheme is registered on the watch.
nonisolated struct WatchLink: Hashable, Sendable {
    let parkID: String
    /// The evening's park-local calendar day; nil opens tonight.
    let day: DateComponents?
    init(park: Park, evening: Date?) {
        parkID = park.id
        day = evening.map { park.calendar.dateComponents([.year, .month, .day], from: $0) }
    }
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "nyx", url.host()?.lowercased() == "park",
              let raw = url.pathComponents.first(where: { $0 != "/" }), let id = PlaceIDText.validated(raw) else { return nil }
        parkID = id
        let date = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "date" }?.value
        day = date.flatMap(LinkDay.components)
    }
    var url: URL? {
        var components = URLComponents()
        components.scheme = "nyx"
        components.host = "park"
        components.path = "/" + parkID
        if let day, let year = day.year, let month = day.month, let date = day.day {
            components.queryItems = [URLQueryItem(name: "date", value: String(format: "%04d-%02d-%02d", year, month, date))]
        }
        return components.url
    }
    /// Nights after tonight at `park` (0…`limit`); a night already past, or none given, is tonight.
    func offset(in park: Park, now: Date, limit: Int) -> Int {
        guard let day, let evening = park.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return 0 }
        let days = park.calendar.dateComponents([.day], from: park.currentNight(at: now), to: evening).day ?? 0
        return min(limit, max(0, days))
    }
}

extension Park {
    /// Whether the park's clock reads differently from this watch's at `date`: its times are park-local.
    nonisolated func keepsOtherTime(at date: Date) -> Bool { timeZone.secondsFromGMT(for: date) != TimeZone.current.secondsFromGMT(for: date) }
    /// A park-local time, carrying the park's short zone ("4:52 AM MST") where its clock is not
    /// this watch's: one glance cannot hold "Times in Mountain Standard Time" without costing the dial.
    nonisolated func wristTime(_ date: Date) -> String {
        guard keepsOtherTime(at: date) else { return time(date) }
        var format = Date.FormatStyle.dateTime.hour().minute().timeZone(.specificName(.short))
        format.timeZone = timeZone
        return date.formatted(format)
    }
    /// "Times in Mountain Time." where the park's clock is not this watch's, for what VoiceOver hears.
    nonisolated func spokenZone(at date: Date) -> String? {
        keepsOtherTime(at: date) ? String(localized: "\(String(localized: "Times in \(timeZoneName)")).") : nil
    }
}

extension NyxPalette {
    /// The quietest text level on the watch (past milestones), by the one rule every surface reads
    /// (`NyxPalette.faintOpacity`): in red, or under Increase Contrast, it is muted, so it holds 4.5:1
    /// for protan eyes too.
    var faint: Color { ink.opacity(Self.faintOpacity(nightVision: nightVision, highContrast: highContrast)) }
}
