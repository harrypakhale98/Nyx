import Foundation

extension VisionModel {
    /// Opens a park and night handed off from park detail on iPhone or iPad. A night that has
    /// already passed opens tonight; one further ahead than the window steps opens as far as it can.
    func open(_ handoff: ParkHandoff) {
        guard let park = parks.first(where: { $0.id == handoff.parkID }) else { return }
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
