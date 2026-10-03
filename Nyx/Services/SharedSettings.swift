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
nonisolated struct SavedSkySnapshot:Codable,Sendable {
    let parks:[Park]
    let forecasts:[String:Forecast]
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
