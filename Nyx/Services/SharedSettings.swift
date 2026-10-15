import Foundation
import Synchronization

nonisolated enum SharedSettings {
    static let group="group.com.harrypakhale.nyx"
    static var defaults:UserDefaults { UserDefaults(suiteName:group) ?? .standard }
    static var snapshotURL:URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("saved-sky.json") }
    /// The App Group's snapshot file, decoded once per process (`SnapshotFile`). Tests bind their own.
    @TaskLocal static var snapshotFile:SnapshotFile = .shared
    /// Writes the snapshot when it differs from the one on disk; true when it did. Keys are sorted,
    /// so the same contents always encode to the same bytes and an unchanged snapshot costs no reload.
    /// About 0.8 MB: the iPhone writes it off the main actor (`SnapshotWriter`).
    @discardableResult static func write(_ snapshot:SavedSkySnapshot)->Bool { snapshotFile.write(snapshot) }
    /// Pre-rendered Moon images for the widget, one per park and night: widgets can't run the
    /// Moon's Metal shader, so the app draws it and leaves the picture here.
    static func moonImageURL(park:String,night:Date)->URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:group)?.appendingPathComponent("moon-\(park)-\(Int(night.timeIntervalSince1970)).png")
    }
    /// The app's picture of this park's Moon on this very night, or nil: a picture of another
    /// night would show another phase beside this night's numbers, so the widget draws its vector
    /// Moon (`MoonDisc`) instead.
    static func moonImage(park:String,night:Date)->URL? {
        guard let exact=moonImageURL(park:park,night:night), FileManager.default.fileExists(atPath:exact.path) else { return nil }
        return exact
    }
    /// The snapshot as last written, decoded at most once per change of the file (`SnapshotFile.read`).
    static func read()->SavedSkySnapshot? { snapshotFile.read() }
    /// `read` off the caller's actor: an intent or entity query on the main actor never waits there for a decode.
    @concurrent static func load() async -> SavedSkySnapshot? { read() }
}
/// The widgets' snapshot on disk, decoded once per process and kept until the file changes. The 63
/// parks' forecasts make it about 0.8 MB of JSON: every widget kind, the Tonight control, Siri's
/// park lists and the app's intents read it, often at once on a reload, in an extension allowed
/// about 30 MB. The copy is keyed by the file's bytes, mapped rather than read and compared with
/// the bytes it was decoded from (well under a millisecond): a file timestamp would be a
/// required-reason API in four privacy manifests for the same answer, and bytes cannot miss a
/// change. Thread-safe: concurrent readers wait for one decode and share it.
nonisolated final class SnapshotFile:Sendable {
    static let shared=SnapshotFile(url:SharedSettings.snapshotURL)
    let url:URL?
    private struct State { var bytes:Data?; var snapshot:SavedSkySnapshot?; var decodes=0 }
    private let state=Mutex(State())
    init(url:URL?) { self.url=url }
    /// How many times the file was decoded in this process.
    var decodes:Int { state.withLock { $0.decodes } }
    func read()->SavedSkySnapshot? {
        guard let url else { return nil }
        return state.withLock { state in
            // No file: nothing written yet (or it was removed); nothing is kept.
            guard let bytes=try? Data(contentsOf:url,options:.mappedIfSafe) else { state=State(decodes:state.decodes); return nil }
            if state.bytes == bytes { return state.snapshot }
            let snapshot=try? JSONDecoder().decode(SavedSkySnapshot.self,from:bytes)
            state.bytes=bytes; state.snapshot=snapshot; state.decodes+=1
            return snapshot
        }
    }
    /// Writes the snapshot when it differs from the file; true when it did. The kept copy goes with the
    /// old file, so the next read decodes what was written.
    @discardableResult func write(_ snapshot:SavedSkySnapshot)->Bool {
        let encoder=JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let url,let data=try? encoder.encode(snapshot) else { return false }
        if let current=try? Data(contentsOf:url,options:.mappedIfSafe), current == data { return false }
        guard (try? data.write(to:url,options:.atomic)) != nil else { return false }
        state.withLock { $0=State(decodes:$0.decodes) }
        return true
    }
}
/// Writes snapshots off the caller's actor (encoding 0.8 MB with sorted keys, reading the old file
/// back to compare, the atomic write: tens of milliseconds, two or three times an activation, during
/// the cold-launch reveal too), one after another in the order asked: each write waits for the one
/// asked before it, so an older snapshot never lands after a newer one. A write runs to the end
/// even when its caller is cancelled (a background run out of time).
nonisolated final class SnapshotWriter:Sendable {
    private let last=Mutex<Task<Bool,Never>?>(nil)
    private let perform:@Sendable (SavedSkySnapshot)->Bool
    init(perform:@escaping @Sendable (SavedSkySnapshot)->Bool) { self.perform=perform }
    convenience init(file:SnapshotFile=SharedSettings.snapshotFile) { self.init { file.write($0) } }
    /// True when the file changed, so the caller reloads the widgets (after the write, never before).
    func write(_ snapshot:SavedSkySnapshot) async -> Bool { await enqueue(snapshot).value }
    /// The write, queued behind the one asked before it; its order is set by this call.
    func enqueue(_ snapshot:SavedSkySnapshot)->Task<Bool,Never> {
        let perform=perform
        return last.withLock { last in
            let previous=last
            let task=Task.detached(priority:.utility) { _=await previous?.value; return perform(snapshot) }
            last=task
            return task
        }
    }
}
/// What the app hands its widgets (and the watch app writes for its complications). Versioned and
/// decoded leniently, so a field added later, or one park that no longer decodes, never blanks a
/// widget until the app is next opened.
nonisolated struct SavedSkySnapshot:Codable,Sendable {
    /// 2 adds the version and the per-park closures (1.1); 3 the carried usual clouds (2.0); 4 when
    /// the closures were fetched. Readers never refuse a version: every field after the parks is optional.
    static let currentVersion=4
    var version=SavedSkySnapshot.currentVersion
    let parks:[Park]
    let forecasts:[String:Forecast]
    /// Smoke and cloud layers for the same parks, so widgets and reminders score as the app does.
    /// Optional: snapshots written before it existed still decode.
    var details:[String:ForecastDetail]?=nil
    var planner:NightPlanner { NightPlanner(forecasts:forecasts,details:details ?? [:],climate:climate) }
    /// Each saved park's closure as Nyx words it beside the score, from the last park update.
    var closures:[String:String]=[:]
    /// The usual clouds of each place here that the bundled per-park file does not hold (saved spots,
    /// world places), worked out on the iPhone from its world grid (`CloudClimate.carriedMonths`):
    /// the widgets and the watch bundle no grid, and score those places with these, as the app does.
    /// Optional both ways: an older reader ignores it, and a snapshot without it still decodes.
    var usualClouds:[String:CloudClimate.Months]?=nil
    /// When the park alerts behind `closures` were fetched, so a reader can tell them from a newer
    /// copy of the alerts (`IntentClosure`). Nil before 2.3, and before any alerts were fetched.
    var closuresUpdated:Date?=nil
    /// The climate every night here is scored with: the bundled one plus the carried months.
    var climate:CloudClimate { CloudClimate.shared.carrying(usualClouds) }
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
        // Absent before 2.0 (15); one place's months that no longer decode cost only that place's usual clouds.
        usualClouds=(try? container.decodeIfPresent([String:Lenient<CloudClimate.Months>].self,forKey:.usualClouds))?.compactMapValues(\.value)
        closuresUpdated=(try? container.decodeIfPresent(Date.self,forKey:.closuresUpdated)) ?? nil
    }
}
