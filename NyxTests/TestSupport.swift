import Foundation
import Synchronization
import Testing
@testable import Nyx

/// What many suites share: the bundled data decoded once per test run, a defaults suite of a test's
/// own, an HTTP stub that keeps each request's headers, and the switch for wall-clock timing checks.
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

/// An ISO 8601 instant: "2026-10-16T21:00:00Z".
func date(_ text: String) throws -> Date { try #require(try? Date(text, strategy: .iso8601)) }

/// "2026-10-03 01:30" on the park's own clock.
func date(_ string: String, park: Park) throws -> Date {
    let formatter=DateFormatter(); formatter.dateFormat="yyyy-MM-dd HH:mm"; formatter.timeZone=park.timeZone
    return try #require(formatter.date(from: string))
}

/// A `UserDefaults` suite no other test touches, emptied before use, so a test that flips a
/// setting never leaves it flipped for the app or for the next test.
func isolatedDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "nyx.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite) ?? .standard
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// Records every request with its headers; answers by path, optionally after a pause, so tests
/// can hold one request open while another screen asks.
actor HeaderHTTP: HTTPTransport {
    struct Call: Sendable { let url: URL; let headers: [String: String]; let constrained: Bool }
    var calls: [Call]=[]
    var bodies: [String: [String]]
    var status: Int?
    var error: URLError?
    var delay: Duration?
    init(_ bodies: [String: [String]]) { self.bodies=bodies }
    func set(status: Int?) { self.status=status }
    func set(error: URLError?) { self.error=error }
    func set(delay: Duration?) { self.delay=delay }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        calls.append(Call(url: url, headers: headers, constrained: constrained))
        if let delay { try? await Task.sleep(for: delay) }
        if let error { throw error }
        if let status { throw HTTPStatusError(status: status) }
        guard var queue=bodies[url.path], !queue.isEmpty else { throw URLError(.badServerResponse) }
        let body=queue.count>1 ? queue.removeFirst() : queue[0]
        bodies[url.path]=queue
        return Data(body.utf8)
    }
}

/// Wall-clock limits are checked only when benchmarks are asked for (`TEST_RUNNER_NYX_BENCH=1`):
/// a loaded machine running tests in parallel would otherwise fail them at random.
enum Bench {
    static let enabled = ProcessInfo.processInfo.environment["NYX_BENCH"] != nil
}
