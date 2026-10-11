import SwiftUI
import UserNotifications

@main struct NyxWatchApp: App {
    @State private var store = WatchStore()
    init() {
        // Dark-adaptation reminders arriving while Nyx is up: a tap, never a bright banner.
        UNUserNotificationCenter.current().delegate = AdaptationNotificationDelegate.shared
    }
    var body: some Scene {
        // Control Center, Siri and Shortcuts can start dark adaptation; the app opens on the red clock.
        WindowGroup { WatchRootView().modifier(AdaptationRequests()).environment(store) }
            // The iPhone sent a new context while Nyx was not running: take it, store it and refresh
            // the face before the wake ends (`receivePending` returns only once all three are done).
            .backgroundTask(.watchConnectivity) { await store.receivePending() }
    }
}
