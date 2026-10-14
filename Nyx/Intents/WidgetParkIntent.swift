import AppIntents
import Foundation
import WidgetKit

/// The Tonight widget's "next park" button. Shared by the app and the widget extension, where it
/// runs: it moves the widget to the next saved park in order of tonight's score.
struct CycleWidgetParkIntent: AppIntent {
    static let title: LocalizedStringResource="Show the next saved park"
    static let description=IntentDescription("Moves the Tonight's sky widget to your next saved park, in order of tonight's score. Tomorrow it returns to your darkest park.")
    static let isDiscoverable=false
    init() {}
    func perform() async throws -> some IntentResult {
        WidgetSelection.cycle(snapshot:SharedSettings.read(),now:.now)
        // A new place starts on its own tonight.
        WidgetNightStep.clearSaved()
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

/// The Tonight widget's previous and next night buttons (medium and large). Each button carries
/// the night it moves to, so a tap on a face drawn a moment ago lands where that face said, and
/// the night it counted from, so a tap made after sunrise lands back on the new tonight.
struct StepWidgetNightIntent: AppIntent {
    static let title: LocalizedStringResource="Show another night"
    static let description=IntentDescription("Moves the Tonight's sky widget to an earlier or later night this week. At sunrise it returns to tonight.")
    static let isDiscoverable=false
    /// The widget's setting and size (`WidgetNightStep.scope`).
    @Parameter(title:"Widget") var scope:String
    @Parameter(title:"Place") var park:String
    /// The night the widget counted from, as seconds since 1970.
    @Parameter(title:"Tonight") var tonight:Double
    /// Nights after tonight: 0 is tonight.
    @Parameter(title:"Night") var offset:Int
    init() {}
    init(scope:String,park:String,tonight:Date,offset:Int) {
        self.scope=scope; self.park=park; self.tonight=tonight.timeIntervalSince1970; self.offset=offset
    }
    func perform() async throws -> some IntentResult {
        WidgetNightStep.set(offset,scope:scope,park:park,tonight:Date(timeIntervalSince1970:tonight),now:.now)
        WidgetCenter.shared.reloadTimelines(ofKind:WidgetSelection.kind)
        return .result()
    }
}

/// Which night each Tonight widget shows. Tonight unless its previous and next buttons moved it,
/// and then only while that night's tonight is still tonight at the same place: the night turns
/// over at sunrise (`TonightTimeline.turnovers`) and the widget is back on tonight. Kept in the
/// App Group per widget setting and size, so two widgets never move each other.
nonisolated enum WidgetNightStep {
    static let key="widgetNights"
    /// Tonight and the six nights after it, the medium widget's week.
    static let nights=7
    /// One widget setting at one size: its chosen place ("saved" follows the darkest saved place) and its family.
    static func scope(place:String?,family:String)->String { "\(place ?? "saved")|\(family)" }
    static func clamped(_ offset:Int)->Int { min(max(offset,0),nights-1) }
    /// The night a widget shows, as nights after `tonight`: 0 unless this scope moved to another
    /// night at this place while `tonight` was tonight.
    static func offset(scope:String,park:String,tonight:Date,defaults:UserDefaults = SharedSettings.defaults)->Int {
        guard let saved=defaults.dictionary(forKey:key)?[scope] as? [String:Any], saved["park"] as? String == park,
              saved["tonight"] as? Double == tonight.timeIntervalSince1970, let offset=saved["offset"] as? Int else { return 0 }
        return clamped(offset)
    }
    /// Keeps a widget's night; tonight keeps nothing. Settings whose night ended two days ago go.
    static func set(_ offset:Int,scope:String,park:String,tonight:Date,now:Date,defaults:UserDefaults = SharedSettings.defaults) {
        var all=(defaults.dictionary(forKey:key) ?? [:]).filter { _,value in
            ((value as? [String:Any])?["tonight"] as? Double).map { $0>now.timeIntervalSince1970-2*86400 } ?? false
        }
        let target=clamped(offset)
        all[scope]=target == 0 ? nil : ["park":park,"tonight":tonight.timeIntervalSince1970,"offset":target]
        if all.isEmpty { defaults.removeObject(forKey:key) } else { defaults.set(all,forKey:key) }
    }
    /// The widgets that follow the darkest saved place: back to tonight when "next saved place" moves them.
    static func clearSaved(defaults:UserDefaults = SharedSettings.defaults) {
        guard let all=defaults.dictionary(forKey:key) else { return }
        let kept=all.filter { !$0.key.hasPrefix("saved|") }
        if kept.isEmpty { defaults.removeObject(forKey:key) } else { defaults.set(kept,forKey:key) }
    }
}
