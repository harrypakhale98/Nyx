import CoreGraphics
import Foundation
import Testing
@testable import Nyx

/// Motion: skies built ahead (off the main thread, from the nights' own astronomy, with
/// sidereal time worked out once) are the skies a screen builds on demand; the river finds its
/// night and best nights as before; the dial's count is a function of time alone and crosses each
/// milestone once at any frame rate; decoration rests by one rule; the lamp's growing dark covers
/// the whole window at the moment the palette turns; a month's rings light along the way it moved.
@MainActor struct MotionTests {
    /// A fixed autumn night (October 15, 2026), so every run checks the same sky.
    private static let date=Date(timeIntervalSince1970: 1_792_080_000)
    private static func night(_ park: Park, days: Int=0) -> Night {
        let evening=park.evening(park.date(park.evening(date), addingDays: days))
        return NightPlanner.night(park: park, sky: AstronomyEngine().conditions(for: park, on: evening), forecast: nil, detail: nil, now: date)
    }
    private static func positions(_ stars: [SkyProjection.Star]) -> [SIMD2<Double>] { stars.map(\.position) }

    // MARK: Skies built ahead

    @Test func siderealOncePerSkyGivesIdenticalPositions() throws {
        let engine=AstronomyEngine()
        for id in ["jotr", "dena", "npsa"] {
            let park=try park(id), moment=Self.date.addingTimeInterval(9*3600)
            let sidereal=engine.localSidereal(date: moment, park: park)
            for star in SkyProjection.catalogue.prefix(300) {
                let each=engine.horizontal(date: moment, park: park, ra: star.ra, dec: star.dec)
                let once=engine.horizontal(localSidereal: sidereal, latitude: park.latitude, ra: star.ra, dec: star.dec)
                #expect(each.altitude == once.altitude && each.azimuth == once.azimuth)
            }
        }
    }
    @Test func realSkyFromTheModelsAstronomyIsTheOnDemandSky() throws {
        for id in ["jotr", "dena", "npsa", "gaar"] {
            let park=try park(id), night=Self.night(park)
            let lights=SkyProjection.shared.lightSources(park)
            let ahead=SkyProjection.build(park: park, night: night.id, conditions: night.sky, lights: lights)
            let fresh=SkyProjection.build(park: park, night: night.id, lights: lights)
            #expect(ahead.id == fresh.id && ahead.id == SkyProjection.key(park: park, night: night.id))
            #expect(Self.positions(ahead.faint) == Self.positions(fresh.faint))
            #expect(Self.positions(ahead.middle) == Self.positions(fresh.middle))
            #expect(Self.positions(ahead.bright) == Self.positions(fresh.bright))
            #expect(ahead.galaxy.map { $0.map(\.position) } == fresh.galaxy.map { $0.map(\.position) })
            #expect(ahead.planets.map(\.position) == fresh.planets.map(\.position) && ahead.radiant?.position == fresh.radiant?.position)
            #expect(ahead.domes.map(\.base) == fresh.domes.map(\.base) && ahead.sunAltitude == fresh.sunAltitude && ahead.dark == fresh.dark)
        }
    }
    @Test func skyWindowFromTheModelsAstronomyIsTheOnDemandSky() throws {
        for id in ["jotr", "acad"] {
            let park=try park(id), night=Self.night(park, days: 3)
            let moment=SkyWindowCard.moment(night.sky), lights=SkyProjection.shared.lightSources(park)
            let ahead=HorizonSkies.build(park: park, night: night.id, at: moment, conditions: night.sky, lights: lights)
            let fresh=HorizonSkies.build(park: park, night: night.id, at: moment, lights: lights)
            #expect(ahead.id == fresh.id && ahead.id == HorizonSkies.key(park: park, at: moment))
            #expect(ahead.stars.map(\.altitude) == fresh.stars.map(\.altitude) && ahead.stars.map(\.azimuth) == fresh.stars.map(\.azimuth))
            #expect(ahead.dust.count == fresh.dust.count && ahead.dust.map(\.azimuth) == fresh.dust.map(\.azimuth))
            #expect(ahead.named.map(\.name) == fresh.named.map(\.name) && ahead.figures.count == fresh.figures.count)
            #expect(ahead.moon?.altitude == fresh.moon?.altitude && ahead.radiant?.name == fresh.radiant?.name && ahead.sunAltitude == fresh.sunAltitude)
        }
    }
    @Test func skiesBuiltAheadAreTheOnesTheScreensDraw() async throws {
        let park=try park("grba")
        let nights=(0..<2).map { Self.night(park, days: 40+$0) }
        await SkyAhead.prepare(nights, trusted: true)
        for night in nights {
            #expect(SkyProjection.shared.holds(SkyProjection.key(park: park, night: night.id)))
            #expect(HorizonSkies.shared.holds(HorizonSkies.key(park: park, at: SkyWindowCard.moment(night.sky))))
            let drawn=SkyProjection.shared.sky(for: park, night: night.id)
            let fresh=SkyProjection.build(park: park, night: night.id, lights: SkyProjection.shared.lightSources(park))
            #expect(Self.positions(drawn.bright) == Self.positions(fresh.bright) && Self.positions(drawn.faint) == Self.positions(fresh.faint))
        }
    }
    @Test func theMoonsMomentIsKeptNotChanged() throws {
        let park=try park("jotr"), night=Self.night(park, days: 5)
        let kept=MoonMoments.moon(for: night), again=MoonMoments.moon(for: night), fresh=AstronomyEngine().moon(for: night)
        #expect(kept.moment == fresh.moment && kept.geometry == fresh.geometry && again.moment == kept.moment)
    }
    @Test func launchSkiesStartAtTheStartingPark() throws {
        let parks=try ParkData.load()
        let defaults=try #require(UserDefaults(suiteName: "nyx-motion-\(UUID().uuidString)"))
        let chosen=CachePreload.skyParks(parks, defaults: defaults, locale: Locale(identifier: "en_US"))
        #expect(chosen.first?.id == Park.defaultID && chosen.count <= CachePreload.skyLimit)
        #expect(Set(chosen.map(\.id)).count == chosen.count)
    }

