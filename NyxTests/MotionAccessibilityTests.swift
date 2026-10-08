import Foundation
import Testing
@testable import Nyx

/// What VoiceOver hears beside the week strip, the rule behind Tonight's double tap, and the
/// record that keeps that tap to once per park and night.
@MainActor @Suite struct MotionAccessibilityTests {
    let engine=AstronomyEngine()
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func nights(_ park:Park,scores:[Int],basis:CloudBasis) throws -> [Night] {
        let start=try #require(try? Date("2026-10-12T20:00:00Z",strategy:.iso8601))
        return scores.enumerated().map { index,score in
            let sky=engine.conditions(for:park,on:park.evening(start.addingTimeInterval(Double(index)*86400)))
            return Night(park:park,sky:sky,score:DarknessScore(value:score,moonPoints:30,cloudPoints:20,bortlePoints:16,lengthPoints:10,basis:basis),cloudCover:5,forecastUpdated:.now)
        }
    }

    @Test func weekSummaryKeepsTheForecastCaveat() throws {
        let jotr=try park("jotr")
        let forecast=try #require(WeekStrip.summary(try nights(jotr,scores:[60,88,70],basis:.forecast)))
        #expect(!forecast.contains("Early look") && !forecast.contains("No cloud forecast yet"))
        let early=try #require(WeekStrip.summary(try nights(jotr,scores:[60,88,70],basis:.blended(weight:0.5,leadDays:6))))
        #expect(early.hasSuffix("Early look."))
        let usual=try #require(WeekStrip.summary(try nights(jotr,scores:[90,70],basis:.usual)))
        #expect(usual.hasPrefix("Tonight is the best night this week.") && usual.hasSuffix("No cloud forecast yet."))
    }

    @Test func doubleTapFollowsTheReminderRule() throws {
        let jotr=try park("jotr")
        let pristine=try nights(jotr,scores:[94],basis:.forecast)[0]
        #expect(pristine.sky.darkHours==0 || NotificationScheduler.worthAReminder(pristine))
        #expect(!NotificationScheduler.worthAReminder(try nights(jotr,scores:[89],basis:.forecast)[0]))
        // No reminder, and no tap, for a night without a full forecast.
        #expect(!NotificationScheduler.worthAReminder(try nights(jotr,scores:[96],basis:.usual)[0]))
        #expect(!NotificationScheduler.worthAReminder(try nights(jotr,scores:[96],basis:.blended(weight:0.6,leadDays:5))[0]))
    }

    @Test func eachFoundNightIsFeltOnce() throws {
        let defaults=try #require(UserDefaults(suiteName:"MotionAccessibilityTests"))
        defaults.removePersistentDomain(forName:"MotionAccessibilityTests")
        #expect(!FoundNights.felt("jotr-2026-10-12",defaults:defaults))
        FoundNights.note("jotr-2026-10-12",defaults:defaults)
        #expect(FoundNights.felt("jotr-2026-10-12",defaults:defaults))
        // Only the most recent twenty are kept.
        for day in 0..<25 { FoundNights.note("deva-\(day)",defaults:defaults) }
        #expect(!FoundNights.felt("jotr-2026-10-12",defaults:defaults))
        #expect(FoundNights.felt("deva-24",defaults:defaults) && !FoundNights.felt("deva-4",defaults:defaults) && FoundNights.felt("deva-5",defaults:defaults))
        defaults.removePersistentDomain(forName:"MotionAccessibilityTests")
    }
}
