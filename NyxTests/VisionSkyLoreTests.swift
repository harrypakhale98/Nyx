import Foundation
import Testing
@testable import Nyx

/// The star names and constellation figures (`Nyx/Resources`) that the Vision Pro sky and Tonight's
/// sky share, checked against the star catalogue both draw (`Nyx/Resources/stars.json`). The files
/// are read from the source tree, independent of either target's loader. The matching rule
/// is written out again here on purpose, so a mistake in `SkyLore` cannot hide itself.
/// No wrong name may ship: every name must land on a catalogue star within 0.2° and 0.3 magnitudes.
struct VisionSkyLoreTests {
    struct Names: Decodable {
        struct Entry: Decodable { let name: String; let designation: String; let constellation: String; let ra: Double; let dec: Double; let mag: Double }
        let stars: [Entry]
    }
    struct Figures: Decodable {
        struct Figure: Decodable { let abbr: String; let name: String; let lines: [[String]] }
        struct Position: Decodable { let ra: Double; let dec: Double; let mag: Double }
        let names: [String: String]
        let figures: [Figure]
        let stars: [String: Position]
    }
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static func load<T: Decodable>(_ path: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: root.appending(path: path)))
    }
    static func catalogue() throws -> [[Double]] { try load("Nyx/Resources/stars.json", as: [[Double]].self) }

    static func separation(_ ra1: Double, _ dec1: Double, _ ra2: Double, _ dec2: Double) -> Double {
        let r = Double.pi/180
        return acos(max(-1, min(1, sin(dec1*r)*sin(dec2*r)+cos(dec1*r)*cos(dec2*r)*cos((ra1-ra2)*r))))/r
    }
    /// The brightest row within 0.2° and 0.3 magnitudes, as the sky picks it.
    static func row(ra: Double, dec: Double, mag: Double, in rows: [[Double]]) -> Int? {
        rows.indices.filter { separation(ra, dec, rows[$0][0], rows[$0][1]) <= 0.2 && abs(rows[$0][2]-mag) <= 0.3 }.min { rows[$0][2] < rows[$1][2] }
    }
    static let greek = ["α": "Alp", "β": "Bet", "γ": "Gam", "δ": "Del", "ε": "Eps", "ζ": "Zet", "η": "Eta", "θ": "The", "ι": "Iot", "κ": "Kap", "λ": "Lam",
                        "μ": "Mu", "ν": "Nu", "ξ": "Xi", "ο": "Omi", "π": "Pi", "ρ": "Rho", "σ": "Sig", "τ": "Tau", "υ": "Ups", "φ": "Phi", "χ": "Chi", "ψ": "Psi", "ω": "Ome"]

    @Test func everyNamedStarIsTheCatalogueStarItNames() throws {
        let rows = try Self.catalogue(), names = try Self.load("Nyx/Resources/star-names.json", as: Names.self)
        #expect((60...70).contains(names.stars.count))
        #expect(Set(names.stars.map(\.name)).count == names.stars.count, "a name used twice")
        var used: [Int: String] = [:]
        for star in names.stars {
            let index = try #require(Self.row(ra: star.ra, dec: star.dec, mag: star.mag, in: rows), "\(star.name) matches no catalogue star")
            #expect(Self.separation(star.ra, star.dec, rows[index][0], rows[index][1]) < 0.2)
            #expect(abs(rows[index][2]-star.mag) < 0.3)
            #expect(used[index] == nil, "\(star.name) and \(used[index] ?? "") name the same point")
            used[index] = star.name
        }
        // The brightest point in the catalogue is Sirius, and the bright stars of each season are there.
        #expect(used[0] == "Sirius")
        for name in ["Vega", "Arcturus", "Betelgeuse", "Rigel", "Antares", "Polaris", "Deneb", "Altair", "Fomalhaut", "Capella"] {
            #expect(used.values.contains(name), "\(name) missing")
        }
    }

    @Test func everyFigureLineJoinsTwoCatalogueStars() throws {
        let rows = try Self.catalogue(), figures = try Self.load("Nyx/Resources/constellations.json", as: Figures.self)
        #expect((28...40).contains(figures.figures.count))
        var resolved: [String: Int] = [:]
        for (key, star) in figures.stars {
            let index = try #require(Self.row(ra: star.ra, dec: star.dec, mag: star.mag, in: rows), "\(key) matches no catalogue star")
            #expect(Self.separation(star.ra, star.dec, rows[index][0], rows[index][1]) < 0.2, "\(key)")
            #expect(abs(rows[index][2]-star.mag) < 0.3, "\(key)")
            resolved[key] = index
        }
        #expect(Set(resolved.values).count == resolved.count, "two designations on one star")
        for figure in figures.figures {
            #expect(figures.names[figure.abbr] == figure.name)
            #expect(!figure.lines.isEmpty)
            for line in figure.lines {
                #expect(line.count == 2 && line[0] != line[1])
                let a = try #require(resolved[line[0]], "\(figure.name): \(line[0]) not listed")
                let b = try #require(resolved[line[1]], "\(figure.name): \(line[1]) not listed")
                // A stick-figure line spans one constellation, never half the sky.
                let length = Self.separation(rows[a][0], rows[a][1], rows[b][0], rows[b][1])
                #expect(length > 0.5 && length < 35, "\(figure.name): \(line[0])–\(line[1]) is \(length)°")
            }
        }
    }

    /// Two independent sources must agree: a named star whose Bayer designation is also a figure
    /// star (IAU's Betelgeuse, the figures' "Alp Ori") lands on the same catalogue row.
    @Test func namesAndFiguresAgreeOnSharedStars() throws {
        let rows = try Self.catalogue()
        let names = try Self.load("Nyx/Resources/star-names.json", as: Names.self)
        let figures = try Self.load("Nyx/Resources/constellations.json", as: Figures.self)
        var checked = 0
        for star in names.stars {
            let parts = star.designation.split(separator: " ")
            guard parts.count == 2, let letter = parts[0].first.map(String.init), let abbr = Self.greek[letter] else { continue }
            let suffix = parts[0].dropFirst().map { ["¹": "1", "²": "2", "³": "3"][String($0)] ?? "" }.joined()
            guard let figureStar = figures.stars["\(abbr)\(suffix) \(parts[1])"] else { continue }
            #expect(parts[1] == star.constellation)
            #expect(Self.row(ra: star.ra, dec: star.dec, mag: star.mag, in: rows) == Self.row(ra: figureStar.ra, dec: figureStar.dec, mag: figureStar.mag, in: rows), "\(star.name)")
            checked += 1
        }
        #expect(checked >= 40)
        // Every named star's constellation has a name to show.
        for star in names.stars { #expect(figures.names[star.constellation] != nil, "\(star.name): \(star.constellation)") }
    }
}

