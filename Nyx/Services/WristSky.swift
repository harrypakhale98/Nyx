import Foundation

/// The watch's pure logic, kept beside `WatchContext` so the watch targets compile it and the
/// iPhone's test suite checks it: which colours the wrist wears, the dark-adaptation clock, the
/// next dark moment, the Moon right now, and how old the clouds are. Nothing here draws or networks.

/// The wearer's colours. Automatic is the default: Nyx's standard colours by day, red from civil
/// dusk to civil dawn at the park Tonight follows. Red light and Starlight stay explicit choices.
nonisolated enum PaletteChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, red, standard, phone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .red: String(localized: "Red light")
        case .standard: String(localized: "Starlight")
        case .phone: String(localized: "Match iPhone")
        }
    }
    /// Whether the wrist wears red. `phone` is the iPhone's night-vision switch, nil before the
    /// first sync (red then: at a dark site that is the safe default). Automatic needs a park for
    /// the Sun; with none chosen yet it reads the watch's clock, red from 6 PM to 7 AM.
    func nightVision(phone: Bool?, park: Park?, at now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .red: return true
        case .standard: return false
        case .phone: return phone ?? true
        case .automatic:
            if let park { return WristSky.isCivilNight(at: park, now) }
            let hour = calendar.component(.hour, from: now)
            return hour >= 18 || hour < 7
        }
    }
}

nonisolated enum WristSky {
    /// Civil night: the Sun more than 6° below the horizon. Under the midnight sun it never comes;
    /// in polar night it lasts all day.
    static func isCivilNight(at park: Park, _ date: Date) -> Bool {
        AstronomyEngine().solarAltitude(at: date, park: park) < -6
    }
    /// When Automatic changes colour between `from` and `to` (the Sun crossing −6°), to the
    /// minute: complication timelines add an entry at each so the face turns red on time.
    static func paletteChanges(at park: Park, from: Date, to: Date) -> [Date] {
        let engine = AstronomyEngine()
        func value(_ date: Date) -> Double { engine.solarAltitude(at: date, park: park) + 6 }
        var changes: [Date] = []
        var a = from, va = value(from)
        while a < to {
            let b = min(to, a.addingTimeInterval(600)), vb = value(b)
            if (va < 0) != (vb < 0) {
                var lo = a, hi = b
                for _ in 0..<10 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
                    if (value(mid) < 0) == (va < 0) { lo = mid } else { hi = mid }
                }
                changes.append(hi)
            }
            a = b; va = vb
        }
        return changes
    }
}

/// Dark adaptation on the wrist: a 30-minute clock from the moment the wearer starts it, with
/// reminders at 25 and 30 minutes. Eyes take 20 to 30 minutes; 30 is the honest end of that range.
nonisolated struct AdaptationClock: Equatable, Sendable {
    static let minutes = 30
    static let reminderMinutes = [25, 30]
    /// A clock left running is forgotten on the next visit after this long: that night is over.
    static let forgetAfter: TimeInterval = 3*3600
    let start: Date
    func elapsed(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(start)) }
    /// Whole minutes, rounded down: "12" means twelve full minutes in the dark.
    func elapsedMinutes(at now: Date) -> Int { min(Self.minutes, Int(elapsed(at: now)/60)) }
    func progress(at now: Date) -> Double { min(1, elapsed(at: now)/Double(Self.minutes*60)) }
    func isAdapted(at now: Date) -> Bool { elapsed(at: now) >= Double(Self.minutes*60) }
    /// Too old to resume, or started in the future (the clock was changed).
    func isStale(at now: Date) -> Bool { now.timeIntervalSince(start) >= Self.forgetAfter || start.timeIntervalSince(now) > 60 }
    /// The reminders still ahead of `now`, as minutes and moments.
    func reminders(after now: Date) -> [(minutes: Int, date: Date)] {
        Self.reminderMinutes.map { ($0, start.addingTimeInterval(Double($0*60))) }.filter { $0.date > now }
    }
}

