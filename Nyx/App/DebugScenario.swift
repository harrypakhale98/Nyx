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
    static var onboardingPage:Int {
        #if DEBUG
        return min(2,max(0,Int(argument("-nyx-onboarding-page") ?? "0") ?? 0))
        #else
        return 0
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
