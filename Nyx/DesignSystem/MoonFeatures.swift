import SwiftUI

/// The Moon's named maria and craters, bundled as `moon-features.json` from the IAU Gazetteer of
/// Planetary Nomenclature (USGS Astrogeology, public domain), placed on the drawn Moon by the Moon
/// shader's own transform (`Moon.metal`, run backwards), so a name sits on the texel its feature is
/// drawn at, with the night's tilt and libration. Names stay in the IAU's Latin, as on lunar maps.
nonisolated struct MoonFeatures: Sendable {
    nonisolated struct Feature: Codable, Sendable, Equatable, Identifiable {
        var id: String { name }
        let name: String
        /// mare, oceanus, sinus, lacus, crater, site.
        let kind: String
        /// Selenographic degrees, longitude east-positive.
        let lat: Double
        let lon: Double
        /// IAU diameter, km (0 for a landing site).
        let km: Double
        /// 1 always named, 2 on a mid-sized Moon, 3 only on a large one.
        let rank: Int
    }
    let features: [Feature]
    static let shared: MoonFeatures = load() ?? MoonFeatures(features: [])
    static func load(bundle: Bundle = .main) -> MoonFeatures? {
        guard let url = bundle.url(forResource: "moon-features", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let features: [Feature] }
        return (try? JSONDecoder().decode(File.self, from: data)).map { MoonFeatures(features: $0.features) }
    }

    /// A feature where it falls on the drawn disc: `x`, `y` from −1 to 1 (x right, y down), and
    /// whether the Sun lights it.
    struct Placed: Sendable, Equatable { let feature: Feature; let x: Double; let y: Double; let lit: Bool }
    /// The Moon shader's screen-to-Moon rotations inverted: Moon frame (longitude about +y from +z,
    /// latitude up +y), undo libration in longitude, then in latitude, then turn lunar north back to
    /// its angle from screen-up. On the near side (facing the viewer) only.
    static func place(_ feature: Feature, geometry: MoonGeometry) -> Placed? {
        let rad = Double.pi/180, phi = feature.lat*rad, lambda = feature.lon*rad
        let m3 = SIMD3(cos(phi)*sin(lambda), sin(phi), cos(phi)*cos(lambda))
        let cl = cos(geometry.librationLongitude), sl = sin(geometry.librationLongitude)
        let m2 = SIMD3(m3.x*cl - m3.z*sl, m3.y, m3.x*sl + m3.z*cl)
        let cb = cos(geometry.librationLatitude), sb = sin(geometry.librationLatitude)
        let m = SIMD3(m2.x, m2.y*cb - m2.z*sb, m2.y*sb + m2.z*cb)
        let c = cos(geometry.north), s = sin(geometry.north)
        let n = SIMD3(m.x*c - m.y*s, m.x*s + m.y*c, m.z)
        // Within about 8° of the limb a name would hang off the disc and the feature is foreshortened to a line.
        guard n.z > 0.14 else { return nil }
        let sun = MoonShading.sunDirection(geometry)
        let lit = n.x*sun.x + n.y*sun.y + n.z*sun.z > 0.05
        return Placed(feature: feature, x: n.x, y: -n.y, lit: lit)
    }
    /// The ranks a Moon this many points across can carry without crowding.
    static func ranks(side: Double) -> Int { side >= 360 ? 3 : side >= 240 ? 2 : side >= 160 ? 1 : 0 }
    /// The named features in sunlight on a Moon of `side` points, largest first.
    func lit(geometry: MoonGeometry, side: Double) -> [Placed] {
        let most = Self.ranks(side: side)
        return features.filter { $0.rank <= most }.compactMap { Self.place($0, geometry: geometry) }.filter(\.lit)
            .sorted { ($0.feature.rank, -$0.feature.km) < ($1.feature.rank, -$1.feature.km) }
    }
    /// For VoiceOver: "Named in sunlight: Mare Tranquillitatis, Tycho, …", or nil with none.
    func spoken(geometry: MoonGeometry, side: Double) -> String? {
        let names = lit(geometry: geometry, side: side).map(\.feature.name)
        return names.isEmpty ? nil : String(localized: "Named in sunlight: \(names.formatted(.list(type: .and))).")
    }
}

/// The named features in sunlight, written over a Moon drawn `side` points across: a hairline tick
/// on the feature and its name beside it, in small type, larger features first, each label kept
/// clear of those already placed (a name that would overlap is left out). Decorative: VoiceOver
/// reads `MoonFeatures.spoken` from the Moon's own element instead.
struct MoonLabels: View {
    let geometry: MoonGeometry
    let side: Double
    var ink: Color
    var features: MoonFeatures = .shared
    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height)/2, centre = CGPoint(x: size.width/2, y: size.height/2)
            var taken: [CGRect] = []
            for placed in features.lit(geometry: geometry, side: side) {
                let point = CGPoint(x: centre.x+placed.x*radius, y: centre.y+placed.y*radius)
                let text = context.resolve(Text(verbatim: placed.feature.name).font(.system(size: max(9, min(12, side/30)), weight: .medium)).foregroundStyle(ink))
                let measured = text.measure(in: CGSize(width: radius, height: 40))
                // Beside the tick, toward the disc's centre so names stay on the Moon.
                let left = point.x > centre.x
                let origin = CGPoint(x: left ? point.x-5-measured.width : point.x+5, y: point.y-measured.height/2)
                let rect = CGRect(origin: origin, size: measured).insetBy(dx: -2, dy: -1)
                guard rect.minX >= 0, rect.maxX <= size.width, !taken.contains(where: { $0.intersects(rect) }) else { continue }
                taken.append(rect)
                var tick = Path(); tick.addEllipse(in: CGRect(x: point.x-1.5, y: point.y-1.5, width: 3, height: 3))
                // A soft dark halo under each name, so it reads over bright maria and highlands alike.
                var haloed = context
                haloed.addFilter(.shadow(color: .black.opacity(0.95), radius: 2.5))
                haloed.addFilter(.shadow(color: .black.opacity(0.8), radius: 1))
                haloed.fill(tick, with: .color(ink))
                haloed.draw(text, at: origin, anchor: .topLeading)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// The iPhone's `MoonView`; Vision Pro has its own (`VisionMoon`), previewed in its window.
#if os(iOS)
#Preview("Moon names · waxing gibbous, 280 pt") {
    let geometry=MoonGeometry(phaseAngle: 0.9, brightLimb: -1.4, north: 0.2, librationLongitude: 0.05, librationLatitude: -0.04)
    MoonView(geometry: geometry).overlay { MoonLabels(geometry: geometry, side: 280, ink: NyxPalette.starlight) }
        .frame(width: 280, height: 280).padding().background(.black)
}
#Preview("Moon names · crescent, 400 pt") {
    let geometry=MoonGeometry(phaseAngle: 2.2, brightLimb: 1.3, north: -0.3, librationLongitude: -0.08, librationLatitude: 0.06)
    MoonView(geometry: geometry).overlay { MoonLabels(geometry: geometry, side: 400, ink: NyxPalette.starlight) }
        .frame(width: 400, height: 400).padding().background(.black)
}
#endif
