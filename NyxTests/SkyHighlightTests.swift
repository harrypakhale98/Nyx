import Foundation
import Testing
@testable import Nyx

/// The night's highlights against an independent reference: JPL Horizons, checked against the U.S.
/// Naval Observatory and Fred Espenak's almanac (solstices and Full Moons within a minute, distances
/// within 50 km, separations within 0.05°). The engine's planets are good to about a degree and its
/// Moon to a few tenths, so separations are tested to 0.8°; dates to a day and a half.
struct SkyHighlightTests {
    let almanac=SkyAlmanac()
    let engine=AstronomyEngine()
    /// The night that begins on this local date (local noon to noon).
    func sky(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> SkyConditions {
        let noon=try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        return engine.conditions(for: park, on: noon)
    }
    func utc(_ text: String) throws -> Date { try #require(try? Date(text, strategy: .iso8601)) }

    @Test func solsticesFallOnTheirNights() throws {
        let deva=try park("deva")
        // December solstice 2026-12-21 20:50 UTC: Death Valley's night of Dec 21 (12:50 PST).
        #expect(almanac.solstice(park: deva, sky: try sky(deva, 2026, 12, 21)) == .longestNight)
        #expect(almanac.solstice(park: deva, sky: try sky(deva, 2026, 12, 20)) == nil)
        #expect(almanac.solstice(park: deva, sky: try sky(deva, 2026, 12, 22)) == nil)
        // June solstice 2027-06-21 14:11 UTC falls in the night that began on June 20 (07:11 PDT on the 21st).
        #expect(almanac.solstice(park: deva, sky: try sky(deva, 2027, 6, 20)) == .shortestNight)
        // Southern hemisphere: the same solstice is American Samoa's shortest night. At UTC−11 it falls at
        // 09:50 on Dec 21, so in the night that began on Dec 20.
        let npsa=try park("npsa")
        #expect(almanac.solstice(park: npsa, sky: try sky(npsa, 2026, 12, 20)) == .shortestNight)
        #expect(almanac.solstice(park: npsa, sky: try sky(npsa, 2026, 12, 21)) == nil)
        // Under the midnight sun the item says there is no true darkness.
        let dena=try park("dena"), june=try sky(dena, 2027, 6, 20)
        #expect(almanac.solstice(park: dena, sky: june) == .shortestNight)
        #expect(WhatsUp.solsticeItem(.shortestNight, sky: june).detail.contains("no true darkness"))
    }
    @Test func fullMoonAtItsNearest() throws {
        let deva=try park("deva")
        // 2026-12-24 01:28 UTC at 356,738 km: Death Valley's night of Dec 23.
        let near=try #require(almanac.nearFullMoon(sky: try sky(deva, 2026, 12, 23)))
        #expect(abs(near-356_738)<2_500)
        // Full Moon 2027-07-18 at 405,979 km, and a night far from Full Moon.
        #expect(almanac.nearFullMoon(sky: try sky(deva, 2027, 7, 17)) == nil)
        #expect(almanac.nearFullMoon(sky: try sky(deva, 2026, 12, 10)) == nil)
    }
    @Test func greatestElongations() throws {
        let cases: [(SkyAlmanac.Planet, String)]=[(.venus, "2027-01-03T17:58:00Z"), (.mercury, "2027-09-24T21:59:00Z"),
                                                   (.mercury, "2027-03-17T06:50:00Z"), (.venus, "2028-03-22T12:27:00Z")]
        for (planet, text) in cases {
            let reference=try utc(text)
            let found=try #require(almanac.greatestElongation(of: planet, near: reference.addingTimeInterval(-2*86400)), "\(planet) \(text)")
            #expect(abs(found.timeIntervalSince(reference))<1.5*86400, "\(planet) \(text)")
        }
        // Weeks away from any maximum, and never for the outer planets.
        #expect(almanac.greatestElongation(of: .mercury, near: try utc("2027-10-15T00:00:00Z")) == nil)
        #expect(almanac.greatestElongation(of: .jupiter, near: try utc("2027-01-03T00:00:00Z")) == nil)
    }
    /// Topocentric separations from Death Valley at the reference moments (Horizons).
    @Test func moonBesidePlanetsFromDeathValley() throws {
        let deva=try park("deva")
        let cases: [(Int, Int, Int, SkyAlmanac.Planet, Double, String)]=[
            (2026, 11, 1, .mars, 1.16, "2026-11-02T12:29:00Z"),
            (2027, 2, 19, .jupiter, 1.24, "2027-02-20T03:40:00Z"),
            (2027, 3, 18, .jupiter, 1.63, "2027-03-19T09:51:00Z")]
        for (y, m, d, planet, separation, moment) in cases {
            let night=try sky(deva, y, m, d)
            let pairings=almanac.pairings(planets: almanac.planets(for: deva, sky: night), park: deva, sky: night)
            let found=try #require(pairings.first { $0.withMoon && $0.planet==planet }, "\(planet) \(y)-\(m)-\(d)")
            #expect(abs(found.separation-separation)<0.8, "\(planet): \(found.separation) vs \(separation)")
            // The closest moment while both are seen lies near the reference's.
            #expect(abs(found.at.timeIntervalSince(try utc(moment)))<3*3600, "\(planet)")
        }
    }
    @Test func planetPairs() throws {
        let deva=try park("deva")
        // Mars and Jupiter 1.19° on 2026-11-16 02:05 UTC (morning sky); Venus and Jupiter 0.61° on 2028-11-10.
        for (y, m, d, a, b, separation) in [(2026, 11, 15, SkyAlmanac.Planet.jupiter, SkyAlmanac.Planet.mars, 1.19), (2028, 11, 9, .venus, .jupiter, 0.61)] {
            let night=try sky(deva, y, m, d)
            let pairings=almanac.pairings(planets: almanac.planets(for: deva, sky: night), park: deva, sky: night)
            let found=try #require(pairings.first { !$0.withMoon && Set([$0.other, $0.planet]) == Set([a, b]) }, "\(a)-\(b)")
            #expect(abs(found.separation-separation)<0.8, "\(a)-\(b): \(found.separation)")
            // The brighter of the two is named first.
            #expect(found.other==a)
        }
    }
    @Test func pairingWordsNeverClaimUnderADegree() {
        #expect(WhatsUp.apart(0.3)=="about 1° apart")
        #expect(WhatsUp.apart(2.4)=="about 2° apart")
        #expect(WhatsUp.apart(3.6)=="about 4° apart")
    }
    @Test func gegenschein() throws {
        let deva=try park("deva")
        // New Moon on 2026-10-10: the anti-Sun point in Pisces, far from the Milky Way, high near midnight.
        let point=try #require(almanac.gegenschein(park: deva, sky: try sky(deva, 2026, 10, 10)))
        #expect(point.altitude>=SkyAlmanac.gegenscheinAltitude && (120...240).contains(point.azimuth))
        // Full Moon (2026-10-26) washes it out.
        #expect(almanac.gegenschein(park: deva, sky: try sky(deva, 2026, 10, 25)) == nil)
        // Late June: the anti-Sun point lies in the Milky Way, in Sagittarius.
        #expect(almanac.gegenschein(park: deva, sky: try sky(deva, 2027, 6, 26)) == nil)
        // A brighter sky than Bortle 3 never shows it.
        let indu=try park("indu")
        let induNight=try sky(indu, 2026, 10, 10)
        #expect(indu.bortleEstimate>3 && almanac.gegenschein(park: indu, sky: induNight) == nil)
    }
    @Test func galacticLatitude() {
        let rad=Double.pi/180
        #expect(abs(SkyAlmanac.galacticLatitude(ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec))<0.2)
        #expect(abs(SkyAlmanac.galacticLatitude(ra: 192.85948*rad, dec: 27.12825*rad)-90)<1e-6)
    }
    /// Highlights reach every surface through one layout: the iPhone card and the watch page list
    /// the same rows and mentions.
    @MainActor @Test func highlightsShareOneLayout() throws {
        let deva=try park("deva")
        let night=try sky(deva, 2026, 11, 1)
        let up=WhatsUp(park: deva, sky: night, isTonight: false)
        let pairing=try #require(up.highlights.first { $0.kind == .pairing })
        #expect(up.items.contains(pairing))
        #expect(up.layout.after.contains(pairing))
        #expect(WhatsUpPanel.layout(up)==up.layout)
        let december=WhatsUp(park: deva, sky: try sky(deva, 2026, 12, 21), isTonight: false)
        let solstice=try #require(december.highlights.first { $0.kind == .season })
        #expect(december.layout.mentions.contains(solstice))
    }
}

/// NOAA's Kp forecast: reading it, covering a night, and where it puts the aurora.
struct AuroraForecastTests {
    /// The watch is handed the periods of the last day, so a polar night that began yesterday evening
    /// and runs to noon is still covered from its start, as on the iPhone.
    @Test func watchKeepsTheWholeLongNight() throws {
        let now=Date(timeIntervalSince1970: 1_797_000_000), start=now.addingTimeInterval(-21*3600)
        let periods=(0..<12).map { AuroraOutlook.Period(start: start.addingTimeInterval(Double($0)*3*3600), kp: 5, predicted: $0>6) }
        let outlook=AuroraOutlook(updated: now.addingTimeInterval(-3600), periods: periods)
        let context=WatchContext.make(savedParkIDs: ["gaar"], homeParkID: "gaar", nightVision: false, forecasts: [:], aurora: outlook, now: now)
        let sent=try #require(context.aurora)
        #expect(sent.periods.first?.start==start)
        let night=DateInterval(start: start.addingTimeInterval(1800), end: now.addingTimeInterval(3*3600))
        #expect(sent.highest(in: night) != nil && outlook.highest(in: night)?.kp==sent.highest(in: night)?.kp)
    }
    let t0=1_791_000_000.0
    func data(_ text: String) -> Data { Data(text.utf8) }
    @Test func readsBothShapesOfTheProduct() throws {
        let objects=data("""
        [{"time_tag":"2026-10-15T00:00:00","kp":2.33,"observed":"observed","noaa_scale":null},
         {"time_tag":"2026-10-15T03:00:00","kp":5.0,"observed":"predicted","noaa_scale":"G1"},
         {"time_tag":"bad","kp":3,"observed":"predicted"},{"time_tag":"2026-10-15T06:00:00","kp":12,"observed":"predicted"}]
        """)
        let outlook=try #require(AuroraOutlook.parse(objects, now: Date(timeIntervalSince1970: t0)))
        #expect(outlook.periods.count==2 && outlook.periods[1].predicted && !outlook.periods[0].predicted)
        #expect(outlook.periods[0].start==(try? Date("2026-10-15T00:00:00Z", strategy: .iso8601)))
        let rows=data("""
        [["time_tag","kp","observed","noaa_scale"],["2026-10-15 00:00:00.000","3.67","estimated",null],["2026-10-15 03:00:00.000","4","predicted",null]]
        """)
        let table=try #require(AuroraOutlook.parse(rows, now: .now))
        #expect(table.periods.map(\.kp)==[3.67, 4] && table.periods.last?.predicted == true)
        #expect(AuroraOutlook.parse(data("{}"), now: .now) == nil && AuroraOutlook.parse(data("[]"), now: .now) == nil)
    }
    @Test func aNightMustBeWhollyCovered() {
        let start=Date(timeIntervalSince1970: t0)
        let periods=(0..<4).map { AuroraOutlook.Period(start: start.addingTimeInterval(Double($0)*3*3600), kp: [2, 6, 3, 4][$0], predicted: $0>0) }
        let outlook=AuroraOutlook(updated: start, periods: periods)
        #expect(outlook.highest(in: DateInterval(start: start.addingTimeInterval(3600), duration: 6*3600))?.kp==6)
        #expect(outlook.highest(in: DateInterval(start: start.addingTimeInterval(9*3600), duration: 6*3600)) == nil)
        #expect(outlook.usable(now: start.addingTimeInterval(23*3600)) && !outlook.usable(now: start.addingTimeInterval(25*3600)))
    }
    /// The same view line as the standing note's tiers: Kp 3 near 60°, Kp 5 near 56°, Kp 7 near 52°.
    @Test func viewLineMatchesTheStandingTiers() {
        #expect(AuroraForecast.viewLine(kp: 3)==60 && AuroraForecast.viewLine(kp: 5)==56 && AuroraForecast.viewLine(kp: 7)==52)
        #expect(AuroraForecast.reach(kp: 5, magnetic: 55.9) == nil)
        #expect(AuroraForecast.reach(kp: 5, magnetic: 57) == .low)
        #expect(AuroraForecast.reach(kp: 5, magnetic: -61) == .higher)
    }
    @Test func itemWordsAndHonesty() throws {
        let park=try #require(try ParkData.load().first { $0.id=="dena" })
        let evening=try #require(park.calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12)))
        let sky=AstronomyEngine().conditions(for: park, on: evening)
        let start=try #require(sky.darkStart), end=try #require(sky.darkEnd)
        let first=start.addingTimeInterval(-6*3600)
        let periods=stride(from: 0.0, to: end.timeIntervalSince(first)+6*3600, by: 3*3600).map { AuroraOutlook.Period(start: first.addingTimeInterval($0), kp: 4, predicted: true) }
        let outlook=AuroraOutlook(updated: start, periods: periods)
        let item=try #require(AuroraForecast.item(outlook, park: park, sky: sky, now: start, magnetic: 63))
        #expect(item.kind == .aurora && item.value=="Kp 4" && item.note=="NOAA forecast")
        #expect(item.detail.contains("northern sky") && item.detail.contains("often miss"))
        #expect(AuroraForecast.item(outlook, park: park, sky: sky, now: start, magnetic: -63)?.detail.contains("southern sky") == true)
        // Too far from the pole for Kp 4, a stale forecast, or no forecast: nothing.
        #expect(AuroraForecast.item(outlook, park: park, sky: sky, now: start, magnetic: 50) == nil)
        #expect(AuroraForecast.item(outlook, park: park, sky: sky, now: start.addingTimeInterval(2*86400), magnetic: 63) == nil)
        #expect(AuroraForecast.item(nil, park: park, sky: sky, now: start, magnetic: 63) == nil)
        // It leads What's up, after a total eclipse and before the core.
        let up=WhatsUp(park: park, sky: sky, isTonight: true, aurora: item)
        #expect(up.layout.first.first == item && up.items.first == item)
    }
    /// The host is reached only through its own switch, before any connection.
    @Test func switchIsEnforcedAtTheTransport() throws {
        let suite="aurora-switch-test", defaults=try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let url=try #require(URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json"))
        #expect(SafeHTTP.refusal(url, defaults: defaults) == nil)
        defaults.set(false, forKey: "auroraEnabled")
        #expect(SafeHTTP.refusal(url, defaults: defaults) == .cancelled)
        #expect(SafeHTTP.hosts == ["developer.nps.gov", "api.open-meteo.com", "air-quality-api.open-meteo.com", "services.swpc.noaa.gov"])
    }
    @Test func serviceKeepsTheLastGoodCopy() async throws {
        let http=KpStubHTTP(body: """
        [{"time_tag":"2026-10-15T00:00:00","kp":3,"observed":"predicted"}]
        """)
        var now=Date(timeIntervalSince1970: t0)
        let clock=KpClock(now)
        let service=AuroraService(transport: http, persist: false, clock: { clock.now })
        let first=try #require(await service.outlook(network: true))
        let asked=await http.count
        #expect(first.periods.count==1 && asked==1)
        // Fresh: no second request; offline: the copy here.
        _=await service.outlook(network: true)
        let again=await http.count
        #expect(again==1)
        now=now.addingTimeInterval(4*3600); clock.now=now
        await http.fail()
        let kept=await service.outlook(network: true)
        let failed=await http.count
        #expect(kept == first && failed==2)
        await service.forget()
        let forgotten=await service.cached()
        #expect(forgotten == nil)
    }
}

/// Turning "Aurora forecast" off while a request is out keeps nothing that arrives.
struct AuroraSwitchRaceTests {
    @Test func forgettingDuringARequestKeepsNothing() async throws {
        let http=KpGatedHTTP(body: """
        [{"time_tag":"2026-10-15T00:00:00","kp":5,"observed":"predicted"}]
        """)
        let service=AuroraService(transport: http, persist: false)
        async let result=service.outlook(network: true)
        while !(await http.waiting) { await Task.yield() }
        await service.forget()
        await http.release()
        let value=await result
        let kept=await service.cached()
        #expect(value == nil && kept == nil)
    }
}
private actor KpGatedHTTP: HTTPTransport {
    let body: String
    private var held: CheckedContinuation<Void, Never>?
    private(set) var waiting=false
    init(body: String) { self.body=body }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        await withCheckedContinuation { held=$0; waiting=true }
        return Data(body.utf8)
    }
    func release() { held?.resume(); held=nil }
}
private actor KpStubHTTP: HTTPTransport {
    let body: String
    private(set) var count=0
    private var failing=false
    init(body: String) { self.body=body }
    func fail() { failing=true }
    func get(_ url: URL) async throws -> Data { try await get(url, headers: [:], constrained: true) }
    func get(_ url: URL, headers: [String: String], constrained: Bool) async throws -> Data {
        count+=1
        #expect(url.host==AuroraService.host && url.path==AuroraService.path)
        if failing { throw URLError(.notConnectedToInternet) }
        return Data(body.utf8)
    }
}
private final class KpClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now=now }
}

