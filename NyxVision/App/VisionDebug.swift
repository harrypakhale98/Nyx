import Foundation

/// DEBUG launch arguments for screenshots; all of them disappear from Release builds.
/// `-nyx-date 2026-07-15` (now is 21:00 UTC that day), `-nyx-park jotr`, `-nyx-vision-time 0.5`
/// (position in the night, sunset 0 to sunrise 1), `-nyx-vision-body jupiter` (name card shown),
/// flags `-nyx-vision-immersive` (open the sky at launch), `-nyx-night-vision`, `-nyx-ax5`,
/// `-nyx-vision-look yaw,pitch` (degrees; turns the scene for a screenshot),
/// `-nyx-vision-uvtest` (an orientation test card in place of the Moon).
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
    static var time: Double? { argument("-nyx-vision-time").flatMap(Double.init) }
    static var body: String? { argument("-nyx-vision-body") }
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
