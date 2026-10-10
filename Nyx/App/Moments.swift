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
    /// A beat after the moment, so the prompt never lands on a closing sheet.
    static let momentDelay=1.5
    /// Longer after a journal entry: the new star arrives 0.35 s after the editor drops and settles
    /// over 1.6 s (`StarArrival`), and the prompt must not land on the moment it follows.
    static let journalDelay=2.6
    /// Great nights opened, counted per version ("reviewGreatNights-1.2").
    static func greatNightsKey(version:String)->String { "reviewGreatNights-\(version)" }
    /// The version this build would ask for.
    static var version:String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "" }
    /// A night was opened; Excellent (75) or better counts toward this version's third.
    static func noteNightViewed(score:Int,defaults:UserDefaults = .standard,version:String=ReviewPrompt.version,ask:@MainActor (UserDefaults)->Void={ request(defaults:$0) }) {
        guard score>=75 else { return }
        let key=greatNightsKey(version:version)
        let count=defaults.integer(forKey:key)+1
        defaults.set(count,forKey:key)
        if count==3 { ask(defaults) }
    }
    /// The journal grew by one entry (not a store loading or an import of many). Asks when this
    /// version has not asked yet; `request` keeps the once-per-version rule.
    static func noteJournalEntry(old:Int,new:Int,defaults:UserDefaults = .standard,ask:@MainActor (UserDefaults)->Void={ request(defaults:$0,delay:journalDelay) }) {
        guard isJournalMoment(old:old,new:new) else { return }
        ask(defaults)
    }
    nonisolated static func isJournalMoment(old:Int,new:Int)->Bool { new==old+1 }
    /// "Keep this night" saved: at dawn in field mode or on the park's page the morning after. The
    /// save also grows the journal by one, so while the tabs are alive `MomentsWatcher` reaches the
    /// same `request` and the second call finds the version claimed. This path is kept for a park
    /// opened in its own iPad window, where no watcher runs. At dawn inside field mode both are
    /// refused (`inField`), and nothing is recorded, so a later moment can still ask.
    static func noteFieldNightKept(defaults:UserDefaults = .standard,ask:@MainActor (UserDefaults)->Void={ request(defaults:$0) }) { ask(defaults) }
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
    /// Whether field mode is anywhere in a presentation chain, not only on top: its own sheets
    /// (the "Keep this night" editor at dawn) are presented above it.
    static func inField(_ chain:[UIViewController])->Bool { chain.contains { $0 is FieldHostingController } }
    /// Every controller presented in the scene's windows, each window's root first.
    static func presented(in scene:UIWindowScene)->[UIViewController] {
        scene.windows.flatMap { window in
            var chain:[UIViewController]=[], next=window.rootViewController
            while let controller=next { chain.append(controller); next=controller.presentedViewController }
            return chain
        }
    }
    static func request(defaults:UserDefaults,delay:Double=momentDelay) {
        guard DebugScenario.screen == nil,
              let scene=UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where:{ $0.activationState == .foregroundActive }),
              claim(defaults:defaults,version:version,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),inField:inField(presented(in:scene))) else { return }
        // A beat after the moment itself, so the prompt never lands on top of a closing sheet.
        Task { try? await Task.sleep(for:.seconds(delay)); AppStore.requestReview(in:scene) }
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
            // Seeds the constellation's known stars at launch and catches a night recorded while the
            // Journal is not in view, so it arrives as a star on the next visit.
            .onAppear { ConstellationArrivals.note(Set(journal.map(\.id.uuidString))) }
            .onChange(of:Set(journal.map(\.id.uuidString))) { _,ids in ConstellationArrivals.note(ids) }
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
