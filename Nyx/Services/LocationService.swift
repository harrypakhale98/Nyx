import Foundation
import CoreLocation
import Observation

@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    var latitude:Double?
    var longitude:Double?
    var denied=false
    var locating=false
    var message:String?
    private let manager=CLLocationManager()
    override init() { super.init(); manager.delegate=self; manager.desiredAccuracy=kCLLocationAccuracyThreeKilometers }
    /// "Near me" as the starting point, kept across launches: the choice, never a position. While
    /// location stays allowed, the next launch starts from where you are without asking.
    private var remembered:Bool {
        get { DebugScenario.screen == nil && UserDefaults.standard.bool(forKey:"nearMe") }
        set { if DebugScenario.screen == nil { UserDefaults.standard.set(newValue,forKey:"nearMe") } }
    }
    /// The explainer has led to iOS's prompt once: after an "Allow Once" lapses, Near me goes
    /// straight to the prompt instead of explaining again.
    private var explained:Bool {
        get { DebugScenario.screen == nil && UserDefaults.standard.bool(forKey:"locationExplained") }
        set { if DebugScenario.screen == nil { UserDefaults.standard.set(newValue,forKey:"locationExplained") } }
    }
    private var allowed:Bool { manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways }
    /// Near me should explain first: iOS has never asked, and Nyx has never explained.
    var needsPermission:Bool { manager.authorizationStatus == .notDetermined && !explained }
    func request() {
        locating=true
        if allowed { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { denied=true; locating=false; remembered=false }
        else { explained=true; manager.requestWhenInUseAuthorization() }
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,.authorizedAlways: denied=false; if locating { manager.requestLocation() } else { resume() }
        // Turned off in Settings: back to the starting point, not a stale position.
        case .denied,.restricted: denied=true; clear()
        default: break
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        // A fix that lands after a starting point was chosen instead is dropped.
        guard let location=locations.last, locating || latitude != nil else { locating=false; return }
        latitude=location.coordinate.latitude; longitude=location.coordinate.longitude; locating=false; message=nil; remembered=true
    }
    /// Return to the chosen starting park.
    func clear() { latitude=nil; longitude=nil; message=nil; locating=false; remembered=false }
    /// Back in the app: a fresh fix, only when "near me" is in use and already allowed. Never asks.
    func refreshIfAuthorized() {
        guard allowed, !locating else { return }
        if latitude != nil { manager.requestLocation() } else { resume() }
    }
    /// Near me from an earlier launch, only while still allowed. Never asks. iOS's last fix, when
    /// recent, paints at once; a fresh one follows.
    private func resume() {
        guard remembered, latitude == nil, !locating, allowed else { return }
        if let last=manager.location, last.timestamp.timeIntervalSinceNow > -900 { latitude=last.coordinate.latitude; longitude=last.coordinate.longitude }
        else { locating=true }
        manager.requestLocation()
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:any Error) {
        locating=false
        if latitude == nil { message=String(localized:"Location is unavailable. Choose a starting point instead.") }
    }
}
