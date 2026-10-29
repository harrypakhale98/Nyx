import Foundation

/// What is "in reach", one rule for Tonight, Plan's best nights, the trip planner, Ask Nyx and
/// Assistive Access: the places within the one radius (`radiusMeters`) of the one starting point,
/// or of the device under Near me.
extension PlanModel {
    /// The device's location under "Near me", else the starting point.
    var reachOrigin:(latitude:Double,longitude:Double)? {
        if let lat=location.latitude, let lon=location.longitude { return (lat,lon) }
        return origin
    }
    /// Everything within `radiusMeters` (the chosen radius by default) of `reachOrigin`
    /// (`TonightReach`): from a US starting point with only US places in range, the national parks
    /// exactly as before the world catalogue; otherwise every place in range, catalogue and spots too.
    func placesInReach(radiusMeters:Double?=nil)->(places:[Park],world:Bool) {
        let parks=nearby(latitude:location.latitude,longitude:location.longitude,radiusMeters:radiusMeters)
        guard !catalog.isEmpty, let from=reachOrigin else { return (parks,false) }
        let everything=places(near:from.latitude,longitude:from.longitude,radiusMeters:radiusMeters ?? self.radiusMeters)
        let places=TonightReach.candidates(parks:parks,places:everything,originInUS:USOutline.contains(latitude:from.latitude,longitude:from.longitude))
        return (places,places != parks)
    }
    /// `places` as a screen ranks them at once: all of them, or where a radius holds hundreds (abroad)
    /// the darkest skies nearest `reachOrigin` (`TonightReach.shortlist`), never hundreds on the main thread.
    func shortlist(_ places:[Park])->[Park] {
        guard places.count>TonightReach.shortlistSize else { return places }
        let from=reachOrigin
        return TonightReach.shortlist(places,latitude:from?.latitude ?? 0,longitude:from?.longitude ?? 0)
    }
    /// The places in reach, shortlisted (`shortlist`): what Tonight ranks first, and all that Ask Nyx
    /// and Assistive Access weigh, so every one of them names the same place.
    var shortlistInReach:[Park] { shortlist(placesInReach().places) }
    /// Whether a forecast is old enough to say when it is from, and to refresh: older than the age at
    /// which clouds are asked for again (`ForecastReuse.clouds`), measured from `present`.
    func forecastIsStale(_ updated:Date)->Bool { present.timeIntervalSince(updated)>ForecastReuse.clouds }
}
