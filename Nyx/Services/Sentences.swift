import Foundation

/// Whole sentences set one after another for display. English, German, Spanish and French part
/// them with a space; Japanese runs them together, since "。" already ends the sentence and a
/// space after it shows as a gap. Words and tokens that are not sentences keep their own joins.
nonisolated enum Sentences {
    /// The app's language, as `Lettering` reads it.
    static var language: String { Bundle.main.preferredLocalizations.first ?? "en" }

    static func join(_ parts: [String]) -> String { join(parts, language: language) }

    static func end(_ text: String) -> String { end(text, language: language) }

    /// A phrase closed as a sentence, unless it already is: "。" in Japanese, after Japanese text or a
    /// figure ("82%"); "." after a Latin letter (an English closure headline) and in every other language.
    static func end(_ text: String, language: String) -> String {
        guard let last=text.last, !".!?…。！？".contains(last) else { return text }
        let latin=last.isASCII && last.isLetter
        return language.hasPrefix("ja") && !latin ? text+"。" : text+"."
    }

    /// Empty parts are dropped. In Japanese no space follows a sentence that ends in a Japanese
    /// character or full-width mark; one that ends in plain ASCII (a closure headline from the
    /// Park Service, a figure) keeps its space so the next sentence does not stick to it.
    static func join(_ parts: [String], language: String) -> String {
        let kept=parts.filter { !$0.isEmpty }
        guard language.hasPrefix("ja") else { return kept.joined(separator:" ") }
        var out=""
        for part in kept {
            if let last=out.unicodeScalars.last, last.isASCII { out+=" " }
            out+=part
        }
        return out
    }
}

/// The closure beside a score, said one way on every device: the iPhone and its widgets and Siri,
/// Apple Watch and its faces, and Vision Pro. A long drive to a closed road is the worst outcome
/// Nyx can cause, so a closure is said first and never dropped for room.
nonisolated enum ClosureLine {
    /// The warning glyph beside a closure, wherever one is drawn.
    static let symbol = "exclamationmark.triangle.fill"
    /// "Closure alert: Kolob Canyons Road closed"
    static func spoken(_ closure: String) -> String { String(localized: "Closure alert: \(closure)") }
    /// "Closure alert: …." before an answer about a park, when it has one. An NPS headline usually
    /// ends without a full stop; one is added so the score reads as its own sentence.
    static func first(_ body: String, closure: String?) -> String {
        guard let closure=closure?.trimmingCharacters(in: .whitespacesAndNewlines), !closure.isEmpty else { return body }
        return Sentences.join([Sentences.end(spoken(closure)), body])
    }
    /// "94 · Keys View Road closed at night", for one short line: the park's own words, cut by the line
    /// if they must be, never a bare "Closure alert", which reads as the whole park closed when a road is.
    static func inline(score: Int, closure: String) -> String { String(localized: "\(score) · \(closure)") }
    /// Where the Park Service has no alerts Nyx cannot know the closures, and says so rather than let
    /// silence read as "nothing is closed": a place abroad points to its own site, a saved spot to
    /// local checks. Nil for a national park.
    static func unknown(_ park: Park) -> String? {
        guard park.nps == nil else { return nil }
        return park.isCatalogPlace ? String(localized: "Nyx can't check closures here. Check the park's own site before you go.")
            : String(localized: "Nyx has no alerts for this place. Check access, local rules and closures before you go.")
    }
}

