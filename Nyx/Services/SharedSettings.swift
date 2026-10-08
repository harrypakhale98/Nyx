import Foundation

nonisolated enum SharedSettings {
    static let group="group.com.harrypakhale.nyx"
    static var defaults:UserDefaults { UserDefaults(suiteName:group) ?? .standard }
    static var snapshotURL:URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("saved-sky.json") }
    /// Writes the snapshot when it differs from the one on disk; true when it did. Keys are sorted,
    /// so the same contents always encode to the same bytes and an unchanged snapshot costs no reload.
    @discardableResult static func write(_ snapshot:SavedSkySnapshot)->Bool {
        let encoder=JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let url=snapshotURL,let data=try? encoder.encode(snapshot) else { return false }
        if let current=try? Data(contentsOf:url), current == data { return false }
        return (try? data.write(to:url,options:.atomic)) != nil
    }
    /// Pre-rendered Moon images for the widget, one per park and night: widgets can't run the
    /// Moon's Metal shader, so the app draws it and leaves the picture here.
    static func moonImageURL(park:String,night:Date)->URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("moon-\(park)-\(Int(night.timeIntervalSince1970)).png")
    }
    /// The app's picture of this park's Moon on this night, or on the nearest night it drew (within
    /// three nights, where the phase has moved less than a tenth of its cycle); nil past that.
    static func moonImage(park:String,night:Date)->URL? {
        guard let exact=moonImageURL(park:park,night:night) else { return nil }
        if FileManager.default.fileExists(atPath:exact.path) { return exact }
        let folder=exact.deletingLastPathComponent()
        let files=(try? FileManager.default.contentsOfDirectory(atPath:folder.path)) ?? []
        return MoonImages.nearest(in:files,park:park,night:night).map { folder.appendingPathComponent($0) }
    }
    static func read()->SavedSkySnapshot? {
        guard let url=snapshotURL,let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(SavedSkySnapshot.self,from:data)
    }
}
/// Finding the pre-rendered Moon nearest a night among the files the app left ("moon-jotr-1797210000.png").
nonisolated enum MoonImages {
    static let window:TimeInterval=3*86400+3600
    static func nearest(in files:[String],park:String,night:Date)->String? {
        let prefix="moon-\(park)-"
        return files.compactMap { file -> (String,TimeInterval)? in
            guard file.hasPrefix(prefix), file.hasSuffix(".png"), let stamp=Double(file.dropFirst(prefix.count).dropLast(4)) else { return nil }
            return (file,abs(stamp-night.timeIntervalSince1970))
        }.filter { $0.1<=window }.min { $0.1<$1.1 }?.0
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
    /// Smoke and cloud layers for the same parks, so widgets and reminders score as the app does.
    /// Optional: snapshots written before it existed still decode.
    var details:[String:ForecastDetail]?=nil
    var planner:NightPlanner { NightPlanner(forecasts:forecasts,details:details ?? [:]) }
    /// Each saved park's closure as Nyx words it beside the score, from the last park update.
    var closures:[String:String]=[:]
    /// Bulk reminder planning is safe to run off the main actor. It never reads
    /// preferences, does I/O, or assumes missing clouds are clear.
    func nights(from date:Date,count:Int,forecastAsOf:Date = .now)->[Night] {
        let planner=planner
        return parks.flatMap { park in (0..<max(0,count)).map { offset in
            planner.night(park,on:park.date(park.currentNight(at:date),addingDays:offset),now:forecastAsOf)
        } }
    }
}
nonisolated extension SavedSkySnapshot {
    init(from decoder:any Decoder) throws {
        let container=try decoder.container(keyedBy:CodingKeys.self)
        version=try container.decodeIfPresent(Int.self,forKey:.version) ?? 1
        parks=(try container.decodeIfPresent([Lenient<Park>].self,forKey:.parks) ?? []).compactMap(\.value)
        forecasts=(try container.decodeIfPresent([String:Lenient<Forecast>].self,forKey:.forecasts) ?? [:]).compactMapValues(\.value)
        details=(try? container.decodeIfPresent([String:Lenient<ForecastDetail>].self,forKey:.details))?.compactMapValues(\.value)
        closures=(try? container.decodeIfPresent([String:String].self,forKey:.closures)) ?? [:]
    }
}
/// A value that decodes to nil instead of failing the whole document.
nonisolated struct Lenient<T:Decodable>:Decodable {
    let value:T?
    init(from decoder:any Decoder) throws { value=try? T(from:decoder) }
}
