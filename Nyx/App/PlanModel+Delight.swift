import Foundation

extension PlanModel {
    /// Journal entries as plain values for the constellation and the recap, each with that night's
    /// score at its park (with the park's usual clouds for the month: past clouds are not kept).
    /// Scores are kept per entry, night and park (`journalScore`), so a render rescores nothing.
    func loggedNights(_ entries: [JournalEntry]) -> [LoggedNight] {
        entries.map { entry in
            let id=entry.id, date=entry.date, parkID=entry.parkID
            return LoggedNight(id:id,date:date,parkID:parkID,observedBortle:entry.observedBortle,
                               score:journalScore(id:id,date:date,parkID:parkID),notes:entry.notes)
        }
    }
    /// A trip plan from the cached forecasts and park updates, worked out off the main thread.
    /// Nothing is fetched: the plan is as fresh as what Nyx already has, and says so night by night.
    func planTrip(days: [TripDay], latitude: Double, longitude: Double, radiusMeters: Double, maxHopMeters: Double, drivableOnly: Bool = true) async -> TripPlan {
        // Every kind of place in range (the world catalogue once it is read), limited for speed.
        let candidates=tripCandidates(latitude:latitude,longitude:longitude,radiusMeters:radiusMeters,drivableOnly:drivableOnly)
        let ids=Set(candidates.map(\.id))
        let forecasts=self.forecasts.filter { ids.contains($0.key) }, details=self.details.filter { ids.contains($0.key) }
        let closures=Dictionary(candidates.compactMap { park in closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
        let now=DebugScenario.date ?? .now
        return await Task.detached(priority:.userInitiated) {
            TripPlanner.plan(days:days,grid:TripPlanner.nights(parks:candidates,days:days,forecasts:forecasts,details:details,now:now),closures:closures,maxHopMeters:maxHopMeters)
        }.value
    }
}
