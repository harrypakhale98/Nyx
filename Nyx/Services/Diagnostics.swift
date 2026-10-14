import Foundation
import MetricKit

/// Crash and hang reports iOS hands Nyx through MetricKit, kept on this device (the last five, in
/// the App Group container) so the person can copy one into a support email if they choose. Nothing
/// is ever sent by Nyx: there is no server, and the report leaves only by the person's own copy or
/// share. iOS 27 uses the Swift `MetricManager`; iOS 26 the older subscriber.
nonisolated struct DiagnosticRecord: Codable, Sendable, Identifiable, Equatable {
    nonisolated enum Kind: String, Codable, Sendable { case crash, hang }
    let id: String
    let kind: Kind
    let received: Date
    /// MetricKit's own JSON for the report, unchanged.
    let json: String
}
@MainActor final class DiagnosticsStore: NSObject, MXMetricManagerSubscriber {
    static let shared=DiagnosticsStore()
    nonisolated static let keep=5
    private var started=false
    private var listener: Task<Void, Never>?
    /// Where reports live; tests pass their own folder.
    nonisolated static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedSettings.group)?.appendingPathComponent("Diagnostics", isDirectory: true)
    }
    func start() {
        guard !started, DebugScenario.screen == nil else { return }
        started=true
        if #available(iOS 27.0, *) {
            let manager=MetricManager()
            listener=Task.detached(priority: .utility) {
                for await report in manager.diagnosticReports {
                    let kind: DiagnosticRecord.Kind?
                    if case .crash=report.result { kind = .crash } else if case .hang=report.result { kind = .hang } else { kind=nil }
                    guard let kind, let data=try? JSONEncoder().encode(report), let json=String(data: data, encoding: .utf8) else { continue }
                    Self.save(DiagnosticRecord(id: UUID().uuidString, kind: kind, received: report.timeRange.end, json: json))
                }
            }
        } else {
            MXMetricManager.shared.add(self)
        }
    }
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let kind: DiagnosticRecord.Kind?=(payload.crashDiagnostics?.isEmpty == false) ? .crash : (payload.hangDiagnostics?.isEmpty == false) ? .hang : nil
            guard let kind, let json=String(data: payload.jsonRepresentation(), encoding: .utf8) else { continue }
            Self.save(DiagnosticRecord(id: UUID().uuidString, kind: kind, received: payload.timeStampEnd, json: json))
        }
    }
    /// Adds a report and keeps only the newest `keep`.
    nonisolated static func save(_ record: DiagnosticRecord, in folder: URL? = DiagnosticsStore.folder) {
        guard let folder, (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil,
              let data=try? JSONEncoder().encode(record) else { return }
        try? data.write(to: folder.appendingPathComponent("\(record.id).json"), options: .atomic)
        let all=load(from: folder)
        for old in all.dropFirst(keep) { try? FileManager.default.removeItem(at: folder.appendingPathComponent("\(old.id).json")) }
    }
    /// Newest first.
    nonisolated static func load(from folder: URL? = DiagnosticsStore.folder) -> [DiagnosticRecord] {
        guard let folder, let names=try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { name in
            (try? Data(contentsOf: folder.appendingPathComponent(name))).flatMap { try? JSONDecoder().decode(DiagnosticRecord.self, from: $0) }
        }.sorted { $0.received>$1.received }
    }
    nonisolated static func removeAll(in folder: URL? = DiagnosticsStore.folder) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }
    /// What "Copy diagnostic report" puts on the clipboard: the app's version and the reports, nothing else.
    nonisolated static func report(_ records: [DiagnosticRecord], bundle: Bundle = .main) -> String {
        let version=bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build=bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header="Nyx \(version) (\(build)), \(records.count) report(s)"
        return ([header]+records.map { "--- \($0.kind.rawValue) \($0.received.ISO8601Format())\n\($0.json)" }).joined(separator: "\n")
    }
}
