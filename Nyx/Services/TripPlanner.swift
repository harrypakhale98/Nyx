import Foundation

/// A calendar date with no clock or zone: "the night of October 10" is the evening of the 10th in
/// whichever park you stand in, so a trip is planned in days, never in instants.
nonisolated struct TripDay: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    init(year: Int, month: Int, day: Int) { self.year=year; self.month=month; self.day=day }
    /// The Gregorian day `date` falls on in `calendar`'s time zone (the person's own zone for a date
    /// they picked). Only the zone is taken: a device set to the Buddhist or Japanese calendar
    /// numbers its years differently, and a trip is always planned in Gregorian days.
    init(_ date: Date, calendar: Calendar = .current) {
        var gregorian=Calendar(identifier:.gregorian)
        gregorian.timeZone=calendar.timeZone
        let parts=gregorian.dateComponents([.year,.month,.day],from:date)
        self.init(year:parts.year ?? 2000,month:parts.month ?? 1,day:parts.day ?? 1)
    }
    /// "2026-10-10"; nil for anything else, including impossible dates such as February 30.
    init?(iso: String) {
        let parts=iso.split(separator:"-",omittingEmptySubsequences:false)
        guard parts.count==3, parts[0].count==4, parts[1].count==2, parts[2].count==2,
              let y=Int(parts[0]), let m=Int(parts[1]), let d=Int(parts[2]) else { return nil }
        self.init(year:y,month:m,day:d)
        guard let noon=noonUTC, TripDay(noon,calendar:Self.utc)==self else { return nil }
    }
    var iso: String { String(format:"%04d-%02d-%02d",year,month,day) }
    private static let utc: Calendar = { var c=Calendar(identifier:.gregorian); c.timeZone = .gmt; return c }()
    private var noonUTC: Date? { Self.utc.date(from:DateComponents(year:year,month:month,day:day,hour:12)) }
    func adding(_ days: Int) -> TripDay {
        guard let noon=noonUTC, let moved=Self.utc.date(byAdding:.day,value:days,to:noon) else { return self }
        return TripDay(moved,calendar:Self.utc)
    }
    /// Whole days from this day to `other` (negative when `other` is earlier).
    func days(to other: TripDay) -> Int {
        guard let a=noonUTC, let b=other.noonUTC else { return 0 }
        return Int((b.timeIntervalSince(a)/86400).rounded())
    }
    /// 1 Sunday … 7 Saturday, as `Calendar` numbers them.
    var weekday: Int { noonUTC.map { Self.utc.component(.weekday,from:$0) } ?? 1 }
    /// A night before a day off: the evening before one of the device calendar's weekend days.
    /// Friday and Saturday nights where the weekend is Saturday and Sunday; Thursday and Friday
    /// nights where it is Friday and Saturday (`Calendar.isDateInWeekend` reads the region's weekend).
    func isNightBeforeDayOff(calendar: Calendar = .current) -> Bool {
        let next=adding(1)
        var gregorian=Calendar(identifier:.gregorian)
        gregorian.timeZone=calendar.timeZone
        guard let noon=gregorian.date(from:DateComponents(year:next.year,month:next.month,day:next.day,hour:12)) else { return false }
        return calendar.isDateInWeekend(noon)
    }
    /// Local noon of this day in the park, the same instant `Park.evening` uses to name a night.
    func evening(in park: Park) -> Date {
        park.calendar.date(from:DateComponents(year:year,month:month,day:day,hour:12)) ?? park.evening(noonUTC ?? .now)
    }
    static func < (a: TripDay, b: TripDay) -> Bool { (a.year,a.month,a.day)<(b.year,b.month,b.day) }
}

/// One night of a plan: the park chosen, the night as it was compared, and why.
nonisolated struct TripStop: Identifiable, Sendable {
    var id: String { day.iso }
    let day: TripDay
    let night: Night
    /// A closure or danger from the last cached park update, flagged beside the night.
    let closure: String?
    /// Straight-line distance from the previous night's park, when the nights are back to back.
    let hopMeters: Double?
    var isBest = false
    var reason: String { TripPlanner.reason(night) }
}
nonisolated struct TripPlan: Sendable {
    let stops: [TripStop]
    /// Parks inside the radius, so an empty plan can say why.
    let candidates: Int
    var best: TripStop? { stops.first { $0.isBest } }
    /// Nights scored without a full cloud forecast: an early look, or the park's usual clouds.
    var unforecastNights: Int { stops.filter { !$0.night.score.hasForecast }.count }
}

