import Foundation
import Testing
@testable import Nyx

/// Hours that start on the hour, as Open-Meteo returns them.
private let t0=1_789_999_200.0
private func hours(_ count: Int) -> [Double] { (0..<count).map { t0+Double($0)*3600 } }
private func json(_ values: [Double?]) -> String { "["+values.map { $0.map { String($0) } ?? "null" }.joined(separator:",")+"]" }
private func hourly(_ series: [String: [Double?]], count: Int) -> String {
    "{\"latitude\":34,\"longitude\":-116,\"hourly\":{\"time\":\(json(hours(count)))"+series.sorted { $0.key<$1.key }.map { ",\"\($0.key)\":\(json($0.value))" }.joined()+"}}"
}

/// Rain, fog, storms, dry air and dust: context from the same requests, never part of the score.
struct NightDetailsTests {
    private let updated=Date(timeIntervalSince1970:t0)
    /// The window from 02:30 to 05:30 after `t0`: the hours stamped 3, 4 and 5 (and, for values
    /// about the hour before their stamp, 3 to 6).
    private var window: (Date, Date) { (Date(timeIntervalSince1970:t0+2.5*3600),Date(timeIntervalSince1970:t0+5.5*3600)) }
    private func layers(_ extra: [String: [Double?]], clouds: Double=0) -> HourlySeries {
        var values: [String: [Double?]]=["cloud_cover_low":Array(repeating:clouds,count:8),"cloud_cover_mid":Array(repeating:clouds,count:8),
                                          "cloud_cover_high":Array(repeating:clouds,count:8),"temperature_2m":Array(repeating:5,count:8),
                                          "dew_point_2m":Array(repeating:-10,count:8),"wind_gusts_10m":Array(repeating:5,count:8),
                                          "visibility":Array(repeating:5000,count:8)]
        values.merge(extra) { $1 }
        return HourlySeries(updated:updated,times:hours(8),values:values)
    }
    private func outlook(_ detail: ForecastDetail) -> NightOutlook { detail.outlook(from:window.0,to:window.1,now:updated) }