/// Tonight's binocular sights from the bundled list, by the sky each park has.
struct DeepSkyTests {
    let almanac=SkyAlmanac()
    func sky(_ park: Park, _ year: Int, _ month: Int, _ day: Int) throws -> SkyConditions {
        let noon=try #require(park.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
        return AstronomyEngine().conditions(for: park, on: noon)
    }
    @Test func bundledListIsSound() throws {
        let list=try #require(DeepSky.load())
        #expect(list.objects.count>=40)
        #expect(Set(list.objects.map(\.id)).count==list.objects.count)
        for object in list.objects {
            #expect((0..<360).contains(object.ra) && (-90...90).contains(object.dec), "\(object.id)")
            #expect(["naked", "binoculars", "telescope"].contains(object.eye), "\(object.id)")
        }
        // The Double Cluster's halves share one name, so they are offered once.
        #expect(list.objects.first { $0.id=="NGC 869" }?.localizedName == list.objects.first { $0.id=="NGC 884" }?.localizedName)
    }
    @Test func aDarkMoonlessAutumnNightInDeathValley() throws {
        let deva=try park("deva")
        // New Moon 2026-10-10: Andromeda high in the evening, to the eye at Bortle 2.
        let sights=DeepSky.shared.sights(park: deva, sky: try sky(deva, 2026, 10, 10))
        #expect(sights.count==3)
        #expect(sights.allSatisfy { $0.altitude>=DeepSky.minimumAltitude && $0.object.eye != "telescope" })
        #expect(Set(sights.map(\.object.kind)).count==3)
        let andromeda=DeepSky.shared.objects.first { $0.id=="M31" }
        #expect(andromeda != nil)
        let all=DeepSky.shared.sights(park: deva, sky: try sky(deva, 2026, 10, 10), limit: 40)
        let m31=try #require(all.first { $0.object.id=="M31" })
        #expect(m31.toTheEye)
        // The item names each sight with its designation.
        let item=WhatsUp.deepSkyItem(sights, park: deva)
        #expect(item.kind == .deepSky && sights.allSatisfy { item.detail.contains($0.object.id) })
    }
    @Test func moonAndCityLightThinTheList() throws {
        let deva=try park("deva")
        // Full Moon 2026-10-26: nothing diffuse fainter than magnitude 4, nothing "to the eye".
        let full=DeepSky.shared.sights(park: deva, sky: try sky(deva, 2026, 10, 25), limit: 40)
        #expect(full.allSatisfy { !$0.toTheEye || !$0.object.diffuse })
        #expect(full.allSatisfy { !$0.object.diffuse || ($0.object.mag ?? 4.5)<=4 })
        // Indiana Dunes (Bortle 6): no faint galaxy or nebula.
        let indu=try park("indu")
        let city=DeepSky.shared.sights(park: indu, sky: try sky(indu, 2026, 10, 10), limit: 40)
        #expect(city.allSatisfy { !$0.object.diffuse || ($0.object.mag ?? 4.5)<=4 })
        // No true darkness under the midnight sun: nothing at all.
        let dena=try park("dena")
        #expect(DeepSky.shared.sights(park: dena, sky: try sky(dena, 2027, 6, 20)).isEmpty)
    }
    @Test func theSouthernSkyFromAmericanSamoa() throws {
        let npsa=try park("npsa")
        let names=Set(DeepSky.shared.sights(park: npsa, sky: try sky(npsa, 2026, 10, 10), limit: 40).map(\.object.id))
        #expect(names.contains("SMC") || names.contains("NGC 104"))
    }
}