/// The next stretch of truly dark sky: the Sun 18° down and the Moon below the horizon. What the
/// "Next dark" complication counts down to.
nonisolated enum DarkMoment: Equatable, Sendable {
    /// Moon-free true darkness now, until the Moon rises (`moonrise`) or dawn twilight begins.
    case darkNow(until: Date, moonrise: Bool)
    /// The next moon-free true darkness begins: when true darkness begins, or when the Moon sets.
    case begins(Date, moonset: Bool)
    /// True darkness tonight, with the Moon up through all of it.
    case moonlit(from: Date, to: Date)
    /// No true darkness tonight or tomorrow night at this latitude.
    case none

    /// `sky` supplies a night's conditions (evening in, sky out), so timelines can reuse them.
    static func next(at park: Park, now: Date, sky conditions: ((Date) -> SkyConditions)? = nil) -> DarkMoment {
        let engine = AstronomyEngine()
        let tonight = park.currentNight(at: now)
        for offset in 0..<2 {
            let evening = park.date(tonight, addingDays: offset)
            let sky = conditions?(evening) ?? engine.conditions(for: park, on: evening)
            guard let darkStart = sky.darkStart, let darkEnd = sky.darkEnd, darkEnd > darkStart, darkEnd > now else { continue }
            // Split true darkness at the Moon's crossings and keep the stretches it is down.
            let edges = [darkStart] + [sky.moonrise, sky.moonset].compactMap { $0 }.filter { $0 > darkStart && $0 < darkEnd }.sorted() + [darkEnd]
            let free = zip(edges, edges.dropFirst()).filter { a, b in
                engine.lunarAltitude(at: a.addingTimeInterval(b.timeIntervalSince(a)/2), park: park) + 0.833 < 0
            }
            // The Moon up through all of tonight's darkness is tonight's answer; a moon-free stretch
            // already over leaves only moonlight tonight, so the answer is tomorrow night's.
            if free.isEmpty { return .moonlit(from: darkStart, to: darkEnd) }
            guard let stretch = free.first(where: { $0.1 > now }) else { continue }
            if stretch.0 <= now { return .darkNow(until: stretch.1, moonrise: stretch.1 < darkEnd) }
            return .begins(stretch.0, moonset: stretch.0 > darkStart)
        }
        return .none
    }
    /// The moment the countdown runs to at `now`, if any: the start of the dark, or its end once begun.
    func target(at now: Date) -> Date? {
        switch self {
        case .darkNow(let until, _): until
        case .begins(let date, _): date
        case .moonlit(let from, let to): from > now ? from : to
        case .none: nil
        }
    }
}

/// The Moon right now from a park: phase, how much is lit, whether it is up, and its next rise or
/// set. No forecast is involved, so it is never stale.
nonisolated struct MoonNow: Sendable {
    struct Event: Sendable, Equatable {
        let rises: Bool
        let date: Date
    }
    let phase: MoonPhase
    /// Nil without a park: the phase is the same everywhere, rising and setting are not.
    let isUp: Bool?
    let next: Event?
    var percent: Int { Int((phase.illumination*100).rounded()) }

    /// Rises and sets from the night before the park's current one through the night after, in
    /// order. Nights run noon to noon, and in the morning "tonight" is the coming evening, so a
    /// moonset before noon belongs to the night before.
    static func events(at park: Park, around now: Date, sky conditions: ((Date) -> SkyConditions)? = nil) -> [Event] {
        let engine = AstronomyEngine()
        let tonight = park.currentNight(at: now)
        return (-1..<2).flatMap { offset -> [Event] in
            let evening = park.date(tonight, addingDays: offset)
            let sky = conditions?(evening) ?? engine.conditions(for: park, on: evening)
            return [sky.moonrise.map { Event(rises: true, date: $0) }, sky.moonset.map { Event(rises: false, date: $0) }].compactMap { $0 }
        }
        .sorted { $0.date < $1.date }
    }
    init(at now: Date, park: Park?, events: [Event]? = nil) {
        let engine = AstronomyEngine()
        phase = engine.moonPhase(at: now)
        guard let park else { isUp = nil; next = nil; return }
        isUp = engine.lunarAltitude(at: now, park: park) + 0.833 > 0
        next = (events ?? Self.events(at: park, around: now)).first { $0.date > now }
    }
}

/// Where the clouds in a watch score came from, and how old they are. The watch never fetches;
/// it can only say honestly what the iPhone last sent.
nonisolated enum CloudSource: Equatable, Sendable {
    /// The iPhone has never sent anything.
    case unsynced
    /// A forecast fetched at this moment, still in use.
    case fresh(Date)
    /// The iPhone's last forecast for this park is old: still scored (eased toward usual clouds), but worth refreshing.
    case expired(Date)
    /// The iPhone sent a context without a forecast for this park; `followed` says whether it
    /// is one the iPhone sends clouds for (saved, or the starting park).
    case missing(followed: Bool)

    /// After this the watch asks for a fresh forecast; the score itself fades an old one by lead time.
    static let lifetime: TimeInterval = 36*3600

    static func of(context: WatchContext?, park: Park, now: Date) -> CloudSource {
        guard let context else { return .unsynced }
        guard let updated = context.forecasts[park.id]?.updated else {
            return .missing(followed: context.savedParkIDs.contains(park.id) || context.homeParkID == park.id)
        }
        return now.timeIntervalSince(updated) < lifetime ? .fresh(updated) : .expired(updated)
    }
    /// The forecast can no longer be used and the iPhone could fix that.
    var isStale: Bool {
        switch self {
        case .expired, .missing(followed: true): true
        default: false
        }
    }
    /// One short line for the watch, or nil when another line already says it (before any sync).
    func line(for park: Park) -> String? {
        switch self {
        case .unsynced: return nil
        case .fresh(let updated):
            var format = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
            format.timeZone = park.timeZone
            return String(localized: "Clouds from \(updated.formatted(format))")
        case .expired, .missing(followed: true): return String(localized: "No recent forecast. Open Nyx on iPhone to refresh.")
        case .missing(followed: false): return String(localized: "Save this park on iPhone for its clouds.")
        }
    }
}
