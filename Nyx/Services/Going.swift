import Foundation
import Observation

// MARK: The nights kept

/// A night the person has said they are going out for ("I'm going"). Kept on this iPhone only:
/// the place, the night, the score when it was chosen (what a change is measured from), the last
/// fall already announced, and the drive as the person typed it. Nothing leaves the device.
nonisolated struct GoingNight: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(parkID)-\(Int(night.timeIntervalSince1970))" }
    let parkID: String
    /// The night's evening (`Park.evening`).
    let night: Date
    let chosenScore: Int
    let chosenAt: Date
    /// The score a change was last announced at, so the same fall is said once.
    var announcedScore: Int?=nil
    /// The drive to the place in minutes, as the person typed it; Nyx never routes.
    var driveMinutes: Int?=nil
}

/// The nights kept as going, soonest first. At most `limit`; a night is let go a day and a half
/// after its evening, when it is long over.
@MainActor @Observable final class GoingNights {
    static let shared=GoingNights()
    static let key="goingNights"
    static let limit=4
    private(set) var nights: [GoingNight]
    @ObservationIgnored private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults=defaults
        nights=(defaults.data(forKey:Self.key).flatMap { try? JSONDecoder().decode([GoingNight].self,from:$0) }) ?? []
    }
    func isGoing(park: Park, night: Date) -> Bool { going(park:park,night:night) != nil }
    func going(park: Park, night: Date) -> GoingNight? { nights.first { $0.parkID==park.id && $0.night==park.evening(night) } }
    /// Keeps the night, with today's score as the one changes are measured from. False when four are
    /// already kept: one is let go by the person first, never dropped behind their back.
    @discardableResult func go(_ night: Night, now: Date = .now) -> Bool {
        guard !isGoing(park:night.park,night:night.id) else { return true }
        guard nights.count<Self.limit else { return false }
        nights.append(GoingNight(parkID:night.park.id,night:night.park.evening(night.id),chosenScore:night.score.value,chosenAt:now))
        save()
        return true
    }
    func stop(_ going: GoingNight) { nights.removeAll { $0.id==going.id }; save() }
    func setDrive(_ minutes: Int?, for going: GoingNight) { update(going) { $0.driveMinutes=minutes.map { max(0,$0) } } }
    func announced(_ score: Int, for going: GoingNight) { update(going) { $0.announcedScore=score } }
    /// Drops nights that are long over.
    func prune(now: Date = .now) {
        let kept=nights.filter { now.timeIntervalSince($0.night)<36*3600 }
        if kept.count != nights.count { nights=kept; save() }
    }
    private func update(_ going: GoingNight, _ change: (inout GoingNight) -> Void) {
        guard let index=nights.firstIndex(where:{ $0.id==going.id }) else { return }
        change(&nights[index]); save()
    }
    private func save() {
        nights=Array(nights.sorted { ($0.night,$0.parkID)<($1.night,$1.parkID) }.prefix(Self.limit))
        defaults.set(try? JSONEncoder().encode(nights),forKey:Self.key)
    }
}

// MARK: How the night stands

