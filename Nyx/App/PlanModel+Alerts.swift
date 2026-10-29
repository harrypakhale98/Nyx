import Foundation

/// Where a park's access stands, in Nyx's words: its closure, and the lines and facts beside a score.
extension PlanModel {
    /// A closure from the last park update, if any: a road, trail, campground, area or the park
    /// itself, never an amenity notice. Shown beside every score for that park.
    func closure(_ park:Park)->String? {
        AlertRanking.closure(enrichments[park.id]?.alerts ?? [])?.displayTitle(park:park)
    }
    func alertSummary(_ park:Park)->String {
        // The same words Vision Pro says beside its scores (`AlertRanking.summary`).
        guard let data=enrichments[park.id] else { return AlertRanking.unchecked(busy:alertsBusy) }
        return AlertRanking.summary(data.alerts,park:park)
    }
    /// Where a place's access stands for Ask Nyx, in Nyx's own fixed words only. A closure is a flag
    /// (`OnDeviceGuide.closureRecord`), never the Park Service's title or text: that is free text,
    /// and the on-device model must not read it as an instruction or quote it as access advice.
    func guideAccess(_ park:Park)->String {
        guard park.nps != nil else { return park.unknownClosuresLine }
        guard let data=enrichments[park.id] else {
            return alertsBusy ? String(localized:"Park alerts are busy. Check current conditions on nps.gov.") : String(localized:"Access not checked. Confirm closures with the park.")
        }
        if closure(park) != nil { return OnDeviceGuide.closureRecord }
        if data.alerts.contains(where:{ $0.kind == .danger }) { return String(localized:"A safety alert is listed in the last park update. Read it in Nyx before you go.") }
        if data.alerts.isEmpty { return String(localized:"No alerts in the last park update. Confirm access before travel.") }
        return String(localized:"No closures in the last park update. Check all park alerts before you go.")
    }
    /// The curated parks with a closure in the last park update, for Ask Nyx's lookups.
    var closedParks:Set<String> { Set(parks.filter { closure($0) != nil }.map(\.id)) }
    /// `alertSummary` as short facts for one caption, only when the last park update lists nothing
    /// to stop a trip (no closure, no danger): the fact, then the cue to check before going. Nil
    /// otherwise, when the summary's full sentence stands alone.
    func alertFacts(_ park:Park)->[String]? {
        guard let data=enrichments[park.id], closure(park) == nil, !data.alerts.contains(where:{ $0.kind == .danger }) else { return nil }
        if data.alerts.isEmpty { return [String(localized:"No alerts listed"),String(localized:"confirm access before you go")] }
        return [String(localized:"No closures listed"),String(localized:"check alerts before you go")]
    }
}
