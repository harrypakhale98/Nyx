import Foundation

/// The night as it unfolds at one park, for field mode: what happens and when, in order, and
/// what to say about it at any moment. Built from `AstronomyEngine` and `SkyAlmanac` only, so it
/// works with no network at all; clouds never move a milestone. Nonisolated so the Live Activity,
/// alarms and tests share one definition of "next".
nonisolated struct FieldNight: Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case sunset, darkness, moonrise, moonset, coreRises, coreHighest, coreSets, shower, planetRises, planetSets, dawn, sunrise
    }
    struct Milestone: Sendable, Identifiable, Equatable, Codable {
        var id: String { "\(kind.rawValue)-\(subject ?? "")" }
        let kind: Kind
        let date: Date
        let title: String
        let detail: String
        /// The planet or shower a milestone is about.
        var subject: String?=nil
        /// An SF Symbol for the Live Activity and the field screen.
        let symbol: String
    }
    let park: Park
    let sky: SkyConditions
    /// Every milestone from sunset to sunrise, earliest first.
    let milestones: [Milestone]

    init(park: Park, sky: SkyConditions, table: SkyEvents = .shared, almanac: SkyAlmanac = SkyAlmanac()) {
        self.park=park; self.sky=sky
        let engine=AstronomyEngine(), window=SkyAlmanac.nightWindow(sky)
        // A moment inside the night, or at its edges (sunset, sunrise), which bound the list.
        func inside(_ date: Date?) -> Date? { date.flatMap { $0>=window.start.addingTimeInterval(-60) && $0<=window.end.addingTimeInterval(60) ? $0 : nil } }
        func direction(_ date: Date, ra: Double, dec: Double) -> String { Compass.name(engine.horizontal(date: date, park: park, ra: ra, dec: dec).azimuth) }
        var list: [Milestone]=[]
        let darkSpan=sky.darkStart.flatMap { start in sky.darkEnd.map { $0.timeIntervalSince(start) } } ?? 0
        if let sunset=sky.sunset {
            let detail=sky.darkStart.map { String(localized: "Twilight follows. True darkness begins at \(park.time($0)).") } ?? SkyConditions.noDarknessMessage(tonight: true)
            list.append(Milestone(kind: .sunset, date: sunset, title: String(localized: "Sunset"), detail: detail, symbol: "sunset"))
        }
        if let start=sky.darkStart, let end=sky.darkEnd, end>start, start>sky.evening.addingTimeInterval(60) {
            list.append(Milestone(kind: .darkness, date: start, title: String(localized: "True darkness"),
                detail: String(localized: "The Sun is 18° below the horizon: \(Self.span(darkSpan)) of true darkness, until \(park.time(end))."), symbol: "moon.stars"))
        }
        if let end=sky.darkEnd, sky.darkStart != nil, end<sky.end.addingTimeInterval(-60) {
            list.append(Milestone(kind: .dawn, date: end, title: String(localized: "Dawn twilight"), detail: String(localized: "True darkness ends. The sky starts to brighten."), symbol: "sun.horizon"))
        }
        if let sunrise=sky.sunrise {
            list.append(Milestone(kind: .sunrise, date: sunrise, title: String(localized: "Sunrise"), detail: String(localized: "The night is over."), symbol: "sunrise"))
        }
        // The Moon, when it is bright enough to matter (5% lit or more).
        let lit=Int((sky.moon.illumination*100).rounded())
        if sky.moon.illumination>=0.05 {
            let moonAt={ (date: Date) in engine.equatorial(of: .moon, at: date) }
            if let rise=inside(sky.moonrise) {
                let p=moonAt(rise)
                let detail=sky.moon.illumination>=0.25 ? String(localized: "\(lit)% lit, in the \(direction(rise, ra: p.ra, dec: p.dec)). Faint stars fade where it shines.")
                    : String(localized: "A thin Moon, \(lit)% lit, low in the \(direction(rise, ra: p.ra, dec: p.dec)).")
                list.append(Milestone(kind: .moonrise, date: rise, title: String(localized: "Moonrise"), detail: detail, symbol: "moonrise"))
            }
            if let set=inside(sky.moonset) {
                let p=moonAt(set)
                let inDarkness=sky.darkStart.map { set>$0 } ?? false && sky.darkEnd.map { set<$0 } ?? false
                let detail=inDarkness ? String(localized: "It sets in the \(direction(set, ra: p.ra, dec: p.dec)). Moon-free true darkness from here.")
                    : String(localized: "\(lit)% lit, setting in the \(direction(set, ra: p.ra, dec: p.dec)).")
                list.append(Milestone(kind: .moonset, date: set, title: String(localized: "Moonset"), detail: detail, symbol: "moonset"))
            }
        }
        // The Milky Way's bright center, counted from 10° up in true darkness, as on park detail.
        let core=almanac.core(for: park, sky: sky)
        if let dark=core.dark, dark.duration>=600 {
            let at={ (date: Date) in Compass.name(engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec).azimuth) }
            if let start=sky.darkStart, dark.start.timeIntervalSince(start)>120 {
                list.append(Milestone(kind: .coreRises, date: dark.start, title: String(localized: "Milky Way core up"), detail: String(localized: "Its bright center clears 10° in the \(at(dark.start))."), symbol: "sparkle"))
            }
            let peak=almanac.highest(ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec, park: park, in: dark)
            if peak.date.timeIntervalSince(dark.start)>600, dark.end.timeIntervalSince(peak.date)>600 {
                list.append(Milestone(kind: .coreHighest, date: peak.date, title: String(localized: "Core at its highest"),
                    detail: String(localized: "\(Int(peak.altitude.rounded()))° up in the \(Compass.name(peak.azimuth))."), symbol: "sparkle"))
            }
            if let end=sky.darkEnd, end.timeIntervalSince(dark.end)>120 {
                list.append(Milestone(kind: .coreSets, date: dark.end, title: String(localized: "Core sinking"), detail: String(localized: "It drops below 10° in the \(at(dark.end))."), symbol: "sparkle"))
            }
        }
        // A meteor shower's best moment, when one is worth looking for.
        if let shower=WhatsUp.Events(park: park, sky: sky, table: table, almanac: almanac).shower, let best=shower.best, shower.hourlyRate>=2 {
            let moon=shower.moonDownAtBest ? String(localized: "Moon down") : String(localized: "Moon up, \(lit)% lit")
            list.append(Milestone(kind: .shower, date: best, title: String(localized: "\(shower.shower.localizedName) at their best"),
                detail: String(localized: "\(WhatsUp.rateText(shower.hourlyRate).capitalizedFirst) from this park, \(moon). A rough guide."), subject: shower.shower.code, symbol: "sparkles"))
        }
        // Planets rising or setting during the night.
        for planet in almanac.planets(for: park, sky: sky) {
            let note=WhatsUp.brightness(planet.magnitude)
            let at={ (date: Date) in let p=almanac.position(of: planet.planet, at: date); return direction(date, ra: p.ra, dec: p.dec) }
            if let rises=inside(planet.rises) {
                list.append(Milestone(kind: .planetRises, date: rises, title: String(localized: "\(planet.planet.name) rises"), detail: String(localized: "In the \(at(rises)), \(note)."), subject: planet.planet.rawValue, symbol: "circle.circle"))
            }
            if let sets=inside(planet.sets) {
                list.append(Milestone(kind: .planetSets, date: sets, title: String(localized: "\(planet.planet.name) sets"), detail: String(localized: "In the \(at(sets))."), subject: planet.planet.rawValue, symbol: "circle.circle"))
            }
        }
        let order=Dictionary(uniqueKeysWithValues: Kind.allCases.enumerated().map { ($1, $0) })
        milestones=list.sorted { $0.date == $1.date ? (order[$0.kind] ?? 0)<(order[$1.kind] ?? 0) : $0.date<$1.date }
    }

    /// The first milestone still ahead.
    func next(after now: Date) -> Milestone? { milestones.first { $0.date>now } }
    /// Milestones still ahead, earliest first.
    func upcoming(after now: Date) -> [Milestone] { milestones.filter { $0.date>now } }
    /// True once the night shown is over: after sunrise; under the polar night, once true darkness
    /// ends; under the midnight sun, at local noon.
    func isOver(at now: Date) -> Bool { Self.isOver(sky, at: now) }
    static func isOver(_ sky: SkyConditions, at now: Date) -> Bool { now>=(sky.sunrise ?? sky.darkEnd ?? sky.end) }

    // MARK: Now

    /// The one line field mode leads with. `target` is the moment a live countdown runs to.
    struct Status: Sendable, Equatable {
        enum Phase: Sendable, Equatable { case waiting, dark, dawn, noDarkness, over }
        let phase: Phase
        /// "True darkness in", "True darkness for another".
        let lead: String
        let target: Date?
        /// "then 7h 52m of it", "until 5:12 AM".
        let trailing: String
        /// The whole line as one sentence, with the countdown said in words.
        let spoken: String
    }
    func status(at now: Date) -> Status {
        if isOver(at: now) {
            let line=String(localized: "The night is over. Rest your eyes.")
            return Status(phase: .over, lead: line, target: nil, trailing: "", spoken: line)
        }
        guard let start=sky.darkStart, let end=sky.darkEnd, end>start else {
            let lead=SkyConditions.noDarknessMessage(tonight: true)
            let trailing=sky.state == .polarDay ? String(localized: "The Sun stays up all night.")
                : sky.sunrise.map { String(localized: "Sunrise at \(park.time($0)).") } ?? ""
            return Status(phase: .noDarkness, lead: lead, target: nil, trailing: trailing, spoken: [lead, trailing].joined(separator: " "))
        }
        if now<start {
            let trailing=String(localized: "then \(Self.span(end.timeIntervalSince(start))) of it")
            return Status(phase: .waiting, lead: String(localized: "True darkness in"), target: start, trailing: trailing,
                spoken: String(localized: "True darkness in \(Self.spokenSpan(start.timeIntervalSince(now))), at \(park.time(start)), then \(Self.spokenSpan(end.timeIntervalSince(start))) of it."))
        }
        if now<end {
            return Status(phase: .dark, lead: String(localized: "True darkness for another"), target: end, trailing: String(localized: "until \(park.time(end))"),
                spoken: String(localized: "True darkness for another \(Self.spokenSpan(end.timeIntervalSince(now))), until \(park.time(end))."))
        }
        let sunrise=sky.sunrise ?? sky.end
        return Status(phase: .dawn, lead: String(localized: "Sunrise in"), target: sunrise, trailing: String(localized: "True darkness ended at \(park.time(end))"),
            spoken: String(localized: "Sunrise in \(Self.spokenSpan(sunrise.timeIntervalSince(now))). True darkness ended at \(park.time(end))."))
    }

    /// "7h 52m": compact, for figures.
    static func span(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, (seconds/60).rounded()*60)).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
    }
    /// "7 hours, 52 minutes": for VoiceOver.
    static func spokenSpan(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(60, (seconds/60).rounded()*60)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    // MARK: Alarms

    /// A wake-up the night offers: AlarmKit breaks through Silent and Focus, which a notification
    /// cannot, so someone can nap until the sky is worth it.
    struct AlarmOption: Sendable, Identifiable, Equatable {
        enum Kind: String, Sendable { case darkness, core, moonset }
        var id: String { kind.rawValue }
        let kind: Kind
        let fire: Date
        /// The button: "Wake me when the core is up".
        let label: String
        /// What the alarm says when it rings.
        let alarmTitle: String
    }
    /// Alarms are offered only for moments at least five minutes ahead. The core replaces the
    /// darkness alarm when the two fall within two minutes of each other.
    static let alarmLead: TimeInterval=300
    func alarmOptions(at now: Date) -> [AlarmOption] { Self.alarmOptions(park: park, sky: sky, at: now) }
    /// The same, without working out the whole night: cheap enough for park detail.
    static func alarmOptions(park: Park, sky: SkyConditions, at now: Date) -> [AlarmOption] {
        var options: [AlarmOption]=[]
        let name=park.shortName
        if let start=sky.darkStart, let end=sky.darkEnd, end>start, start>sky.evening.addingTimeInterval(60) {
            options.append(AlarmOption(kind: .darkness, fire: start, label: String(localized: "Wake me when true darkness begins"), alarmTitle: String(localized: "True darkness at \(name)")))
        }
        let core=SkyAlmanac().core(for: park, sky: sky)
        if let dark=core.dark, dark.duration>=600 {
            options.removeAll { $0.kind == .darkness && abs($0.fire.timeIntervalSince(dark.start))<120 }
            options.append(AlarmOption(kind: .core, fire: dark.start, label: String(localized: "Wake me when the core is up"), alarmTitle: String(localized: "The Milky Way core is up at \(name)")))
        }
        // Thirty minutes before a Moon that sets in true darkness, for the moon-free hours before dawn.
        if sky.moon.illumination>=0.05, let set=sky.moonset, let start=sky.darkStart, let end=sky.darkEnd, set>start, set<end {
            options.append(AlarmOption(kind: .moonset, fire: set.addingTimeInterval(-1800), label: String(localized: "Wake me 30 minutes before the Moon sets"),
                alarmTitle: String(localized: "The Moon sets at \(name) in 30 minutes")))
        }
        return options.filter { $0.fire.timeIntervalSince(now)>=Self.alarmLead }.sorted { $0.fire<$1.fire }
    }
}

