import SwiftUI
import UIKit

/// Crash and hang reports kept on this device, for the person to copy or share with the developer
/// if they want to. Linked from Settings → Support.
struct DiagnosticsView: View {
    @Environment(\.nyx) private var palette
    @State private var records: [DiagnosticRecord]
    @State private var copied=0
    @State private var confirmClear=false
    init(records: [DiagnosticRecord]?=nil) { _records=State(initialValue:records ?? DiagnosticsStore.load()) }
    var body: some View {
        Form {
            Section {
                Text("When Nyx crashes or stops responding, iOS may give it a technical report about a day later. Nyx keeps the last five here, on this device. Nothing is sent anywhere unless you copy or share it yourself.")
                    .font(.subheadline).foregroundStyle(palette.ink)
            }
            if records.isEmpty {
                Section { Text("No crash or hang reports on this device.").foregroundStyle(palette.muted) }
            } else {
                Section("Reports") {
                    ForEach(records) { record in
                        LabeledContent {
                            Text(record.received.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(palette.muted)
                        } label:{
                            Label(record.kind == .crash ? String(localized:"Crash") : String(localized:"Stopped responding"),systemImage:record.kind == .crash ? "exclamationmark.triangle" : "hourglass")
                        }
                        .accessibilityElement(children:.combine)
                    }
                }
                Section {
                    Button { UIPasteboard.general.string=DiagnosticsStore.report(records); copied+=1 } label:{ Label("Copy diagnostic report",systemImage:"doc.on.doc").frame(minHeight:44) }
                    ShareLink(item:DiagnosticsStore.report(records)) { Label("Share diagnostic report",systemImage:"square.and.arrow.up").frame(minHeight:44) }
                    Button(role:.destructive) { confirmClear=true } label:{ Text("Delete reports").frame(minHeight:44) }
                } footer:{ Text("A report describes where the app stopped, with the app and iOS versions. It contains no location, journal or account information.").foregroundStyle(palette.muted) }
            }
        }
        .readableForm().navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success,trigger:copied)
        .confirmationDialog("Delete these reports?",isPresented:$confirmClear,titleVisibility:.visible) {
            Button("Delete reports",role:.destructive) { DiagnosticsStore.removeAll(); records=[] }
        }
        .onChange(of:copied) { _,_ in AccessibilityNotification.Announcement(String(localized:"Report copied")).post() }
    }
}
#Preview("No reports") { NavigationStack { DiagnosticsView(records:[]) }.preferredColorScheme(.dark) }
#Preview("Reports") {
    NavigationStack { DiagnosticsView(records:[DiagnosticRecord(id:"a",kind:.crash,received:.now,json:"{}"),DiagnosticRecord(id:"b",kind:.hang,received:.now-86_400,json:"{}")]) }.preferredColorScheme(.dark)
}
