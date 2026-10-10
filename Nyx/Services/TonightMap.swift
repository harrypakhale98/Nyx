import Foundation
import CoreGraphics

/// Tonight across the country: each park's night as a mark at its place on the `SkyMap` canvas
/// (the US outline the constellation uses, with insets for Alaska, Hawaiʻi, American Samoa and
/// the Virgin Islands). Marks follow the calendar's night cells exactly: size by score on the
/// same curve, fill by what the clouds rest on, a star for Excellent and Pristine under
/// Differentiate Without Color. Pure, so the order and the look are tested without a screen.
nonisolated struct TonightMap: Sendable {
    struct Mark: Identifiable, Sendable {
        let id: String
        let name: String
        /// Canvas units, as `SkyMap.position`.
        let point: CGPoint
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
    /// Geographic reading order: the lower 48 from west to east, then the insets in the order
    /// they sit on the map (Alaska, Hawaiʻi, American Samoa, the Virgin Islands), each west to east.
    let marks: [Mark]
    /// The same marks ranked as every list ranks nights: score, then the darker measured sky.
    let darkest: [Mark]

    init(nights: [Night], closures: [String: String] = [:]) {
        let built=nights.map { night in
            let park=night.park, closure=closures[park.id]
            var parts=[String(localized:"\(park.shortName), \(night.score.value), \(night.score.band.label)")]
            if let basis=night.basisLabel { parts.append(basis) }
            if let closure { parts.append(String(localized:"Closure: \(closure)")) }
            return (night,Mark(id:park.id,name:park.shortName,point:SkyMap.position(park),region:SkyMap.region(park),score:night.score.value,
                               band:night.score.band,fill:night.basis.fill,closure:closure,label:parts.joined(separator:". ")))
        }
        marks=Self.geographic(built.map(\.1),longitude:Dictionary(nights.map { ($0.park.id,$0.park.longitude) },uniquingKeysWith:{ a,_ in a }))
        darkest=built.sorted { NightPlanner.better($0.0,$1.0) }.map(\.1)
    }
    static func geographic(_ marks: [Mark], longitude: [String: Double]) -> [Mark] {
        let regions=SkyMap.Region.allCases
        return marks.sorted { a,b in
            let ra=regions.firstIndex(of:a.region) ?? 0, rb=regions.firstIndex(of:b.region) ?? 0
            if ra != rb { return ra<rb }
            let la=longitude[a.id] ?? 0, lb=longitude[b.id] ?? 0
            return la != lb ? la<lb : a.name<b.name
        }
    }
    /// The parks named on the map itself: the darkest few, so the picture reads at a glance and
    /// labels never pile up. Everything else is named on selection and to VoiceOver.
    func labelled(_ count: Int = 3) -> [Mark] { Array(darkest.prefix(count)) }
    /// One sentence for the whole map: how many parks, and the darkest tonight.
    var summary: String {
        guard let best=darkest.first else { return String(localized:"No parks to show.") }
        let closed=marks.filter { $0.closure != nil }.count
        var line=String(localized:"Map of \(marks.count) national parks by tonight's score. Darkest: \(best.name), \(best.score), \(best.band.label).")
        if closed>0 { line+=" "+String(localized:"\(closed) parks have a closure.") }
        return line
    }
    /// The night cell's curve, so a 95 reads clearly larger than a 70.
    static func radius(score: Int) -> Double { 1.5+8*pow(Double(min(100,max(0,score)))/100,1.5) }
    static func fillOpacity(score: Int) -> Double { NyxPalette.markRamp(score:score) }
}
