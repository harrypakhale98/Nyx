import AppIntents
import Foundation
import WidgetKit

/// The Tonight widget's "next park" button. Shared by the app and the widget extension, where it
/// runs: it moves the widget to the next saved park in order of tonight's score.
struct CycleWidgetParkIntent: AppIntent {
    static let title: LocalizedStringResource="Show the next saved park"
    static let description=IntentDescription("Moves Nyx's Tonight's sky widget to your next saved park, in order of tonight's score. The next day it returns to the darkest one.")
    static let isDiscoverable=false
    init() {}
    func perform() async throws -> some IntentResult {
        WidgetSelection.cycle(snapshot:SharedSettings.read(),now:.now)
        WidgetCenter.shared.reloadTimelines(ofKind:WidgetSelection.kind)
        return .result()
    }
}

/// Which saved park the Tonight widget shows. By default the darkest tonight; a tap on "next"
/// holds another park until that park's night turns over at sunrise, so the widget never keeps
/// showing a choice from yesterday.
nonisolated enum WidgetSelection {
    static let kind="TonightWidget"
    /// The Tonight control's kind (`TonightControl`), reloaded whenever the snapshot changes.
    static let controlKind="TonightScoreControl"
    static let key="widgetPark"
    /// The order the button walks: tonight's best first, as `NightPlanner` ranks nights.
    static func ordered(_ nights:[Night])->[Night] { NightPlanner.ranked(nights) }
    /// The chosen park while its chosen night is still tonight; otherwise the best.
    static func pick(_ nights:[Night],defaults:UserDefaults = SharedSettings.defaults)->Night? {
        let order=ordered(nights)
        guard let choice=defaults.dictionary(forKey:key), let id=choice["park"] as? String, let stamp=choice["night"] as? Double,
              let chosen=order.first(where:{ $0.park.id==id && $0.id.timeIntervalSince1970==stamp }) else { return order.first }
        return chosen
    }
    /// Position of the shown park among the saved ones, 1-based, for "2 of 3".
    static func position(of night:Night,in nights:[Night])->Int { (ordered(nights).firstIndex { $0.park.id==night.park.id } ?? 0)+1 }
    /// Moves to the next park; after the last, back to the best.
    static func cycle(snapshot:SavedSkySnapshot?,now:Date,defaults:UserDefaults = SharedSettings.defaults) {
        guard let snapshot, snapshot.parks.count>1 else { defaults.removeObject(forKey:key); return }
        let planner=snapshot.planner
        let tonight=snapshot.parks.map { planner.night($0,on:$0.currentNight(at:now),now:now) }
        let order=ordered(tonight)
        guard let shown=pick(tonight,defaults:defaults), let index=order.firstIndex(where:{ $0.park.id==shown.park.id }) else { return }
        let next=order[(index+1)%order.count]
        defaults.set(["park":next.park.id,"night":next.id.timeIntervalSince1970],forKey:key)
    }
}