/// How long the eye has been adapting to the dark. Cones adjust within about 10 minutes; rods,
/// which see faint stars, need 20 to 30. Red light barely touches rods; white light resets them.
/// Nyx cannot see what the eye saw while it was away, so leaving is treated as a reset, which the
/// person can undo if their screen stayed dark.
nonisolated struct DarkAdaptation: Sendable, Equatable {
    static let full: TimeInterval=30*60
    /// A glance at a notification is not counted; this long away is.
    static let grace: TimeInterval=5
    private(set) var start: Date
    private(set) var leftAt: Date?
    struct Reset: Sendable, Equatable { let at: Date; let previousStart: Date }
    init(start: Date) { self.start=start }
    func elapsed(at now: Date) -> TimeInterval { max(0, (leftAt ?? now).timeIntervalSince(start)) }
    func progress(at now: Date) -> Double { min(1, elapsed(at: now)/Self.full) }
    enum Stage: Sendable, Equatable { case cones, rods, adapted }
    func stage(at now: Date) -> Stage {
        let e=elapsed(at: now)
        return e<10*60 ? .cones : e<Self.full ? .rods : .adapted
    }
    /// When the eye should be dark-adapted, if Nyx stays dark.
    var adaptedAt: Date { start.addingTimeInterval(Self.full) }
    mutating func leave(at date: Date) { if leftAt == nil { leftAt=date } }
    /// Back in field mode. A short absence changes nothing; a longer one restarts the clock from
    /// the moment of leaving.
    mutating func returned(at now: Date) -> Reset? {
        guard let left=leftAt else { return nil }
        leftAt=nil
        guard now.timeIntervalSince(left)>=Self.grace else { return nil }
        let reset=Reset(at: left, previousStart: start)
        start=left
        return reset
    }
    /// "My screen stayed dark": the clock continues as if nothing happened.
    mutating func undo(_ reset: Reset) { if start == reset.at { start=reset.previousStart } }
}

extension String {
    /// "about 80 an hour" → "About 80 an hour", locale-safe for a sentence start.
    nonisolated var capitalizedFirst: String { prefix(1).localizedUppercase+dropFirst() }
}
