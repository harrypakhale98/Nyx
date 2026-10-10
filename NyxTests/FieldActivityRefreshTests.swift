import Foundation
import Testing
@testable import Nyx

/// A followed night's Live Activity follows the forecast: its score, band and closure travel in the
/// content state, old scores name their day, and a refresh decides between keeping, updating and
/// requesting a scheduled night again. ActivityKit itself is not reachable from unit tests, so the
/// decisions are tested as the pure functions `FieldActivities.refresh` calls.
@MainActor struct FieldActivityRefreshTests {
    typealias State=FieldActivityAttributes.ContentState
    typealias Scored=FieldActivityAttributes.Scored
    let parks: [Park]
    let engine=AstronomyEngine()
    init() throws { parks=try ParkData.load() }
    func park(_ id: String) throws -> Park { try #require(parks.first { $0.id == id }) }
    /// Joshua Tree on Sunday 13 December 2026, followed with a 94, Pristine and a closure.
    func followed() throws -> (park: Park, sky: SkyConditions, attributes: FieldActivityAttributes, heading: State) {
        let jotr=try park("jotr")
        let sky=engine.conditions(for: jotr, on: jotr.evening(try #require(try? Date("2026-12-13T20:00:00Z", strategy: .iso8601))))
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine", closure: "Keys View Road closed")
        let start=FieldActivityAttributes.followStart(sky)
        return (jotr, sky, attributes, attributes.state(at: start, nightVision: false, heading: true))
    }
    func scored(_ state: State, _ score: Int, _ band: String, _ closure: String?, at: Date) -> State {
        FieldActivityAttributes.rescored(state, score: score, band: band, closure: closure, at: at)
    }

    /// A state written by build 8 has no score: it still decodes, and the faces show the attributes'.
    @Test func buildEightStateDecodesAndShowsTheAttributesScore() throws {
        let (_, _, attributes, _)=try followed()
        let old=#"{"nightVision":false,"finished":false,"heading":true}"#.data(using: .utf8) ?? Data()
        let state=try JSONDecoder().decode(State.self, from: old)
        #expect(state.score == nil && state.scored == nil)
        #expect(attributes.score(state) == 94 && attributes.band(state) == "Pristine" && attributes.closure(state) == "Keys View Road closed")
        #expect(attributes.scoreLine(state) == "94 · Pristine")
        // And the new fields round-trip, within ActivityKit's 4 KB.
        let now=scored(state, 71, "Good", nil, at: attributes.dusk)
        let data=try JSONEncoder().encode(now)
        #expect(try JSONDecoder().decode(State.self, from: data) == now)
        #expect(try JSONEncoder().encode(attributes).count+data.count<4096)
    }

    /// More than 18 hours before dusk the face names the score's day, and VoiceOver hears it in full.
    @Test func oldScoreNamesItsDay() throws {
        let (_, _, attributes, heading)=try followed()
        // Wednesday 9 December, four days before.
        let wednesday=attributes.dusk.addingTimeInterval(-4*24*3600)
        let old=scored(heading, 94, "Pristine", "Keys View Road closed", at: wednesday)
        #expect(attributes.scoreLine(old) == "94 · Pristine as of Wed")
        #expect(attributes.spokenScore(old) == "Darkness score 94, Pristine, as of Wednesday.")
        // Twelve hours before dusk is recent: no day.
        let recent=scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-12*3600))
        #expect(attributes.scoreLine(recent) == "94 · Pristine" && attributes.spokenScore(recent) == "Darkness score 94, Pristine.")
        // A night followed ahead by build 8 counts from when it was planned.
        var planned=heading
        planned.updated=wednesday
        #expect(attributes.scoreDay(planned) == wednesday)
    }

    /// A score worked out in the small hours of the night's own day, still more than 18 hours before
    /// sunset (a June night at Joshua Tree, sunset near 8 PM), names its time in park time, never
    /// today's weekday; one from the evening before still names its day.
    @Test func oldScoreFromTheSameDayNamesItsTime() throws {
        let jotr=try park("jotr")
        let sky=engine.conditions(for: jotr, on: jotr.evening(try #require(try? Date("2027-06-20T20:00:00Z", strategy: .iso8601))))
        let attributes=FieldActivityAttributes(night: FieldNight(park: jotr, sky: sky), score: 94, band: "Pristine", closure: nil)
        let heading=attributes.state(at: FieldActivityAttributes.followStart(sky), nightVision: false, heading: true)
        var calendar=Calendar(identifier: .gregorian)
        calendar.timeZone=attributes.timeZone
        let early=calendar.startOfDay(for: attributes.dusk).addingTimeInterval(70*60)
        try #require(attributes.dusk.timeIntervalSince(early)>FieldActivityAttributes.scoreAgeLimit)
        let same=scored(heading, 88, "Excellent", nil, at: early)
        let plain={ (text: String) in text.replacingOccurrences(of: "\u{202F}", with: " ") }
        #expect(plain(attributes.scoreLine(same)) == "88 · Excellent as of 1:10 AM")
        #expect(plain(attributes.spokenScore(same)) == "Darkness score 88, Excellent, as of 1:10 AM.")
        let evening=scored(heading, 88, "Excellent", nil, at: early.addingTimeInterval(-3*3600))
        #expect(attributes.scoreLine(evening) == "88 · Excellent as of Sat")
    }

    /// The closure follows the state: posted after following, it appears; lifted, it goes.
    @Test func closureFollowsTheState() throws {
        let (_, _, attributes, heading)=try followed()
        let lifted=scored(heading, 94, "Pristine", nil, at: .now)
        #expect(attributes.closure(lifted) == nil)
        let plain=FieldActivityAttributes(night: FieldNight(park: try park("jotr"), sky: try followed().sky), score: 94, band: "Pristine")
        let posted=scored(heading, 94, "Pristine", "Park Boulevard closed", at: .now)
        #expect(plain.closure(heading) == nil && plain.closure(posted) == "Park Boulevard closed")
    }

    /// Without the park's alerts read, the last closure stays: an unknown is never a lifted closure.
    @Test func unknownClosureKeepsTheLastOne() throws {
        let (jotr, sky, attributes, heading)=try followed()
        let night=NightPlanner(forecasts: [:]).night(jotr, on: sky.evening, now: attributes.dusk.addingTimeInterval(-86400))
        let unknown=FieldActivities.Now(night: night, closure: nil, closureKnown: false)
        let known=FieldActivities.Now(night: night, closure: nil, closureKnown: true)
        let now=attributes.dusk.addingTimeInterval(-3600)
        #expect(FieldActivities.scored(unknown, attributes: attributes, previous: heading, now: now)?.closure == "Keys View Road closed")
        #expect(FieldActivities.scored(known, attributes: attributes, previous: heading, now: now)?.closure == nil)
        #expect(FieldActivities.scored(known, attributes: attributes, previous: heading, now: now)?.score == night.score.value)
        // Nothing handed over: the state keeps what it carries.
        let carried=scored(heading, 80, "Excellent", nil, at: now)
        #expect(FieldActivities.scored(nil, attributes: attributes, previous: carried, now: now) == carried.scored)
    }

    /// The score's time is its forecast's; a night no forecast reaches is scored now.
    @Test func scoreTimeIsTheForecastsTime() throws {
        let (jotr, sky, attributes, _)=try followed()
        let now=attributes.dusk.addingTimeInterval(-2*86400)
        let hours=(0..<(16*24)).map { floor(now.timeIntervalSince1970/86400)*86400-86400+Double($0)*3600 }
        let issued=now.addingTimeInterval(-5*3600)
        let forecast=Forecast(updated: issued, times: hours, clouds: hours.map { _ in 70 })
        let clouded=NightPlanner(forecasts: ["jotr": forecast]).night(jotr, on: sky.evening, now: now)
        #expect(clouded.forecastUpdated == issued && FieldActivities.scoredAt(clouded, now: now) == issued)
        let usual=NightPlanner(forecasts: [:]).night(jotr, on: sky.evening, now: now)
        #expect(FieldActivities.scoredAt(usual, now: now) == now)
    }

    /// The decision: a scheduled night is requested again when its face changed and Nyx is in the
    /// foreground; a running one is updated; nothing changes without a new score.
    @Test func refreshDecidesKeepUpdateOrReschedule() throws {
        let (_, _, attributes, heading)=try followed()
        // Tuesday 8 and Saturday 12 December, in park time, before Sunday's dusk.
        let tuesday=attributes.dusk.addingTimeInterval(-5*24*3600), saturday=attributes.dusk.addingTimeInterval(-26*3600)
        let followed=scored(heading, 94, "Pristine", "Keys View Road closed", at: tuesday)
        func action(pending: Bool, canRequest: Bool=true, _ previous: State, _ next: Scored?) -> FieldActivities.Action {
            FieldActivities.action(pending: pending, canRequest: canRequest, attributes: attributes, previous: previous, scored: next)
        }
        // Scheduled: 70% cloud arrived, the band changed.
        #expect(action(pending: true, followed, Scored(score: 58, band: "Fair", closure: "Keys View Road closed", at: saturday)) == .reschedule)
        // Scheduled: the closure lifted, or a new one posted.
        #expect(action(pending: true, followed, Scored(score: 94, band: "Pristine", closure: nil, at: saturday)) == .reschedule)
        #expect(action(pending: true, followed, Scored(score: 94, band: "Pristine", closure: "Park Boulevard closed", at: saturday)) == .reschedule)
        // Scheduled: the same answer from a later day moves its "as of" day, so it is requested again.
        #expect(action(pending: true, followed, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: saturday)) == .reschedule)
        // ... and confirmed within 18 hours of dusk, it names no day at all.
        #expect(action(pending: true, followed, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: attributes.dusk.addingTimeInterval(-3600))) == .reschedule)
        // Scheduled: the same answer later the same day shows the same face and keeps its plan.
        #expect(action(pending: true, followed, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: tuesday.addingTimeInterval(3600))) == .keep)
        #expect(action(pending: true, followed, nil) == .keep)
        // In the background iOS refuses a request: a scheduled night keeps its plan, never unfollowed.
        #expect(action(pending: true, canRequest: false, followed, Scored(score: 58, band: "Fair", closure: nil, at: saturday)) == .keep)
        #expect(action(pending: true, canRequest: false, followed, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: saturday)) == .keep)
        // A build-8 scheduled night (no score in its state) compares with its attributes.
        let recent=attributes.dusk.addingTimeInterval(-3600)
        #expect(action(pending: true, heading, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: recent)) == .keep)
        #expect(action(pending: true, heading, Scored(score: 61, band: "Good", closure: "Keys View Road closed", at: recent)) == .reschedule)
        // Running: any change of score, band or closure updates it, foreground or not.
        let running=attributes.state(at: attributes.dusk.addingTimeInterval(3000), nightVision: false)
        let tonight=scored(running, 94, "Pristine", "Keys View Road closed", at: attributes.dusk.addingTimeInterval(-3600))
        #expect(action(pending: false, canRequest: false, tonight, Scored(score: 92, band: "Pristine", closure: "Keys View Road closed", at: attributes.dusk)) == .update)
        #expect(action(pending: false, tonight, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: attributes.dusk)) == .keep)
        // Running with Tuesday's score: the same score confirmed today drops "as of Tue".
        let stale=scored(running, 94, "Pristine", "Keys View Road closed", at: tuesday)
        #expect(action(pending: false, stale, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: attributes.dusk)) == .update)
        // ... and confirmed on a later, still old, day it reads that day instead.
        #expect(action(pending: false, stale, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: saturday)) == .update)
        #expect(action(pending: false, stale, Scored(score: 94, band: "Pristine", closure: "Keys View Road closed", at: tuesday.addingTimeInterval(3600))) == .keep)
    }

    /// `changed` ignores the exact score time unless it changes the day the face names.
    @Test func changedIgnoresScoreTimeUnlessTheDayShows() throws {
        let (_, _, attributes, heading)=try followed()
        let a=scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-3600))
        let b=scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-7200))
        #expect(!FieldActivities.changed(a, b, attributes: attributes))
        let old=scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-3*86400))
        #expect(FieldActivities.changed(a, old, attributes: attributes))
        // Two old scores from different days name different days; from the same day, the same one.
        let older=scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-4*86400))
        #expect(attributes.scoreLine(old) != attributes.scoreLine(older))
        #expect(FieldActivities.changed(old, older, attributes: attributes))
        #expect(!FieldActivities.changed(old, scored(heading, 94, "Pristine", nil, at: attributes.dusk.addingTimeInterval(-3*86400+3600)), attributes: attributes))
        #expect(FieldActivities.changed(a, scored(heading, 94, "Pristine", "Park Boulevard closed", at: attributes.dusk.addingTimeInterval(-3600)), attributes: attributes))
    }
}
