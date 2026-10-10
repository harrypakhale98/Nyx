import Foundation

/// DEBUG launch arguments for screenshots; all of them disappear from Release builds.
/// `-nyx-date 2026-07-15` (now is 21:00 UTC that day), `-nyx-park jotr`, `-nyx-vision-time 0.5`
/// (position in the night, sunset 0 to sunrise 1), `-nyx-vision-body jupiter` (name card shown),
/// flags `-nyx-vision-immersive` (open the sky at launch), `-nyx-night-vision`, `-nyx-ax5`,
/// `-nyx-vision-look yaw,pitch` (degrees; turns the scene for a screenshot),
/// `-nyx-vision-uvtest` (an orientation test card in place of the Moon), `-nyx-vision-partial`
/// (the sky opens at its everyday 0.6 instead of fully), `-nyx-vision-moon` (opens the Moon
/// volume; add `-nyx-vision-moon-only` to close the planner behind it, for screenshots of the Moon alone), `-nyx-vision-credits` (the credits sheet), `-nyx-vision-no-lines` (figures off),
/// `-nyx-vision-widget-shots` (renders the widget's faces to PNGs in the app's tmp folder),
/// `-nyx-vision-privacy` (the Your privacy sheet), `-nyx-vision-night 6`, `-nyx-vision-clouds 60`.
/// A pinned date never makes a network request.
/// Named stars take `-nyx-vision-body star.Vega`.
enum VisionDebug {
    static var date: Date? {
        #if DEBUG
        guard let text = argument("-nyx-date") else { return nil }
        return try? Date(text+"T21:00:00Z", strategy: .iso8601)
        #else
        return nil
        #endif
    }
    static var park: String? { argument("-nyx-park") }
    /// `-nyx-vision-night 6`: the planner opens that many nights after tonight (an early look).
    static var nightOffset: Int? { argument("-nyx-vision-night").flatMap(Int.init).map { min(365, max(0, $0)) } }
    /// `-nyx-vision-clouds 60`: every park gets a forecast of that constant cover, issued at the
    /// pinned date; no request is made.
    static var clouds: Double? { argument("-nyx-vision-clouds").flatMap(Double.init) }
    static var time: Double? { argument("-nyx-vision-time").flatMap(Double.init) }
    static var body: String? { argument("-nyx-vision-body") }
    /// `-nyx-vision-moon-night 9`: the Moon volume opens on that many nights after tonight.
    static var moonNights: Int? { argument("-nyx-vision-moon-night").flatMap(Int.init) }
    static var look: (yaw: Float, pitch: Float)? {
        guard let parts = argument("-nyx-vision-look")?.split(separator: ",").compactMap({ Float($0) }), parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
    static func isEnabled(_ value: String) -> Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-nyx-"+value)
        #else
        return false
        #endif
    }
    private static func argument(_ key: String) -> String? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index+1 < args.count else { return nil }
        return args[index+1]
        #else
        return nil
        #endif
    }
}
