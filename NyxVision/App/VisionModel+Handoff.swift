import AppIntents
import SwiftUI

extension VisionModel {
    /// Opens a park and night handed off from park detail on iPhone or iPad. A night that has
    /// already passed opens tonight; one further ahead than the window steps opens as far as it can.
    /// Vision Pro carries the US national parks only: a saved spot or a place abroad is answered
    /// with a calm alert (`handoffElsewhere`), never silence.
    func open(_ handoff: ParkHandoff) {
        guard let park = parks.first(where: { $0.id == handoff.parkID }) else { handoffElsewhere = true; return }
        selectedID = park.id
        nightOffset = Self.offset(for: handoff, park: park, now: now)
    }
    /// Nights after tonight (park-local) for the handed-off night, 0 for tonight or a past night.
    nonisolated static func offset(for handoff: ParkHandoff, park: Park, now: Date) -> Int {
        guard let evening = handoff.evening(in: park) else { return 0 }
        let tonight = park.currentNight(at: now)
        let days = park.calendar.dateComponents([.day], from: tonight, to: evening).day ?? 0
        return min(365, max(0, days))
    }
}

/// The planner offers its park and night to Handoff, as park detail does on iPhone and iPad
/// (`ParkHandoffActivity`): an iPhone or iPad signed in to the same Apple Account can continue
/// with that park on that night. The payload is a public park code and a date; nothing is offered
/// to Spotlight or Siri suggestions. The entity names the park on screen to Siri.
struct VisionHandoff: ViewModifier {
    let park: Park?
    let night: Date?
    func body(content: Content) -> some View {
        content.userActivity(ParkHandoff.type, isActive: park != nil && night != nil) { activity in
            guard let park, let night else { return }
            let handoff = ParkHandoff(park: park, night: night)
            activity.title = park.shortName
            activity.userInfo = handoff.userInfo
            activity.requiredUserInfoKeys = ["park"]
            activity.targetContentIdentifier = park.id
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = false
            activity.isEligibleForPrediction = false
            activity.appEntityIdentifier = EntityIdentifier(for: ParkEntity.self, identifier: park.id)
        }
    }
}