    // MARK: The river

    @Test func riverFindsTheNightAsTheSameParkDayDid() throws {
        let park=try park("jotr")
        let nights=(0..<30).map { Self.night(park, days: $0) }
        let calendar=park.calendar
        for day in [0, 1, 7, 29, 30, -1] {
            for hour in [0, 1, 11, 12, 13, 23] {
                let base=park.date(park.evening(Self.date), addingDays: day)
                let date=try #require(calendar.date(bySettingHour: hour, minute: 30, second: 0, of: base))
                let before=nights.firstIndex { calendar.isDate($0.id, inSameDayAs: date) }
                #expect(TimeRiver.index(of: date, in: nights) == before)
            }
        }
        #expect(TimeRiver.index(of: Self.date, in: []) == nil)
    }
    /// Consecutive Joshua Tree nights scoring `values`, every part alike but the score.
    private static func river(_ values: [Int]) throws -> [Night] {
        let park=try park("jotr"), engine=AstronomyEngine()
        return values.enumerated().map { i, value in
            Night(park: park, sky: engine.conditions(for: park, on: park.date(park.evening(date), addingDays: i)),
                  score: DarknessScore(value: value, moonPoints: 30, cloudPoints: 20, bortlePoints: 18, lengthPoints: 12), cloudCover: 10, forecastUpdated: date)
        }
    }
    @Test func riverPeaksAreTheThreeBestAtLeastGood() throws {
        #expect(TimeRiver.peaks(try Self.river([50, 90, 61, 90, 75, 59])) == [1, 3, 4])
        #expect(TimeRiver.peaks(try Self.river([59, 40, 10])) == [])
        // Best first; a tie broken as every best night is (`NightPlanner.better`); the set is the same nights.
        let even=try Self.river([80, 80, 80, 80])
        #expect(TimeRiver.peakOrder(even) == NightPlanner.ranked(even).prefix(3).compactMap { night in even.firstIndex { $0.id == night.id } })
        let mixed=try Self.river([50, 90, 61, 90, 75, 59])
        #expect(Array(TimeRiver.peakOrder(mixed).suffix(1)) == [4] && Set(TimeRiver.peakOrder(mixed).prefix(2)) == [1, 3])
        #expect(TimeRiver.peakOrder(mixed).first == mixed.firstIndex { $0.id == NightPlanner.best(mixed)?.id })
        #expect(TimeRiver.peakOrder(try Self.river([60, 75, 99, 40])) == [2, 1, 0])
    }

    // MARK: The count-up

