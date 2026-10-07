import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

/// Asks for an App Store rating once per version, only after a good moment: the first night kept
/// in the journal, or the third time an Excellent or Pristine night is opened. Never in field mode
/// or night vision, where a bright system sheet would cost the eyes their adaptation. iOS decides
/// whether the prompt actually appears (and limits it on its own); Nyx never fakes one.
@MainActor enum ReviewPrompt {
    static let askedKey="reviewAskedVersion"
    static let greatNightsKey="reviewGreatNights"
    /// The version this build would ask for.
    static var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "" }
    /// A night was opened; Excellent (75) or better counts toward the third.
    static func noteNightViewed(score:Int,defaults:UserDefaults = .standard) {
        guard score>=75 else { return }
        let count=defaults.integer(forKey:greatNightsKey)+1
        defaults.set(count,forKey:greatNightsKey)
        if count==3 { request(defaults:defaults) }
    }
    /// The first night saved in the journal.
    static func noteFirstJournalEntry(defaults:UserDefaults = .standard) { request(defaults:defaults) }
    /// Pure: whether to ask now. Once per version, never in the dark.
    nonisolated static func shouldAsk(askedVersion:String?,version:String,nightVision:Bool,inField:Bool)->Bool {
        !version.isEmpty && askedVersion != version && !nightVision && !inField
    }
    private static func request(defaults:UserDefaults) {
        guard DebugScenario.screen == nil else { return }
        let scene=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        let inField=SceneCommands.top(in:scene) is FieldHostingController
        guard let scene, shouldAsk(askedVersion:defaults.string(forKey:askedKey),version:version,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),inField:inField) else { return }
        defaults.set(version,forKey:askedKey)
        // A beat after the moment itself, so the prompt never lands on top of a closing sheet.
        Task { try? await Task.sleep(for:.seconds(1.5)); AppStore.requestReview(in:scene) }
    }
}

/// Watches for the moments that lead somewhere: the first park saved offers promising-night
/// reminders (once, and only while iOS has not yet been asked), and the first journal entry may
/// ask for a rating. Invisible; lives behind the tabs.
struct MomentsWatcher: View {
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyx) private var palette
    @Query private var saved:[SavedPark]
    @Query private var journal:[JournalEntry]
    @AppStorage("notificationsEnabled") private var notificationsEnabled=false
    @AppStorage("reminderOfferShown") private var offerShown=false
    @State private var offering=false
    var body: some View {
        Color.clear.frame(width:0,height:0).accessibilityHidden(true)
            .onChange(of:saved.count) { old,new in
                // A park saved just now (not a store loading), by someone never asked about reminders.
                guard new>old, DebugScenario.screen == nil, !offerShown, !notificationsEnabled,
                      saved.contains(where:{ Date.now.timeIntervalSince($0.savedAt)<30 }) else { return }
                Task {
                    guard await Self.undecided() else { return }
                    offerShown=true
                    offer()
                }
            }
            .onChange(of:journal.count) { old,new in if old==0, new==1 { ReviewPrompt.noteFirstJournalEntry() } }
            .sheet(isPresented:$offering) { explainer.nyxPresentation() }
    }
    private var explainer:some View { RemindersExplainer { granted in notificationsEnabled=granted } }
    /// iOS has not yet asked about notifications.
    nonisolated private static func undecided() async -> Bool { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined }
    /// Over whatever is open (a park's page in a sheet, say), or as this window's own sheet.
    private func offer() {
        if let top=commands?.topController, top.presentingViewController != nil {
            let host=UIHostingController(rootView:explainer.nyxPresentation().environment(\.nyx,palette))
            host.sheetPresentationController?.detents=[.medium(),.large()]
            top.present(host,animated:true)
        } else { offering=true }
    }
}
