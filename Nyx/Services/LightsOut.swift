import Foundation

/// "With the lights out": for someone starting from a town or from where they are, the same sky
/// drawn at the starting point's estimated class and then at the darkest place within reach, with
/// that place's distance and its best night soon. The light at the start comes from the satellite
/// grid (or, without it, an assumed suburban Bortle 7, said as such); the place's is its own estimate.
nonisolated enum LightsOut {
    struct Target: Sendable {
        let place: Park
        let meters: Double
        /// The starting point's class, and whether it is the grid's estimate or the assumed suburban sky.
        let homeClass: Int
        let homeKnown: Bool
        /// The place's best night in the next `horizon` nights, when one is worth naming.
        var best: Night?=nil
    }
    /// Only where the difference is plain to see: two classes or more.
    static let difference=2
    /// The nights looked at for the best one soon.
    static let horizon=14
    /// The starting point's class: the sky grid's estimate where it has one, else a suburban sky.
    static func homeClass(latitude: Double, longitude: Double, grid: SkyGrid = .shared) -> (bortle: Int, known: Bool) {
        guard let magnitude=grid.skyBrightness(latitude:latitude,longitude:longitude) else { return (HomeSky.assumedBortle,false) }
        return (SkyGrid.bortle(fromMagnitude:magnitude),true)
    }
    /// The darkest place in reach (the lowest estimate), the nearer of equals, then by id; nil unless
    /// it is at least `difference` classes darker than the start.
    static func darkest(_ places: [Park], latitude: Double, longitude: Double, homeClass: Int) -> (place: Park, meters: Double)? {
        let ranked=places.map { ($0,$0.distanceMeters(latitude:latitude,longitude:longitude)) }.min { a, b in
            if a.0.bortleEstimate != b.0.bortleEstimate { return a.0.bortleEstimate<b.0.bortleEstimate }
            if a.1 != b.1 { return a.1<b.1 }
            return a.0.id<b.0.id
        }
        guard let ranked, ranked.0.bortleEstimate<=homeClass-difference else { return nil }
        return (ranked.0,ranked.1)
    }
    /// The best of the coming nights, ranked as everywhere a best night is chosen (a closure counts against it).
    static func best(_ nights: [Night], closure: String?) -> Night? {
        let closures=closure.map { [nights.first?.park.id ?? "": $0] } ?? [:]
        return nights.min { NightPlanner.better($0,$1,closures:closures) }
    }
    /// "That's the sky at Great Basin, 160 mi away."
    static func sentence(_ target: Target) -> String {
        String(localized:"That's the sky at \(target.place.shortName), \(DarkerSky.distance(target.meters)) away.")
    }
    /// "Best night at Great Basin in the next two weeks: Sat, Oct 31, 88." Names the place, so it
    /// reads on its own before the sky has cleared.
    static func bestLine(_ night: Night) -> String {
        String(localized:"Best night at \(night.park.shortName) in the next two weeks: \(night.park.dayLabel(night.id)), \(night.score.value).")
    }
    /// The figure for VoiceOver: what is drawn, both classes, and what the dark sky shows.
    static func spoken(_ target: Target, origin: String) -> String {
        let home=target.homeKnown ? String(localized:"the sky over \(origin) at its estimated Class \(target.homeClass)")
                                  : String(localized:"a suburban sky, Class \(target.homeClass), as Nyx assumes for \(origin)")
        return String(localized:"Illustration: \(home), then the same sky at \(target.place.shortName)'s Class \(target.place.bortleEstimate). With the lights out, the Milky Way and many fainter stars appear.")
    }
}