/// What a kept night looks like now, against the night as it was chosen. One rule for the Tonight
/// card and for the alert, so the two never disagree.
nonisolated enum GoingCheck {
    /// A fall of this many points, or a fall into a lower band, is worth saying.
    static let fall=15
    /// A fall already announced is said again only after this many more points.
    static let further=10
    enum Status: Equatable { case good, uncertain, worse }
    static func status(chosen: Int, night: Night, agreement: ModelAgreement?) -> Status {
        if fell(chosen:chosen,to:night.score.value) { return .worse }
        if night.basis != .forecast || agreement?.band == .disagree { return .uncertain }
        return .good
    }
    /// Down by `fall`, or into a lower band by more than a few points (so 76 to 74 is not news).
    static func fell(chosen: Int, to score: Int) -> Bool {
        let lower=rank(ScoreBand.band(score))>rank(ScoreBand.band(chosen))
        return score<=chosen-fall || (lower && score<=chosen-5)
    }
    private static func rank(_ band: ScoreBand) -> Int { ScoreBand.allCases.firstIndex(of:band) ?? 0 }
    /// An alert only on a night some forecast reaches (a month's usual clouds never move enough
    /// to mean anything), only once for a fall, and again only if it falls `further`.
    static func announces(_ going: GoingNight, night: Night) -> Bool {
        guard night.basis != .usual, fell(chosen:going.chosenScore,to:night.score.value) else { return false }
        guard let announced=going.announcedScore else { return true }
        return night.score.value<=announced-further
    }
    /// A clearly better choice: the same place on a nearby night, or a place close by on the same
    /// night. At least 10 points better and Good, never at a closed place; the best first, then the
    /// same place, then the nearer, then the earlier.
    struct Alternative: Equatable {
        let night: Night
        /// Nil at the same place.
        let meters: Double?
        static func == (a: Alternative, b: Alternative) -> Bool { a.night.park.id==b.night.park.id && a.night.id==b.night.id && a.meters==b.meters }
    }
    static let margin=10
    static let nearby: Double=160_934
    static func alternative(to night: Night, sameplace: [Night], nearby: [(night: Night, meters: Double, closed: Bool)]) -> Alternative? {
        let floor=max(night.score.value+margin,60)
        let here=sameplace.filter { $0.id != night.id && $0.score.value>=floor }.map { Alternative(night:$0,meters:nil) }
        let near=nearby.filter { !$0.closed && $0.night.park.id != night.park.id && $0.night.score.value>=floor }.map { Alternative(night:$0.night,meters:$0.meters) }
        let options=here+near
        return options.min { a, b in
            if a.night.score.value != b.night.score.value { return a.night.score.value>b.night.score.value }
            if (a.meters == nil) != (b.meters == nil) { return a.meters == nil }
            if a.meters != b.meters { return (a.meters ?? 0)<(b.meters ?? 0) }
            return a.night.id<b.night.id
        }
    }
    /// "Saturday is 86 there." or "Mojave Trails is 81 that night, 70 mi away."
    static func sentence(_ alternative: Alternative) -> String {
        let night=alternative.night
        guard let meters=alternative.meters else {
            return String(localized:"\(night.park.dayLabel(night.id)) is \(NightVerdict.scored(night)) there.")
        }
        return String(localized:"\(night.park.shortName) is \(NightVerdict.scored(night)) that night, \(DarkerSky.distance(meters)) away.")
    }
    /// The card's line and the alert's body: the score now against the score when chosen, what
    /// holds it down, and the better choice when there is one.
    static func summary(_ going: GoingNight, night: Night, alternative: Alternative?) -> String {
        let now=String(localized:"Now \(night.score.value), \(night.score.band.label), down from \(going.chosenScore) when you chose it.")
        let why=night.score.limit.flatMap { $0.cap<night.score.partsSum ? $0.sentence(tonight:false) : nil }
        return Sentences.join([now,why,alternative.map(sentence)].compactMap { $0 })
    }
}

// MARK: Leaving, and being ready

nonisolated enum LeaveBy {
    /// Leave so as to arrive by sunset, with the evening's light to park and set up in. Nil with no
    /// sunset (a polar day or night) or no drive given.
    static func time(sky: SkyConditions, driveMinutes: Int?) -> Date? {
        guard let driveMinutes, let sunset=sky.sunset else { return nil }
        return sunset.addingTimeInterval(-Double(driveMinutes)*60)
    }
    /// "Leave by 2:40 PM to arrive before sunset (5:41 PM)." in the place's time, and the person's
    /// own clock beside it when the two differ at that moment.
    static func line(park: Park, sky: SkyConditions, driveMinutes: Int?, deviceZone: TimeZone = .current) -> String? {
        guard let leave=time(sky:sky,driveMinutes:driveMinutes), let sunset=sky.sunset else { return nil }
        let main=String(localized:"Leave by \(park.time(leave)) to arrive before sunset (\(park.time(sunset))).")
        guard deviceZone.secondsFromGMT(for:leave) != park.timeZone.secondsFromGMT(for:leave) else { return main }
        var own=Date.FormatStyle.dateTime.hour().minute(); own.timeZone=deviceZone
        return Sentences.join([main,String(localized:"That is \(leave.formatted(own)) your time.")])
    }
    /// "3 h 15 min", as the drive is shown and edited.
    static func drive(_ minutes: Int) -> String {
        Duration.seconds(minutes*60).formatted(.units(allowed:[.hours,.minutes],width:.abbreviated))
    }
}

