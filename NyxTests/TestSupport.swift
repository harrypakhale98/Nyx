import Foundation
import Synchronization
import Testing
@testable import Nyx

/// What many suites share: the bundled data decoded once per test run, a defaults suite of a test's
/// own, and the switch for wall-clock timing checks.
enum TestData {
    /// The 63 bundled parks, decoded once.
    static let parks: [Park] = (try? ParkData.load()) ?? []
    private static let catalogs = Mutex<[String: [Park]]>([:])
    /// The world catalogue in `language` (nil: the app's own), decoded once per language.
    static func catalog(language: String? = nil) throws -> [Park] {
        let key = language ?? ""
        if let kept = catalogs.withLock({ $0[key] }) { return kept }
        let loaded = try CatalogData.load(language: language)
        catalogs.withLock { $0[key] = loaded }
        return loaded
    }
}

/// A bundled park by id.
func park(_ id: String) throws -> Park { try #require(TestData.parks.first { $0.id == id }) }

/// A `UserDefaults` suite no other test touches, emptied before use, so a test that flips a
/// setting never leaves it flipped for the app or for the next test.
func isolatedDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "nyx.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// Wall-clock limits are checked only when benchmarks are asked for (`TEST_RUNNER_NYX_BENCH=1`):
/// a loaded machine running tests in parallel would otherwise fail them at random.
enum Bench {
    static let enabled = ProcessInfo.processInfo.environment["NYX_BENCH"] != nil
}