/// Assigns the best reachable park to each night of a trip.
///
/// **Assignment.** Dynamic programming over (night, park): the value of a park on a night is its
/// darkness score, less `closurePenalty` when its last park update lists a closure. Between two
/// back-to-back nights the straight-line hop may not exceed `maxHopMeters`; nights separated by a
/// gap (weekends only) are independent, since you go home in between. The plan maximises the total
/// value; ties are broken in `NightPlanner.better`'s order (darker measured sky, sum of parts,
/// longer true darkness, closer models, surer clouds), each summed over the nights, then the shorter total distance driven, then the park whose id sorts first, so the
/// same inputs always give the same plan. 14 nights × 63 parks × 63 parks is about 56,000 steps;
/// with the world catalogue the candidates are the places in range, at most `maxCandidates`.
/// Staying put is always allowed (a hop of zero), so a plan exists whenever one park is in reach.
///
/// **Honest comparison.** Every night is scored by `NightPlanner.night`, so every score counts
/// clouds: the forecast, an early look eased toward the park's usual clouds, or the usual clouds
/// for the month alone (ERA5 2015–2024). Scores therefore compare directly across parks, and a park
/// whose winter nights are usually overcast does not tie a desert.
nonisolated enum TripPlanner {
    /// `NightPlanner.better`'s tie-breaks after the score, with its margins, summable over a trip's nights.
    struct Tie {
        var glow=0.0, parts=0.0, dark=0.0, spread=0.0, certainty=0.0
        init() {}
        init(_ night: Night) {
            glow=NightPlanner.glowRank(night.park.id); parts=night.score.rawPartsSum; dark=night.sky.darkHours
            // No models' spread ranks below any spread, as in `better`.
            spread=night.modelSpread ?? 1000; certainty=NightPlanner.certainty(night.basis)
        }
        func adding(_ o: Tie) -> Tie { Tie(glow:glow+o.glow,parts:parts+o.parts,dark:dark+o.dark,spread:spread+o.spread,certainty:certainty+o.certainty) }
        private init(glow: Double, parts: Double, dark: Double, spread: Double, certainty: Double) {
            self.glow=glow; self.parts=parts; self.dark=dark; self.spread=spread; self.certainty=certainty
        }
        /// Whether this side wins, term by term; nil when every term ties. Each term is rounded to
        /// its grid first and compared exactly (`NightPlanner.tieGrid`), so ties stay transitive.
        func beats(_ o: Tie) -> Bool? {
            func grid(_ a: Double, _ b: Double, _ step: Double) -> (Double, Double) { (NightPlanner.tieGrid(a, step), NightPlanner.tieGrid(b, step)) }
            let g=grid(glow,o.glow,1e-9), p=grid(parts,o.parts,0.5), d=grid(dark,o.dark,1.0/60), s=grid(spread,o.spread,0.5), c=grid(certainty,o.certainty,1e-9)
            if g.0 != g.1 { return g.0<g.1 }
            if p.0 != p.1 { return p.0>p.1 }
            if d.0 != d.1 { return d.0>d.1 }
            if s.0 != s.1 { return s.0<s.1 }
            if c.0 != c.1 { return c.0>c.1 }
            return nil
        }
    }
    static let maxNights = 14
    /// The latest last night the planner offers: 13 nights after the first, or 69 for weekends
    /// only, whose filter keeps about one night in five (seven weekends' worth). Calendar days, so a
    /// change of clocks in between never lands the limit a day short.
    static func latestLast(first: Date, weekendsOnly: Bool, calendar: Calendar = .current) -> Date {
        let days = weekendsOnly ? 69 : 13
        return calendar.date(byAdding: .day, value: days, to: first) ?? first.addingTimeInterval(Double(days)*86400)
    }
    /// A last night kept inside what the planner offers: never before the first, never past `latestLast`
    /// (turning weekends only off, or moving the first night earlier, brings it back in).
    static func clampedLast(_ last: Date, first: Date, weekendsOnly: Bool, calendar: Calendar = .current) -> Date {
        min(max(last, first), latestLast(first: first, weekendsOnly: weekendsOnly, calendar: calendar))
    }
    /// A closure in the last park update costs a park this many points in the assignment only; the
    /// score shown is never changed. The same penalty every best night uses (`NightPlanner.closurePenalty`).
    static let closurePenalty = NightPlanner.closurePenalty
    /// The nights of a trip, first to last inclusive, at most `maxNights` of them (counted after the
    /// weekend filter, so "weekends only" can span seven weekends).
    static func days(first: TripDay, last: TripDay, weekendsOnly: Bool, calendar: Calendar = .current) -> [TripDay] {
        guard first<=last else { return [] }
        var days:[TripDay]=[], day=first
        while day<=last && days.count<maxNights {
            if !weekendsOnly || day.isNightBeforeDayOff(calendar:calendar) { days.append(day) }
            day=day.adding(1)
        }
        return days
    }
    /// Parks within `radiusMeters` of the starting point, as the crow flies, sorted by id. With
    /// `drivableOnly`, parks whose sky needs a boat or a plane (`Park.drivable`) are left out.
    static func candidates(_ parks: [Park], latitude: Double, longitude: Double, radiusMeters: Double, drivableOnly: Bool = false) -> [Park] {
        parks.filter { (!drivableOnly || $0.drivable) && $0.distanceMeters(latitude:latitude,longitude:longitude)<=radiusMeters }.sorted { $0.id<$1.id }
    }
    /// The most places one plan weighs. The assignment is nights × places², so with the world
    /// catalogue a wide radius is limited first: 14 × 120 × 120 is about 200,000 steps, as fast as
    /// the 63 parks ever were.
    static let maxCandidates = 120
    /// `candidates` cut to `limit`, when there are more: the darkest skies first (the lower Bortle
    /// class, a dark-sky designation, then nearer), so a plan still weighs every truly dark place in
    /// range; returned sorted by id, as `candidates` are. Under the limit, unchanged.
    static func limited(_ candidates: [Park], latitude: Double, longitude: Double, limit: Int = maxCandidates) -> [Park] {
        guard candidates.count>limit else { return candidates }
        func key(_ park: Park) -> (Int, Int, Double, String) {
            (park.bortleEstimate, park.darkSkyDesignated ? 0 : 1, park.distanceMeters(latitude:latitude,longitude:longitude), park.id)
        }
        return Array(candidates.sorted { key($0)<key($1) }.prefix(max(0,limit))).sorted { $0.id<$1.id }
    }
    /// Every candidate's night for every day, `[day][park]`, scored as `PlanModel.night` scores it.
    /// Pure and off the main actor: astronomy, the cached forecasts and nothing else.
    static func nights(parks: [Park], days: [TripDay], forecasts: [String:Forecast], details: [String:ForecastDetail] = [:], now: Date = .now,
                       astronomy: AstronomyEngine = AstronomyEngine()) -> [[Night]] {
        days.map { day in
            parks.map { park in
                NightPlanner.night(park:park,sky:astronomy.conditions(for:park,on:day.evening(in:park)),forecast:forecasts[park.id],detail:details[park.id],now:now)
            }
        }
    }
    /// `grid[d][p]` is park `p`'s night on `days[d]`; every row lists the same parks in the same order.
    static func plan(days: [TripDay], grid: [[Night]], closures: [String:String], maxHopMeters: Double) -> TripPlan {
        guard let parks=grid.first?.map(\.park), !parks.isEmpty, grid.count==days.count, grid.allSatisfy({ $0.count==parks.count }) else {
            return TripPlan(stops:[],candidates:grid.first?.count ?? 0)
        }
        let n=parks.count
        var hop=Array(repeating:Array(repeating:0.0,count:n),count:n)
        for a in 0..<n { for b in 0..<n where a != b { hop[a][b]=Park.distance(parks[a].latitude,parks[a].longitude,parks[b].latitude,parks[b].longitude) } }
        let ranks=grid.map { $0.map(\.score.value) }
        func value(_ d: Int, _ p: Int) -> Int { ranks[d][p]-(closures[parks[p].id] == nil ? 0 : closurePenalty) }
        // Equal totals are broken in `NightPlanner.better`'s order, each term summed over the nights,
        // so a one-night choice is exactly the one every other best surface makes.
        func tie(_ d: Int, _ p: Int) -> Tie { Tie(grid[d][p]) }
        struct Cell { var total: Int; var tie: Tie; var distance: Double; var previous: Int? }
        func better(_ a: Cell, than b: Cell?) -> Bool {
            guard let b else { return true }
            if a.total != b.total { return a.total>b.total }
            if let wins=a.tie.beats(b.tie) { return wins }
            return a.distance<b.distance-1e-6
        }
        var table:[[Cell]]=[(0..<n).map { Cell(total:value(0,$0),tie:tie(0,$0),distance:0,previous:nil) }]
        for d in 1..<max(1,days.count) {
            let backToBack=days[d-1].adding(1)==days[d]
            var row:[Cell]=[]
            for p in 0..<n {
                var best:Cell?
                for q in 0..<n {
                    if backToBack && hop[q][p]>maxHopMeters { continue }
                    let cell=Cell(total:table[d-1][q].total+value(d,p),tie:table[d-1][q].tie.adding(tie(d,p)),distance:table[d-1][q].distance+(backToBack ? hop[q][p] : 0),previous:q)
                    if better(cell,than:best) { best=cell }
                }
                // Unreachable only if no park is within a hop, which staying put rules out.
                row.append(best ?? Cell(total:Int.min/4,tie:Tie(),distance:0,previous:p))
            }
            table.append(row)
        }
        guard var p=(0..<n).reduce(nil as Int?, { best,p in best.map { better(table[days.count-1][p],than:table[days.count-1][$0]) ? p : $0 } ?? p }) else { return TripPlan(stops:[],candidates:n) }
        var chosen=Array(repeating:0,count:days.count)
        for d in stride(from:days.count-1,through:0,by:-1) { chosen[d]=p; p=table[d][p].previous ?? p }
        var stops=days.indices.map { d in
            let park=chosen[d], backToBack=d>0 && days[d-1].adding(1)==days[d]
            return TripStop(day:days[d],night:grid[d][park],closure:closures[parks[park].id],hopMeters:backToBack ? hop[chosen[d-1]][park] : nil)
        }
        // The single best night, as every best night is picked (`NightPlanner.better(_:_:closures:)`:
        // a closure counts against it, then the darker sky and longer darkness), then the earliest.
        if let best=stops.indices.max(by:{ a,b in
            if NightPlanner.better(stops[a].night,stops[b].night,closures:closures) { return false }
            if NightPlanner.better(stops[b].night,stops[a].night,closures:closures) { return true }
            return a>b
        }) { stops[best].isBest=true }
        return TripPlan(stops:stops,candidates:n)
    }
    /// Back-to-back nights at one park, kept together as one stay ("3 nights at Death Valley ·
    /// Oct 7–9"), in plan order. A gap (weekends only) or a change of park starts a new stay.
    static func stays(_ stops: [TripStop]) -> [[TripStop]] {
        var stays:[[TripStop]]=[]
        for stop in stops {
            if let last=stays.last?.last, last.night.park.id==stop.night.park.id, last.day.adding(1)==stop.day { stays[stays.count-1].append(stop) }
            else { stays.append([stop]) }
        }
        return stays
    }
    /// One line on why a night was chosen: "Moon down, 0% cloud forecast, Bortle 2". The Moon in the
    /// words every glance uses for true darkness (`MoonInDarkness.short`), with how much is lit
    /// whenever it is up for some of it ("Dark, Moon up, 98% lit").
    static func reason(_ night: Night) -> String {
        var parts=[night.sky.moonShort(park:night.park)]
        switch night.sky.moonInDarkness {
        case .allUp, .setsAt, .risesAt, .partial: parts.append(night.sky.moon.litText)
        case .noDarkness, .allFree, .negligible: break
        }
        if let cloud=night.cloudCover { parts.append(night.score.hasForecast ? String(localized:"\(Int(cloud.rounded()))% cloud forecast") : String(localized:"\(Int(cloud.rounded()))% cloud forecast, an early look")) }
        // "Not yet" beyond the forecast's reach, "unavailable" within it, as every surface says it.
        else if let usual=night.usualCloud { parts.append(night.beyondForecast ? String(localized:"no cloud forecast yet, usually \(Int(usual.rounded()))% cloud") : String(localized:"cloud forecast unavailable, usually \(Int(usual.rounded()))% cloud")) }
        else { parts.append(night.beyondForecast ? String(localized:"no cloud forecast yet") : String(localized:"cloud forecast unavailable")) }
        parts.append(String(localized:"Bortle \(night.park.bortleEstimate)"))
        return parts.joined(separator:", ")
    }
    /// The plan as plain text for Messages or Notes: one line a night, the best night, and the caveats.
    static func shareText(_ plan: TripPlan, distance: (Double) -> String) -> String {
        var lines=[String(localized:"A dark-sky trip, planned with Nyx")]
        for stop in plan.stops {
            let park=stop.night.park
            var parts=[stop.night.spokenSummary(.tripLine(reason:stop.reason))]
            if let hop=stop.hopMeters, hop>1000 { parts.append(String(localized:"\(distance(hop)) from the night before.")) }
            if let closure=stop.closure { parts.append(ClosureLine.spoken(closure)) }
            if let access=park.accessNote { parts.append(access) }
            lines.append(Sentences.join(parts))
        }
        if let best=plan.best { lines.append(String(localized:"Best night: \(best.night.park.dayLabel(best.night.id)), \(best.night.park.shortName).")) }
        lines.append(String(localized:"Distances are straight lines, not driving routes. Scores are estimates. Check closures and the forecast before you go."))
        return lines.joined(separator:"\n")
    }
}

