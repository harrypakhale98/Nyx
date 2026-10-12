import Foundation
import Testing
@testable import Nyx

/// A slow launch never shows a score its caches would change, and its decoration never delays the
/// scores: every tab but the Journal waits behind one gate; the launch skies come after the reads;
/// the sky cache keeps what was used last; the dial's frames stop with its count, and a landing on
/// 70 or 90 is one haptic, not two.
@MainActor struct LaunchGateTests {
    private static func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }

    // MARK: The score gate

    @Test func everyTabButTheJournalWaitsForTheCaches() {
        for tab in SceneCommands.tabs.indices { #expect(ScoreGate.gates(tab: tab) == (tab != 3), "tab \(tab)") }
        // A tab added later waits unless it is listed as carrying no score.
        #expect(ScoreGate.gates(tab: SceneCommands.tabs.count))
        #expect(ScoreGate.waits(enabled: true, cachesPending: true))
        #expect(!ScoreGate.waits(enabled: true, cachesPending: false))
        #expect(!ScoreGate.waits(enabled: false, cachesPending: true))
    }

    // MARK: Launch skies after the reads

    @Test func launchSkiesFollowTheReadsWithoutHoldingThem() async throws {
        let preload=CachePreload.start()
        let read=await preload.contents()
        // The reads are complete without the skies: those arrive on their own.
        #expect(read.skies.isEmpty)
        let skies=await preload.skies()
        let expected=CachePreload.skyParks(try ParkData.load())
        #expect(skies.count == expected.count)
        #expect(Set(skies.map(\.id)) == Set(expected.map { SkyProjection.key(park: $0, night: $0.currentNight(at: .now)) }))
        // Once built, the first frame's wait brings them along.
        #expect(preload.wait(timeout: 5)?.skies.count == expected.count)
    }

    // MARK: The sky cache

    @Test func skyCacheLetsGoOfTheLeastRecentlyUsed() throws {
        let park=try Self.park("jotr"), cache=SkyProjection(capacity: 3)
        let start=park.currentNight(at: Date(timeIntervalSince1970: 1_792_080_000))
        let nights=(0..<4).map { park.date(start, addingDays: $0) }
        let keys=nights.map { SkyProjection.key(park: park, night: $0) }
        func sky(_ index: Int) -> SkyProjection.Sky { SkyProjection.Sky(id: keys[index], faint: [], middle: [], bright: [], galaxy: [], dark: true) }
        for index in 0..<3 { cache.store(sky(index)) }
        // The oldest is read (a screen drawing it), so the next arrival lets go of the second instead.
        #expect(cache.sky(for: park, night: nights[0]).id == keys[0])
        cache.store(sky(3))
        #expect(cache.holds(keys[0]) && !cache.holds(keys[1]) && cache.holds(keys[2]) && cache.holds(keys[3]))
        // Storing one already kept counts as a use too.
        cache.store(sky(2))
        cache.store(sky(1))
        #expect(!cache.holds(keys[0]) && cache.holds(keys[1]) && cache.holds(keys[2]) && cache.holds(keys[3]))
        // Asking whether a sky is kept is not a use.
        #expect(cache.holds(keys[3]))
        cache.store(sky(0))
        #expect(!cache.holds(keys[3]) && cache.holds(keys[0]))
        // Room for the launch's skies and a river's thirty.
        #expect(SkyProjection.capacity >= CachePreload.skyLimit+30)
    }

    // MARK: The dial

    @Test func onlyTheOdometerKeepsTheDialsFramesRunning() {
        let plans: [CelestialGauge.RevealPlan]=[.hold, .instant, .sweep, .settle, .odometer]
        for plan in plans { #expect(CelestialGauge.counts(after: plan) == (plan == .odometer)) }
        let began=Date.now
        #expect(CelestialGauge.framesRun(countStart: began, counting: true, still: false))
        // A count overtaken by a hold (counting stopped) or landed (no start) asks for no frames.
        #expect(!CelestialGauge.framesRun(countStart: began, counting: false, still: false))
        #expect(!CelestialGauge.framesRun(countStart: nil, counting: true, still: false))
        #expect(!CelestialGauge.framesRun(countStart: began, counting: true, still: true))
    }
    @Test func aLandingOnAMilestoneIsOneHaptic() {
        #expect(CelestialGauge.landingPulse(from: 69, score: 70) == .milestone)
        #expect(CelestialGauge.landingPulse(from: 89, score: 90) == .milestone)
        #expect(CelestialGauge.landingPulse(from: 70, score: 70) == .light)
        #expect(CelestialGauge.landingPulse(from: 93, score: 94) == .light)
        // Frames then the landing: each milestone once, and the landing exactly one haptic.
        for rate in [24.0, 60, 120] {
            for score in [70, 90, 94] {
                var shown=0, mediums=0
                let frames=Int((CelestialGauge.duration(score: score)*rate).rounded(.down))
                for frame in 0..<frames {
                    let value=CelestialGauge.countValue(score: score, at: Double(frame)/rate)
                    mediums+=CelestialGauge.milestones(from: shown, to: value).isEmpty ? 0 : 1
                    shown=value
                }
                let landing=CelestialGauge.landingPulse(from: shown, score: score)
                if landing == .milestone { mediums+=1 }
                #expect(mediums == (score>=90 ? 2 : 1), "\(score) at \(rate) Hz")
            }
        }
    }
}
