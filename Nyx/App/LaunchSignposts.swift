import Foundation
import os

/// Signposted launch phases (Instruments' Points of Interest and `log show --signpost`), plus a
/// log line at the first frame and when caches are ready, timed from the app's start. Measured on this device
/// only; nothing is recorded or sent anywhere.
nonisolated enum LaunchSignposts {
    static let signposter=OSSignposter(subsystem:"com.harrypakhale.nyx",category:.pointsOfInterest)
    private static let log=Logger(subsystem:"com.harrypakhale.nyx",category:"Launch")
    nonisolated struct Interval { let name:StaticString; let state:OSSignpostIntervalState }
    static func begin(_ name:StaticString)->Interval { Interval(name:name,state:signposter.beginInterval(name,id:signposter.makeSignpostID())) }
    static func end(_ interval:Interval) { signposter.endInterval(interval.name,interval.state) }
    /// The app's `init`, the earliest point Nyx's own code runs. Phases are timed from here
    /// (pre-main loading is the same before and after any change Nyx makes).
    nonisolated(unsafe) private static var origin:Date?
    static func start(_ now:Date = .now) { if origin == nil { origin=now } }
    static func sinceStart(_ now:Date = .now)->Double? { origin.map { now.timeIntervalSince($0)*1000 } }
    /// Once per process: the first frame of the first window.
    @MainActor private static var marked=false
    @MainActor private static var frameAt:Date?
    @MainActor static func firstFrame() {
        guard !marked else { return }
        marked=true
        frameAt = .now
        signposter.emitEvent("First frame")
        if let ms=sinceStart() { log.notice("First frame \(Int(ms.rounded()),privacy:.public) ms after app init") }
    }
    /// Once per process: the first score count-up to land, the time to an answer. The count-up
    /// itself is the "Score reveal" interval.
    @MainActor private static var answered=false
    @MainActor static func firstLanding(countStarted:Date,_ now:Date = .now) {
        guard !answered else { return }
        answered=true
        signposter.emitEvent("First score landed")
        let afterFrame=frameAt.map { Int((now.timeIntervalSince($0)*1000).rounded()) } ?? -1
        let counting=Int((now.timeIntervalSince(countStarted)*1000).rounded())
        if let ms=sinceStart() { log.notice("First score landed \(Int(ms.rounded()),privacy:.public) ms after app init, \(afterFrame,privacy:.public) ms after the first frame; the count-up ran \(counting,privacy:.public) ms") }
    }
    static func note(_ phase:StaticString) {
        if let ms=sinceStart() { log.notice("\(String(describing:phase),privacy:.public) done \(Int(ms.rounded()),privacy:.public) ms after app init") }
    }
}
