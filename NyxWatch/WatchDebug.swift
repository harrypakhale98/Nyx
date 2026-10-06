import SwiftUI

/// Screenshot routes for the watch, DEBUG only (Release always starts on Tonight):
/// `-nyx-watch-screen tonight | milestones | week | dark | parks | chooser | complications`
/// `-nyx-watch-state synced | unsynced | polar | samoa`, `-nyx-watch-palette red | phone | standard`.
/// States change who is followed, never a score: every night is computed by the real engine.
enum WatchDebug {
    static var screen: String? {
        #if DEBUG
        return argument("-nyx-watch-screen")
        #else
        return nil
        #endif
    }
    static var initialPage: Int { ["milestones": 1, "week": 2][screen ?? ""] ?? 0 }
    /// Screens that are Tonight itself (a page, or the dark-adaptation cover over it).
    static let homeScreens: Set<String> = ["tonight", "milestones", "week", "dark"]
    /// `-nyx-watch-ax`: the largest accessibility text size (the watch simulator cannot set it).
    struct TypeSize: ViewModifier {
        func body(content: Content) -> some View {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-nyx-watch-ax") { content.dynamicTypeSize(.accessibility5) } else { content }
            #else
            content
            #endif
        }
    }
    #if DEBUG
    private static func argument(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: key), index+1 < args.count else { return nil }
        return args[index+1]
    }
    static func apply(to store: WatchStore) {
        if let palette = argument("-nyx-watch-palette").flatMap(PaletteChoice.init(rawValue:)) { store.palette = palette }
        // Fixture contexts carry no forecast: a fixture never invents clouds.
        let synced = WatchContext(sent: .now, savedParkIDs: ["jotr", "deva", "grba", "bibe"], homeParkID: "jotr", nightVision: true, forecasts: [:])
        switch argument("-nyx-watch-state") {
        case "unsynced": store.debugSet(context: nil, pinned: nil)
        case "synced": store.debugSet(context: synced, pinned: nil)
        case "polar": store.debugSet(context: synced, pinned: "dena")
        case "samoa": store.debugSet(context: synced, pinned: "npsa")
        default: break
        }
    }
    @MainActor @ViewBuilder static func view(_ screen: String) -> some View {
        switch screen {
        case "parks": ParksList()
        case "chooser": ParkChooser()
        case "complications": DebugFeatured { ComplicationReview(park: $0) }
        default: EmptyView()
        }
    }
    #endif
}

#if DEBUG
private struct DebugFeatured<Content: View>: View {
    @Environment(WatchStore.self) private var store
    @ViewBuilder let content: (Park) -> Content
    var body: some View {
        if let park = store.featured(at: .now) ?? store.park("jotr") { content(park) }
    }
}
/// Every complication family drawn from the live engine, for review; the face itself is checked on device.
private struct ComplicationReview: View {
    @Environment(WatchStore.self) private var store
    let park: Park
    var body: some View {
        let night = store.tonight(park, at: .now)
        let entry = WatchSkyEntry(date: .now, night: night, next: NightMilestone.next(after: .now, in: night.sky), nightVision: store.nightVision)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    WatchComplicationView(previewFamily: .accessoryCircular, entry: entry).frame(width: 50, height: 50)
                    WatchComplicationView(previewFamily: .accessoryCorner, entry: entry).frame(width: 50, height: 50)
                }
                WatchComplicationView(previewFamily: .accessoryRectangular, entry: entry).frame(height: 60)
                WatchComplicationView(previewFamily: .accessoryInline, entry: entry).frame(height: 20)
                WatchComplicationView(previewFamily: .accessoryRectangular, entry: WatchSkyEntry(date: .now, night: nil, next: nil, nightVision: store.nightVision)).frame(height: 50)
            }
        }
        .navigationTitle("Complications")
    }
}
#endif
