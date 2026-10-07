import Foundation

nonisolated enum SharedSettings {
    static let group="group.com.harrypakhale.nyx"
    static var defaults:UserDefaults { UserDefaults(suiteName:group) ?? .standard }
    static var snapshotURL:URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("saved-sky.json") }
    static func write(_ snapshot:SavedSkySnapshot) {
        guard let url=snapshotURL,let data=try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to:url,options:.atomic)
    }
    /// Pre-rendered Moon images for the widget, one per park and night: widgets can't run the
    /// Moon's Metal shader, so the app draws it and leaves the picture here.
    static func moonImageURL(park:String,night:Date)->URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("moon-\(park)-\(Int(night.timeIntervalSince1970)).png")
    }
    static func read()->SavedSkySnapshot? {
        guard let url=snapshotURL,let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(SavedSkySnapshot.self,from:data)
    }
}
/// What the app hands its widgets (and the watch app writes for its complications). Versioned and
/// decoded leniently, so a field added later, or one park that no longer decodes, never blanks a
/// widget until the app is next opened.
nonisolated struct SavedSkySnapshot:Codable,Sendable {
    /// 2 adds the version and the per-park closures (1.1).
    static let currentVersion=2
    var version=SavedSkySnapshot.currentVersion
    let parks:[Park]
    let forecasts:[String:Forecast]
    /// Each saved park's closure as Nyx words it beside the score, from the last park update.
    var closures:[String:String]=[:]
    /// Bulk reminder planning is safe to run off the main actor. It never reads
    /// preferences, does I/O, or assumes missing clouds are clear.
    func nights(from date:Date,count:Int,forecastAsOf:Date = .now)->[Night] {
        let astronomy=AstronomyEngine(),scoring=ScoreEngine()
        return parks.flatMap { park in (0..<max(0,count)).map { offset in
            let sky=astronomy.conditions(for:park,on:park.date(park.currentNight(at:date),addingDays:offset))
            let forecast=forecasts[park.id]
            let cloud=forecast?.mean(from:sky.cloudWindow.start,to:sky.cloudWindow.end,now:forecastAsOf)
            return Night(park:park,sky:sky,score:scoring.score(sky:sky,bortle:park.bortleEstimate,cloudCover:cloud),cloudCover:cloud,forecastUpdated:cloud==nil ? nil : forecast?.updated)
        } }
    }
}
nonisolated extension SavedSkySnapshot {
    init(from decoder:any Decoder) throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        version=try container.decodeIfPresent(Int.self,forKey:.version) ?? 1
        parks=(try container.decodeIfPresent([Lenient<Park>].self,forKey:.parks) ?? []).compactMap(\.value)
        forecasts=(try container.decodeIfPresent([String:Lenient<Forecast>].self,forKey:.forecasts) ?? [:]).compactMapValues(\.value)
        closures=(try? container.decodeIfPresent([String:String].self,forKey:.closures)) ?? [:]
    }
}
/// A value that decodes to nil instead of failing the whole document.
nonisolated struct Lenient<T:Decodable>:Decodable {
    let value:T?
    init(from decoder:any Decoder) throws { value=try? T(from:decoder) }
}
