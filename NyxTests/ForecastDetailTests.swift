import Foundation
import Testing
@testable import Nyx

/// Answers by request kind: the models request, the layers request, or the air-quality request.
actor RoutedHTTP: HTTPTransport {
    var urls: [URL]=[]
    var fail=false
    let models: String?, layers: String?, air: String?, clouds: String?
    init(models: String?=nil, layers: String?=nil, air: String?=nil, clouds: String?=nil) { self.models=models; self.layers=layers; self.air=air; self.clouds=clouds }
    func setFailure() { fail=true }
    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        if fail { throw URLError(.notConnectedToInternet) }
        let query=url.query ?? ""
        let body: String?=url.path=="/v1/air-quality" ? air : query.contains("models=") ? models : query.contains("cloud_cover_low") ? layers : clouds
        guard let body else { throw URLError(.badServerResponse) }
        return Data(body.utf8)
    }
}
/// Holds the first request until released, so a test can act while it is in flight.
actor GatedHTTP: HTTPTransport {
    let body: String
    private var held: CheckedContinuation<Void, Never>?
    private var gate=true
    private(set) var waiting=false
    init(body: String) { self.body=body }
    func get(_ url: URL) async throws -> Data {
        if gate {
            gate=false
            await withCheckedContinuation { held=$0; waiting=true }
        }
        return Data(body.utf8)
    }
    func release() { held?.resume(); held=nil }
}
/// Hours that start on the hour, as Open-Meteo returns them.
private let t0=1_789_999_200.0
private func hours(_ count: Int) -> [Double] { (0..<count).map { t0+Double($0)*3600 } }
private func json(_ values: [Double?]) -> String { "["+values.map { $0.map { String($0) } ?? "null" }.joined(separator:",")+"]" }
private func hourly(_ series: [String: [Double?]], count: Int) -> String {
    "{\"latitude\":34,\"longitude\":-116,\"hourly\":{\"time\":\(json(hours(count)))"+series.sorted { $0.key<$1.key }.map { ",\"\($0.key)\":\(json($0.value))" }.joined()+"}}"
}

struct ForecastDetailTests {
    func parks(_ count: Int) throws -> [Park] { Array(try ParkData.load().prefix(count)) }

