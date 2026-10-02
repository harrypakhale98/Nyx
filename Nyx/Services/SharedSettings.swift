import Foundation

nonisolated enum SharedSettings {
    static let group="group.com.harrypakhale.nyx"
    static var defaults:UserDefaults { UserDefaults(suiteName:group) ?? .standard }
    static var snapshotURL:URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("saved-sky.json") }
    static func write(_ snapshot:SavedSkySnapshot) {
        guard let url=snapshotURL,let data=try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to:url,options:.atomic)
    }
    static func read()->SavedSkySnapshot? {
        guard let url=snapshotURL,let data=try? Data(contentsOf:url) else { return nil }
        return try? JSONDecoder().decode(SavedSkySnapshot.self,from:data)
    }
}
nonisolated struct SavedSkySnapshot:Codable,Sendable {
    let parks:[Park]
    let forecasts:[String:Forecast]
}
