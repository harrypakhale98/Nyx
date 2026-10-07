import Foundation
import Testing
@testable import Nyx

/// The cloud forecast client the iPhone and Vision Pro share (CloudForecastClient.swift), the
/// switch that keeps Vision Pro silent, and the immersive sky's forecast clouds (`SkyDome`).
struct VisionCloudsTests {
    /// Moving the client out of DataServices.swift changed nothing on the wire: all 63 parks in
    /// two requests (50 and 13), each the exact query the iPhone has sent since 1.1 (7).
    @Test func sharedClientSendsTheSameRequests() async throws {
        let parks=try ParkData.load()
        #expect(parks.count == 63)
        let http=StubHTTP([:])
        _=await WeatherService(transport: http, persist: false).forecasts(for: parks, network: true, force: true)
        let urls=await http.urls
        #expect(urls.count == 2)
        for (url, chunk) in zip(urls, [Array(parks[0..<50]), Array(parks[50...])]) {
            let latitudes=chunk.map { String($0.forecastPoint.latitude) }.joined(separator: ","), longitudes=chunk.map { String($0.forecastPoint.longitude) }.joined(separator: ",")
            #expect(url.absoluteString == "https://api.open-meteo.com/v1/forecast?latitude=\(latitudes)&longitude=\(longitudes)&hourly=cloud_cover&forecast_days=15&past_days=1&timeformat=unixtime&timezone=GMT")
        }
        // Clouds only: no models, layers or air ride along with this request.
        #expect(urls.allSatisfy { $0.host == "api.open-meteo.com" && !$0.absoluteString.contains("models") })
    }
    /// The switch is on unless turned off; off, the service is told not to ask, and the transport
    /// refuses before connecting even if something did ask.
    @Test func switchOffMeansNoRequest() async throws {
        let suite="nyx-vision-clouds-\(UUID().uuidString)"
        let defaults=try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(CloudForecastSwitch.isOn(defaults))
        defaults.set(false, forKey: CloudForecastSwitch.key)
        #expect(!CloudForecastSwitch.isOn(defaults))
        #expect(SafeHTTP.preferences["api.open-meteo.com"] == CloudForecastSwitch.key)
        let http=StubHTTP([:]), parks=try ParkData.load()
        let result=await WeatherService(transport: http, persist: false).forecasts(for: parks, network: CloudForecastSwitch.isOn(defaults), force: true)
        #expect(result.isEmpty)
        #expect(await http.urls.isEmpty)
        let url=try #require(URL(string: "https://api.open-meteo.com/v1/forecast?latitude=34&longitude=-116&hourly=cloud_cover"))
        do { _=try await SafeHTTP(suite: suite).get(url); Issue.record("A forecast request went out with the switch off") }
        catch let error as URLError { #expect(error.code == .cancelled) }
    }
    /// More cloud never shows more stars; clear leaves them all, overcast a tenth.
    @Test func cloudDimmingIsMonotonic() {
        let levels=stride(from: -0.2, through: 1.2, by: 0.01).map(SkyDome.cloudDimming)
        #expect(zip(levels, levels.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(SkyDome.cloudDimming(0) == 1 && abs(SkyDome.cloudDimming(1)-0.1) < 1e-12)
        #expect(SkyDome.cloudDimming(.nan) == 1 && SkyDome.cloudDimming(-1) == 1 && abs(SkyDome.cloudDimming(3)-0.1) < 1e-12)
    }
    /// The sky draws the forecast's hour, eased toward the usual clouds by lead as the score is;
    /// nothing at all without a forecast or a value for that hour.
    @Test func skyCloudFollowsTheForecastHour() throws {
        let issued=Date(timeIntervalSince1970: 1_790_000_000)
        let times=(0..<384).map { (issued.timeIntervalSince1970/3600).rounded(.down)*3600+Double($0)*3600 }
        var clouds: [Double?]=times.map { _ in 80 }
        clouds[30]=nil
        let forecast=Forecast(updated: issued, times: times, clouds: clouds)
        let soon=Date(timeIntervalSince1970: times[10]+600)
        #expect(SkyDome.cloud(at: soon, forecast: forecast, basis: .forecast, usual: 50) == 0.8)
        #expect(SkyDome.cloud(at: soon, forecast: forecast, basis: .usual, usual: 50) == nil)
        #expect(SkyDome.cloud(at: soon, forecast: nil, basis: .forecast, usual: 50) == nil)
        #expect(SkyDome.cloud(at: Date(timeIntervalSince1970: times[30]), forecast: forecast, basis: .forecast, usual: 50) == nil)
        // Six days out the forecast counts 4/7, the usual clouds the rest.
        let later=issued.addingTimeInterval(6*86400)
        let eased=try #require(SkyDome.cloud(at: later, forecast: forecast, basis: .blended(weight: 4.0/7, leadDays: 6), usual: 50))
        #expect(abs(eased-(4.0/7*80+3.0/7*50)/100) < 0.01)
        // Past the forecast's last hour, nothing.
        #expect(SkyDome.cloud(at: Date(timeIntervalSince1970: times[383]+3600), forecast: forecast, basis: .blended(weight: 0.1, leadDays: 9), usual: 50) == nil)
    }
}
