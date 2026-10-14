import Foundation
import Testing
@testable import Nyx

/// A cold start never shows a score the data arriving a moment later would contradict: Haleakalā
/// is never scored from its total cloud while its summit layers are on their way, the layers are
/// asked for with the first refresh rather than only once a park page opens, and whatever arrives
/// later (layers, smoke, the models) is seen by Tonight and the park page alike.
@MainActor @Suite struct ColdStartScoreTests {
    let engine=AstronomyEngine()
    func named(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func model(_ http:any HTTPTransport) -> PlanModel {
        PlanModel(weather:WeatherService(transport:http,persist:false),parkStore:ParkStore(transport:http,persist:false),detail:ForecastDetailService(transport:http,persist:false),defaults:isolatedDefaults())
    }
    /// Hourly values across tonight's window at a park, issued now.
    func hours(_ night:Night) -> [Double] {
        let window=night.sky.cloudWindow
        let first=(floor(window.start.timeIntervalSince1970/3600)-2)*3600
        return (0..<36).map { first+Double($0)*3600 }
    }
    func total(_ night:Night,_ cloud:Double) -> Forecast {
        let times=hours(night)
        return Forecast(updated:.now,times:times,clouds:times.map { _ in cloud })
    }
    func layers(_ night:Night,low:Double,mid:Double,high:Double,updated:Date = .now) -> HourlySeries {
        let times=hours(night)
        return HourlySeries(updated:updated,times:times,values:["cloud_cover_low":times.map { _ in low },"cloud_cover_mid":times.map { _ in mid },"cloud_cover_high":times.map { _ in high }])
    }

    /// Haleakalā with 95% total cloud (the inversion's low cloud) and no layers yet: the score uses
    /// its usual clouds, labelled as such, never the 95%. Once the layers arrive, the score Tonight
    /// ranks and the score the page shows are the same night, worked out afresh.
    @Test func theSummitIsNeverScoredFromItsTotalCloud() throws {
        let hale=try named("hale"), havo=try named("havo")
        let model=model(RoutedHTTP())
        let first=model.night(hale)
        model.forecasts["hale"]=total(first,95)
        model.forecasts["havo"]=total(model.night(havo),95)
        // Tonight ranks, the page looks: both before the layers arrive.
        _=model.ranked([hale,havo])
        let cold=model.night(hale)
        let byTotal=ScoreEngine().score(sky:cold.sky,bortle:hale.bortleEstimate,cloud:95,basis:.forecast,aerosol:nil)
        #expect(cold.basis == .usual && cold.cloudCover == nil && !cold.upperCloudOnly && cold.usualCloud != nil)
        #expect(cold.score.value > byTotal.value)
        // Within the layers' reach, the caption says the summit's forecast is unavailable, not "not yet".
        #expect(!cold.beyondForecast)
        // A park below the inversion still counts its total cloud.
        #expect(model.night(havo).cloudCover == 95)
        // The layers arrive: the kept nights are let go everywhere.
        model.details["hale"]=ForecastDetail(layers:layers(cold,low:95,mid:0,high:0))
        let ranked=model.ranked([havo,hale]), tonight=model.night(hale)
        let page=model.night(hale,on:model.tonight(hale))
        #expect(page.upperCloudOnly && page.cloudCover == 0 && page.basis == .forecast)
        #expect(tonight.score.value == page.score.value && tonight.upperCloudOnly)
        #expect(ranked.first?.id == "hale")
        let fresh=NightPlanner.night(park:hale,sky:engine.conditions(for:hale,on:hale.evening(model.tonight(hale))),forecast:model.forecasts["hale"],detail:model.details["hale"],now:.now)
        #expect(page.score.value == fresh.score.value && (page.score.cloudPoints ?? 0) > (cold.score.cloudPoints ?? 0))
    }

    /// Smoke and the three models arriving after a night was kept change it on every surface at once.
    @Test func laterDetailReachesEveryKeptNight() throws {
        let deva=try named("deva")
        let model=model(RoutedHTTP())
        model.smokeEnabled=true
        let first=model.night(deva)
        model.forecasts["deva"]=total(first,0)
        let clear=model.night(deva)
        _=model.ranked([deva]); _=model.outlook(clear)
        let times=hours(first)
        model.details["deva"]=ForecastDetail(air:HourlySeries(updated:.now,times:times,values:["aerosol_optical_depth":times.map { _ in 0.8 }]))
        let smoky=model.night(deva)
        #expect(smoky.score.value < clear.score.value && smoky.aerosol != nil)
        #expect(model.night(deva,on:model.tonight(deva)).score.value == smoky.score.value)
        #expect(model.smokeCaveat(smoky) != nil)
    }

    /// The summit's layers come with the first refresh, before any park page has opened, in a
    /// request for that one public park (no smoke); a page opened later does not ask for it again.
    @Test func theFirstRefreshAsksForTheSummitLayers() async throws {
        let hale=try named("hale")
        let http=OpenMeteoEcho()
        let model=model(http)
        model.weatherEnabled=true
        await model.refreshForecasts(watching:[])
        let urls=await http.urls
        func latitudes(_ url:URL) -> [String] { OpenMeteoEcho.list(url,"latitude") }
        let layered=urls.filter { OpenMeteoEcho.list($0,"hourly").contains("cloud_cover_mid") }
        #expect(layered.count == 1 && layered.first.map(latitudes) == [String(hale.forecastPoint.latitude)])
        #expect(!urls.contains { $0.host == "air-quality-api.open-meteo.com" })
        #expect(model.details["hale"]?.layers != nil)
        // Only the summit: every other park's detail waits for a page.
        #expect(model.details.keys.sorted() == ["hale"])
        // A page opens: every other park is asked for, the summit is not asked twice within its twelve hours.
        await model.refresh([],parkUpdates:false,programs:true)
        let later=await http.urls.dropFirst(urls.count).filter { OpenMeteoEcho.list($0,"hourly").contains("cloud_cover_mid") }
        let asked=later.flatMap(latitudes)
        #expect(asked.count == model.parks.count-1 && !asked.contains(String(hale.forecastPoint.latitude)))
    }
}