/// The Moon's names sit exactly where the shader draws their features.
struct MoonFeatureTests {
    /// `Moon.metal`'s screen-to-Moon transform, as the shader runs it.
    func shaderLatLon(x: Double, y: Double, geometry: MoonGeometry) -> (lat: Double, lon: Double) {
        let p=SIMD2(x, -y), z=sqrt(max(0, 1-p.x*p.x-p.y*p.y))
        let c=cos(geometry.north), s=sin(geometry.north)
        let m=SIMD3(p.x*c+p.y*s, -p.x*s+p.y*c, z)
        let cb=cos(geometry.librationLatitude), sb=sin(geometry.librationLatitude), cl=cos(geometry.librationLongitude), sl=sin(geometry.librationLongitude)
        let m2=SIMD3(m.x, m.y*cb+m.z*sb, -m.y*sb+m.z*cb)
        let m3=SIMD3(m2.x*cl+m2.z*sl, m2.y, -m2.x*sl+m2.z*cl)
        return (asin(m2.y)*180/Double.pi, atan2(m3.x, m3.z)*180/Double.pi)
    }
    @Test func placementInvertsTheShader() throws {
        let features=try #require(MoonFeatures.load())
        #expect(features.features.count>=40)
        let geometries=[MoonGeometry(phaseAngle: 0.3, brightLimb: 1.2, north: 0.4, librationLongitude: 0.09, librationLatitude: -0.1),
                        MoonGeometry(phaseAngle: 2.0, brightLimb: -1.0, north: -0.7, librationLongitude: -0.12, librationLatitude: 0.11)]
        for geometry in geometries {
            for feature in features.features {
                guard let placed=MoonFeatures.place(feature, geometry: geometry) else { continue }
                let back=shaderLatLon(x: placed.x, y: placed.y, geometry: geometry)
                #expect(abs(back.lat-feature.lat)<1e-6 && abs(back.lon-feature.lon)<1e-6, "\(feature.name)")
            }
        }
    }
    @Test func mapOrientation() throws {
        let features=try #require(MoonFeatures.load())
        let upright=MoonGeometry(phaseAngle: 0, brightLimb: 0, north: 0, librationLongitude: 0, librationLatitude: 0)
        let crisium=try #require(features.features.first { $0.name=="Mare Crisium" }).nonOptionalPlace(upright)
        let tycho=try #require(features.features.first { $0.name=="Tycho" }).nonOptionalPlace(upright)
        // Crisium near the eastern limb is drawn on the right; Tycho in the south, below the centre.
        #expect(crisium.x>0.6 && tycho.y>0.5)
        // At full Moon everything near the centre is lit; a far-side point is never placed.
        #expect(crisium.lit && tycho.lit)
        #expect(MoonFeatures.place(.init(name: "Far", kind: "crater", lat: 0, lon: 170, km: 10, rank: 1), geometry: upright) == nil)
        // A Moon too small carries no names; a hero-sized one at least the rank-one names.
        #expect(MoonFeatures.ranks(side: 120)==0 && features.lit(geometry: upright, side: 280).count>=10)
        #expect(features.spoken(geometry: upright, side: 280)?.contains("Tycho") == true)
    }
}
private extension MoonFeatures.Feature {
    func nonOptionalPlace(_ geometry: MoonGeometry) throws -> MoonFeatures.Placed { try #require(MoonFeatures.place(self, geometry: geometry)) }
}

/// The real terrain at the viewing spots, as bundled, and what Nyx says from it.
struct HorizonTests {
    @Test func bundledProfilesAreSound() throws {
        let table=try #require(Horizon.Table.load())
        let parks=try ParkData.load()
        #expect(table.places.count==parks.count)
        for park in parks {
            let names=Set(park.viewingSpots.map(\.name))
            for (name, raw) in table.places[park.id]?.spots ?? [:] {
                #expect(names.contains(name), "\(park.id): \(name)")
                #expect(raw.h.count==72 && raw.h.allSatisfy { (-50...900).contains($0) }, "\(name)")
            }
        }
    }
    /// Great Basin's spots where the agencies put them (NPS Public POIs, BLM recreation points), the park's
    /// own amphitheater first, and every bundled dataset covering each one.
    @Test func greatBasinSpotsAreWhereTheAgenciesPutThem() throws {
        let grba=try park("grba")
        let official=[("Astronomy Amphitheater (Lehman Caves Visitor Center)", 39.008653, -114.218176),
                      ("Mather Overlook", 39.020359, -114.274754), ("Baker Archaeological Site", 39.036158, -114.124409)]
        #expect(grba.viewingSpots.map(\.name)==official.map(\.0))
        for (spot, (_, lat, lon)) in zip(grba.viewingSpots, official) {
            #expect(Park.distance(spot.latitude, spot.longitude, lat, lon)<100, "\(spot.name)")
            let horizon=try #require(Horizon.Table.shared.spot(spot.name, park: "grba"), "\(spot.name)")
            #expect((1500...2900).contains(horizon.elevation), "\(spot.name)")
            #expect(SkyGlow.shared.spot(spot.name, park: "grba") != nil && AccessData.shared.access(park: "grba", spot: spot.name) != nil)
        }
        #expect(NightClimate.shared.parks["grba"] != nil)
        #expect(NightAccess.shared.rules("grba", spot: "Mather Overlook").count==1)
        #expect(grba.viewingSpots[2].localizedNote.hasPrefix("Outside the park"))
    }
    @Test func canyonAgainstRim() throws {
        let table=try #require(Horizon.Table.load())
        let canyon=try #require(table.spot("Checkerboard Mesa Pullout", park: "zion"))
        let rim=try #require(table.spot("Mather Point", park: "grca"))
        #expect(canyon.highest.altitude>30 && rim.highest.altitude<Horizon.open)
        #expect((1500...2400).contains(rim.elevation))
        #expect(canyon.altitude(toward: 135)>30 && canyon.altitude(toward: 495)==canyon.altitude(toward: 135))
        let us=Locale(identifier: "en_US"), metric=Locale(identifier: "en_GB")
        #expect(SpotTerrain.line(rim, locale: metric).contains("Open horizon"))
        #expect(SpotTerrain.line(canyon, locale: us).contains("ft") && SpotTerrain.line(canyon, locale: us).contains("southeast"))
    }
    /// From the canyon floor the walls hide the core for part or all of a summer night; from the
    /// rim nothing changes.
    @Test func terrainChangesTheCoreTimesOnlyWhereItShould() throws {
        let almanac=SkyAlmanac(), engine=AstronomyEngine()
        let zion=try park("zion"), grca=try park("grca")
        func dark(_ park: Park) throws -> DateInterval {
            let noon=try #require(park.calendar.date(from: DateComponents(year: 2027, month: 6, day: 5, hour: 12)))
            return try #require(almanac.core(for: park, sky: engine.conditions(for: park, on: noon)).dark)
        }
        let canyon=try #require(WhatsUp.terrainSentence(dark: try dark(zion), park: zion, almanac: almanac))
        #expect(canyon.contains("Checkerboard Mesa Pullout"))
        #expect(WhatsUp.terrainSentence(dark: try dark(grca), park: grca, almanac: almanac) == nil)
    }
}

/// The Park Service's night access rules and visit months, as bundled.
struct ParkSeasonsTests {
    @Test func accessRulesAreSound() throws {
        let access=try #require(NightAccess.load())
        let parks=Dictionary(uniqueKeysWithValues: try ParkData.load().map { ($0.id, $0) })
        #expect(!access.parks.isEmpty)
        for (id, rules) in access.parks {
            let park=try #require(parks[id], "\(id)")
            let names=Set(park.viewingSpots.map(\.name))
            for rule in rules {
                #expect(["seasonalRoad", "nightClosure", "reservation"].contains(rule.kind), "\(rule.title)")
                #expect(rule.spots.map { Set($0).isSubset(of: names) } ?? true, "\(rule.title)")
                #expect(rule.months.map { !$0.isEmpty && $0.allSatisfy { (1...12).contains($0) } } ?? true, "\(rule.title)")
                #expect(rule.source != nil && !rule.evidence.isEmpty, "\(rule.title)")
            }
        }
        // Logan Pass is usually closed to cars in May, open in August.
        let logan=try #require(access.rules("glac", spot: "Logan Pass (visitor center parking lot)").first)
        #expect(logan.applies(inMonth: 5) && !logan.applies(inMonth: 8))
        #expect(logan.monthLine(5)?.contains("Usually closed") == true && logan.monthLine(8) == nil)
    }
    @Test func busyAndQuietMonths() throws {
        let visits=try #require(ParkVisits.load())
        #expect(visits.parks.count==63)
        let deva=try #require(visits.parks["deva"])
        // Death Valley is busiest in spring and quiet in the summer heat.
        #expect(deva.busiest==3 && deva.level(month: 3) == .busy && deva.level(month: 9) == .quiet)
        #expect(deva.quietest.count==3 && deva.quietest==deva.quietest.sorted())
        #expect(BusyMonthsPanel.summary(deva, month: 9).contains("quietest"))
    }
}

/// The month's usual night temperatures, as bundled.
struct NightClimateTests {
    @Test func parksAndGridAgreeInShape() throws {
        let climate=try #require(NightClimate.load())
        #expect(climate.parks.count>=60)
        for (id, months) in climate.parks {
            #expect(zip(months.dawn, months.evening).allSatisfy { $0<=$1+0.5 }, "\(id): dawn above evening")
            #expect(months.dawn.allSatisfy { (-50...45).contains($0) } && months.dewSpread.allSatisfy { $0>=0 }, "\(id)")
        }
        let deva=try #require(try ParkData.load().first { $0.id=="deva" })
        let july=try #require(climate.usual(deva, month: 7)), january=try #require(climate.usual(deva, month: 1))
        #expect(july.dawn>january.dawn+15)
        // A place beyond the curated parks reads the world grid.
        let grid=SkyGrid()
        let paris=try #require(grid.nightTemperatures(latitude: 48.85, longitude: 2.35, month: 1))
        #expect((-8...8).contains(paris.dawn) && paris.evening>=paris.dawn)
        // Raising the place lowers the temperature at 6.5 °C a kilometre.
        let low=try #require(grid.nightTemperatures(latitude: 39.0, longitude: -114.2, month: 7, elevation: 1600))
        let high=try #require(grid.nightTemperatures(latitude: 39.0, longitude: -114.2, month: 7, elevation: 2600))
        #expect(abs((low.dawn-high.dawn)-6.5)<1e-9)
    }
    @Test func wordsSayUsualAndNeverLow() throws {
        let deva=try #require(try ParkData.load().first { $0.id=="deva" })
        let lines=try #require(NightClimate.shared.lines(deva, month: 10))
        #expect(lines.temperatures.hasPrefix("Usually about") && lines.temperatures.contains("before dawn") && !lines.temperatures.contains("low"))
        // Death Valley's dry October air: no dew line.
        #expect(lines.dew == nil)
    }
}
