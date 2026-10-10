import Foundation
import Testing
import simd
@testable import Nyx

/// Field mode: the night's milestones and what "now" says, the eye's clock, the wake-up times,
/// the compass geometry and the Live Activity's payload. Real computed nights throughout.
@Suite struct FieldModeTests {
    let engine = AstronomyEngine()
    func park(_ id: String) throws -> Park { try #require(try ParkData.load().first(where: { $0.id == id })) }
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }

    // MARK: Milestones

    /// Geminid peak night at Joshua Tree: sunset to sunrise in order, with darkness, dawn and the shower.
    @Test func milestonesRunSunsetToSunriseInOrder() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-12-13")
        let night = FieldNight(park: jotr, sky: sky)
        let kinds = night.milestones.map(\.kind)
        #expect(kinds.first == .sunset && kinds.last == .sunrise)
        #expect(zip(night.milestones, night.milestones.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(night.milestones.first { $0.kind == .darkness }?.date == sky.darkStart)
        #expect(night.milestones.first { $0.kind == .dawn }?.date == sky.darkEnd)
        let shower = try #require(night.milestones.first { $0.kind == .shower })
        #expect(shower.title == "Geminids at their best" && shower.detail.contains("an hour from this park"))
        #expect(Set(night.milestones.map(\.id)).count == night.milestones.count)
        // Venus sets in the evening twilight; nothing is invented outside the night.
        let window = SkyAlmanac.nightWindow(sky)
        #expect(night.milestones.allSatisfy { $0.date >= window.start.addingTimeInterval(-60) && $0.date <= window.end.addingTimeInterval(60) })
    }
    @Test func nextAndStatusFollowTheClock() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-12-13")
        let night = FieldNight(park: jotr, sky: sky)
        let start = try #require(sky.darkStart), end = try #require(sky.darkEnd), sunrise = try #require(sky.sunrise)
        let early = start.addingTimeInterval(-14*60)
        #expect(night.next(after: early)?.kind == .darkness)
        let waiting = night.status(at: early)
        #expect(waiting.phase == .waiting && waiting.target == start && waiting.lead == "True darkness in")
        #expect(waiting.trailing.hasPrefix("at ") && waiting.trailing.contains(", then ") && waiting.spoken.contains("14 minutes"))
        let dark = night.status(at: start.addingTimeInterval(3600))
        #expect(dark.phase == .dark && dark.target == end)
        #expect(night.status(at: end.addingTimeInterval(60)).phase == .dawn)
        #expect(night.status(at: sunrise.addingTimeInterval(60)).phase == .over && night.isOver(at: sunrise))
        #expect(night.next(after: start)?.date ?? .distantFuture > start)
        #expect(night.upcoming(after: sunrise).isEmpty)
    }
    /// Denali at midsummer: no darkness milestone, said plainly; the night still ends.
    @Test func midnightSunHasNoDarkness() throws {
        let dena = try park("dena"), sky = try sky(dena, "2026-06-21")
        let night = FieldNight(park: dena, sky: sky)
        #expect(!night.milestones.contains { $0.kind == .darkness || $0.kind == .dawn })
        let status = night.status(at: sky.evening.addingTimeInterval(11*3600))
        #expect(status.phase == .noDarkness && status.target == nil && status.lead == "No true darkness tonight at this latitude.")
        #expect(night.alarmOptions(at: sky.evening).allSatisfy { $0.kind == .moonset } )
        #expect(!night.alarmOptions(at: sky.evening).contains { $0.kind == .darkness || $0.kind == .core })
    }
    /// Gates of the Arctic at the winter solstice: no sunset or sunrise, a long true darkness, and
    /// the night ends with it.
    @Test func polarNightRunsOnDarkness() throws {
        let gaar = try park("gaar"), sky = try sky(gaar, "2026-12-21")
        #expect(sky.state == .polarNight)
        let night = FieldNight(park: gaar, sky: sky)
        #expect(!night.milestones.contains { $0.kind == .sunset || $0.kind == .sunrise })
        let start = try #require(sky.darkStart), end = try #require(sky.darkEnd)
        #expect(night.status(at: start.addingTimeInterval(3600)).phase == .dark)
        #expect(night.isOver(at: end) && !night.isOver(at: end.addingTimeInterval(-60)))
    }
    /// American Samoa, southern hemisphere: an ordinary night with darkness either side of midnight.
    @Test func samoaIsAnOrdinaryNight() throws {
        let npsa = try park("npsa"), sky = try sky(npsa, "2027-07-04")
        let night = FieldNight(park: npsa, sky: sky)
        #expect(night.milestones.first?.kind == .sunset && night.milestones.contains { $0.kind == .darkness })
        // In July the core is high from the southern tropics: it is timed.
        #expect(night.milestones.contains { $0.kind == .coreHighest || $0.kind == .coreRises })
    }

    // MARK: The eye's clock

    @Test func darkAdaptationResetsOnlyAfterRealAbsence() throws {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var eye = DarkAdaptation(start: t0)
        #expect(eye.stage(at: t0.addingTimeInterval(300)) == .cones)
        #expect(eye.stage(at: t0.addingTimeInterval(15*60)) == .rods)
        #expect(eye.stage(at: t0.addingTimeInterval(31*60)) == .adapted && eye.progress(at: t0.addingTimeInterval(3600)) == 1)
        // A glance at a notification: under five seconds away changes nothing.
        eye.leave(at: t0.addingTimeInterval(600))
        #expect(eye.elapsed(at: t0.addingTimeInterval(900)) == 600)
        let glance = eye.returned(at: t0.addingTimeInterval(604))
        #expect(glance == nil && eye.start == t0)
        // Ten minutes away: the clock restarts from the moment of leaving.
        let left = t0.addingTimeInterval(1200)
        eye.leave(at: left); eye.leave(at: left.addingTimeInterval(30))
        let returned = eye.returned(at: left.addingTimeInterval(600))
        let reset = try #require(returned)
        #expect(reset == DarkAdaptation.Reset(at: left, previousStart: t0) && eye.start == left)
        let again = eye.returned(at: left.addingTimeInterval(700))
        #expect(again == nil)
        // "My screen stayed dark."
        eye.undo(reset)
        #expect(eye.start == t0)
    }

    // MARK: Alarms

    /// Over a month at Joshua Tree, every alarm lands on the moment it names, and only ahead of now.
    @Test func alarmTimesMatchTheirMoments() throws {
        let jotr = try park("jotr")
        var kinds = Set<FieldNight.AlarmOption.Kind>()
        for day in 1...30 {
            let sky = try sky(jotr, String(format: "2027-04-%02d", day))
            let options = FieldNight.alarmOptions(park: jotr, sky: sky, at: sky.evening)
            for option in options {
                kinds.insert(option.kind)
                switch option.kind {
                case .darkness: #expect(option.fire == sky.darkStart)
                case .core: #expect(option.fire == SkyAlmanac().core(for: jotr, sky: sky).dark?.start)
                case .moonset:
                    let set = try #require(sky.moonset)
                    #expect(option.fire == set.addingTimeInterval(-1800) && set > (sky.darkStart ?? .distantFuture) && set < (sky.darkEnd ?? .distantPast))
                }
                // Five minutes' lead: offered at six minutes before, not at four.
                #expect(FieldNight.alarmOptions(park: jotr, sky: sky, at: option.fire.addingTimeInterval(-360)).contains { $0.kind == option.kind })
                #expect(!FieldNight.alarmOptions(park: jotr, sky: sky, at: option.fire.addingTimeInterval(-240)).contains { $0.kind == option.kind })
            }
            #expect(zip(options, options.dropFirst()).allSatisfy { $0.fire <= $1.fire })
            #expect(!(options.contains { $0.kind == .darkness } && options.contains { $0.kind == .core } && abs((options.first { $0.kind == .darkness }?.fire ?? .now).timeIntervalSince(options.first { $0.kind == .core }?.fire ?? .distantPast)) < 120))
        }
        #expect(kinds == [.darkness, .core, .moonset])
    }

    // MARK: Compass

    @Test func compassPlacesTheSkyAroundTheView() {
        let pose = SkyCompass.Pose(azimuth: 180, altitude: 30)
        #expect(abs(pose.azimuth - 180) < 1e-6 && abs(pose.altitude - 30) < 1e-6)
        let w = 390.0, h = 700.0
        let centre = SkyCompass.place(altitude: 30, azimuth: 180, pose: pose, width: w, height: h)
        #expect(abs((centre.point?.x ?? 0) - w/2) < 1e-6 && abs((centre.point?.y ?? 0) - h/2) < 1e-6 && centre.separation < 1e-6)
        // Facing south, west is to the right; higher is up the screen.
        let west = SkyCompass.place(altitude: 30, azimuth: 190, pose: pose, width: w, height: h)
        #expect((west.point?.x ?? 0) > w/2 + 20)
        let higher = SkyCompass.place(altitude: 40, azimuth: 180, pose: pose, width: w, height: h)
        #expect((higher.point?.y ?? h) < h/2 - 20 && abs((higher.point?.x ?? 0) - w/2) < 1e-6)
        // Behind the viewer: no point, and the arrow points the right way round.
        let behind = SkyCompass.place(altitude: 30, azimuth: 0, pose: pose, width: w, height: h)
        #expect(behind.point == nil && behind.separation > 90)
        let farWest = SkyCompass.place(altitude: 30, azimuth: 260, pose: pose, width: w, height: h)
        #expect(farWest.point == nil && abs(farWest.edgeAngle) < .pi/4)
        // Turned a quarter clockwise, "higher" lies to the left of the screen.
        let rolled = SkyCompass.Pose(azimuth: 180, altitude: 30, roll: 90)
        let up = SkyCompass.place(altitude: 40, azimuth: 180, pose: rolled, width: w, height: h)
        #expect((up.point?.x ?? w) < w/2 - 20 && abs((up.point?.y ?? 0) - h/2) < 1)
        // Pointing straight up stays defined.
        #expect(SkyCompass.place(altitude: 85, azimuth: 10, pose: SkyCompass.Pose(azimuth: 0, altitude: 90), width: w, height: h).point != nil)
    }
    /// Core Motion's frame (x north, y west, z up): upright and facing north reads as north, level,
    /// whichever way round the quaternion is applied.
    // MARK: The Milky Way in the compass

    @Test func galacticPlaneMatchesPyEphem() {
        let plane=SkyCompass.galacticPlane(step: 90), deg=180/Double.pi
        // PyEphem 4.2.1, Galactic(l, 0) → Equatorial, J2000.
        let reference: [(ra: Double, dec: Double)]=[(266.405, -28.936), (318.004, 48.330), (86.405, 28.936), (138.004, -48.330)]
        #expect(plane.count == 4)
        for (point, ref) in zip(plane, reference) {
            #expect(abs(point.ra*deg-ref.ra)<0.02 && abs(point.dec*deg-ref.dec)<0.02)
        }
        // Brightest and widest at the core, faintest and narrowest toward the anticentre.
        #expect(plane[0].brightness == 1 && abs(plane[2].brightness-0.35)<1e-9)
        #expect(plane[0].halfWidth == 13 && plane[2].halfWidth == 6)
        #expect(SkyCompass.galacticPlane().count == 120)
    }
    @Test func milkyWayFadesWithTwilightMoonAndGlow() {
        func v(_ sun: Double, _ moon: Double = -20, _ lit: Double = 0, _ bortle: Int = 2) -> Double { SkyCompass.milkyWayVisibility(sunAltitude: sun, moonAltitude: moon, moonIllumination: lit, bortle: bortle) }
        #expect(v(-20) == 1 && v(-10) == 0 && abs(v(-15)-0.5)<1e-9)
        // A full Moon up leaves a tenth; the same Moon below the horizon leaves all of it.
        #expect(abs(v(-20, 30, 1)-0.1)<1e-9 && v(-20, -5, 1) == 1)
        #expect(abs(v(-20, 30, 0.25)-0.55)<1e-9)
        #expect(v(-20, -20, 0, 3) == 1 && abs(v(-20, -20, 0, 5)-0.5)<1e-9 && v(-20, -20, 0, 7) == 0)
    }
    @Test func joshuaTreeSummerCoreStandsSouth() throws {
        let park=try park("jotr")
        // 3 July 2027, 23:25 PDT: no Moon (new on the 4th, rises after dawn), the core near transit.
        let night=try Date("2027-07-04T06:25:00Z", strategy: .iso8601)
        let band=CompassBand.visible(park: park, moonIllumination: 0.01, at: night)
        #expect(band.visibility>0.95)
        let core=try #require(band.samples.max { $0.brightness<$1.brightness })
        #expect(abs(core.altitude-27)<1.5 && abs(core.azimuth-180)<8)
        // From there the band climbs to about 59° toward Sagitta and Cygnus in the east (PyEphem: 59.0° at l = 57°).
        let top=try #require(band.samples.max { $0.altitude<$1.altitude })
        #expect(abs(top.altitude-59)<1.5 && top.azimuth<180)
        // At noon nothing is drawn.
        #expect(CompassBand.visible(park: park, moonIllumination: 0.01, at: night.addingTimeInterval(-11*3600)).samples.isEmpty)
    }
    @Test func skySideIsAboveTheHorizon() throws {
        let w=390.0, h=700.0, pose=SkyCompass.Pose(azimuth: 180, altitude: 30)
        let side=try #require(SkyCompass.skySide(pose: pose, width: w, height: h))
        // The horizon crosses the middle column 30° below the centre; the polygon closes far above it.
        let focal=(w/2)/tan(SkyCompass.fieldOfView*Double.pi/360)
        let middle=try #require(side.dropLast(2).min { abs($0.x-w/2)<abs($1.x-w/2) })
        #expect(abs(middle.y-(h/2+focal*tan(30*Double.pi/180)))<2)
        #expect(side.suffix(2).allSatisfy { $0.y < -h*5 })
        // Looking straight up, the horizon is out of view.
        #expect(SkyCompass.skySide(pose: SkyCompass.Pose(azimuth: 0, altitude: 90), width: w, height: h) == nil)
    }
    @Test func compassReadsCoreMotionsAttitude() {
        // Device axes in the reference frame: x (right) east = −y, y (top) up = z, z (screen) south = −x.
        let rotation = simd_double3x3(columns: (SIMD3(0, -1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0)))
        let q = simd_quatd(rotation), gravity = SIMD3<Double>(0, -1, 0)
        for attitude in [q, q.inverse] {
            let pose = SkyCompass.Pose(quaternion: attitude, gravity: gravity)
            #expect(abs(pose.altitude) < 1e-6)
            #expect(min(pose.azimuth, 360 - pose.azimuth) < 1e-6)
            #expect(simd_distance(pose.right, SIMD3(1, 0, 0)) < 1e-6 && simd_distance(pose.up, SIMD3(0, 0, 1)) < 1e-6)
        }
        #expect(Compass.fine(112.5) == "east-southeast" && Compass.fine(359) == "north")
        #expect(SkyCompass.spoken(altitude: 32.4, azimuth: 112) == "32° up, east-southeast" && SkyCompass.spoken(altitude: -5, azimuth: 0) == "below the horizon")
    }

    // MARK: Live Activity

    @Test func liveActivityPayloadIsSmallAndCorrect() throws {
        let jotr = try park("jotr"), sky = try sky(jotr, "2026-12-13")
        let night = FieldNight(park: jotr, sky: sky)
        let attributes = FieldActivityAttributes(night: night, score: 94, band: "Pristine")
        #expect(attributes.milestones.count <= FieldActivityAttributes.maximumMilestones && !attributes.milestones.isEmpty)
        #expect(zip(attributes.milestones, attributes.milestones.dropFirst()).allSatisfy { $0.date <= $1.date })
        #expect(attributes.milestones.contains { $0.title == "True darkness" } && attributes.dusk == sky.sunset && attributes.dawn == sky.sunrise)
        let start = try #require(sky.darkStart)
        let state = attributes.state(at: start.addingTimeInterval(-60), nightVision: true)
        #expect(state.next?.date == start && state.nightVision && !state.finished)
        let data = try JSONEncoder().encode(attributes), stateData = try JSONEncoder().encode(state)
        #expect(data.count + stateData.count < 4096)
        #expect(try JSONDecoder().decode(FieldActivityAttributes.ContentState.self, from: stateData) == state)
        #expect(try JSONDecoder().decode(FieldActivityAttributes.self, from: data).milestones == attributes.milestones)
        let content = attributes.content(at: start.addingTimeInterval(-60), nightVision: false)
        #expect(content.staleDate == start)
        let dawn = attributes.state(at: attributes.dawn, nightVision: false)
        #expect(dawn.finished && dawn.next == nil)
        #expect(attributes.after(state.next).allSatisfy { $0.date > start } && attributes.fraction(attributes.dusk) == 0 && attributes.fraction(attributes.dawn) == 1)
    }

    // MARK: Focus, requests and nearby parks

    @Test func stargazingFocusRestoresNightVision() throws {
        let defaults = try #require(UserDefaults(suiteName: "nyx-tests-focus"))
        defaults.removePersistentDomain(forName: "nyx-tests-focus")
        defaults.set(false, forKey: "nightVision")
        // The system calls the filter with its defaults (both off) when Nyx launches with no Focus on: nothing changes.
        StargazingFocus.apply(nightVision: false, offerField: false, defaults: defaults)
        #expect(!defaults.bool(forKey: "nightVision") && !StargazingFocus.offersField(defaults) && !StargazingFocus.holdsNightVision(defaults))
        StargazingFocus.apply(nightVision: true, offerField: true, defaults: defaults)
        #expect(defaults.bool(forKey: "nightVision") && StargazingFocus.offersField(defaults) && StargazingFocus.holdsNightVision(defaults))
        // A second call while on (the filter changed) keeps the original value to restore.
        StargazingFocus.apply(nightVision: true, offerField: false, defaults: defaults)
        #expect(!StargazingFocus.offersField(defaults) && defaults.bool(forKey: "nightVision"))
        // The Focus ends: the system passes the defaults.
        StargazingFocus.apply(nightVision: false, offerField: false, defaults: defaults)
        #expect(!defaults.bool(forKey: "nightVision") && !StargazingFocus.holdsNightVision(defaults))
        // A Focus that only offers field mode leaves night vision as the person set it.
        defaults.set(true, forKey: "nightVision")
        StargazingFocus.apply(nightVision: false, offerField: true, defaults: defaults)
        #expect(StargazingFocus.offersField(defaults) && !StargazingFocus.holdsNightVision(defaults))
        StargazingFocus.apply(nightVision: false, offerField: false, defaults: defaults)
        #expect(defaults.bool(forKey: "nightVision") && !StargazingFocus.offersField(defaults))
        defaults.removePersistentDomain(forName: "nyx-tests-focus")
    }
    @Test func fieldRequestsAreTakenOnceAndFresh() throws {
        let defaults = try #require(UserDefaults(suiteName: "nyx-tests-field-request"))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func post(_ park: String?) { FieldModeRequest.post(parkID: park, now: now, defaults: defaults, notify: false) }
        post("jotr")
        #expect(FieldModeRequest.take(now: now.addingTimeInterval(5), defaults: defaults) == FieldModeRequest.Pending(parkID: "jotr"))
        #expect(FieldModeRequest.take(now: now.addingTimeInterval(6), defaults: defaults) == nil)
        post(nil)
        #expect(FieldModeRequest.take(now: now.addingTimeInterval(120), defaults: defaults) == nil)
        post(nil)
        #expect(FieldModeRequest.take(now: now, defaults: defaults) == FieldModeRequest.Pending(parkID: nil))
        defaults.removePersistentDomain(forName: "nyx-tests-field-request")
    }
    @MainActor @Test func nearbyParkIsFoundOnlyWhenClose() {
        let model = PlanModel()
        #expect(model.fieldPark(latitude: 33.87, longitude: -115.90)?.id == "jotr")
        #expect(model.fieldPark(latitude: 39.10, longitude: -94.58) == nil)
    }
}