    @Test func weatherCodesReadAsWords() {
        #expect(NightWeather(codes:[0,1,2,3]) == NightWeather(codes:[]))
        #expect(NightWeather(codes:[45]).fog && NightWeather(codes:[48]).fog)
        #expect(NightWeather(codes:[51]).rain && NightWeather(codes:[67]).rain && NightWeather(codes:[81]).rain)
        #expect(NightWeather(codes:[71]).snow && NightWeather(codes:[86]).snow && !NightWeather(codes:[86]).rain)
        #expect(NightWeather(codes:[95]).thunder && NightWeather(codes:[99]).thunder)
    }
    /// The highest chance in the window, counted for the hour before its stamp; codes and water
    /// vapour only from hours inside the window.
    @Test func rainFogAndVapourComeFromTheWindow() {
        let detail=ForecastDetail(layers:layers(["precipitation_probability":[90,90,10,20,30,40,35,90],
                                                 "weather_code":[95,95,0,45,3,0,95,95],
                                                 "total_column_integrated_water_vapour":[50,50,6,8,10,12,50,50]]))
        let night=outlook(detail)
        #expect(night.rainChance==40)
        #expect(night.weather == NightWeather(codes:[45]))
        #expect(abs((night.waterVapour ?? 0)-10)<1e-9)
        #expect(night.fogText=="Fog possible, mostly in low ground")
        // Fog is named, so the visibility hint is not.
        #expect(night.hazeHint==nil && night.visibility==5000)
        #expect(night.precipitationLine?.text=="Rain possible, up to 40% chance")
        #expect(night.precipitationLine?.symbol=="cloud.rain")
    }
    @Test func precipitationLineRules() {
        var night=NightOutlook()
        #expect(night.precipitationLine==nil)
        night.rainChance=24
        #expect(night.precipitationLine==nil)
        night.weather=NightWeather(codes:[95])
        #expect(night.precipitationLine?.text=="Thunderstorms possible, up to 24% chance of rain")
        night.rainChance=5
        #expect(night.precipitationLine?.text=="Thunderstorms possible")
        night.rainChance=nil
        #expect(night.precipitationLine?.symbol=="cloud.bolt")
        night.weather=NightWeather(codes:[73])
        #expect(night.precipitationLine?.text=="Snow possible")
        night.rainChance=60
        #expect(night.precipitationLine?.text=="Snow possible, up to 60% chance")
        #expect(night.precipitationLine?.symbol=="cloud.snow")
        night.weather=NightWeather(codes:[0])
        #expect(night.precipitationLine?.text=="Rain possible, up to 60% chance")
    }
    /// Dry air is named only under a cloudless sky and, when there is a smoke forecast, clean air;
    /// "clean" only when the smoke forecast says so.
    @Test func crispAirNeedsDryCleanCloudlessAir() {
        var night=NightOutlook()
        night.waterVapour=6
        #expect(night.crispText=="Very dry air: good for faint stars.")
        night.aerosol=0.05
        #expect(night.crispText=="Very dry, clean air: good for faint stars.")
        night.aerosol=0.12
        #expect(!night.crispAir)
        night.aerosol=0.05; night.layers=CloudLayers(low:0,mid:0,high:12)
        #expect(!night.crispAir)
        night.layers=CloudLayers(low:2,mid:0,high:5)
        #expect(night.crispAir)
        // Never beside dew or fog, which say the air at the ground is near saturation.
        night.dewMargin=1.5
        #expect(!night.crispAir)
        night.dewMargin=6; night.weather=NightWeather(codes:[45])
        #expect(!night.crispAir)
        night.weather=NightWeather(codes:[0])
        #expect(night.crispAir)
        night.waterVapour=10
        #expect(!night.crispAir)
        // From the series: cloud above a trace in any layer rules it out.
        let cloudy=outlook(ForecastDetail(layers:layers(["total_column_integrated_water_vapour":Array(repeating:4,count:8)],clouds:20)))
        #expect(cloudy.waterVapour==4 && !cloudy.crispAir)
        let clear=outlook(ForecastDetail(layers:layers(["total_column_integrated_water_vapour":Array(repeating:4,count:8)])))
        #expect(clear.crispAir)
    }
    @Test func dustIsNamedOnlyWhenItMakesTheHaze() {
        let air=HourlySeries(updated:updated,times:hours(8),values:["aerosol_optical_depth":Array(repeating:0.4,count:8),"pm2_5":Array(repeating:30,count:8),
                                                                    "dust":Array(repeating:120,count:8)])
        let dusty=outlook(ForecastDetail(air:air))
        #expect(dusty.dusty && dusty.dust==120 && dusty.fineParticles==30)
        #expect(dusty.airLabel=="Dust or haze")
        #expect(dusty.airSentence=="Dust in the air: the Milky Way will look faint.")
        var smoky=dusty
        smoky.dust=40
        #expect(!smoky.dusty && smoky.airLabel=="Haze or smoke")
        smoky.dust=80; smoky.fineParticles=90
        #expect(!smoky.dusty)
        smoky.aerosol=0.6; smoky.dust=200
        #expect(smoky.airLabel=="Heavy dust or haze" && smoky.airSentence=="Heavy dust in the air: faint stars hidden.")
        // Clean air reads the same whatever the dust.
        smoky.aerosol=0.05
        #expect(smoky.airLabel=="Clear")
        // Without a dust series nothing changes.
        let plain=outlook(ForecastDetail(air:HourlySeries(updated:updated,times:hours(8),values:["aerosol_optical_depth":Array(repeating:0.4,count:8)])))
        #expect(!plain.dusty && plain.airLabel=="Haze or smoke")
    }
    /// Extras are kept when whole and skipped otherwise; a missing extra never costs the series.
    @Test func extrasNeverCostTheSeries() {
        let ids=["a"]
        let whole=Data(hourly(["cloud_cover":[1,2],"dust":[3,4]],count:2).utf8)
        let kept=OpenMeteoAnswer.series(whole,ids:ids,keys:["cloud_cover"],extras:["dust","weather_code"],now:updated)
        #expect(kept.first?.1.values["dust"] == [3,4] && kept.first?.1.values["weather_code"]==nil)
        let short=Data(hourly(["cloud_cover":[1,2],"dust":[3]],count:2).utf8)
        let skipped=OpenMeteoAnswer.series(short,ids:ids,keys:["cloud_cover"],extras:["dust"],now:updated)
        #expect(skipped.first?.1.values["cloud_cover"] == [1,2] && skipped.first?.1.values["dust"]==nil)
        let missing=Data(hourly(["dust":[3,4]],count:2).utf8)
        #expect(OpenMeteoAnswer.series(missing,ids:ids,keys:["cloud_cover"],extras:["dust"],now:updated).isEmpty)
    }
    /// The iPhone asks for the extras with the layers and the air (ten variables at most per request,
    /// one call per place); Vision Pro asks for exactly what it always did.
    @Test func requestsCarryExtrasOnlyWhereAsked() async throws {
        let park=Array(try ParkData.load().prefix(1))
        let layers=hourly(Dictionary(uniqueKeysWithValues:(ForecastDetail.layerKeys+ForecastDetail.layerExtras).map { ($0,[1,2]) }),count:2)
        let air=hourly(["aerosol_optical_depth":[0.1,0.1],"pm2_5":[1,1],"dust":[2,2]],count:2)
        let models=hourly(["cloud_cover_gfs_seamless":[0,0],"cloud_cover_ecmwf_ifs025":[0,0],"cloud_cover_icon_seamless":[0,0]],count:2)
        let phone=RoutedHTTP(models:models,layers:layers,air:air)
        let details=await ForecastDetailService(transport:phone,persist:false).details(for:park,weather:true,smoke:true)
        #expect(details[park[0].id]?.layers?.values["weather_code"] == [1,2])
        #expect(details[park[0].id]?.air?.values["dust"] == [2,2])
        let urls=await phone.urls
        let hourlyLists=urls.compactMap { URLComponents(url:$0,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name=="hourly" }?.value }
        #expect(hourlyLists.contains((ForecastDetail.layerKeys+ForecastDetail.layerExtras).joined(separator:",")))
        #expect(hourlyLists.contains("aerosol_optical_depth,pm2_5,dust"))
        #expect(hourlyLists.allSatisfy { $0.split(separator:",").count<=10 })
        // Each request still costs Open-Meteo's one call per place.
        #expect(urls.allSatisfy { CallWeight.of($0)==1 })

        let vision=RoutedHTTP(layers:layers,air:air)
        _=await ForecastDetailService(transport:vision,persist:false,extras:false).details(for:park,weather:false,smoke:true)
        let visionLists=await vision.urls.compactMap { URLComponents(url:$0,resolvingAgainstBaseURL:false)?.queryItems?.first { $0.name=="hourly" }?.value }
        #expect(visionLists == ["aerosol_optical_depth,pm2_5"])
    }
}

