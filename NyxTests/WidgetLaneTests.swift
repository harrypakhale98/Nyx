import AlarmKit
import Foundation
import Testing
import WidgetKit
@testable import Nyx

/// What the widgets and the field alarm's Live Activity say outside the app: a park's closure in
/// every Tonight family (the Lock Screen and the small widget show only its mark, so VoiceOver
/// must say it whole), the Moon's Lock Screen rectangle, and a snoozed alarm's states.
@MainActor @Suite struct WidgetLaneTests {
    private let now = Date(timeIntervalSince1970: 1_791_158_400) // 2026-10-05 00:00 UTC
    private let closure = "Keys View Road closed at night"

    @Test func everyFamilySpeaksTheClosureWholeAfterTheScore() throws {
        var builder = TonightTimeline(snapshot: SavedSkySnapshot(parks: [try park("jotr")], forecasts: [:]), large: true)
        var entry = builder.entry(at: now)
        let night = try #require(entry.night)
        var families: [WidgetFamily] = [.accessoryInline, .accessoryCircular, .accessoryRectangular, .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, *) { families.append(.systemExtraLargePortrait) }
        for family in families {
            entry.closure = nil
            let plain = TonightWidgetView.summary(night, entry: entry, family: family)
            #expect(!plain.contains("Closure alert"), "\(family)")
            entry.closure = closure
            let spoken = TonightWidgetView.summary(night, entry: entry, family: family)
            #expect(spoken.contains("Closure alert: \(closure)"), "\(family)")
            // The score is said first, and the closure adds to the summary without replacing anything.
            let score = try #require(spoken.range(of: "\(night.score.value) out of 100"), "\(family)")
            let alert = try #require(spoken.range(of: "Closure alert"), "\(family)")
            #expect(score.upperBound <= alert.lowerBound, "\(family)")
            #expect(spoken.replacingOccurrences(of: " Closure alert: \(closure)", with: "") == plain, "\(family)")
        }
    }

    @Test func moonRectangleNamesThePhaseTheLightAndTheNextRiseOrSetInParkTime() throws {
        let jotr = try park("jotr")
        var parkTime = Date.FormatStyle.dateTime.hour().minute()
        parkTime.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        for step in 0..<16 {
            let date = now.addingTimeInterval(Double(step)*11*3600)
            let moon = MoonNow(at: date, park: jotr)
            let text = MoonRectangleText(moon: moon, park: jotr, locale: Locale(identifier: "en_US"))
            #expect(text.phase == moon.phase.name)
            #expect(text.lit == "\(moon.percent)% lit")
            let next = try #require(moon.next)
            let time = next.date.formatted(parkTime)
            #expect(text.shortEvent == (next.rises ? "Rises \(time)" : "Sets \(time)"), "\(step)")
            #expect(text.event == (next.rises ? "Rises \(time) · Joshua Tree" : "Sets \(time) · Joshua Tree"), "\(step)")
        }
    }

    @Test func moonRectangleFollowsTheReadersPercentAndSaysNoEventItCannotKnow() throws {
        let gaar = try park("gaar")
        let moon = MoonNow(at: now, park: nil)
        // The reader's own percent style: "42 %" in French, never the English "42%".
        let french = MoonRectangleText(moon: moon, park: nil, locale: Locale(identifier: "fr_FR"))
        #expect(french.lit.hasPrefix("\(moon.percent)") && french.lit != "\(moon.percent)% lit")
        // Without a park there is no rise or set; far north, the Moon may neither rise nor set for days.
        #expect(french.event == nil && french.shortEvent == nil)
        let north = MoonRectangleText(moon: MoonNow(at: now, park: gaar, events: []), park: gaar)
        #expect(north.event == nil && north.shortEvent == nil && north.phase == moon.phase.name)
    }

    @Test func aSnoozedAlarmSaysWhatItIsDoingAndHoldsItsTimeWhenPaused() {
        let fire = now.addingTimeInterval(540)
        let snoozing = FieldAlarmStatus(.countdown(.init(totalCountdownDuration: 540, previouslyElapsedDuration: 0, startDate: now, fireDate: fire)))
        let paused = FieldAlarmStatus(.paused(.init(totalCountdownDuration: 540, previouslyElapsedDuration: 170)))
        let ringing = FieldAlarmStatus(.alert(.init(time: .init(hour: 19, minute: 42))))
        #expect(snoozing.phase == .snoozing(fire: fire))
        #expect(paused.phase == .paused(left: 370))
        #expect(ringing.phase == .ringing)
        // AlarmKit's own titles where Nyx set them; Nyx's words where it did not.
        #expect(snoozing.line(countdownTitle: "Snoozing", pausedTitle: nil, park: "Joshua Tree") == "Snoozing · Joshua Tree")
        #expect(paused.line(countdownTitle: "Snoozing", pausedTitle: nil, park: "Joshua Tree") == "Snooze paused · Joshua Tree")
        #expect(paused.word(countdownTitle: nil, pausedTitle: "Held") == "Held")
        #expect(ringing.line(countdownTitle: "Snoozing", pausedTitle: nil, park: "Joshua Tree") == "Joshua Tree")
        #expect([snoozing, paused, ringing].map(\.symbol) == ["zzz", "pause.fill", "alarm"])
        // A paused snooze's time is rounded up, never down to nothing, and never negative.
        #expect(FieldAlarmStatus.left(370) == "7 min")
        #expect(FieldAlarmStatus.left(0) == "1 min")
        #expect(FieldAlarmStatus(.paused(.init(totalCountdownDuration: 60, previouslyElapsedDuration: 90))).phase == .paused(left: 0))
    }
}
