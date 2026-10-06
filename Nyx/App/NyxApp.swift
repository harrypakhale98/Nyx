import AppIntents
import SwiftUI
import SwiftData
import TipKit
import UserNotifications

@main struct NyxApp: App {
    @State private var model=PlanModel()
    private let container:ModelContainer?
    init() {
        do { container=try ModelContainer(for:SavedPark.self,JournalEntry.self,configurations:ModelConfiguration(isStoredInMemoryOnly:DebugScenario.screen != nil)) }
        catch { container=nil }
        try? Tips.configure([.datastoreLocation(.applicationDefault)])
        UNUserNotificationCenter.current().delegate=NotificationRouter.shared
        // Registers park names as Siri / Shortcuts phrase parameters.
        NyxShortcuts.updateAppShortcutParameters()
        SkyProjection.shared.lightSources=SkyGlow.lightSources
    }
    var body:some Scene {
        WindowGroup {
            if let container { RootView().environment(model).modelContainer(container) }
            else { CalmState(symbol:"externaldrive",title:"Your journal is safe to leave closed",message:"Nyx could not open local storage. Restart the app after making space on this iPhone. Existing data has not been replaced.").background(Color.black).preferredColorScheme(.dark) }
        }
    }
}
