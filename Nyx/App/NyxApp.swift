import AppIntents
import SwiftUI
import SwiftData
import TipKit
import UserNotifications

@main struct NyxApp: App {
    @State private var model:PlanModel
    private let container:ModelContainer?
    init() {
        LaunchSignposts.start()
        let launch=LaunchSignposts.begin("App init")
        // The offline caches start loading on background threads at once.
        let preload=DebugScenario.screen == nil ? CachePreload.start() : nil
        BundledData.warm()
        let store=LaunchSignposts.begin("Open store")
        let opened=JournalStore.open(inMemory:DebugScenario.screen != nil)
        container=opened.container
        LaunchSignposts.end(store)
        let planner=LaunchSignposts.begin("PlanModel init")
        let model=PlanModel(preload:preload)
        // `-nyx-journal-unavailable` (DEBUG) shows the journal banner for screenshots.
        model.journalUnavailable=opened.failed || DebugScenario.isEnabled("journal-unavailable")
        model.journalNeedsSpace=opened.shortOfSpace
        // Journal entries from Siri (`AddJournalEntryIntent`) go to the same store as the windows, and
        // are refused when that store is only the stand-in in memory.
        JournalAccess.configure(container:opened.container,unavailable:model.journalUnavailable)
        _model=State(initialValue:model)
        LaunchSignposts.end(planner)
        #if DEBUG
        // Captures (`-nyx-river-tip`): the river's tip shows even after a test run has closed it.
        if DebugScenario.isEnabled("river-tip") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure([.datastoreLocation(.applicationDefault)])
        UNUserNotificationCenter.current().delegate=NotificationRouter.shared
        // Registers park names as Siri / Shortcuts phrase parameters.
        NyxShortcuts.updateAppShortcutParameters()
        SkyProjection.shared.lightSources=SkyGlow.lightSources
        DiagnosticsStore.shared.start()
        LaunchSignposts.end(launch)
    }
    var body:some Scene {
        WindowGroup {
            // Age assurance only where the system says the law requires it; stores and gates nothing (`AgeAssurance`).
            if let container { RootView().environment(model).modelContainer(container).modifier(AgeAssuranceCheck()) }
            else { CalmState(symbol:"externaldrive",title:"Nyx could not open its storage",message:"Restart Nyx after making some space. Existing data has not been replaced.").background(Color.black).preferredColorScheme(.dark) }
        }
        // iPad's menu bar and ⌘-hold overlay: tabs, Find a Park, previous and next night, a park in a new window.
        .commands { NyxCommands() }
        // About every six hours, when iOS allows: saved parks' clouds (and alerts when due), the
        // widget, the watch and reminders, so a reminder never rests on a stale forecast.
        .backgroundTask(.appRefresh(SavedSkySync.refreshTask)) { [model] in await model.savedSync.backgroundRefresh(model) }
        // Assistive Access (Settings › Accessibility): one park, one word, the Moon and when it gets dark.
        AssistiveAccess {
            if let container { AssistiveAccessRoot().environment(model).modelContainer(container) }
            else { CalmState(symbol:"externaldrive",title:"Nyx could not open its storage",message:"Restart Nyx after making some space. Existing data has not been replaced.").background(Color.black).preferredColorScheme(.dark) }
        }
        // iPad: a park in a window of its own ("Open in New Window", ⌘⇧N). Links and Spotlight keep
        // landing in the main window, never in a new park window.
        WindowGroup("Park",id:"park",for:ParkWindow.self) { $value in
            if let container { ParkWindowRoot(value:$value).environment(model).modelContainer(container) }
        }
        .handlesExternalEvents(matching:[])
    }
}

/// The bundled tables every first screen reads (sky glow, usual clouds, sky events, step-free
/// spots, the star catalogue), decoded on a background thread at launch instead of on the main
/// thread at first use. Each is a `static let`, initialised once and thread-safely: a screen that
/// asks first simply waits for the same read.
nonisolated enum BundledData {
    static func warm() {
        DispatchQueue.global(qos:.userInitiated).async {
            _=SkyGlow.shared; _=NightPlanner.glowRank(""); _=CloudClimate.shared
            _=SkyEvents.shared; _=AccessData.shared; _=SkyProjection.catalogue.count
        }
    }
}