/// The Park Service's measured night skies, as bundled.
struct MeasuredSkyTests {
    @Test func bundledMeasurementsCoverTheCuratedParks() throws {
        let measured=try MeasuredSky.load()
        let parks=Set(try ParkData.load().map(\.id))
        #expect(measured.parks.count>=50)
        #expect(Set(measured.parks.keys).isSubset(of:parks))
        for (park,sites) in measured.parks {
            #expect(!sites.isEmpty, "\(park)")
            // Darkest latest reading first, and every reading a plausible sky.
            let latest=sites.compactMap { $0.latest?.sqm }
            #expect(latest==latest.sorted(by:>), "\(park)")
            for night in sites.flatMap(\.nights) {
                #expect((16...22.5).contains(night.sqm), "\(park) \(night.date)")
                #expect(night.year.map { (2001...2026).contains($0) } == true, "\(park) \(night.date)")
                #expect(night.bortle.map { (1...9).contains($0) } ?? true)
            }
        }
        // Parks the Park Service has not measured have no rows.
        #expect(measured.sites("cong").isEmpty)
    }
    @Test func spotsMatchSitesWithinOneKilometre() throws {
        let measured=try MeasuredSky.load()
        let glacier=try #require(try ParkData.load().first { $0.id=="glac" })
        let logan=try #require(glacier.viewingSpots.first { $0.name.hasPrefix("Logan Pass") })
        #expect(measured.site(near:logan.latitude,logan.longitude,park:"glac")?.name=="Logan Pass")
        // 2 km away: nothing.
        #expect(measured.site(near:logan.latitude+0.018,logan.longitude,park:"glac")==nil)
        // A site whose positions disagree is never placed.
        #expect(measured.sites("bibe").first { $0.name=="Sotol Vista" }?.latitude==nil)
    }
    @Test func readingsAndYearsAreWrittenPlainly() {
        #expect(MeasuredSky.reading(21.84)==21.8.formatted(.number.precision(.fractionLength(1))))
        #expect(MeasuredSky.span(2009...2009)=="2009")
        #expect(MeasuredSky.span(2005...2012)=="2005\u{2060}–\u{2060}2012")
        let site=MeasuredSky.Site(name:"Somewhere",nights:[.init(date:"2005-01-01",sqm:21),.init(date:"2018-06-01",sqm:21.5)])
        #expect(site.latest?.date=="2018-06-01")
        let sky=MeasuredSky(parks:["x":[MeasuredSky.Site(name:"Empty",nights:[]),site]])
        #expect(sky.sites("x").map(\.name)==["Somewhere"])
        #expect(sky.years("x")==2005...2018)
    }
}

/// The smoke caveat beside a score is one rule on every device (`Night.smokeCaveat`): from the air
/// the score counted, from 0.25, whether or not smoke is what holds the score down.
struct SmokeCaveatTests {
    @Test func oneRuleForEveryDevice() throws {
        let jotr=try #require(try ParkData.load().first { $0.id=="jotr" })
        let now=Date(timeIntervalSince1970: 1_797_000_000)
        var night=NightPlanner(forecasts: [:]).night(jotr, on: jotr.evening(jotr.currentNight(at: now)), now: now)
        #expect(night.smokeCaveat==nil)
        night.aerosol=0.2
        #expect(night.smokeCaveat==nil && night.smokeCaveatLabel==nil)
        night.aerosol=0.3
        #expect(night.smokeCaveat=="Haze or smoke: the Milky Way will look faint." && night.smokeCaveatLabel=="Haze or smoke")
        night.aerosol=0.6
        #expect(night.smokeCaveat=="Heavy smoke or haze: faint stars hidden." && night.smokeCaveatLabel=="Heavy smoke or haze")
    }
}
