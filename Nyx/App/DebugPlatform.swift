#if DEBUG
import SwiftUI

/// Review routes for the platform surfaces that live outside the app: `-nyx-screen widgets`,
/// `widgets-large` and `snippet`. The widgets are computed exactly as the extension computes them
/// (`NightPlanner`, `WidgetSelection`), from the model's forecasts; only the host is simulated.
@MainActor enum DebugPlatform {
    /// Three saved parks, as after one tap of "next": the shown park is the starting park.
    static func widgetEntry(_ model: PlanModel, large: Bool) -> TonightEntry {
        let now=model.today
        let ids=[model.homeID]+["grba","brca","deva"].filter { $0 != model.homeID }.prefix(2)
        let parks=ids.compactMap(model.park)
        let planner=NightPlanner(forecasts:model.forecasts,details:model.details)
        let tonight=parks.map { planner.night($0,on:$0.currentNight(at:now),now:now) }
        guard let shown=tonight.first else { return TonightEntry(date:now,night:nil,nightVision:false) }
        let week=planner.nights(shown.park,from:now,count:7,now:now)
        return TonightEntry(date:now,night:shown,nightVision:false,week:week,month:large ? planner.month(shown.park,at:now) : nil,
                            position:WidgetSelection.position(of:shown,in:tonight),savedCount:parks.count)
    }
}
/// The "Find the best night" snippet for the starting park over 30 nights, as Siri shows it.
struct DebugSnippetView: View {
    @Environment(PlanModel.self) private var model
    var body: some View {
        ScrollView { VStack(alignment:.leading,spacing:16) {
            Text("Snippet review").font(.system(size:20,design:.serif))
            if let park=model.home, let answer=BestNightSearch.answer(parks:[park],planner:NightPlanner(forecasts:model.forecasts,details:model.details),from:model.today,nights:30,now:model.today) {
                Text(BestNightSearch.dialog(answer,voiceOnly:false)).font(.callout)
                BestNightSnippetView(night:answer.best,rank:0,total:answer.ranked.count,nights:answer.count)
                Text("Voice only (iOS 27):").font(.caption)
                Text(BestNightSearch.dialog(answer,voiceOnly:true)).font(.callout)
                if answer.ranked.count>1 { BestNightSnippetView(night:answer.ranked[1],rank:1,total:answer.ranked.count,nights:answer.count) }
            }
            Text("Content preview. Siri and Shortcuts host the real snippet.").font(.caption)
        }.padding(24) }.background(Color(white:0.12))
    }
}
#endif
