import Foundation

/// "Looking back" (`Hindsight`): Tonight's answer noted while its clouds are ahead, and answered
/// once a forecast issued after the night arrives. Only with cloud forecasts on; nothing is fetched.
extension PlanModel {
    func updateHindsight() {
        guard hindsightLoaded, weatherEnabled else { return }
        let now=present
        var records=Hindsight.pruned(hindsight,now:now)
        // What Nyx says about tonight's answer (only while it is still tonight's: `tonightPick`), kept up to
        // date until its clouds begin. A night has one answer: one Tonight moved away from is let go.
        if let id=tonightPick, let park=park(id), let said=Hindsight.note(night(park),now:now) {
            let kept=records.first { $0.placeID==said.placeID && $0.day==said.day }
            if kept?.looked == nil { records=Hindsight.upsert(said,into:Hindsight.replacing(said,in:records)) }
        }
        // Earlier nights answered by the forecasts now held.
        for record in records where record.looked == nil && record.evening<now {
            guard let park=park(record.placeID), let answered=Hindsight.check(record,against:night(park,on:record.evening)) else { continue }
            records=Hindsight.upsert(answered,into:records)
        }
        guard records != hindsight else { return }
        hindsight=records
        defaults.set(try? JSONEncoder().encode(records),forKey:"hindsight")
    }
    /// "Forget these nights": every record let go.
    func forgetHindsight() {
        hindsight=[]
        defaults.removeObject(forKey:"hindsight")
    }
}
