import ActivityKit
import AlarmKit
import Foundation

/// The Live Activity for a night in the field, shared by the app (which starts and updates it)
/// and the widget extension (which draws it). Everything is computed on the phone when it starts,
/// so it needs no push server: the night's milestones travel in the attributes, the countdown is a
/// system timer, and the line from dusk to dawn fills by itself.
nonisolated struct FieldActivityAttributes: ActivityAttributes {
    struct Milestone: Codable, Hashable, Sendable {
        let title: String
        let date: Date
        let symbol: String
    }
    struct ContentState: Codable, Hashable, Sendable {
        /// The next milestone when the app last looked; the countdown runs to it.
        var next: Milestone?
        /// Draw in red: night vision was on.
        var nightVision: Bool
        /// Set once the night is over.
        var finished: Bool=false
        /// "Heading out": a night followed ahead, before true darkness and before field mode. The
        /// face then leads with sunset, true darkness and the park's closure line. Optional, like
        /// every field added after 1.1 (7), so a state written by an earlier build still decodes.
        var heading: Bool?=nil
        /// When Nyx worked this state out; the stale face says so ("Updated 7:44 PM").
        var updated: Date?=nil
        /// The night's darkness score, band and closure line as Nyx last worked them out, so a night
        /// followed on Monday shows Friday's clouds once Nyx has seen them. Optional so a state
        /// written by build 8 still decodes; the faces then read the attributes' copies, set when the
        /// night was followed. Once `score` is set the state's closure is the whole truth: nil means
        /// the closure was lifted.
        var score: Int?=nil
        var band: String?=nil
        var closure: String?=nil
        /// When that score was worked out: the time of the cloud forecast it rests on.
        var scoredAt: Date?=nil
        /// The four together, read and written as one.
        var scored: Scored? {
            get { score.map { Scored(score: $0, band: band ?? "", closure: closure, at: scoredAt ?? updated ?? .distantPast) } }
            set { score=newValue?.score; band=newValue?.band; closure=newValue?.closure; scoredAt=newValue?.at }
        }
    }
    /// A followed night's score as Nyx last worked it out (`ContentState.scored`).
    struct Scored: Hashable, Sendable {
        let score: Int
        let band: String
        let closure: String?
        /// When the score was worked out: the time of the cloud forecast it rests on.
        let at: Date
    }
    let parkID: String
    let parkName: String
    let score: Int
    let band: String
    /// Sunset (or the start of the night window) and sunrise: the ends of the line.
    let dusk: Date
    let dawn: Date
    let darkStart: Date?
    let darkEnd: Date?
    /// At most eight, earliest first, so the whole activity stays far below ActivityKit's 4 KB.
    let milestones: [Milestone]
    /// The park's IANA zone: the Lock Screen shows park time, as field mode does, wherever the
    /// phone's clock is set. Optional so an activity started by an earlier build still decodes.
    var timeZoneID: String? = nil
    var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// The night as the park's calendar names it (`Night.id`), so each night is followed once.
    var nightID: Date?=nil
    /// The park's closure, as Nyx words it beside the score, when the night was followed.
    var closure: String?=nil
    /// The score, band and closure the faces show: the state's, once it carries them, else the
    /// copies made when the night was followed (a state written by build 8).
    func score(_ state: ContentState) -> Int { state.score ?? score }
    func band(_ state: ContentState) -> String { state.band ?? band }
    func closure(_ state: ContentState) -> String? { state.score != nil ? state.closure : closure }
    /// How long a score may be old before the faces name its day: "94 · Pristine as of Wed".
    static let scoreAgeLimit: TimeInterval=18*3600
    /// The day the shown score was worked out, when that was more than 18 hours before dusk; nil
    /// when it is recent. A night followed ahead by build 8 has no score time; its plan time
    /// (`updated`, set when it was followed) stands in, which is when its score was worked out.
    func scoreDay(_ state: ContentState) -> Date? {
        guard let at=state.scoredAt ?? (state.score == nil && state.heading == true ? state.updated : nil) else { return nil }
        return dusk.timeIntervalSince(at)>Self.scoreAgeLimit ? at : nil
    }
    /// "94 · Pristine", or "94 · Pristine as of Wed" when the score is old. Park time.
    func scoreLine(_ state: ContentState) -> String {
        guard let day=scoreDay(state) else { return "\(score(state)) · \(band(state))" }
        return String(localized: "\(score(state)) · \(band(state)) as of \(day.formatted(weekday(.abbreviated)))")
    }
    /// What a state's face shows of its night, for deciding whether a refresh changes anything:
    /// the score line (score, band and the "as of" day in park time) and the closure.
    func shows(_ state: ContentState) -> [String?] { [scoreLine(state), closure(state)] }
    /// What VoiceOver hears for the score: "Darkness score 94, Pristine, as of Wednesday."
    func spokenScore(_ state: ContentState) -> String {
        guard let day=scoreDay(state) else { return String(localized: "Darkness score \(score(state)), \(band(state)).") }
        return String(localized: "Darkness score \(score(state)), \(band(state)), as of \(day.formatted(weekday(.wide))).")
    }
    private func weekday(_ width: Date.FormatStyle.Symbol.Weekday) -> Date.FormatStyle {
        var style=Date.FormatStyle().weekday(width)
        style.timeZone=timeZone
        return style
    }
    /// True when this activity is for that park on that night. An activity from an earlier build
    /// (no night recorded) matches the night whose sunset it starts from.
    func covers(parkID id: String, night evening: Date) -> Bool {
        guard id == parkID else { return false }
        if let nightID { return nightID == evening }
        let since=dusk.timeIntervalSince(evening)
        return since>=0 && since<24*3600
    }
    /// The one milestone every face counts down to, so title, symbol and countdown never disagree:
    /// the state's next milestone. Nil when the night is over, when only sunrise is left, and once
    /// that moment has passed with no update (stale): Nyx cannot know which moment is next while
    /// the phone sleeps, so the faces then list the night's times and name none of them next.
    func shown(_ state: ContentState, isStale: Bool) -> Milestone? {
        guard !state.finished, !isStale else { return nil }
        return state.next
    }

    /// The stale face's schedule: every milestone after the one the state was counting down to, as
    /// clock times. They stay true however long the phone sleeps; none of them is called next.
    func schedule(_ state: ContentState) -> [Milestone] {
        guard !state.finished, let next=state.next else { return [] }
        return after(next)
    }
    /// The milestones after the one the state points at, for when the state has gone stale.
    func after(_ milestone: Milestone?) -> [Milestone] {
        guard let milestone else { return milestones }
        return milestones.filter { $0.date>milestone.date }
    }
    /// Where a moment falls along the night, 0 at dusk and 1 at dawn.
    func fraction(_ date: Date) -> Double {
        let span=dawn.timeIntervalSince(dusk)
        return span>0 ? min(1, max(0, date.timeIntervalSince(dusk)/span)) : 0
    }
    /// The state at `now`: the next marked milestone, or finished once the night is over. A night
    /// followed ahead stays "heading out" until true darkness begins (or sunset, without any).
    func state(at now: Date, nightVision: Bool, heading: Bool=false) -> ContentState {
        let finished=now>=dawn
        let ahead=heading && !finished && now<(darkStart ?? dusk)
        return ContentState(next: finished ? nil : milestones.first { $0.date>now }, nightVision: nightVision, finished: finished,
                            heading: ahead ? true : nil, updated: now)
    }
    /// Stale when the countdown reaches its milestone (the view then shows the night's remaining
    /// times, not a timer); at dawn when nothing is left.
    /// `scored` carries the night's latest score, band and closure (`ContentState.scored`).
    func content(at now: Date, nightVision: Bool, heading: Bool=false, updated: Date?=nil, scored: Scored?=nil) -> ActivityContent<ContentState> {
        var state=state(at: now, nightVision: nightVision, heading: heading)
        if let updated { state.updated=updated }
        state.scored=scored
        return ActivityContent(state: state, staleDate: state.finished ? nil : state.next?.date ?? dawn, relevanceScore: state.finished ? 0 : 50)
    }
}

/// What a field-mode alarm carries, so the alarm's own Live Activity can name the park.
nonisolated struct FieldAlarmMetadata: AlarmMetadata {
    let parkName: String
    let kind: String
}
