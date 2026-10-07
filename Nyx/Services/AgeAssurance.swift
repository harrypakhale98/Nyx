import DeclaredAgeRange
import SwiftUI

/// Age assurance where a law requires it (Texas SB 2420 since 2026-06-04; Utah and Louisiana later).
/// Nyx has no age-restricted content, so the answer changes nothing in the app. The rule:
/// - ask the system for an age range only when it reports that this account needs one
///   (`requiredRegulatoryFeatures` contains `.declaredAgeRangeRequired`, iOS 26.4; before that,
///   `isEligibleForAgeFeatures`, iOS 26.2; on iOS 26.0–26.1 the system cannot say, so Nyx never asks);
/// - store nothing (the response is dropped when the check ends; the system itself caches it);
/// - gate nothing and never block: no answer, a refusal or an error all leave Nyx exactly as it was.
/// The age gates follow the Texas categories (under 13, 13–15, 16–17, 18 and over).
enum AgeAssurance {
    enum Need: Equatable { case required, notRequired, unknown }
    enum Outcome: Equatable { case notRequired, shared, declined, failed }
    static let gates=(13, 16, 18)
    /// Once per process, even with several iPad windows; never written to disk.
    private static var ran=false

    /// The whole decision, with the system behind a seam so tests can drive every branch.
    static func run(_ source: some AgeSignalSource) async -> Outcome {
        guard await source.need() == .required else { return .notRequired }
        do { return try await source.requestRange() ? .shared : .declined } catch { return .failed }
    }
    /// The launch hook: once, after the first frame, never in DEBUG screenshot scenarios.
    static func runAtLaunch() async {
        guard !ran, DebugScenario.screen == nil else { return }
        ran=true
        // Let the first frame and the launch reveal land before any system sheet can appear.
        try? await Task.sleep(for: .seconds(1.5))
        _ = await run(SystemAgeSignals())
    }
}

/// What Nyx needs from the system: whether this account requires an age range, and the request itself
/// (true when the person or the system shared a range, false when sharing was declined).
protocol AgeSignalSource {
    func need() async -> AgeAssurance.Need
    func requestRange() async throws -> Bool
}

struct SystemAgeSignals: AgeSignalSource {
    func need() async -> AgeAssurance.Need {
        switch await Self.requiresAgeRange() { case true?: .required; case false?: .notRequired; case nil: .unknown }
    }
    /// Asked off the main actor (the service is not Sendable). nil: the system could not say.
    @concurrent nonisolated private static func requiresAgeRange() async -> Bool? {
        do {
            if #available(iOS 26.4, *) {
                guard try await AgeRangeService.shared.isEligibleForAgeFeatures else { return false }
                return try await AgeRangeService.shared.requiredRegulatoryFeatures.contains(.declaredAgeRangeRequired)
            }
            if #available(iOS 26.2, *) { return try await AgeRangeService.shared.isEligibleForAgeFeatures }
        } catch { return nil }
        return nil
    }
    func requestRange() async throws -> Bool {
        // The system's sheet needs a view controller: the top of the key window's stack.
        guard let controller=SceneCommands.top(in:nil) else { throw AgeRangeService.Error.notAvailable }
        let g=AgeAssurance.gates
        return try await Self.ask(gates:g.0, g.1, g.2, in:controller)
    }
    /// The range itself is not kept or read: Nyx has nothing to unlock or withhold by age.
    @concurrent nonisolated private static func ask(gates first: Int, _ second: Int, _ third: Int, in controller: UIViewController) async throws -> Bool {
        if case .sharing=try await AgeRangeService.shared.requestAgeRange(ageGates:first, second, third, in:controller) { return true }
        return false
    }
}

/// Attached once to the root of every window (`NyxApp`).
struct AgeAssuranceCheck: ViewModifier {
    func body(content: Content) -> some View { content.task { await AgeAssurance.runAtLaunch() } }
}
