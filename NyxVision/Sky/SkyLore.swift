import Foundation

/// Names and figures for the immersive sky: the IAU's proper names for the brightest stars
/// (`star-names.json`, from the Working Group on Star Names) and constellation stick figures
/// drawn for Nyx between catalogue stars (`constellations.json`, keyed by Bayer designation).
///
/// Neither file holds catalogue row numbers. Each star is matched to the brightest row of the
/// star catalogue within 0.2° of its J2000 position and 0.3 magnitudes of its brightness, so a
/// star that does not match is left out rather than misnamed. `NyxTests` checks that every entry
/// matches today, so the sky never shows a wrong name.
nonisolated struct SkyLore: Sendable {
    struct Star: Sendable, Identifiable {
        /// "star.Vega": the id after "body:" on its sky entity and in `VisionModel.selectedBody`.
        var id: String { "star.\(name)" }
        let name: String
        /// "α Lyr", as written on star charts.
        let designation: String
        /// The constellation's name, localized ("Lyra").
        let constellation: String
        let magnitude: Double
        /// The matching catalogue row.
        let row: Int
    }
    let stars: [Star]
    /// Each figure's lines as pairs of catalogue rows.
    let figures: [(name: String, lines: [(Int, Int)])]
    var lines: [(Int, Int)] { figures.flatMap(\.lines) }

    static let empty = SkyLore(stars: [], figures: [])
    /// How far a listed position may sit from its catalogue row, in degrees, and how far apart
    /// their magnitudes may be.
    static let tolerance = 0.2, magnitudeTolerance = 0.3

    // MARK: Files

    struct NamesFile: Decodable {
        struct Entry: Decodable { let name: String; let designation: String; let constellation: String; let ra: Double; let dec: Double; let mag: Double }
        let stars: [Entry]
    }
    struct FiguresFile: Decodable {
        struct Figure: Decodable { let abbr: String; let name: String; let lines: [[String]] }
        struct Position: Decodable { let ra: Double; let dec: Double; let mag: Double }
        let names: [String: String]
        let figures: [Figure]
        let stars: [String: Position]
    }

    /// Loads both files and matches them to the catalogue. Missing or unreadable files give an
    /// empty lore: the sky still works, unnamed.
    static func load(catalogue: [SkyScene.CatalogueStar], bundle: Bundle = .main) -> SkyLore {
        let decoder = JSONDecoder()
        guard let namesURL = bundle.url(forResource: "star-names", withExtension: "json"),
              let figuresURL = bundle.url(forResource: "constellations", withExtension: "json"),
              let namesData = try? Data(contentsOf: namesURL), let figuresData = try? Data(contentsOf: figuresURL),
              let names = try? decoder.decode(NamesFile.self, from: namesData),
              let figures = try? decoder.decode(FiguresFile.self, from: figuresData) else { return .empty }
        let positions = catalogue.map { (ra: $0.ra*180/Double.pi, dec: $0.dec*180/Double.pi, mag: $0.mag) }
        func constellation(_ abbr: String) -> String {
            // Localized by key, with the bundled English as the fallback (as shower names are).
            Bundle.main.localizedString(forKey: "constellation.\(abbr)", value: figures.names[abbr] ?? abbr, table: nil)
        }
        let stars: [Star] = names.stars.compactMap { entry in
            match(ra: entry.ra, dec: entry.dec, mag: entry.mag, in: positions).map {
                Star(name: entry.name, designation: entry.designation, constellation: constellation(entry.constellation), magnitude: entry.mag, row: $0)
            }
        }
        var rows: [String: Int] = [:]
        for (key, p) in figures.stars { rows[key] = match(ra: p.ra, dec: p.dec, mag: p.mag, in: positions) }
        let drawn = figures.figures.map { figure in
            (name: constellation(figure.abbr), lines: figure.lines.compactMap { pair -> (Int, Int)? in
                guard pair.count == 2, let a = rows[pair[0]], let b = rows[pair[1]], a != b else { return nil }
                return (a, b)
            })
        }
        return SkyLore(stars: stars, figures: drawn)
    }

    /// The brightest catalogue row within the tolerances of a position (degrees) and magnitude.
    static func match(ra: Double, dec: Double, mag: Double, in catalogue: [(ra: Double, dec: Double, mag: Double)]) -> Int? {
        var best: Int?
        for (i, row) in catalogue.enumerated() where abs(row.dec-dec) <= tolerance && abs(row.mag-mag) <= magnitudeTolerance {
            guard separation(ra, dec, row.ra, row.dec) <= tolerance else { continue }
            if best.map({ catalogue[$0].mag > row.mag }) ?? true { best = i }
        }
        return best
    }
    /// Angular separation in degrees.
    static func separation(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
        let r = Double.pi/180
        let c = sin(dec1*r)*sin(dec2*r) + cos(dec1*r)*cos(dec2*r)*cos((ra1-ra2)*r)
        return acos(max(-1, min(1, c)))/r
    }

    // MARK: Words

    /// Where to look, in words: "high in the west", "low in the northeast", "nearly overhead".
    static func direction(altitude: Double, azimuth: Double) -> String {
        if altitude >= 75 { return String(localized: "nearly overhead") }
        let compass = Compass.name(azimuth)
        return altitude >= 30 ? String(localized: "high in the \(compass)") : altitude < 15 ? String(localized: "low in the \(compass)") : String(localized: "in the \(compass)")
    }
    /// A star's brightness in words, for the name card.
    static func brightness(_ magnitude: Double) -> String {
        magnitude < 0.5 ? String(localized: "one of the brightest stars")
            : magnitude < 1.5 ? String(localized: "a bright star")
            : magnitude < 2.5 ? String(localized: "easy to see")
            : String(localized: "easy to see from a dark site")
    }
}
