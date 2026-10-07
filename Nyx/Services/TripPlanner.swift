import Foundation

/// A calendar date with no clock or zone: "the night of October 10" is the evening of the 10th in
/// whichever park you stand in, so a trip is planned in days, never in instants.
nonisolated struct TripDay: Hashable, Comparable, Codable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    init(year: Int, month: Int, day: Int) { self.year=year; self.month=month; self.day=day }
    /// The day `date` falls on in `calendar` (the person's own calendar for a date they picked).
    init(_ date: Date, calendar: Calendar = .current) {
        let parts=calendar.dateComponents([.year,.month,.day],from:date)
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
    /// Friday and Saturday nights: the ones that need no day off work.
    var isWeekendNight: Bool { weekday==6 || weekday==7 }
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
/// value; ties go to the darker measured skies and longer true darkness (`NightPlanner.better`'s
/// order), then the shorter total distance driven, then the park whose id sorts first, so the
/// same inputs always give the same plan. 14 nights × 63 parks × 63 parks is about 56,000 steps.
/// Staying put is always allowed (a hop of zero), so a plan exists whenever one park is in reach.
///
/// **Honest comparison.** Every night is scored by `NightPlanner.night`, so every score counts
/// clouds: the forecast, an early look eased toward the park's usual clouds, or the usual clouds
/// for the month alone (ERA5 2015–2024). Scores therefore compare directly across parks, and a park
/// whose winter nights are usually overcast does not tie a desert.
nonisolated enum TripPlanner {
    static let maxNights = 14
    /// A closure in the last park update costs a park this many points in the assignment only; the
    /// score shown is never changed. A closed road beats a slightly darker sky every time.
    static let closurePenalty = 10
    /// The nights of a trip, first to last inclusive, at most `maxNights` of them (counted after the
    /// weekend filter, so "weekends only" can span seven weekends).
    static func days(first: TripDay, last: TripDay, weekendsOnly: Bool) -> [TripDay] {
        guard first<=last else { return [] }
        var days:[TripDay]=[], day=first
        while day<=last && days.count<maxNights {
            if !weekendsOnly || day.isWeekendNight { days.append(day) }
            day=day.adding(1)
        }
        return days
    }
    /// Parks within `radiusMiles` of the starting point, as the crow flies, sorted by id. With
    /// `drivableOnly`, parks whose sky needs a boat or a plane (`Park.drivable`) are left out.
    static func candidates(_ parks: [Park], latitude: Double, longitude: Double, radiusMiles: Double, drivableOnly: Bool = false) -> [Park] {
        parks.filter { (!drivableOnly || $0.drivable) && $0.distanceMeters(latitude:latitude,longitude:longitude)<=radiusMiles*1609.344 }.sorted { $0.id<$1.id }
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
        let ranks=grid.map { $0.map(\.rankScore) }
        func value(_ d: Int, _ p: Int) -> Int { ranks[d][p]-(closures[parks[p].id] == nil ? 0 : closurePenalty) }
        // Equal totals go to the darker measured sky, then the longer true darkness: under 1 a night.
        func tie(_ d: Int, _ p: Int) -> Double { (1-NightPlanner.glowRank(parks[p].id))*0.5+min(24,grid[d][p].sky.darkHours)/48 }
        struct Cell { var total: Int; var tie: Double; var distance: Double; var previous: Int? }
        func better(_ a: Cell, than b: Cell?) -> Bool {
            guard let b else { return true }
            if a.total != b.total { return a.total>b.total }
            if abs(a.tie-b.tie)>1e-9 { return a.tie>b.tie }
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
                    let cell=Cell(total:table[d-1][q].total+value(d,p),tie:table[d-1][q].tie+tie(d,p),distance:table[d-1][q].distance+(backToBack ? hop[q][p] : 0),previous:q)
                    if better(cell,than:best) { best=cell }
                }
                // Unreachable only if no park is within a hop, which staying put rules out.
                row.append(best ?? Cell(total:Int.min/4,tie:0,distance:0,previous:p))
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
        // The single best night: highest value (closures count against it here too), then
        // `NightPlanner.better`'s tie-breaks (darker sky, longer darkness), then the earliest.
        if let best=stops.indices.max(by:{ a,b in
            let va=stops[a].night.rankScore-(stops[a].closure == nil ? 0 : closurePenalty), vb=stops[b].night.rankScore-(stops[b].closure == nil ? 0 : closurePenalty)
            if va != vb { return va<vb }
            if NightPlanner.better(stops[a].night,stops[b].night) { return false }
            if NightPlanner.better(stops[b].night,stops[a].night) { return true }
            return a>b
        }) { stops[best].isBest=true }
        return TripPlan(stops:stops,candidates:n)
    }
    /// One line on why a night was chosen: "New moon, 0% cloud forecast, Bortle 2".
    static func reason(_ night: Night) -> String {
        let lit=Int((night.sky.moon.illumination*100).rounded())
        var parts:[String]=[]
        if night.sky.darkHours==0 { parts.append(String(localized:"No true darkness at this latitude")) }
        else if lit<=1 { parts.append(String(localized:"New moon")) }
        else if night.sky.moonBelowFraction>=0.95 { parts.append(String(localized:"Moon down through the dark hours")) }
        else { parts.append(String(localized:"Moon \(lit)% lit")) }
        if let cloud=night.cloudCover { parts.append(night.score.hasForecast ? String(localized:"\(Int(cloud.rounded()))% cloud forecast") : String(localized:"\(Int(cloud.rounded()))% cloud forecast, an early look")) }
        else if let usual=night.usualCloud { parts.append(String(localized:"no cloud forecast yet, usually \(Int(usual.rounded()))% cloud")) }
        else { parts.append(String(localized:"no cloud forecast yet")) }
        parts.append(String(localized:"Bortle \(night.park.bortleEstimate)"))
        return parts.joined(separator:", ")
    }
    /// The plan as plain text for Messages or Notes: one line a night, the best night, and the caveats.
    static func shareText(_ plan: TripPlan, distance: (Double) -> String) -> String {
        var lines=[String(localized:"A dark-sky trip, planned with Nyx")]
        for stop in plan.stops {
            let park=stop.night.park
            var line=String(localized:"\(park.dayLabel(stop.night.id)): \(park.shortName), \(stop.night.score.value)/100 \(stop.night.bandWithBasis). \(stop.reason).")
            if let hop=stop.hopMeters, hop>1000 { line+=" "+String(localized:"\(distance(hop)) from the night before.") }
            if let closure=stop.closure { line+=" "+String(localized:"Closure alert: \(closure)") }
            if let access=park.accessNote { line+=" "+access }
            lines.append(line)
        }
        if let best=plan.best { lines.append(String(localized:"Best night: \(best.night.park.dayLabel(best.night.id)) at \(best.night.park.shortName).")) }
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
    init(night: Night, closure: String?) {
        let park=night.park, sky=night.sky
        title=String(localized:"Stargazing at \(park.shortName)")
        // True darkness when there is any; otherwise the hours between sunset and sunrise.
        start=sky.darkStart ?? sky.sunset ?? sky.cloudWindow.start
        end=max(start.addingTimeInterval(3600),sky.darkEnd ?? sky.sunrise ?? sky.cloudWindow.end)
        timeZone=park.timeZone
        location=park.name
        var lines=[night.score.hasForecast
                   ? String(localized:"Darkness score \(night.score.value)/100 (\(night.score.band.label)), with the cloud forecast as Nyx last saw it.")
                   : String(localized:"Darkness score \(night.score.value)/100 (\(night.score.band.label)).")+" "+(night.basisCaption(typical:true) ?? ""),
                   TripPlanner.reason(night)+"."]
        if sky.darkHours==0 { lines.append(SkyConditions.noDarknessMessage(tonight:false)) }
        if let closure { lines.append(String(localized:"The last park update listed a closure: \(closure)")) }
        lines.append(String(localized:"Scores are estimates. Check closures and the forecast before you go."))
        notes=lines.joined(separator:"\n")
        url=DeepLink.whatsUp(park:park.id,day:TripDay(night.id,calendar:park.calendar)).url
    }
}
