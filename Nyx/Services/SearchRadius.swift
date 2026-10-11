import Foundation

/// How far "in reach" goes, as the crow flies. Stored in metres (`radiusMeters`) and shown in the
/// locale's unit: miles where roads are signed in miles (the US and UK measurement systems),
/// kilometres everywhere else. Tonight, launch's preload, Ask Nyx and the trip planner all read it here.
/// Nonisolated, so the widget's preload reads it off the main actor.
nonisolated enum SearchRadius {
    static let key="radiusMeters"
    /// Before G1 the radius was kept in miles under this key. It is converted exactly, once, and left
    /// in place, so an older build installed again still finds the person's choice.
    static let legacyKey="radiusMiles"
    static let metersPerMile=1609.344

    /// The unit the choices are counted in.
    enum System: Sendable, Equatable {
        case miles, kilometers
        init(_ locale: Locale = .current) {
            self=[Locale.MeasurementSystem.us, .uk].contains(locale.measurementSystem) ? .miles : .kilometers
        }
        /// One of this unit, in metres.
        var meters: Double { self == .miles ? SearchRadius.metersPerMile : 1000 }
        /// Round numbers of this unit, in metres: the miles list or the kilometre list.
        func pick(_ miles: [Double], _ kilometers: [Double]) -> [Double] { (self == .miles ? miles : kilometers).map { $0*meters } }
    }

    /// Tonight's four reaches: 100, 200, 500 and 1,000 miles, or 150, 300, 800 and 1,500 km (the
    /// same spread in the unit's own round numbers).
    static func steps(_ system: System = System()) -> [Double] { system.pick([100, 200, 500, 1000], [150, 300, 800, 1500]) }
    /// Until a person chooses: 200 miles, or 300 km.
    static func standard(_ system: System = System()) -> Double { system.pick([200], [300])[0] }
    /// The farther reach Tonight offers when the answer is thin: 500 miles, or 800 km.
    static func wider(_ system: System = System()) -> Double { system.pick([500], [800])[0] }
    /// The trip planner's reaches, and its farthest hop between back-to-back nights.
    static func tripSteps(_ system: System = System()) -> [Double] { system.pick([100, 200, 300, 500, 1000], [150, 300, 500, 800, 1500]) }
    static func hopSteps(_ system: System = System()) -> [Double] { system.pick([100, 200, 300, 500], [150, 300, 500, 800]) }
    /// The trip planner's starting reach and hop: 300 miles, or 500 km.
    static func tripStandard(_ system: System = System()) -> Double { system.pick([300], [500])[0] }

    /// The chosen radius in metres: as stored, else a radius kept in miles converted exactly, else
    /// the locale's standard reach.
    static func meters(_ defaults: UserDefaults = .standard, locale: Locale = .current) -> Double {
        if let stored=defaults.object(forKey: key) as? Double, stored.isFinite, stored>0 { return stored }
        if let miles=defaults.object(forKey: legacyKey) as? Double, miles.isFinite, miles>0 { return miles*metersPerMile }
        return standard(System(locale))
    }
    /// Writes a radius kept in miles as metres, once; later calls find the metres and do nothing.
    static func migrate(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: key) == nil, let miles=defaults.object(forKey: legacyKey) as? Double, miles.isFinite, miles>0 else { return }
        defaults.set(miles*metersPerMile, forKey: key)
    }
    /// Also in miles under the old key, so a build from before G1, installed again, keeps the latest choice.
    static func store(_ meters: Double, _ defaults: UserDefaults = .standard) {
        defaults.set(meters, forKey: key); defaults.set(meters/metersPerMile, forKey: legacyKey)
    }

    /// The choices a picker offers: `steps`, plus the current radius when it is none of them (one set
    /// in the other unit before a change of region), so a person's choice is never silently replaced.
    static func choices(_ steps: [Double], keeping current: Double) -> [Double] {
        steps.contains { abs($0-current)<1 } ? steps : (steps+[current]).sorted()
    }
    /// A radius in words, in the locale's unit: "200 mi", "300 km". A whole number of the unit reads
    /// exactly; any other (a radius set in the other unit) is rounded to ten and says so: "about 320 km".
    static func label(_ meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let system=System(locale), value=meters/system.meters
        if abs(value-value.rounded())*system.meters<1 { return format(value.rounded(), system, locale: locale) }
        let text=format(max(10, (value/10).rounded()*10), system, locale: locale)
        return String(localized: "about \(text)", locale: locale)
    }
    /// Miles as Tonight always wrote them (road usage, abbreviated); kilometres as given.
    static func format(_ value: Double, _ system: System, locale: Locale = .autoupdatingCurrent) -> String {
        system == .miles
            ? Measurement(value: value, unit: UnitLength.miles).formatted(Measurement<UnitLength>.FormatStyle(width: .abbreviated, locale: locale, usage: .road))
            : Measurement(value: value, unit: UnitLength.kilometers).formatted(Measurement<UnitLength>.FormatStyle(width: .abbreviated, locale: locale, usage: .asProvided))
    }
}
