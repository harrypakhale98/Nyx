import SwiftUI

/// "Update from iPhone": one request to Nyx on iPhone and what came of it. The iPhone answers at
/// once and the context follows by the usual path, so the answer is only ever "asked", never
/// "updated": the forecast lines say what actually arrived. The watch makes no network request.
nonisolated struct IPhoneAsk: Equatable, Sendable {
    enum State: Hashable, Sendable {
        case asking
        /// The iPhone is asking for fresh clouds, then handing the context over.
        case asked
        /// Cloud forecasts are switched off on the iPhone: it hands over what it has.
        case resending
        case unreachable
        /// The iPhone has restarted and must be unlocked before the watch can reach it.
        case locked
    }
    let state: State
    let at: Date
    init(_ state: State, at: Date) { self.state = state; self.at = at }
    /// The message, spelled as the iPhone reads it (`WatchRequest` in Nyx/Services/WatchBridge.swift),
    /// naming the places this watch wants clouds for (`WatchSky.wantedPlaces`).
    static func message(places: [String]) -> [String: Any] { ["request": "context", "places": places] }
    static let replyKey = "reply"
    /// The iPhone's answer: "refreshing" or "resending". Anything else is an iPhone that does not
    /// know the request (an older Nyx), which cannot help either.
    static func state(reply: String?) -> State {
        switch reply {
        case "refreshing": .asked
        case "resending": .resending
        default: .unreachable
        }
    }
    /// How long an answer stays beside the forecast; after it the button is offered again.
    static let shown: TimeInterval = 120
    /// How long a request waits for an answer. WatchConnectivity may call neither handler (the
    /// iPhone lost mid-request), so a request older than this reads as unreachable, and can be made again.
    static let patience: TimeInterval = 30
    /// The state to show at `now`: a request still on its way, or an answer under two minutes old.
    func current(at now: Date) -> State? {
        let age = now.timeIntervalSince(at)
        guard state == .asking else { return age < Self.shown ? state : nil }
        if age < Self.patience { return .asking }
        return age < Self.patience+Self.shown ? .unreachable : nil
    }
    /// The moments `current(at:)` changes: a request running out of time, and an answer leaving.
    var changes: [Date] {
        state == .asking ? [at.addingTimeInterval(Self.patience), at.addingTimeInterval(Self.patience+Self.shown)] : [at.addingTimeInterval(Self.shown)]
    }
    static func line(_ state: State) -> String {
        switch state {
        case .asking: String(localized: "Asking your iPhone")
        case .asked: String(localized: "Asked your iPhone to refresh.")
        case .resending: String(localized: "Cloud forecasts are off in Nyx on iPhone.")
        case .unreachable: String(localized: "iPhone not reachable. Open Nyx on iPhone.")
        case .locked: String(localized: "Unlock your iPhone, then try again.")
        }
    }
    /// Whether the button stays beside the answer, to try again.
    static func retry(_ state: State) -> Bool { state == .unreachable || state == .locked }
}

/// Beside a forecast the iPhone could refresh, or before anything has come from it: a button that
/// asks it to, then what came of asking. Hidden once the clouds are fresh.
struct AskIPhoneRow: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.nyx) private var palette
    @Environment(\.watchNow) private var now
    /// The app's clock ticks once a minute; a request keeps its own, so it turns unreachable and
    /// its answer leaves on time (`IPhoneAsk.changes`).
    @State private var tick = Date.distantPast
    let source: CloudSource
    var body: some View {
        if source.isStale || source == .unsynced {
            let state = store.ask?.current(at: max(now, tick))
            VStack(alignment: .leading, spacing: 4) {
                if state == .asking {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).fixedSize().accessibilityHidden(true)
                        Text(IPhoneAsk.line(.asking)).font(.caption2).foregroundStyle(palette.muted)
                    }
                    .accessibilityElement(children: .combine)
                } else if let state {
                    Text(IPhoneAsk.line(state)).font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
                if state == nil || state.map(IPhoneAsk.retry) == true {
                    Button { store.askIPhone() } label: { Label("Update from iPhone", systemImage: "iphone") }
                        .accessibilityHint(Text("Asks Nyx on iPhone to refresh the cloud forecast and send it to this watch."))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: store.ask) {
                guard let ask = store.ask else { return }
                for mark in ask.changes where mark > .now {
                    do { try await Task.sleep(for: .seconds(mark.timeIntervalSinceNow)) } catch { return }
                    tick = mark
                }
            }
            // VoiceOver hears the answer where it lands, without moving focus to it: a reply, a
            // request that ran out of time, or the same answer to a new request.
            .onChange(of: state.flatMap { state in store.ask.map { IPhoneAsk(state, at: $0.at) } }) { _, shown in
                guard let shown, shown.state != .asking else { return }
                AccessibilityNotification.Announcement(IPhoneAsk.line(shown.state)).post()
            }
        }
    }
}

#Preview("Ask • every state") {
    WatchPreviewHost(nightVision: true) { _, _ in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AskIPhoneRow(source: .expired(.now.addingTimeInterval(-3*86400)))
                ForEach([IPhoneAsk.State.asking, .asked, .resending, .unreachable, .locked], id: \.self) { state in
                    AskStatePreview(state: state)
                }
            }
        }
    }
}
#Preview("Ask • AX5") {
    WatchPreviewHost(nightVision: false) { _, _ in
        ScrollView { AskStatePreview(state: .unreachable) }
    }
    .dynamicTypeSize(.accessibility5)
}
/// One answer, set on its own store so each shows side by side.
private struct AskStatePreview: View {
    @State private var store = WatchStore()
    let state: IPhoneAsk.State
    var body: some View {
        AskIPhoneRow(source: .missing(followed: true)).environment(store)
            .onAppear {
                #if DEBUG
                store.debugSet(ask: IPhoneAsk(state, at: .now))
                #endif
            }
    }
}
