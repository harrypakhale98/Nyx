import BackgroundTasks
import SwiftUI
import WidgetKit

/// Brings the widget, the watch, Siri's park list and reminders in line with the saved parks. One
/// per process (owned by `PlanModel`), so two iPad windows never run it twice. It publishes from
/// what is cached first, so unsaving a park or switching shower reminders off takes effect at once
/// even on a weak signal, then again once fresh forecasts arrive. A change made while a run is under
/// way is never dropped: the run goes again when it ends.
@MainActor final class SavedSkySync {
    static let refreshTask="com.harrypakhale.nyx.refresh"
    private var running=false
    private var again=false
    /// The saved parks, once a window has read them (or, in a background launch, from the widget's snapshot).
    private(set) var parkIDs:[String]?
    /// The palette the widget's Moon pictures are drawn in; the window keeps it current.
    var palette=NyxPalette(nightVision:false,highContrast:false)

    func update(_ model:PlanModel,parkIDs ids:[String]?=nil) async {
        guard DebugScenario.screen == nil else { return }
        // When the store could not open, the windows read their saved parks from an empty stand-in.
        // That empty list must never reach the widget, the watch or reminders: the parks of the last
        // snapshot stay, and their forecasts keep being refreshed.
        if model.journalUnavailable { if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) } }
        else if let ids { parkIDs=ids }
        guard let current=parkIDs else { return }
        guard !running else { again=true; return }
        running=true
        defer {
            running=false
            if again { again=false; Task { await update(model) } }
        }
        let parks=current.compactMap { model.park($0) }
        let ids=Set(parks.map(\.id))
        let cached=model.forecasts.filter { ids.contains($0.key) }.mapValues(\.updated)
        await publish(model,parks)
        // The widget and reminders need only forecasts; park alerts follow once they are done,
        // so a quick visit still leaves both up to date.
        await model.refreshForecasts(watching:parks)
        if !again, model.forecasts.filter({ ids.contains($0.key) }).mapValues(\.updated) != cached { await publish(model,parks) }
        let closures=self.closures(model,parks)
        await model.refreshParkUpdates(parks)
        // A new closure reaches the widget's snapshot (and the watch) without waiting for the next refresh.
        if !again, self.closures(model,parks) != closures { writeSnapshot(model,parks) }
        Self.scheduleRefresh()
    }
    /// The system's background refresh: saved-park clouds (and alerts when due), the widget's
    /// snapshot, the watch and reminders, then the next request about six hours on. Same hosts and
    /// the same requests as in the app; nothing about the person is sent.
    func backgroundRefresh(_ model:PlanModel) async {
        if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) }
        await update(model)
        // A followed night's Live Activity catches up too: its next moment, or its end at dawn.
        await FieldActivities.refresh(nightVision:SharedSettings.defaults.bool(forKey:"nightVision"))
        Self.scheduleRefresh()
    }
    /// Asks iOS for the next background refresh, about six hours from now (iOS decides when).
    static func scheduleRefresh(after delay:TimeInterval=6*3600,now:Date = .now) {
        let request=BGAppRefreshTaskRequest(identifier:refreshTask)
        request.earliestBeginDate=now.addingTimeInterval(delay)
        // Unavailable in the simulator and when Background App Refresh is off; the app then refreshes on open.
        try? BGTaskScheduler.shared.submit(request)
    }
    private func closures(_ model:PlanModel,_ parks:[Park])->[String:String] {
        Dictionary(parks.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    @discardableResult private func writeSnapshot(_ model:PlanModel,_ parks:[Park])->SavedSkySnapshot {
        let ids=Set(parks.map(\.id))
        let snapshot=SavedSkySnapshot(parks:parks,forecasts:model.forecasts.filter { ids.contains($0.key) },details:model.details.filter { ids.contains($0.key) },closures:closures(model,parks))
        SharedSettings.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        return snapshot
    }
    private func publish(_ model:PlanModel,_ parks:[Park]) async {
        let snapshot=writeSnapshot(model,parks)
        // Siri's suggested parks for the App Shortcuts phrases start with the saved ones.
        NyxShortcuts.updateAppShortcutParameters()
        WatchBridge.shared.push(savedParkIDs:parks.map(\.id),homeParkID:model.homeID,forecasts:model.forecasts)
        renderWidgetMoons(model,parks)
        WidgetCenter.shared.reloadAllTimelines()
        // The Smart Stack's dusk hints come from the same snapshot; a timeline reload alone may not refresh them.
        WidgetCenter.shared.invalidateRelevance(ofKind:WidgetSelection.kind)
        let defaults=UserDefaults.standard
        guard defaults.bool(forKey:"notificationsEnabled") else { return }
        let today=model.today, showers=defaults.object(forKey:"showerReminders") as? Bool ?? true
        let nights=await Task.detached(priority:.utility) { snapshot.nights(from:today,count:14) }.value
        // Reminders may have been switched off while the nights were computed.
        if defaults.bool(forKey:"notificationsEnabled") { await NotificationScheduler().reschedule(nights:nights,showers:showers,details:snapshot.details ?? [:]) }
    }
    /// The next week's Moons for each saved park, drawn once each for the widgets, so a widget left
    /// for days without Nyx being opened still shows the real Moon (`MoonImages.nearest`).
    static let moonNights=7
    private func renderWidgetMoons(_ model:PlanModel,_ parks:[Park]) {
        let engine=AstronomyEngine()
        // Drawn in starlight: the widget turns its own pictures red in night vision, so a picture
        // drawn red would stay red once night vision is off.
        let neutral=NyxPalette(nightVision:false,highContrast:palette.highContrast)
        var keep=Set<String>()
        for park in parks {
            for offset in 0..<Self.moonNights {
                let night=model.night(park,on:park.date(model.tonight(park),addingDays:offset))
                guard let url=SharedSettings.moonImageURL(park:park.id,night:night.id) else { continue }
                keep.insert(url.lastPathComponent)
                if FileManager.default.fileExists(atPath:url.path) { continue }
                let renderer=ImageRenderer(content:MoonView(geometry:engine.moon(for:night).geometry).frame(width:60,height:60).environment(\.nyx,neutral))
                renderer.scale=3
                try? renderer.uiImage?.pngData()?.write(to:url,options:.atomic)
            }
        }
        // Forget pictures of nights that have passed or parks no longer saved.
        if let folder=SharedSettings.moonImageURL(park:"x",night:.now)?.deletingLastPathComponent(),
           let files=try? FileManager.default.contentsOfDirectory(atPath:folder.path) {
            for file in files where file.hasPrefix("moon-") && !keep.contains(file) { try? FileManager.default.removeItem(at:folder.appendingPathComponent(file)) }
        }
    }
}