    /// One coordinate returns an object, several an array; every model and layer is read.
    @Test func decodesSingleAndManyCoordinates() async throws {
        let one=try parks(1)
        let models=hourly(["cloud_cover_gfs_seamless":[0,10],"cloud_cover_ecmwf_ifs025":[20,30],"cloud_cover_icon_seamless":[40,50]],count:2)
        let layers=hourly(Dictionary(uniqueKeysWithValues:ForecastDetail.layerKeys.map { ($0,[1,2]) }),count:2)
        let air=hourly(["aerosol_optical_depth":[0.3,nil],"pm2_5":[30,nil]],count:2)
        let http=RoutedHTTP(models:models,layers:layers,air:air)
        let single=await ForecastDetailService(transport:http,persist:false).details(for:one,weather:true,smoke:true)
        let detail=try #require(single[one[0].id])
        #expect(detail.models?.values["cloud_cover_icon_seamless"] == [40,50])
        #expect(detail.layers?.values["visibility"] == [1,2])
        #expect(detail.air?.values["aerosol_optical_depth"] == [0.3,nil])
        #expect(detail.air?.times == hours(2))
        let urls=await http.urls
        #expect(urls.count==3)
        let airURL=try #require(urls.first { $0.host=="air-quality-api.open-meteo.com" })
        let airQuery=airURL.query ?? ""
        #expect(airURL.path=="/v1/air-quality" && airQuery.contains("domains=cams_global") && airQuery.contains("forecast_days=7") && airQuery.contains("past_days=1"))
        #expect(urls.filter { $0.host=="api.open-meteo.com" }.allSatisfy { ($0.query ?? "").contains("forecast_days=7") })
        #expect(urls.contains { ($0.query ?? "").contains("models=gfs_seamless,ecmwf_ifs025,icon_seamless") })

        let three=try parks(3)
        var modelBodies:[String]=[], airBodies:[String]=[]
        for i in 0..<3 {
            let d=Double(i)
            let series:[String:[Double?]]=["cloud_cover_gfs_seamless":[d],"cloud_cover_ecmwf_ifs025":[d+10],"cloud_cover_icon_seamless":[d+20]]
            modelBodies.append(hourly(series,count:1))
            airBodies.append(hourly(["aerosol_optical_depth":[d/10],"pm2_5":[1]],count:1))
        }
        let many="["+modelBodies.joined(separator:",")+"]", manyAir="["+airBodies.joined(separator:",")+"]"
        let http2=RoutedHTTP(models:many,air:manyAir)
        let result=await ForecastDetailService(transport:http2,persist:false).details(for:three,weather:true,smoke:true)
        #expect(result[three[2].id]?.models?.values["cloud_cover_ecmwf_ifs025"] == [12])
        #expect(result[three[1].id]?.air?.values["aerosol_optical_depth"] == [0.1])
        // The layers request failed: that part is simply absent, never filled in.
        #expect(result[three[0].id]?.layers == nil)
        let requested=await http2.urls
        for url in requested {
            let items:[URLQueryItem]=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems ?? []
            let latitude:String=items.first { $0.name=="latitude" }?.value ?? ""
            #expect(latitude.split(separator:",").count==3)
        }
    }
    /// A short or mismatched payload is dropped rather than misread.
    @Test func mismatchedPayloadIsRejected() async throws {
        let one=try parks(1)
        let missing=hourly(["cloud_cover_gfs_seamless":[0,10],"cloud_cover_ecmwf_ifs025":[20,30]],count:2)
        let short=hourly(["aerosol_optical_depth":[0.1],"pm2_5":[1,2]],count:2)
        let result=await ForecastDetailService(transport:RoutedHTTP(models:missing,air:short),persist:false).details(for:one,weather:true,smoke:true)
        #expect(result[one[0].id] == nil)
    }
    /// Spread bands: 15 points or less agree, 35 or less roughly agree, beyond that disagree.
    @Test func agreementBands() {
        #expect(ModelAgreement.band(spread:0) == .agree)
        #expect(ModelAgreement.band(spread:15) == .agree)
        #expect(ModelAgreement.band(spread:15.1) == .roughly)
        #expect(ModelAgreement.band(spread:35) == .roughly)
        #expect(ModelAgreement.band(spread:35.1) == .disagree)
        #expect(ModelAgreement(low:2,high:9).sentence(tonight:true)=="Clear in all three forecast models.")
        #expect(ModelAgreement(low:80,high:92).sentence(tonight:true)=="Cloudy in all three forecast models.")
        #expect(ModelAgreement(low:20,high:30).sentence(tonight:false)=="All three forecast models agree: 20\u{2060}–\u{2060}30% cloud.")
        #expect(ModelAgreement(low:0,high:40).sentence(tonight:false)=="Models disagree: 0\u{2060}–\u{2060}40% cloud. Check again tomorrow.")
        #expect(ModelAgreement(low:0,high:40).sentence(tonight:true)=="Models disagree: 0\u{2060}–\u{2060}40% cloud. Check again before you leave.")
    }
    /// Aerosol optical depth bands; from 0.25 the caveat stands beside the score.
    @Test func aerosolBands() {
        #expect(AirClarity.band(0.05) == .clear)
        #expect(AirClarity.band(0.1) == .lightHaze)
        #expect(AirClarity.band(0.249) == .lightHaze)
        #expect(AirClarity.band(0.25) == .haze)
        #expect(AirClarity.band(0.5) == .heavy)
        #expect(!AirClarity.lightHaze.isCaveat && AirClarity.haze.isCaveat && AirClarity.heavy.isCaveat)
    }
    /// Coldest hour, dew margin and strongest gust come only from moments inside the window: an
    /// instant value stands for the half hour around it, a gust for the hour before it, and one
    /// that merely touches the window's ends does not count.
    @Test func coldDewAndWind() throws {
        let updated=Date(timeIntervalSince1970:t0)
        let layers=HourlySeries(updated:updated,times:hours(8),values:[
            "cloud_cover_low":[0,0,5,5,5,5,0,0],"cloud_cover_mid":[0,0,5,5,5,5,0,0],"cloud_cover_high":[0,0,60,60,60,60,0,0],
            "temperature_2m":[10,9,8,7,6,5,4,3],"dew_point_2m":[0,0,0,0,0,3.5,0,0],
            "wind_gusts_10m":[5,5,40,20,10,30,25,60],"visibility":[30000,30000,8000,8000,8000,8000,30000,30000]])
        let detail=ForecastDetail(layers:layers)
        let start=Date(timeIntervalSince1970:t0+2.5*3600), end=Date(timeIntervalSince1970:t0+5.5*3600)
        let outlook=detail.outlook(from:start,to:end,now:updated)
        #expect(outlook.coldest==5)
        #expect(outlook.coldestAt==Date(timeIntervalSince1970:t0+5*3600))
        #expect(outlook.dewMargin==1.5 && outlook.dewLikely)
        #expect(outlook.gust==30)
        #expect(outlook.layers?.note=="Thin high cloud; bright stars only.")
        #expect(outlook.visibility==8000)
        #expect(outlook.hazeHint==8000)
        #expect(outlook.agreement==nil && outlook.aerosol==nil)
        // A window running past the last hour is not described at all.
        let partial=detail.outlook(from:start,to:Date(timeIntervalSince1970:t0+9*3600),now:updated)
        #expect(partial.coldest==nil && partial.gust==nil && partial.dewMargin==nil && partial.layers==nil)
        // Old detail is not described either.
        #expect(detail.outlook(from:start,to:end,now:updated.addingTimeInterval(40*3600)).isEmpty)
    }
    /// Agreement from three models' window means; aerosols beyond CAMS' horizon are null, never clear.
    @Test func agreementAndSmokeFromSeries() {
        let updated=Date(timeIntervalSince1970:t0)
        let models=HourlySeries(updated:updated,times:hours(4),values:["cloud_cover_gfs_seamless":[10,10,10,10],"cloud_cover_ecmwf_ifs025":[20,30,20,30],"cloud_cover_icon_seamless":[50,50,50,50]])
        let air=HourlySeries(updated:updated,times:hours(4),values:["aerosol_optical_depth":[0.3,0.4,nil,nil],"pm2_5":[1,1,nil,nil]])
        let detail=ForecastDetail(models:models,air:air)
        let early=detail.outlook(from:Date(timeIntervalSince1970:t0),to:Date(timeIntervalSince1970:t0+3600),now:updated)
        #expect(early.agreement==ModelAgreement(low:10,high:50))
        #expect(early.agreement?.band == .disagree)
        #expect(abs((early.aerosol ?? 0)-0.35)<1e-9)
        #expect(early.clarity == .haze)
        #expect(early.hazeHint==nil)
        let late=detail.outlook(from:Date(timeIntervalSince1970:t0+1.5*3600),to:Date(timeIntervalSince1970:t0+3.5*3600),now:updated)
        #expect(late.aerosol==nil && late.clarity==nil)
        #expect(late.agreement != nil)
    }
    /// Caches written before this release still decode, and the detail cache decodes with any part missing.
    @Test func oldCachesStillDecode() throws {
        let old=Data("{\"updated\":781000000,\"times\":[\(t0),\(t0+3600)],\"clouds\":[10,null]}".utf8)
        let forecast=try JSONDecoder().decode(Forecast.self,from:old)
        #expect(forecast.clouds==[10,nil])
        #expect(try JSONDecoder().decode(ForecastDetail.self,from:Data("{}".utf8)) == ForecastDetail())
        let detail=ForecastDetail(air:HourlySeries(updated:Date(timeIntervalSince1970:t0),times:hours(1),values:["aerosol_optical_depth":[0.2]]))
        let roundTrip=try JSONDecoder().decode(ForecastDetail.self,from:JSONEncoder().encode(detail))
        #expect(roundTrip==detail && roundTrip.models==nil)
    }
    /// The smoke switch is enforced at the transport, before any connection; the air host is
    /// allowed only through it, and no other host is reachable.
    @Test func smokeSwitchIsEnforcedAtTheTransport() async throws {
        let suite="nyx-transport-test-\(UUID().uuidString)"
        let defaults=try #require(UserDefaults(suiteName:suite))
        defaults.set(false,forKey:"smokeEnabled")
        defer { defaults.removePersistentDomain(forName:suite) }
        #expect(SafeHTTP.hosts==["developer.nps.gov","api.open-meteo.com","air-quality-api.open-meteo.com"])
        let air=try #require(URL(string:"https://air-quality-api.open-meteo.com/v1/air-quality?latitude=0&longitude=0"))
        do { _=try await SafeHTTP(suite:suite).get(air); Issue.record("Smoke request was not blocked") }
        catch let error as URLError { #expect(error.code == .cancelled) }
        let other=try #require(URL(string:"https://air-quality.open-meteo.com/v1/air-quality"))
        do { _=try await SafeHTTP(suite:suite).get(other); Issue.record("Unknown host was not rejected") }
        catch let error as URLError { #expect(error.code == .unsupportedURL) }
    }
    /// Each of the three hosts has its own switch: turning one off refuses that host before any
    /// connection and leaves the other two allowed. No other host, and nothing but HTTPS, is ever allowed.
    @Test func eachHostHasItsOwnSwitch() async throws {
        #expect(SafeHTTP.hosts == ["developer.nps.gov", "api.open-meteo.com", "air-quality-api.open-meteo.com"])
        #expect(SafeHTTP.preferences == ["developer.nps.gov": "npsEnabled", "api.open-meteo.com": "weatherEnabled", "air-quality-api.open-meteo.com": "smokeEnabled"])
        let urls=try SafeHTTP.hosts.sorted().map { try #require(URL(string: "https://\($0)/v1/test")) }
        for off in SafeHTTP.hosts.sorted() {
            let suite="nyx-switch-test-\(UUID().uuidString)"
            let defaults=try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(false, forKey: try #require(SafeHTTP.preferences[off]))
            for url in urls {
                let expected: URLError.Code?=url.host == off ? .cancelled : nil
                #expect(SafeHTTP.refusal(url, defaults: defaults) == expected)
            }
            // The transport itself refuses before connecting (a connection would fail differently, or succeed).
            let refused=try #require(urls.first { $0.host == off })
            do { _=try await SafeHTTP(suite: suite).get(refused); Issue.record("\(off) was contacted with its switch off") }
            catch let error as URLError { #expect(error.code == .cancelled) }
        }
        let fresh=try #require(UserDefaults(suiteName: "nyx-switch-test-\(UUID().uuidString)"))
        for url in urls { #expect(SafeHTTP.refusal(url, defaults: fresh) == nil) }
        for text in ["http://api.open-meteo.com/v1/forecast", "https://open-meteo.com/v1/forecast", "https://example.com/", "https://developer.nps.gov.example.com/"] {
            #expect(SafeHTTP.refusal(try #require(URL(string: text)), defaults: fresh) == .unsupportedURL)
        }
    }
    /// With the smoke switch off the service never asks; with forecasts off it asks only for smoke.
    @Test func serviceRespectsEachSwitch() async throws {
        let one=try parks(1)
        let http=RoutedHTTP(models:hourly(["cloud_cover_gfs_seamless":[0],"cloud_cover_ecmwf_ifs025":[0],"cloud_cover_icon_seamless":[0]],count:1),
                            air:hourly(["aerosol_optical_depth":[0.1],"pm2_5":[1]],count:1))
        _=await ForecastDetailService(transport:http,persist:false).details(for:one,weather:true,smoke:false)
        #expect(await http.urls.allSatisfy { $0.host=="api.open-meteo.com" })
        let http2=RoutedHTTP(air:hourly(["aerosol_optical_depth":[0.1],"pm2_5":[1]],count:1))
        _=await ForecastDetailService(transport:http2,persist:false).details(for:one,weather:false,smoke:true)
        #expect(await http2.urls.map(\.host)==["air-quality-api.open-meteo.com"])
        let http3=RoutedHTTP()
        #expect(await ForecastDetailService(transport:http3,persist:false).details(for:one,weather:false,smoke:false).isEmpty)
        #expect(await http3.urls.isEmpty)
    }
    /// Smoke that arrives after the switch went off is dropped, not stored; a later request with
    /// the switch back on stores it again.
    @Test func smokeInFlightWhenSwitchedOffIsDropped() async throws {
        let one=try parks(1)
        let http=GatedHTTP(body:hourly(["aerosol_optical_depth":[0.6],"pm2_5":[1]],count:1))
        let service=ForecastDetailService(transport:http,persist:false)
        let inFlight=Task { await service.details(for:one,weather:false,smoke:true) }
        var tries=0
        while !(await http.waiting), tries<500 { tries+=1; try await Task.sleep(for:.milliseconds(5)) }
        #expect(await http.waiting)
        await service.forgetAir()
        await http.release()
        #expect(await inFlight.value[one[0].id]?.air == nil)
        #expect(await service.details(for:one,weather:false,smoke:false)[one[0].id]?.air == nil)
        #expect(await service.details(for:one,weather:false,smoke:true)[one[0].id]?.air != nil)
    }
    /// A failed refresh keeps the last good detail, and a fresh one is not asked for again.
    @Test func failureKeepsLastGoodDetail() async throws {
        let one=try parks(1)
        let http=RoutedHTTP(air:hourly(["aerosol_optical_depth":[0.6],"pm2_5":[1]],count:1))
        let service=ForecastDetailService(transport:http,persist:false)
        let first=await service.details(for:one,weather:false,smoke:true)
        await http.setFailure()
        let second=await service.details(for:one,weather:false,smoke:true,force:true)
        #expect(second[one[0].id]==first[one[0].id] && first[one[0].id]?.air != nil)
        #expect(await http.urls.count==1)
    }
    /// The score never changes; agreement appears only beside a score with clouds, with the
    /// range of scores the clearest and cloudiest model would give.
    @MainActor @Test func outlookKeepsTheScore() async throws {
        let park=try #require(try ParkData.load().first { $0.id=="jotr" })
        let model=PlanModel(weather:WeatherService(transport:RoutedHTTP(),persist:false),parkStore:ParkStore(transport:RoutedHTTP(),persist:false),detail:ForecastDetailService(transport:RoutedHTTP(),persist:false))
        let night=model.night(park,on:park.date(model.tonight(park),addingDays:2))
        let window=night.sky.cloudWindow
        let first=(floor(window.start.timeIntervalSince1970/3600)-1)*3600
        let times=(0..<30).map { first+Double($0)*3600 }
        model.forecasts[park.id]=Forecast(updated:.now,times:times,clouds:times.map { _ in 20 })
        model.details[park.id]=ForecastDetail(models:HourlySeries(updated:.now,times:times,values:[
            "cloud_cover_gfs_seamless":times.map { _ in 0 },"cloud_cover_ecmwf_ifs025":times.map { _ in 20 },"cloud_cover_icon_seamless":times.map { _ in 60 }]))
        let scored=model.night(park,on:night.id)
        let outlook=try #require(model.outlook(scored))
        let engine=ScoreEngine()
        #expect(scored.score.value==engine.score(sky:scored.sky,bortle:park.bortleEstimate,cloudCover:20).value)
        #expect(outlook.scoreRange==engine.score(sky:scored.sky,bortle:park.bortleEstimate,cloudCover:60).value...engine.score(sky:scored.sky,bortle:park.bortleEstimate,cloudCover:0).value)
        #expect(outlook.agreement?.band == .disagree)
        model.forecasts[park.id]=nil
        #expect(model.outlook(model.night(park,on:night.id))?.agreement==nil)
    }
}
