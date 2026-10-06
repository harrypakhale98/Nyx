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
    private let detailService: any DetailProviding
    @ObservationIgnored private var conditions: [String: [Date:SkyConditions]] = [:]
    var forecasts: [String:Forecast] = [:] { didSet { outlookCache=[:] } }
    /// Model agreement, cloud layers, cold, dew, wind and smoke. Context only; never in the score.
    var details: [String:ForecastDetail] = [:] { didSet { outlookCache=[:] } }
    /// Outlooks already derived, so a river scrub does not rescan every hour of 30 nights per frame.
    @ObservationIgnored private var outlookCache: [String:[Date:NightOutlook?]] = [:]
    /// What's up each night. Astronomy only, so never invalidated by a forecast.
    @ObservationIgnored private var skyCache: [String:WhatsUp] = [:]
    @ObservationIgnored private var eventCache: [String:WhatsUp.Events] = [:]
    /// Parks whose forecast could not be updated on the last attempt, so the UI can say so calmly.
    var staleForecasts: Set<String> = []
    /// Shared by Tonight and Ask Nyx, so both reason from the same starting point.
    let location=LocationService()
    var enrichments: [String:ParkEnrichment] = [:]
    var homeID: String { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(homeID,forKey:"homePark") } } }
    var radiusMiles: Double { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(radiusMiles,forKey:"radiusMiles") } } }
    var weatherEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(weatherEnabled,forKey:"weatherEnabled") } } }
    var npsEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(npsEnabled,forKey:"npsEnabled") } } }
    var smokeEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(smokeEnabled,forKey:"smokeEnabled") } } }
    var today: Date {
        #if DEBUG
        if DebugScenario.state=="polar-night" { return Date(timeIntervalSince1970:1797886800) }
        if DebugScenario.state=="polar" { return Date(timeIntervalSince1970:1782086400) }
        if let fixed=DebugScenario.date { return fixed }
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
         weather: any WeatherProviding = WeatherService(), parkStore: any ParkProviding = ParkStore(),
         detail: any DetailProviding = ForecastDetailService()) {
        do { parks=try ParkData.load(); loadError=false } catch { parks=[]; loadError=true }
        self.astronomy=astronomy; self.scoring=scoring; self.weather=weather; self.parkStore=parkStore; self.detailService=detail
        homeID=UserDefaults.standard.string(forKey:"homePark") ?? "jotr"
        radiusMiles=UserDefaults.standard.object(forKey:"radiusMiles") as? Double ?? 200
        weatherEnabled=UserDefaults.standard.object(forKey:"weatherEnabled") as? Bool ?? true
        npsEnabled=UserDefaults.standard.object(forKey:"npsEnabled") as? Bool ?? true
        smokeEnabled=UserDefaults.standard.object(forKey:"smokeEnabled") as? Bool ?? true
        // Show the last forecasts and park updates immediately, offline included; refreshes replace them.
        if DebugScenario.screen == nil {
            for park in parks {
                if let cached=CacheDirectory.read(Forecast.self,name:"weather-\(park.id)") { forecasts[park.id]=cached }
                if let cached=CacheDirectory.read(ParkEnrichment.self,name:"park-\(park.id)") { enrichments[park.id]=cached }
                if let cached=CacheDirectory.read(ForecastDetail.self,name:"detail-\(park.id)") { details[park.id]=cached }
            }
        }
        #if DEBUG
        if DebugScenario.screen != nil { homeID="jotr" }
        if DebugScenario.state=="polar" { homeID="dena" }
        if DebugScenario.state=="polar-night" { homeID="gaar" }
        if let park=DebugScenario.park { homeID=park }
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
    /// What the forecast says around the score for one night: model agreement (with the score the
    /// clearest and cloudiest model would give), cloud layers, cold, dew, wind and smoke. Agreement
    /// is shown only beside a score that includes clouds, so the two never contradict each other.
    func outlook(_ night:Night)->NightOutlook? {
        if let cached=outlookCache[night.park.id]?[night.id] { return cached }
        let outlook=deriveOutlook(night)
        outlookCache[night.park.id,default:[:]][night.id]=outlook
        return outlook
    }
    private func deriveOutlook(_ night:Night)->NightOutlook? {
        guard let detail=details[night.park.id] else { return nil }
        let window=night.sky.cloudWindow
        var outlook=detail.outlook(from:window.start,to:window.end)
        if night.score.hasForecast, let agreement=outlook.agreement {
            let clearest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloudCover:agreement.low).value
            let cloudiest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloudCover:agreement.high).value
            outlook.scoreRange=min(clearest,cloudiest)...max(clearest,cloudiest)
        } else { outlook.agreement=nil }
        return outlook.isEmpty ? nil : outlook
    }
    /// The core, planets, a meteor shower and an eclipse for one night, worded for that night
    /// ("peak tonight" only on tonight). Kept per park and night: scrubbing recomputes nothing.
    func whatsUp(_ night:Night)->WhatsUp {
        let isTonight=night.id==tonight(night.park), key=Self.skyKey(night,isTonight:isTonight)
        if let cached=skyCache[key] { return cached }
        let value=WhatsUp(park:night.park,sky:night.sky,isTonight:isTonight)
        skyCache[key]=value
        return value
    }
    /// Only the shower and eclipse: cheap enough for every night of a calendar month.
    func events(_ night:Night)->WhatsUp.Events {
        let key="\(night.park.id)-\(Int(night.id.timeIntervalSince1970))"
        if let cached=eventCache[key] { return cached }
        let value=skyCache[Self.skyKey(night,isTonight:night.id==tonight(night.park))]?.events ?? WhatsUp.Events(park:night.park,sky:night.sky)
        eventCache[key]=value
        return value
    }
    /// Eclipse and shower-peak marks for a run of nights, keyed by night.
    func markers(_ nights:[Night])->[Date:WhatsUp.Events.Marker] {
        Dictionary(nights.compactMap { night in events(night).marker(park:night.park).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// Works out the river's nights off the main thread, so a scrub finds each one ready.
    func prepareWhatsUp(_ nights:[Night]) async {
        let missing=nights.map { ($0,$0.id==tonight($0.park)) }.filter { skyCache[Self.skyKey($0.0,isTonight:$0.1)] == nil }
        guard !missing.isEmpty else { return }
        let inputs=missing.map { (key:Self.skyKey($0.0,isTonight:$0.1),park:$0.0.park,sky:$0.0.sky,isTonight:$0.1) }
        let computed=await Task.detached(priority:.utility) { inputs.map { ($0.key,WhatsUp(park:$0.park,sky:$0.sky,isTonight:$0.isTonight)) } }.value
        for (key,value) in computed where skyCache[key] == nil { skyCache[key]=value }
    }
    private static func skyKey(_ night:Night,isTonight:Bool)->String { "\(night.park.id)-\(Int(night.id.timeIntervalSince1970))-\(isTonight)" }
    func outlooks(_ nights:[Night])->[Date:NightOutlook] {
        Dictionary(nights.compactMap { night in outlook(night).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// The amber caveat beside a score: haze or smoke thick enough to hide the Milky Way.
    func smokeCaveat(_ night:Night)->String? {
        guard let clarity=outlook(night)?.clarity, clarity.isCaveat else { return nil }
        return clarity.sentence
    }
    /// True when a night without clouds simply lies past the forecast's last hour (or about two
    /// weeks out when no forecast has arrived), rather than having a forecast that failed.
    func beyondForecast(_ night:Night)->Bool {
        guard !night.score.hasForecast else { return false }
        if let last=forecasts[night.park.id]?.times.last { return night.sky.cloudWindow.end.timeIntervalSince1970>last+3600 }
        return night.id.timeIntervalSince(today)>14*86400
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
    /// Forecasts for every park arrive together (one or two requests); park updates (alerts, and
    /// ranger programs where they are shown) follow park by park, and only when asked for.
    func refresh(_ parks:[Park],force:Bool=false,parkUpdates:Bool=true,programs:Bool=false) async {
        await refreshForecasts(watching:parks,force:force)
        if parkUpdates { await refreshParkUpdates(parks,force:force,programs:programs) }
    }
    /// Always asks for all 63 parks, never only those near the device: it costs the same request,
    /// and a list of nearby parks would tell the forecast service roughly where you are.
    func refreshForecasts(watching parks:[Park],force:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        if DebugScenario.state=="no-forecast" { for park in parks { forecasts[park.id]=nil; details[park.id]=nil }; return }
        #if DEBUG
        if let state=DebugScenario.state, let fixture=DebugForecasts(state:state,parks:self.parks,now:today) {
            forecasts=fixture.forecasts; details=fixture.details; return
        }
        #endif
        let network=weatherEnabled && live
        let fresh=await weather.forecasts(for:self.parks,network:network,force:force)
        for park in self.parks where forecasts[park.id]?.updated != fresh[park.id]?.updated { forecasts[park.id]=fresh[park.id] }
        let detail=await detailService.details(for:self.parks,weather:network,smoke:smokeEnabled && live,force:force)
        for park in self.parks where details[park.id] != detail[park.id] { details[park.id]=detail[park.id] }
        guard network else { return }
        for park in parks {
            if let forecast=fresh[park.id],Date.now.timeIntervalSince(forecast.updated)<6*3600 { staleForecasts.remove(park.id) } else { staleForecasts.insert(park.id) }
        }
    }
    func refreshParkUpdates(_ parks:[Park],force:Bool=false,programs:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        for park in parks {
            if Task.isCancelled { return }
            enrichments[park.id]=await parkStore.enrichment(for:park,key:npsKey,network:npsEnabled && live,force:force,programs:programs)
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
