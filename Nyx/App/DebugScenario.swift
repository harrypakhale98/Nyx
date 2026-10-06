import Foundation

/// All fixtures and direct-screen routing disappear from Release builds.
enum DebugScenario {
    static var screen: String? {
        #if DEBUG
        return argument("-nyx-screen")
        #else
        return nil
        #endif
    }
    static var state: String? {
        #if DEBUG
        return argument("-nyx-state")
        #else
        return nil
        #endif
    }
    /// `-nyx-date 2026-12-13`: "now" is that afternoon (21:00 UTC), so tonight is that night in every US park.
    static var date: Date? {
        #if DEBUG
        guard let text=argument("-nyx-date") else { return nil }
        return try? Date(text+"T21:00:00Z",strategy:.iso8601)
        #else
        return nil
        #endif
    }
    /// `-nyx-park ever`: the starting park for a scenario (Joshua Tree otherwise).
    static var park: String? {
        #if DEBUG
        return argument("-nyx-park")
        #else
        return nil
        #endif
    }
    /// `-nyx-link nyx://whatsup?date=2026-12-13&park=grba`: opened as if tapped, once the app is up
    /// (the simulator's own `openurl` asks "Open in Nyx?" first, which scripts cannot answer).
    static var link: URL? {
        #if DEBUG
        return argument("-nyx-link").flatMap(URL.init(string:))
        #else
        return nil
        #endif
    }
    static var onboardingPage:Int {
        #if DEBUG
        return min(2,max(0,Int(argument("-nyx-onboarding-page") ?? "0") ?? 0))
        #else
        return 0
        #endif
    }
    /// A numeric launch argument, such as `-nyx-field-minutes 90`.
    static func number(_ key: String) -> Double? {
        #if DEBUG
        return argument(key).flatMap(Double.init)
        #else
        return nil
        #endif
    }
    static func isEnabled(_ value: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-nyx-"+value)
        #else
        return false
        #endif
    }
    private static func argument(_ key:String)->String? {
        let args=ProcessInfo.processInfo.arguments
        guard let index=args.firstIndex(of:key),index+1<args.count else { return nil }
        return args[index+1]
    }
}