/// What Nyx hands the system's event editor for one night. The person edits and saves it in
/// Calendar's own sheet; Nyx never reads a calendar.
nonisolated struct CalendarDraft: Sendable, Equatable {
    let title: String
    let start: Date
    let end: Date
    let timeZone: TimeZone
    let location: String
    let notes: String
    let url: URL?
    init(stop: TripStop) { self.init(night:stop.night,closure:stop.closure) }
    /// A stay of several nights at one park as one event: from the first night's darkness to the
    /// last night's dawn, each night's score in the notes. A single night is `init(stop:)`; nil for none.
    init?(stay: [TripStop]) {
        guard let first=stay.first, let last=stay.last else { return nil }
        guard stay.count>1 else { self.init(stop:first); return }
        let park=first.night.park
        let opening=CalendarDraft(night:first.night,closure:first.closure), closing=CalendarDraft(night:last.night,closure:last.closure)
        var lines=stay.map { stop in stop.night.spokenSummary(.stayNote(reason:stop.reason)) }
        if let closure=stay.compactMap(\.closure).first { lines.append(String(localized:"The last park update listed a closure: \(closure)")) }
        lines.append(String(localized:"Scores are estimates. Check closures and the forecast before you go."))
        self.init(title:opening.title,start:opening.start,end:max(opening.start.addingTimeInterval(3600),closing.end),timeZone:park.timeZone,location:park.name,notes:lines.joined(separator:"\n"),url:opening.url)
    }
    private init(title:String,start:Date,end:Date,timeZone:TimeZone,location:String,notes:String,url:URL?) {
        self.title=title; self.start=start; self.end=end; self.timeZone=timeZone; self.location=location; self.notes=notes; self.url=url
    }
    init(night: Night, closure: String?) {
        let park=night.park, sky=night.sky
        title=String(localized:"Stargazing at \(park.shortName)")
        // True darkness when there is any; otherwise the hours between sunset and sunrise.
        start=sky.darkStart ?? sky.sunset ?? sky.cloudWindow.start
        end=max(start.addingTimeInterval(3600),sky.darkEnd ?? sky.sunrise ?? sky.cloudWindow.end)
        timeZone=park.timeZone
        location=park.name
        var lines=[night.spokenSummary(.eventNote),TripPlanner.reason(night)+"."]
        if sky.darkHours==0 { lines.append(SkyConditions.noDarknessMessage(tonight:false)) }
        if let closure { lines.append(String(localized:"The last park update listed a closure: \(closure)")) }
        lines.append(String(localized:"Scores are estimates. Check closures and the forecast before you go."))
        notes=lines.joined(separator:"\n")
        url=DeepLink.whatsUp(park:park.id,day:TripDay(night.id,calendar:park.calendar)).url
    }
}
