import SwiftUI

@main struct NyxWatchApp: App {
    @State private var store = WatchStore()
    var body: some Scene {
        WindowGroup { WatchRootView().environment(store) }
            // The iPhone sent a new context while Nyx was not running: take it, refresh the face.
            .backgroundTask(.watchConnectivity) { await store.receivePending() }
    }
}
