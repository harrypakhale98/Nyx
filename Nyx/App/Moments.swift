import SwiftUI
import SwiftData
import StoreKit
import UserNotifications

/// Asks for an App Store rating once per version, only after a good moment: a night kept in the
/// journal, a night from field mode kept the morning after, or the third time an Excellent or
/// Pristine night is opened in this version. Never in field mode or night vision, where a bright
/// system sheet would cost the eyes their adaptation. iOS decides whether the prompt actually
/// appears (and limits it on its own); Nyx never fakes one. Every counter belongs to one version,
/// so 1.3 asks again on its own good moments rather than never.
@MainActor enum ReviewPrompt {
    static let askedKey="reviewAskedVersion"
    /// Great nights opened, counted per version ("reviewGreatNights-1.2").
    static func greatNightsKey(version:String)->String { "reviewGreatNights-\(version)" }
    /// The version this build would ask for.
    static var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "" }
    /// A night was opened; Excellent (75) or better counts toward this version's third.
    static func noteNightViewed(score:Int,defaults:UserDefaults = .standard,version:String=ReviewPrompt.version,ask:@MainActor (UserDefaults)->Void=request) {
        guard score>=75 else { return }
        let key=greatNightsKey(version:version)
        let count=defaults.integer(forKey:key)+1
        defaults.set(count,forKey:key)
        if count==3 { ask(defaults) }
    }
    /// The journal grew by one entry (not a store loading or an import of many). Asks when this
    /// version has not asked yet; `request` keeps the once-per-version rule.
    static func noteJournalEntry(old:Int,new:Int,defaults:UserDefaults = .standard,ask:@MainActor (UserDefaults)->Void=request) {
        guard isJournalMoment(old:old,new:new) else { return }
        ask(defaults)
    }
    nonisolated static func isJournalMoment(old:Int,new:Int)->Bool { new==old+1 }
    /// "Keep this night" saved the morning after field mode: the night itself, written down.
    static func noteFieldNightKept(defaults:UserDefaults = .standard,ask:@MainActor (UserDefaults)->Void=request) { ask(defaults) }
    /// Pure: whether to ask now. Once per version, never in the dark.
    nonisolated static func shouldAsk(askedVersion:String?,version:String,nightVision:Bool,inField:Bool)->Bool {
        !version.isEmpty && askedVersion != version && !nightVision && !inField
    }
    /// Records the ask for this version when `shouldAsk` allows it; false leaves nothing recorded.
    static func claim(defaults:UserDefaults,version:String,nightVision:Bool,inField:Bool)->Bool {
        guard shouldAsk(askedVersion:defaults.string(forKey:askedKey),version:version,nightVision:nightVision,inField:inField) else { return false }
        defaults.set(version,forKey:askedKey)
        return true
    }
    static func request(defaults:UserDefaults) {
        guard DebugScenario.screen == nil else { return }
        let scene=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        let inField=SceneCommands.top(in:scene) is FieldHostingController
        guard let scene, claim(defaults:defaults,version:version,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),inField:inField) else { return }
        // A beat after the moment itself, so the prompt never lands on top of a closing sheet.
        Task { try? await Task.sleep(for:.seconds(1.5)); AppStore.requestReview(in:scene) }
    }
}

/// Watches for the moments that lead somewhere: the first park saved offers promising-night
/// reminders (once, and only while iOS has not yet been asked), and a new journal entry may
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
            .onChange(of:journal.count) { old,new in ReviewPrompt.noteJournalEntry(old:old,new:new) }
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