nonisolated enum OfflineReady {
    /// Older than this, the forecast is worth refreshing while there is still a signal.
    static let stale: TimeInterval=6*3600
    /// What is kept on this iPhone for the night, and how old it is.
    static func line(park: Park, forecast: Date?, alerts: Date?, parkServicePlace: Bool, forecastsOn: Bool = true, now: Date = .now) -> String {
        guard forecastsOn else { return String(localized:"Cloud forecasts are off in Your privacy, so this night rests on the Moon, the darkness and the usual clouds.") }
        guard let forecast else { return String(localized:"No cloud forecast is saved for this night yet. Open Nyx with a signal before you go.") }
        let kept=parkServicePlace && alerts != nil
            ? String(localized:"Saved on this iPhone for offline use: the forecast from \(park.timestamp(forecast)), park alerts from \(park.timestamp(alerts ?? forecast)).")
            : String(localized:"Saved on this iPhone for offline use: the forecast from \(park.timestamp(forecast)).")
        return now.timeIntervalSince(forecast)>stale ? Sentences.join([kept,String(localized:"Refresh before you lose signal.")]) : kept
    }
}

// MARK: Telling someone

/// The plan in words, for the person to send through the share sheet to someone who should know
/// where they are. Nyx sends nothing; the Apple Maps link is opened only by whoever receives it.
nonisolated enum TellSomeone {
    static func mapsLink(latitude: Double, longitude: Double, label: String) -> URL? {
        // Built from parts, as `BrowserLink` builds pages: a link in a message, never a request of Nyx's.
        var components=URLComponents()
        components.scheme="https"; components.host="maps.apple.com"; components.path="/"
        components.queryItems=[URLQueryItem(name:"ll",value:String(format:"%.5f,%.5f",latitude,longitude)),URLQueryItem(name:"q",value:label)]
        return components.url
    }
    static func message(night: Night, spot: ViewingSpot?, closure: String?) -> String {
        let park=night.park, sky=night.sky
        let place=spot?.name ?? park.shortName
        let latitude=spot?.latitude ?? park.latitude, longitude=spot?.longitude ?? park.longitude
        var lines=[String(localized:"My plan for the night: \(park.shortName), \(park.dayLabel(night.id)).")]
        let coordinates=String(format:"%.5f, %.5f",latitude,longitude)
        lines.append(Sentences.join([String(localized:"Where: \(place) (\(coordinates))."),mapsLink(latitude:latitude,longitude:longitude,label:place)?.absoluteString ?? ""]))
        if let sunset=sky.sunset, let start=sky.darkStart, let end=sky.darkEnd {
            lines.append(String(localized:"Sunset \(park.time(sunset)); true darkness from \(park.time(start)) to \(park.time(end))."))
        }
        if let sunrise=sky.sunrise { lines.append(String(localized:"I expect to be back by sunrise, \(park.time(sunrise)).")) }
        if let closure { lines.append(Sentences.end(ClosureLine.spoken(closure))) }
        lines.append(park.countryCode=="US" ? String(localized:"In an emergency there, call 911.") : String(localized:"In an emergency there, call the local emergency number."))
        lines.append(Sentences.end(String(localized:"Times in \(park.timeZoneName)")))
        return lines.joined(separator:"\n")
    }
}
