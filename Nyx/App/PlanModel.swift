import Foundation
import Observation
import CoreLocation

@MainActor @Observable final class PlanModel {
    let parks: [Park]
    let loadError: Bool
    private let astronomy: any AstronomyProviding
    private let scoring: any ScoreProviding
    private let weather: any WeatherProviding
    private let parkStore: any ParkProviding
    @ObservationIgnored private var conditions: [String: [Date:SkyConditions]] = [:]
    var forecasts: [String:Forecast] = [:]
    /// Parks whose forecast could not be updated on the last attempt, so the UI can say so calmly.
    var staleForecasts: Set<String> = []
    /// Shared by Tonight and Ask Nyx, so both reason from the same starting point.
    let location=LocationService()
    var enrichments: [String:ParkEnrichment] = [:]
    private var activeRefreshes=0
    var refreshing:Bool { activeRefreshes>0 }
    var homeID: String { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(homeID,forKey:"homePark") } } }
    var radiusMiles: Double { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(radiusMiles,forKey:"radiusMiles") } } }
    var weatherEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(weatherEnabled,forKey:"weatherEnabled") } } }
    var npsEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(npsEnabled,forKey:"npsEnabled") } } }
    var today: Date {
        #if DEBUG
        if DebugScenario.state=="polar-night" { return Date(timeIntervalSince1970:1797886800) }
        if DebugScenario.state=="polar" { return Date(timeIntervalSince1970:1782086400) }
        #endif
        return clock
    }
    /// The moment "tonight" is judged from. Advanced only when some park's night turns over
    /// (at its sunrise or local noon), so open screens move on without constant redraws.
    private(set) var clock=Date.now
    func tick(_ now:Date = .now) {
        guard parks.contains(where:{ $0.currentNight(at:clock) != $0.currentNight(at:now) }) else { return }
        clock=now
    }
    init(astronomy: any AstronomyProviding = AstronomyEngine(), scoring: any ScoreProviding = ScoreEngine(),
         weather: any WeatherProviding = WeatherService(), parkStore: any ParkProviding = ParkStore()) {
        do { parks=try ParkData.load(); loadError=false } catch { parks=[]; loadError=true }
        self.astronomy=astronomy; self.scoring=scoring; self.weather=weather; self.parkStore=parkStore
        homeID=UserDefaults.standard.string(forKey:"homePark") ?? "jotr"
        radiusMiles=UserDefaults.standard.object(forKey:"radiusMiles") as? Double ?? 200
        weatherEnabled=UserDefaults.standard.object(forKey:"weatherEnabled") as? Bool ?? true
        npsEnabled=UserDefaults.standard.object(forKey:"npsEnabled") as? Bool ?? true
        // Show the last forecasts and park updates immediately, offline included; refreshes replace them.
        if DebugScenario.screen == nil {
            for park in parks {
                if let cached=CacheDirectory.read(Forecast.self,name:"weather-\(park.id)") { forecasts[park.id]=cached }
                if let cached=CacheDirectory.read(ParkEnrichment.self,name:"park-\(park.id)") { enrichments[park.id]=cached }
            }
        }
        #if DEBUG
        if DebugScenario.screen != nil { homeID="jotr" }
        if DebugScenario.state=="polar" { homeID="dena" }
        if DebugScenario.state=="polar-night" { homeID="gaar" }
        #endif
    }
    var home: Park? { parks.first { $0.id==homeID } ?? parks.first }
    /// The park-local night in progress (or about to begin) right now.
    func tonight(_ park:Park)->Date { park.currentNight(at:today) }
    func park(_ id:String)->Park? { parks.first { $0.id==id } }
    func night(_ park:Park,on date:Date?=nil)->Night {
        let evening=park.evening(date ?? tonight(park))
        let sky:SkyConditions
        if let cached=conditions[park.id]?[evening] { sky=cached } else {
            sky=astronomy.conditions(for:park,on:evening); conditions[park.id,default:[:]][evening]=sky
        }
        let forecast=forecasts[park.id]
        let clouds=forecast?.mean(from:sky.cloudWindow.start,to:sky.cloudWindow.end)
        return Night(park:park,sky:sky,score:scoring.score(sky:sky,bortle:park.bortleEstimate,cloudCover:clouds),cloudCover:clouds,forecastUpdated:clouds==nil ? nil : forecast?.updated)
    }
    func nights(_ park:Park,from date:Date,count:Int)->[Night] { (0..<count).map { night(park,on:park.date(date,addingDays:$0)) } }
    func nearby(latitude:Double?,longitude:Double?)->[Park] {
        guard let home else { return [] }
        let lat=latitude ?? home.latitude, lon=longitude ?? home.longitude
        return parks.filter { $0.distanceMeters(latitude:lat,longitude:lon)<=radiusMiles*1609.344 }
    }
    func ranked(_ candidates:[Park])->[Park] {
        let scores=Dictionary(candidates.map { ($0.id,night($0).score.value) },uniquingKeysWith:{ first,_ in first })
        return candidates.sorted { a,b in
            let first=scores[a.id] ?? 0, second=scores[b.id] ?? 0
            return first==second ? a.name<b.name : first>second
        }
    }
    var npsKey: String { Bundle.main.object(forInfoDictionaryKey:"NPS_API_KEY") as? String ?? "" }
    /// Forecasts for every park arrive together in one request; park updates (alerts and
    /// programs) follow park by park, and only when asked for.
    func refresh(_ parks:[Park],force:Bool=false,parkUpdates:Bool=true) async {
        activeRefreshes+=1; defer { activeRefreshes-=1 }
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        if DebugScenario.state=="no-forecast" { for park in parks { forecasts[park.id]=nil } }
        else {
            let network=weatherEnabled && live
            let fresh=await weather.forecasts(for:parks,network:network,force:force)
            for park in parks {
                forecasts[park.id]=fresh[park.id]
                if network {
                    if let forecast=fresh[park.id],Date.now.timeIntervalSince(forecast.updated)<6*3600 { staleForecasts.remove(park.id) } else { staleForecasts.insert(park.id) }
                }
            }
        }
        guard parkUpdates else { return }
        for park in parks {
            if Task.isCancelled { return }
            enrichments[park.id]=await parkStore.enrichment(for:park,key:npsKey,network:npsEnabled && live,force:force)
        }
    }
    /// A closure from the last park update, if any. Shown beside every score for that park.
    func closure(_ park:Park)->String? {
        // NPS files some closures under "Caution"; a closure or danger anywhere in the alert counts.
        enrichments[park.id]?.alerts.first { alert in
            let text=(alert.category+" "+alert.title).lowercased()
            return ["closure","closed","danger"].contains { text.contains($0) }
        }?.title
    }
    func alertSummary(_ park:Park)->String {
        guard let data=enrichments[park.id] else { return String(localized:"Access not checked. Confirm closures with the park.") }
        if let closure=closure(park) { return closure }
        if let first=data.alerts.first { return first.title }
        return String(localized:"No alerts in the last park update. Confirm access before travel.")
    }
}
@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    var latitude:Double?
    var longitude:Double?
    var denied=false
    var locating=false
    var message:String?
    private let manager=CLLocationManager()
    override init() { super.init(); manager.delegate=self; manager.desiredAccuracy=kCLLocationAccuracyThreeKilometers }
    func request() {
        locating=true
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { denied=true; locating=false }
        else { manager.requestWhenInUseAuthorization() }
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,.authorizedAlways: denied=false; if locating { manager.requestLocation() }
        case .denied,.restricted: denied=true; locating=false
        default: break
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location=locations.last else { locating=false; return }
        latitude=location.coordinate.latitude; longitude=location.coordinate.longitude; locating=false; message=nil
    }
    /// Return to the chosen starting park.
    func clear() { latitude=nil; longitude=nil; message=nil }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:any Error) {
        locating=false; message=String(localized:"Location is unavailable. Choose a starting park instead.")
    }
}