    @Test func countIsAFunctionOfTimeAndLandsOnTheScore() {
        for score in [0, 12, 69, 70, 89, 94, 100] {
            let total=CelestialGauge.duration(score: score)
            var last=0
            for frame in 0...Int(total*240)+2 {
                let value=CelestialGauge.countValue(score: score, at: Double(frame)/240)
                #expect(value >= last && value <= score)
                last=value
            }
            #expect(CelestialGauge.countValue(score: score, at: total) == score)
        }
    }
    @Test func milestonesAreCrossedOnceAtAnyFrameRate() {
        for rate in [24.0, 60, 120] {
            for (score, expected) in [(94, [70, 90]), (72, [70]), (65, []), (100, [70, 90])] {
                var shown=0, crossed:[Int]=[]
                let frames=Int((CelestialGauge.duration(score: score)*rate).rounded(.up))
                for frame in 0...frames {
                    let value=CelestialGauge.countValue(score: score, at: Double(frame)/rate)
                    crossed+=CelestialGauge.milestones(from: shown, to: value)
                    shown=value
                }
                // The landing writes the score itself: never a second crossing.
                crossed+=CelestialGauge.milestones(from: shown, to: score)
                #expect(crossed == expected, "\(score) at \(rate) Hz")
            }
        }
    }
    @Test func quickeningIsContinuousAndSettles() {
        #expect(CelestialGauge.surgeTurn(-1) == 0 && CelestialGauge.surgeTurn(0) == 0)
        var last=0.0
        for step in 1...300 { let turn=CelestialGauge.surgeTurn(Double(step)/120); #expect(turn > last); last=turn }
        #expect(abs(CelestialGauge.surgeTurn(3)-CelestialGauge.surgeAngle) < 0.001)
        // A frame's step stays small: no visible jump at 30 Hz.
        #expect(CelestialGauge.surgeTurn(1.0/30) < 0.2)
        let start=CelestialGauge.landingGlow(0), end=CelestialGauge.landingGlow(1.2)
        #expect(start.strength == 0 && end.strength == 0 && CelestialGauge.landingGlow(0.05).strength > 0.8)
    }

    // MARK: Decoration, the lamp, the month, the loader

    @Test func decorationRestsByOneRule() {
        #expect(!Decoration.rests(still: false, covered: false, offscreen: false, lowPower: false, hot: false))
        for flags in [(true, false, false, false, false), (false, true, false, false, false), (false, false, true, false, false),
                      (false, false, false, true, false), (false, false, false, false, true)] {
            #expect(Decoration.rests(still: flags.0, covered: flags.1, offscreen: flags.2, lowPower: flags.3, hot: flags.4))
        }
        #expect(Decoration.rate == 30)
    }
    /// The tilt is read as the screen sees it: held at the reading angle in either landscape, the
    /// dial's glint rests where it does in portrait, and tipping the screen's right edge down reads as
    /// right in every orientation (the same quarter turns as the compass's `Pose.turned`).
    @Test func tiltFollowsTheInterfaceOrientation() {
        // Portrait, held up: gravity toward the device's bottom.
        #expect(MotionTilt.screenGravity(x:0,y:-0.6,quarterTurns:0) == (0,-0.6))
        // Landscape right (the device's top at the screen's left), held up: gravity toward the device's left edge,
        // which is the screen's bottom.
        #expect(MotionTilt.screenGravity(x:-0.6,y:0,quarterTurns:1) == (0,-0.6))
        // Landscape left: the device's right edge is the screen's bottom.
        #expect(MotionTilt.screenGravity(x:0.6,y:0,quarterTurns:3) == (0,-0.6))
        // The screen's right edge down: toward the device's bottom in landscape right, its top in landscape left.
        #expect(MotionTilt.screenGravity(x:0,y:-0.5,quarterTurns:1).x == 0.5)
        #expect(MotionTilt.screenGravity(x:0,y:0.5,quarterTurns:3).x == 0.5)
        #expect(MotionTilt.screenGravity(x:0.3,y:-0.6,quarterTurns:2) == (-0.3,0.6))
        #expect(MotionTilt.screenGravity(x:0.3,y:-0.6,quarterTurns:-1) == MotionTilt.screenGravity(x:0.3,y:-0.6,quarterTurns:3))
    }
    @Test func lampDarkCoversTheWindowWhenThePaletteTurns() {
        let size=CGSize(width: 390, height: 844)
        for center in [CGPoint(x: 360, y: 60), CGPoint(x: 20, y: 820), CGPoint(x: 195, y: 422), CGPoint(x: -10, y: -10)] {
            let full=NightVisionLamp.radius(cover: 1, center: center, size: size)
            let solid=full-NightVisionLamp.feather
            for corner in [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)] {
                #expect(hypot(corner.x-center.x, corner.y-center.y) <= solid+0.0001)
            }
            #expect(NightVisionLamp.radius(cover: 0, center: center, size: size) == 0 && NightVisionLamp.radius(cover: -0.1, center: center, size: size) == 0)
            #expect(NightVisionLamp.radius(cover: 0.5, center: center, size: size) < full)
        }
    }
    @Test func ringsLightAlongTheWayTheMonthMoved() {
        let nights=(0..<5).map { Self.date.addingTimeInterval(Double($0)*86_400) }
        #expect(CalendarView.lightingOrder(nights, forward: true) == nights)
        #expect(CalendarView.lightingOrder(nights, forward: false) == Array(nights.reversed()))
        #expect(CalendarView.ringStagger == 0.06)
    }
    @Test func skeletonLightPassesAndReturns() {
        #expect(SkeletonRow.sweep(0) == 0)
        #expect(SkeletonRow.sweep(1.799) > 0.999 && SkeletonRow.sweep(1.8) < 0.001)
        var last = -1.0
        for step in 0..<180 { let x=SkeletonRow.sweep(Double(step)/100); #expect(x >= last && x <= 1); last=x }
    }
    @Test func trackingSpringIsQuickerThanTheShared() {
        #expect(NyxMotion.trackingResponse < NyxMotion.response/3 && NyxMotion.trackingDamping >= NyxMotion.dampingFraction)
        #expect(CelestialGauge.settleDuration == NyxMotion.settleDuration)
    }
}
