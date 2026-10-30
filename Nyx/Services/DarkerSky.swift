import Foundation

/// "The nearest dark sky": when nothing is in reach, or the darkest place in reach still has a
/// suburban or brighter sky, the nearest stretch of genuinely dark land on the bundled satellite
/// light map (`SkyGrid.nearestDark`). One rule and one set of words for every surface that answers
/// "where is it dark near me?": Tonight on iPhone and iPad, Assistive Access and Ask Nyx.
///
/// The area is a cell on a light map, never a place: it has no name and no score, nobody has
/// checked it for roads, access or a view, and every surface says so. Saved as a spot it becomes a
/// place with nights, which the widgets, Apple Watch, reminders and Siri then follow like any other.
/// Read on this device from the bundled grid; nothing is asked of any server.
nonisolated enum DarkerSky {
    /// From this class (suburban) the Milky Way has lost its structure: worth pointing farther.
    static let brightFrom = 5
    /// What the pointer calls a dark sky: Bortle 4 (rural to suburban transition) or darker.
    static let darkUpTo = 4
    /// An area this close is the starting point's own sky (the From home panel's to describe).
    static let minimumMeters = 5_000.0

    struct Offer: Sendable, Hashable {
        let area: SkyGrid.DarkArea
        /// Initial great-circle bearing from the starting point, degrees from true north.
        let bearing: Double
        /// The darkest class among the places in reach; nil when nothing is in reach.
        let darkestInReach: Int?
    }

    /// The class an area must reach to be worth the trip: dark, and two classes darker than the
    /// darkest place already in reach. Nil when a place in reach is dark enough already.
    static func needed(darkestInReach: Int?) -> Int? {
        guard let darkest=darkestInReach else { return darkUpTo }
        guard darkest>=brightFrom else { return nil }
        return min(darkUpTo, darkest-2)
    }

    /// The nearest dark area worth pointing to from `origin`, searched as far as the chosen radius
    /// or Tonight's wider reach, whichever is farther. Nil when a place in reach is dark enough,
    /// the starting point's own sky already is, or the grid has nothing dark enough (or no sky
    /// layer: widgets, the watch and Vision Pro bundle none). Reads tiles: call it off the main thread.
    /// `onLand`: the sky layer gives coastal sea a value, so the area must lie on the bundled land
    /// (Natural Earth), 5 km inland by its outline; without the outline nothing is offered.
    static func offer(from origin: (latitude: Double, longitude: Double), radiusMeters: Double, darkestInReach: Int?,
                      system: SearchRadius.System = .init(), grid: SkyGrid = .shared,
                      onLand: (Double, Double) -> Bool = { WorldLand.bundled?.inland(latitude: $0, longitude: $1) ?? false }) -> Offer? {
        guard let needed=needed(darkestInReach: darkestInReach) else { return nil }
        if let own=grid.skyBrightness(latitude: origin.latitude, longitude: origin.longitude), SkyGrid.bortle(fromMagnitude: own)<=needed { return nil }
        let reach=max(radiusMeters, SearchRadius.wider(system))
        guard let area=grid.nearestDark(to: origin, radiusMeters: reach, atMostBortle: needed, onLand: onLand), area.distanceMeters>=minimumMeters else { return nil }
        return Offer(area: area, bearing: bearing(from: origin, to: (area.latitude, area.longitude)), darkestInReach: darkestInReach)
    }

    /// Initial great-circle bearing, degrees from true north, 0..<360.
    static func bearing(from a: (latitude: Double, longitude: Double), to b: (latitude: Double, longitude: Double)) -> Double {
        let r=Double.pi/180, phi1=a.latitude*r, phi2=b.latitude*r, dLambda=(b.longitude-a.longitude)*r
        let y=sin(dLambda)*cos(phi2), x=cos(phi1)*sin(phi2)-sin(phi1)*cos(phi2)*cos(dLambda)
        let degrees=atan2(y, x)/r
        return (degrees.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)
    }

    // MARK: Words, shared by every surface

    /// "about 140 km", in the unit Tonight's radius uses.
    static func distance(_ meters: Double, _ system: SearchRadius.System = .init()) -> String {
        let value=meters/system.meters
        let rounded=value<15 ? max(1, value.rounded()) : (value/10).rounded()*10
        return String(localized: "about \(SearchRadius.format(rounded, system))")
    }
    /// "The nearest dark sky is about 140 km northeast, in a straight line."
    static func headline(_ offer: Offer, system: SearchRadius.System = .init()) -> String {
        String(localized: "The nearest dark sky is \(distance(offer.area.distanceMeters, system)) \(Compass.name(offer.bearing)), in a straight line.")
    }
    /// "Rural sky, Bortle 3, estimated from satellite data."
    static func skyLine(_ offer: Offer) -> String {
        String(localized: "\(BortleScale.name(offer.area.bortle)), Bortle \(offer.area.bortle), estimated from satellite data.")
    }
    /// What it is darker than: "The darkest place in reach has a Bortle 6 sky." Nil with nothing in reach.
    static func comparison(_ offer: Offer) -> String? {
        offer.darkestInReach.map { String(localized: "The darkest place in reach has a Bortle \($0) sky.") }
    }
    /// The honest limit, said wherever the area is shown.
    static var caution: String {
        String(localized: "It has no name and no score: it is a patch on a light map that nobody has checked. See what is there, and whether you may go, before you set out.")
    }
    /// Assistive Access's shorter limit.
    static var shortCaution: String { String(localized: "Nobody has checked it. See what is there before you go.") }
    /// The record Ask Nyx is given: the same facts, labelled as a light-map estimate with no name or score.
    static func record(_ offer: Offer, from origin: String, system: SearchRadius.System) -> String {
        String(localized: "Nearest dark area on the satellite light map (no name, no score, not checked on the ground): \(distance(offer.area.distanceMeters, system)) \(Compass.name(offer.bearing)) of \(origin) in a straight line, Bortle \(offer.area.bortle).")
    }
}