/// Turning the Vision Pro sky by hand (`SkyDome.dragTarget`, `SkyDome.chaseStep`).
struct VisionSkyDragTests {
    let night = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 10*3600)

    @Test func aDragMovesTheClockAsFarAsTheSkyTurns() {
        // 15.04° is an hour of sky: a tenth of a ten-hour night.
        #expect(abs(SkyDome.dragTarget(from: 0.5, degrees: 15.04, southern: false, span: night)-0.6) < 1e-9)
        #expect(abs(SkyDome.dragTarget(from: 0.5, degrees: -15.04, southern: false, span: night)-0.4) < 1e-9)
        // Facing north from American Samoa, west is to the left: the same hand motion runs time back.
        #expect(abs(SkyDome.dragTarget(from: 0.5, degrees: 15.04, southern: true, span: night)-0.4) < 1e-9)
        #expect(SkyDome.dragTarget(from: 0.9, degrees: 90, southern: false, span: night) == 1)
        #expect(SkyDome.dragTarget(from: 0.1, degrees: -90, southern: false, span: night) == 0)
        #expect(SkyDome.dragTarget(from: 0.3, degrees: 40, southern: false, span: DateInterval(start: .now, duration: 0)) == 0.3)
        #expect(SkyDome.dragTarget(from: 0.3, degrees: .nan, southern: false, span: night) == 0.3)
    }

    @Test func theSkyNeverTurnsFasterThanTheComfortLimit() {
        let degreesPerNight = 10*15.04, limit = 20.0, tick = 0.011
        var fraction = 0.0, turned = 0.0
        // A flick across the whole night: one simulated second of following it.
        for _ in 0..<Int(1/tick) {
            let next = SkyDome.chaseStep(from: fraction, toward: 1, seconds: tick, degreesPerNight: degreesPerNight, limit: limit)
            #expect((next-fraction)*degreesPerNight <= limit*tick+1e-9)
            turned += (next-fraction)*degreesPerNight
            fraction = next
        }
        #expect(turned <= limit+1e-6 && turned > limit*0.95)
        // A small move is eased, not capped, and lands exactly.
        var small = 0.5
        for _ in 0..<200 { small = SkyDome.chaseStep(from: small, toward: 0.502, seconds: tick, degreesPerNight: degreesPerNight, limit: limit) }
        #expect(small == 0.502)
        // No time passed, no turn; no night to turn through, straight there.
        #expect(SkyDome.chaseStep(from: 0.2, toward: 0.8, seconds: 0, degreesPerNight: degreesPerNight, limit: limit) == 0.2)
        #expect(SkyDome.chaseStep(from: 0.2, toward: 0.8, seconds: tick, degreesPerNight: 0, limit: limit) == 0.8)
    }
}
