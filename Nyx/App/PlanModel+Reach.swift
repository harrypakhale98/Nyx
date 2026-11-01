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
    /// True while the answer for the places in reach still waits on the world catalogue: until it is
    /// ready, from a starting point outside the US, or one whose reach crosses the US edge, where a
    /// place across a border (or the catalogue's kept forecasts) would change a parks-only answer a
    /// moment after it was shown. Tonight and Plan's best nights show their loader meanwhile.
    var awaitingWorld:Bool {
        guard !catalogIsReady, let from=reachOrigin else { return false }
        return !USOutline.contains(latitude:from.latitude,longitude:from.longitude) || reachCrossesUSEdge(from:from)
    }
    /// Whether the circle of the chosen radius around `from` leaves the US outline anywhere (a border,
    /// or a coast, which is treated alike): tested at 36 bearings on three rings, once per origin and radius.
    func reachCrossesUSEdge(from:(latitude:Double,longitude:Double))->Bool {
        let key="\(from.latitude),\(from.longitude),\(radiusMeters)"
        if let memo=edgeMemo, memo.key == key { return memo.crosses }
        let crosses=TonightReach.crossesUSEdge(latitude:from.latitude,longitude:from.longitude,radiusMeters:radiusMeters)
        edgeMemo=(key,crosses)
        return crosses
    }
    /// `places` as a screen ranks them at once: all of them, or where a radius holds hundreds (abroad)
    /// the darkest skies nearest `reachOrigin` (`TonightReach.shortlist`), never hundreds on the main thread.
    func shortlist(_ places:[Park])->[Park] {
        guard places.count>TonightReach.shortlistSize else { return places }
        let from=reachOrigin
        return TonightReach.shortlist(places,latitude:from?.latitude ?? 0,longitude:from?.longitude ?? 0)
    }
    /// Abroad, more places in reach than a shortlist holds: the clouds kept for those newly in reach,
    /// and tonight at each, worked out off the main thread (`reachPrepared`), so they can all be ranked
    /// at once. Nothing to do where the places are few.
    /// Marked ready only for the reach still asked about: a late task for an earlier one (another
    /// window's, or a page opened before the radius changed) never stands in for the current reach.
    func prepareReach(_ places:[Park]) async {
        guard places.count>TonightReach.shortlistSize else { return }
        let key=TonightReach.key(places), night=today
        await takeKeptForecasts(newIn:places)
        await prepareNights(places,count:1)
        if !Task.isCancelled, TonightReach.key(placesInReach().places)==key { reachPrepared=(key,night,places) }
    }
    /// The places whose tonight is worked out (`reachPrepared`) while that night is still tonight: nil once
    /// one of their own nights turns over (`tick`), until tonight at each is worked out again off the main
    /// thread. A sunrise elsewhere (a US park's, seen from abroad) leaves them as they are.
    var preparedReach:String? { reachPrepared.flatMap { $0.night==today ? $0.places : nil } }
    /// The places in reach as Tonight, Ask Nyx and Assistive Access rank them: all of them, so every one
    /// names the same place; nil while Tonight shows its loader: the world catalogue abroad or near a
    /// border (`awaitingWorld`), the launch's cache reads (`cachesPending`), or abroad while their tonight
    /// is still being worked out (`prepareReach`), as a shortlist's leader could give way to a place beyond it.
    var wholeReach:[Park]? {
        guard !awaitingWorld, !cachesPending else { return nil }
        let places=placesInReach().places
        return TonightReach.waits(places,prepared:preparedReach) ? nil : places
    }
    /// Whether a forecast is old enough to say when it is from, and to refresh: older than the age at
    /// which clouds are asked for again (`ForecastReuse.clouds`), measured from `present`.
    func forecastIsStale(_ updated:Date)->Bool { present.timeIntervalSince(updated)>ForecastReuse.clouds }
}