/// What a score leaves out and why, one set of words on every device: the iPhone and Vision Pro
/// (`ScoreInputs`) and the watch (`WatchContext`), so silence never reads as "nothing closed" or
/// "clear air" on one of them.
nonisolated enum MissingInput {
    static var alertsOff: String { String(localized: "Park alerts are off in Your privacy, so closures are not checked.") }
    /// No park update covers the park yet: the Park Service refusing requests, or nothing fetched.
    static func unchecked(busy: Bool) -> String {
        busy ? String(localized: "Park alerts are busy. Check current conditions on nps.gov.") : String(localized: "Access not checked. Confirm closures with the park.")
    }
    static var smokeOff: String { String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.") }
    static var noSmokeYet: String { String(localized: "No smoke forecast on this device yet, so smoke is not counted.") }
    static var smokeShort: String { String(localized: "No smoke forecast on this device reaches this night, so smoke is not counted.") }
    /// Why smoke is not in a night's score; nil when it is. `counted`: whether the night's score
    /// counts an aerosol forecast (`Night.aerosol`), nil without the night. A forecast that ends
    /// before the night is said too, never passed off as clear air.
    static func smoke(on: Bool, known: Bool, counted: Bool?) -> String? {
        if !on { return smokeOff }
        guard known else { return noSmokeYet }
        return counted == false ? smokeShort : nil
    }
}

/// The sky's state by the Sun's altitude, one set of words on every device (Tonight's sky on iPhone
/// and iPad, Vision Pro's sky): "Twilight", "Late twilight", "Nearly dark", "True darkness".
nonisolated enum SkyPhase {
    /// `sunAltitude` in degrees, refraction included; "The Sun is up" above the horizon.
    static func name(sunAltitude: Double) -> String {
        if sunAltitude > -0.833 { return String(localized: "The Sun is up") }
        if sunAltitude > -6 { return String(localized: "Twilight") }
        if sunAltitude > -12 { return String(localized: "Late twilight") }
        if sunAltitude > -18 { return String(localized: "Nearly dark") }
        return String(localized: "True darkness")
    }
}

/// Every source Nyx draws on, credited in the words each asks for, in one list for every device:
/// Settings › Credits on iPhone and iPad, Credits on Apple Watch and on Vision Pro. Each device
/// lists the sources something on it rests on; a licence that asks to be named (CC BY) is named in
/// the line itself, so no device can shorten it away.
nonisolated enum Credits {
    struct Device: OptionSet, Sendable {
        let rawValue: Int
        static let phone = Device(rawValue: 1), watch = Device(rawValue: 2), vision = Device(rawValue: 4)
        static let all: Device = [.phone, .watch, .vision]
    }
    struct Line: Sendable {
        let text: String
        let devices: Device
    }
    enum Section: CaseIterable, Sendable {
        case weather, sky, places
        var title: String {
            switch self {
            case .weather: String(localized: "Weather and air")
            case .sky: String(localized: "Sky and light")
            case .places: String(localized: "Parks and places")
            }
        }
        /// Every device's lines; `lines(for:)` keeps one device's.
        var lines: [Line] {
            switch self {
            case .weather: [
                // The iPhone links its own "Weather data by Open-Meteo.com" row to open-meteo.com, as the licence asks.
                Line(text: String(localized: "Weather data by Open-Meteo.com (CC BY 4.0), as averaged by Nyx."), devices: [.watch, .vision]),
                Line(text: String(localized: "Cloud forecasts and the three forecast models: Open-Meteo, CC BY 4.0."), devices: .all),
                Line(text: String(localized: "Smoke and haze: contains modified Copernicus Atmosphere Monitoring Service information (2026), via Open-Meteo."), devices: .all),
                Line(text: String(localized: "Usual clouds: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024, Hersbach et al. 2020, CC BY 4.0."), devices: .all),
                Line(text: String(localized: "Usual night temperatures: contains modified Copernicus Climate Change Service information (2026): ERA5, 2015 to 2024, CC BY 4.0."), devices: [.phone, .vision]),
                Line(text: String(localized: "Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains."), devices: .all),
            ]
            case .sky: [
                Line(text: String(localized: "The Moon: NASA's Scientific Visualization Studio, CGI Moon Kit, with the LRO LROC (Hapke Normalized WAC Mosaic) and LOLA teams."), devices: .all),
                Line(text: String(localized: "Night lights from space: NASA Black Marble (VNP46A4, Román et al. 2018), public domain."), devices: .all),
                Line(text: String(localized: "Stars: the Yale Bright Star Catalogue (Hoffleit and Warren), via NASA HEASARC."), devices: .all),
                Line(text: String(localized: "Star names: the IAU Working Group on Star Names (WGSN)."), devices: [.phone, .vision]),
                Line(text: String(localized: "Lunar eclipses: NASA eclipse predictions by Fred Espenak (NASA/GSFC)."), devices: .all),
                Line(text: String(localized: "Meteor showers: the International Meteor Organization (IMO) calendar."), devices: .all),
                Line(text: String(localized: "Aurora latitude: computed from the International Geomagnetic Reference Field (IGRF-14, IAGA; coefficients from NOAA NCEI, U.S. Government work)."), devices: .all),
                Line(text: String(localized: "Aurora forecast: the planetary K-index forecast of NOAA's Space Weather Prediction Center, U.S. Government work."), devices: .all),
                Line(text: String(localized: "Deep-sky positions and magnitudes: Wikidata (CC0), the SIMBAD database (CDS, Strasbourg) and the Harris globular cluster catalogue."), devices: .all),
                Line(text: String(localized: "Moon names and positions: the IAU Gazetteer of Planetary Nomenclature, USGS (public domain)."), devices: [.phone, .vision]),
            ]
            case .places: [
                Line(text: String(localized: "Parks, alerts and ranger programs: the National Park Service."), devices: .all),
                Line(text: String(localized: "Measured night skies: the National Park Service Night Skies Program, public domain."), devices: .phone),
                Line(text: String(localized: "Night and seasonal access: National Park Service, nps.gov, public domain."), devices: .phone),
                Line(text: String(localized: "Busy and quiet months: National Park Service Visitor Use Statistics, 2021 to 2025 monthly averages, CC0."), devices: .phone),
                Line(text: String(localized: "Starting points in the United States and its outline: U.S. Census Bureau Gazetteer Files, population estimates and cartographic boundaries, public domain."), devices: .phone),
                Line(text: String(localized: "Starting points outside the United States: GeoNames (geonames.org), CC BY 4.0."), devices: .phone),
                Line(text: String(localized: "World parks and dark-sky places: Wikidata, CC0."), devices: [.phone, .watch]),
                Line(text: String(localized: "World map: Natural Earth, public domain."), devices: .phone),
                Line(text: String(localized: "Terrain horizons: USGS 3D Elevation Program (public domain); produced using Copernicus WorldDEM-30 and WorldDEM-90 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved. The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30 and WorldDEM-90."), devices: .all),
            ]
            }
        }
        /// The lines one device shows, in order.
        func lines(for device: Device) -> [String] { lines.filter { $0.devices.contains(device) }.map(\.text) }
    }
    /// Said last on every device.
    static var notAffiliated: String { String(localized: "Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International.") }
}
