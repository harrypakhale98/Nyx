import Foundation

/// The naked-eye and binocular deep-sky objects of both hemispheres, bundled as `deep-sky.json`:
/// positions and magnitudes from Wikidata (CC0), checked against SIMBAD, the Harris globular cluster
/// catalogue and the SEDS Messier pages; the darkest Bortle class each is a fair naked-eye target at,
/// where J. E. Bortle (Sky & Telescope, 2001) names one. Telescope-only objects are in the file but
/// never offered.
nonisolated struct DeepSky: Sendable {
    nonisolated struct Object: Codable, Sendable, Identifiable, Equatable {
        let id: String
        var name: String?=nil
        /// galaxy, globular, openCluster, nebula, darkNebula, cloud.
        let kind: String
        /// J2000, degrees.
        let ra: Double
        let dec: Double
        /// Visual magnitude, when two sources agree on one.
        var mag: Double?=nil
        /// Major axis, arcminutes.
        var size: Double?=nil
        /// naked, binoculars, telescope.
        let eye: String
        /// The brightest sky (Bortle class) it is still a fair naked-eye target under, where Bortle names one.
        var bortle: Int?=nil
        /// Diffuse light (galaxies, nebulae, star clouds) fades into a bright sky; star clusters hold up.
        var diffuse: Bool { ["galaxy", "nebula", "darkNebula", "cloud"].contains(kind) }
        /// The name in the reader's language (catalog key `dso.<id>`), else the bundled English
        /// without its qualifier; the designation for an object with no common name.
        var localizedName: String? {
            name.map { Bundle.main.localizedString(forKey: "dso.\(id)", value: $0.components(separatedBy: " (").first ?? $0, table: nil) }
        }
        /// "Andromeda Galaxy (M31)", or "M3" alone.
        var label: String { localizedName.map { "\($0) (\(id))" } ?? id }
    }
    let objects: [Object]
    static let shared: DeepSky = load() ?? DeepSky(objects: [])
    /// Nil where the file is not bundled (the widgets, which never show What's up in full).
    static func load(bundle: Bundle = .main) -> DeepSky? {
        guard let url = bundle.url(forResource: "deep-sky", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let objects: [Object] }
        return (try? JSONDecoder().decode(File.self, from: data)).map { DeepSky(objects: $0.objects) }
    }

    /// One object at its best moment tonight.
    struct Sight: Sendable, Equatable {
        let object: Object
        let at: Date
        let altitude: Double
        let azimuth: Double
        /// A fair naked-eye target here tonight: Bortle's class for it (4 where he names none) or
        /// darker, and the Moon down.
        let toTheEye: Bool
    }
    /// High enough to clear haze and the horizon's glow.
    static let minimumAltitude = 30.0
    /// Up to `limit` objects best placed in true darkness, one of each kind before a second of any:
    /// each at its highest moment with the Moon down (else its highest at all), at least 30° up.
    /// Diffuse objects fainter than magnitude 4 need a Bortle 4 sky or darker and the Moon down;
    /// under a Moon more than a quarter lit only objects brighter than magnitude 4 (clusters 5.5)
    /// are offered; star clusters need Bortle 7 or darker. Two objects with the same name (the
    /// Double Cluster's halves) count once. Nothing without true darkness.
    func sights(park: Park, sky: SkyConditions, limit: Int = 3, engine: AstronomyEngine = AstronomyEngine()) -> [Sight] {
        guard let start = sky.darkStart, let end = sky.darkEnd, end > start else { return [] }
        let rad = Double.pi/180, bortle = park.bortleEstimate
        var times: [Date] = []
        var t = start
        while t <= end { times.append(t); t = t.addingTimeInterval(1200) }
        let moonUp = times.map { sky.moon.illumination >= 0.25 && engine.lunarAltitude(at: $0, park: park) > 0 }
        var found: [Sight] = []
        for object in objects where object.eye != "telescope" {
            let magnitude = object.mag ?? 4.5
            if object.diffuse, magnitude > 4, bortle > 4 { continue }
            if !object.diffuse, bortle > 7 { continue }
            var best: (Int, Double, Double)?, bestDark: (Int, Double, Double)?
            for (i, time) in times.enumerated() {
                let p = engine.horizontal(date: time, park: park, ra: object.ra*rad, dec: object.dec*rad)
                guard p.altitude >= Self.minimumAltitude else { continue }
                if p.altitude > (best?.1 ?? -90) { best = (i, p.altitude, p.azimuth) }
                if !moonUp[i], p.altitude > (bestDark?.1 ?? -90) { bestDark = (i, p.altitude, p.azimuth) }
            }
            guard let chosen = bestDark ?? best else { continue }
            let moonlit = moonUp[chosen.0]
            if moonlit, magnitude > (object.diffuse ? 4 : 5.5) { continue }
            let eye = object.eye == "naked" && !moonlit && bortle <= (object.bortle ?? 4)
            found.append(Sight(object: object, at: times[chosen.0], altitude: chosen.1, azimuth: chosen.2, toTheEye: eye))
        }
        // Best placed first; then one of each kind, then the rest, each name once.
        let ordered = found.sorted { ($0.altitude, $1.object.id) > ($1.altitude, $0.object.id) }
        var picked: [Sight] = [], kinds = Set<String>(), names = Set<String>()
        for pass in 0..<2 {
            for sight in ordered where picked.count < limit && !picked.contains(sight) {
                let name = sight.object.localizedName ?? sight.object.id
                guard !names.contains(name), pass == 1 || !kinds.contains(sight.object.kind) else { continue }
                picked.append(sight); kinds.insert(sight.object.kind); names.insert(name)
            }
        }
        return picked
    }
}
