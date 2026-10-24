import SwiftUI

/// "Looking back", below Tonight's starting point: the morning after, what Nyx said about last
/// night's answer beside what the weather models now say happened (`Hindsight`), and, once there
/// are a few, how often the two were close. Only with cloud forecasts on; hidden until a night is
/// answered, and gone once it is more than a day and a half old.
struct LookingBackPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @State private var confirming=false
    /// The records shown: the model's, or under `-nyx-state looking-back` (DEBUG) ten nights at Joshua Tree.
    private var records:[HindsightRecord] {
        #if DEBUG
        if DebugScenario.state=="looking-back", let park=model.park("jotr") {
            return (1...10).map { day in
                let evening=park.evening(model.present.addingTimeInterval(-Double(day)*86400))
                let said=[82,74,90,61,88,79,93,70,85,77][day-1], seen=[78,75,90,48,86,80,92,71,84,64][day-1]
                return HindsightRecord(placeID:park.id,evening:evening,day:park.isoDay(evening),said:said,saidCloud:Double(100-said)/4,issued:evening,
                                       rules:ScoreEngine.rulesVersion,looked:.init(score:seen,cloud:Double(100-seen)/3,issued:evening.addingTimeInterval(86400)))
            }
        }
        #endif
        return model.hindsight
    }
    var body: some View {
        if model.weatherEnabled, let record=Hindsight.lastNight(records,now:model.present),
           let place=model.park(record.placeID), let sentence=Hindsight.sentence(record,name:place.shortName) {
            Panel { VStack(alignment:.leading,spacing:12) {
                Eyebrow(text:"Looking back")
                Text(sentence).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                if let tally=Hindsight.tally(records) {
                    Text("Within 10 points on \(tally.close) of the last \(tally.of) nights Nyx answered.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                Text("This is the weather models' own look back at recent hours, not a measurement from the ground.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                // A quiet way out, never the accent: it lets go of data, and the dialog says so in red.
                Button("Forget these nights",role:.destructive) { confirming=true }.font(.footnote).foregroundStyle(palette.muted).frame(minHeight:44)
                    .confirmationDialog("Forget these nights?",isPresented:$confirming,titleVisibility:.visible) {
                        Button("Forget",role:.destructive) { model.forgetHindsight() }
                    } message:{ Text("Nyx lets go of what it said about past nights and what the weather models said afterwards. Your journal is not touched.") }
            } }
        }
    }
}
