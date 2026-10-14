import Foundation
import CoreGraphics

/// Tonight on the map: each place's night as a mark at its true place on a `MapFrame` (the world's
/// land under it, `WorldLand`). Marks follow the calendar's night cells exactly: size by score on
/// the same curve, fill by what the clouds rest on, a star for Excellent and Pristine under
/// Differentiate Without Color. Pure, so the order and the look are tested without a screen.
nonisolated struct TonightMap: Sendable {
    struct Mark: Identifiable, Sendable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        /// Canvas units on the map's frame.
        let point: CGPoint
        /// The US area the place lies in (`SkyMap.region(of:)`), `.world` elsewhere: the reading order's first key.
        let region: SkyMap.Region
        let score: Int
        let band: ScoreBand
        let fill: NightFill
        /// The park's closure from the last park update, if any.
        let closure: String?
        /// "Death Valley, 97, Pristine", then the cloud basis and any closure.
        let label: String
        /// The dot's radius in points before any scale, the night cell's own curve.
        var radius: Double { TonightMap.radius(score:score) }
    }
    /// The map the marks sit on.
    let frame: MapFrame
    /// Geographic reading order: the five US areas in turn (lower 48, Alaska, Hawaiʻi, American
    /// Samoa, the Virgin Islands), each west to east, then everywhere else west to east.
    let marks: [Mark]
    /// The same marks ranked as every list ranks nights: score, then the darker measured sky.
    let darkest: [Mark]
    /// How many places lay in view before a crowded map was thinned (`SkyMap.shown`).
    let inView: Int
    /// Each mark's turn in the reveal, 0…1: west to east across the map as drawn.
    let reveal: [String: Double]

    /// `frame`: the map (the lower 48 unless given). A place the projection cannot draw (Lambert's
    /// antipode) is left out.
    init(nights: [Night], closures: [String: String] = [:], frame: MapFrame = SkyMap.lower48, inView: Int? = nil) {
        self.frame=frame
        let built=nights.compactMap { night -> (Night,Mark)? in
            let park=night.park, closure=closures[park.id]
            guard let point=frame.point(park) else { return nil }
            var parts=[String(localized:"\(park.shortName), \(night.score.value), \(night.score.band.label)")]
            parts+=night.basisLabels
            if let closure { parts.append(String(localized:"Closure: \(closure)")) }
            return (night,Mark(id:park.id,name:park.shortName,latitude:park.latitude,longitude:park.longitude,point:point,region:SkyMap.region(park) ?? .world,
                               score:night.score.value,band:night.score.band,fill:night.basis.fill,closure:closure,label:parts.joined(separator:". ")))
        }
        marks=Self.geographic(built.map(\.1))
        darkest=built.sorted { NightPlanner.better($0.0,$1.0) }.map(\.1)
        self.inView=max(inView ?? built.count,built.count)
        let across=built.map(\.1).sorted { $0.point.x != $1.point.x ? $0.point.x<$1.point.x : $0.id<$1.id }
        let count=Double(max(1,across.count))
        reveal=Dictionary(across.enumerated().map { ($1.id,Double($0)/count) },uniquingKeysWith:{ a,_ in a })
    }
    static func geographic(_ marks: [Mark]) -> [Mark] {
        let regions=SkyMap.Region.unitedStates
        func rank(_ mark: Mark) -> Int { regions.firstIndex(of:mark.region) ?? regions.count }
        return marks.sorted { a,b in
            let ra=rank(a), rb=rank(b)
            if ra != rb { return ra<rb }
            return a.longitude != b.longitude ? a.longitude<b.longitude : a.name<b.name
        }
    }
    /// The parks named on the map itself: the darkest few, so the picture reads at a glance and
    /// labels never pile up. Everything else is named on selection and to VoiceOver.
    func labelled(_ count: Int = 3) -> [Mark] { Array(darkest.prefix(count)) }
    /// One sentence for the whole map: how many places, the darkest tonight, closures, and how many
    /// more lie in view when a crowded map shows only the darkest of each crowd.
    var summary: String {
        guard let best=darkest.first else { return String(localized:"No parks to show.") }
        let closed=marks.filter { $0.closure != nil }.count
        var line=String(localized:"Map of \(marks.count) places by tonight's score. Darkest: \(best.name), \(best.score), \(best.band.label).")
        if closed>0 { line+=" "+String(localized:"\(closed) parks have a closure.") }
        if inView>marks.count { line+=" "+String(localized:"Showing \(marks.count) of \(inView) places in view, the darkest where they crowd together.") }
        return line
    }
    /// The night cell's curve, so a 95 reads clearly larger than a 70.
    static func radius(score: Int) -> Double { 1.5+8*pow(Double(min(100,max(0,score)))/100,1.5) }
    static func fillOpacity(score: Int) -> Double { NyxPalette.markRamp(score:score) }
}
