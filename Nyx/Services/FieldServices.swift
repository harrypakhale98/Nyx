import ActivityKit
import AlarmKit
import AppIntents
import CoreLocation
import CoreMotion
import Foundation
import SwiftUI
import simd

// MARK: Live Activity content

extension FieldActivityAttributes {
    /// The milestones worth a mark on the Lock Screen, most important first when there are too many.
    nonisolated static let priority: [FieldNight.Kind]=[.darkness, .dawn, .moonset, .coreRises, .shower, .moonrise, .coreHighest, .coreSets, .planetRises, .planetSets, .sunset, .sunrise]
    nonisolated static let maximumMilestones=8
    nonisolated init(night: FieldNight, score: Int, band: String) {
        let window=SkyAlmanac.nightWindow(night.sky)
        let ranked=night.milestones.filter { $0.kind != .sunset && $0.kind != .sunrise }
            .sorted { (Self.priority.firstIndex(of: $0.kind) ?? 99, $0.date)<(Self.priority.firstIndex(of: $1.kind) ?? 99, $1.date) }
        let kept=ranked.prefix(Self.maximumMilestones).sorted { $0.date<$1.date }
        self.init(parkID: night.park.id, parkName: night.park.shortName, score: score, band: band,
                  dusk: night.sky.sunset ?? window.start, dawn: night.sky.sunrise ?? window.end,
                  darkStart: night.sky.darkStart, darkEnd: night.sky.darkEnd,
                  milestones: kept.map { Milestone(title: $0.title, date: $0.date, symbol: $0.symbol) })
    }
    /// The state at `now`: the next marked milestone, or finished once the night is over.
    nonisolated func state(at now: Date, nightVision: Bool) -> ContentState {
        let finished=now>=dawn
        return ContentState(next: finished ? nil : milestones.first { $0.date>now }, nightVision: nightVision, finished: finished)
    }
    /// Stale when the countdown reaches its milestone (the view then shows times, not a timer);
    /// at dawn when nothing is left.
    nonisolated func content(at now: Date, nightVision: Bool) -> ActivityContent<ContentState> {
        let state=state(at: now, nightVision: nightVision)
        return ActivityContent(state: state, staleDate: state.finished ? nil : state.next?.date ?? dawn, relevanceScore: state.finished ? 0 : 50)
    }
}

/// Starts, refreshes and ends the night's Live Activity. One at a time; it ends itself at dawn the
/// next time Nyx is opened, and the system retires it after its own limit regardless.
@MainActor enum FieldActivities {
    static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    static var current: Activity<FieldActivityAttributes>? { Activity<FieldActivityAttributes>.activities.first { $0.activityState == .active || $0.activityState == .stale } }
    static func isFollowing(_ park: Park) -> Bool { current?.attributes.parkID == park.id }
    static func start(night: FieldNight, score: DarknessScore, nightVision: Bool, now: Date = .now) async {
        guard enabled, !night.isOver(at: now) else { return }
        let attributes=FieldActivityAttributes(night: night, score: score.value, band: score.band.label)
        for activity in Activity<FieldActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        _=try? Activity.request(attributes: attributes, content: attributes.content(at: now, nightVision: nightVision))
    }
    /// Brings every running activity up to date; ends one whose night is over.
    static func refresh(nightVision: Bool, now: Date = .now) async {
        for activity in Activity<FieldActivityAttributes>.activities where activity.activityState == .active || activity.activityState == .stale {
            let content=activity.attributes.content(at: now, nightVision: nightVision)
            if content.state.finished { await activity.end(content, dismissalPolicy: .immediate) }
            else if content.state != activity.content.state || activity.activityState == .stale { await activity.update(content) }
        }
    }
    static func stop() async {
        for activity in Activity<FieldActivityAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}

// MARK: Alarms

/// Wake-ups for the night, through AlarmKit: they ring through Silent and Focus, which a
/// notification cannot. Set on this iPhone only. AlarmKit's alert without a stop button needs
/// iOS 26.1, so alarms are offered from 26.1; on 26.0 the rows are simply absent.
@MainActor enum FieldAlarms {
    static var supported: Bool { if #available(iOS 26.1, *) { true } else { false } }
    static let tint=Color(red:1,green:0.27,blue:0.23)
    private static let ledgerKey="fieldAlarms"
    enum Access { case allowed, notAsked, denied }
    static var access: Access {
        switch AlarmManager.shared.authorizationState {
        case .authorized: .allowed
        case .denied: .denied
        default: .notAsked
        }
    }
    static func requestAccess() async -> Bool { (try? await AlarmManager.shared.requestAuthorization()) == .authorized }
    /// One key per park, kind and moment, so tomorrow's core alarm is a different alarm.
    nonisolated static func key(park: Park, option: FieldNight.AlarmOption) -> String { "\(park.id)-\(option.kind.rawValue)-\(Int(option.fire.timeIntervalSince1970))" }
    private static var ledger: [String:String] {
        get { UserDefaults.standard.dictionary(forKey: ledgerKey) as? [String:String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: ledgerKey) }
    }
    /// True when this option's alarm is set and still pending.
    static func isSet(park: Park, option: FieldNight.AlarmOption) -> Bool {
        guard let id=ledger[key(park: park, option: option)].flatMap(UUID.init(uuidString:)) else { return false }
        return ((try? AlarmManager.shared.alarms) ?? []).contains { $0.id == id }
    }
    static func toggle(park: Park, option: FieldNight.AlarmOption) async throws {
        let key=key(park: park, option: option)
        if let id=ledger[key].flatMap(UUID.init(uuidString:)), isSet(park: park, option: option) {
            try AlarmManager.shared.cancel(id: id)
            ledger[key]=nil
            return
        }
        guard #available(iOS 26.1, *) else { return }
        let id=UUID()
        let snooze=AlarmButton(text: "Snooze", textColor: tint, systemImageName: "zzz")
        let alert=AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: option.alarmTitle), secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        let attributes=AlarmAttributes(presentation: AlarmPresentation(alert: alert, countdown: AlarmPresentation.Countdown(title: "Snoozing")),
                                       metadata: FieldAlarmMetadata(parkName: park.shortName, kind: option.kind.rawValue), tintColor: tint)
        let snoozeFor=Alarm.CountdownDuration(preAlert: nil, postAlert: 9*60)
        let configuration: AlarmManager.AlarmConfiguration<FieldAlarmMetadata>
        if #available(iOS 27.0, *) {
            // Siri and the system can then name the park the alarm belongs to.
            configuration=AlarmManager.AlarmConfiguration(countdownDuration: snoozeFor, schedule: .fixed(option.fire), attributes: attributes,
                                                          appEntityIdentifier: EntityIdentifier(for: ParkEntity.self, identifier: park.id))
        } else {
            configuration=AlarmManager.AlarmConfiguration(countdownDuration: snoozeFor, schedule: .fixed(option.fire), attributes: attributes)
        }
        _=try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        var entries=ledger
        // Forget alarms that have already rung or were removed in the Clock app.
        let live=Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id.uuidString))
        entries=entries.filter { live.contains($0.value) }
        entries[key]=id.uuidString
        ledger=entries
    }
}

// MARK: Motion

/// The phone's attitude for "where to look", from Core Motion: true north when location is
/// allowed (Core Motion corrects for magnetic declination), magnetic north otherwise, and said so.
/// No permission prompt; nothing is recorded or leaves the phone. Values are read inside per-frame
/// drawing, so they are not observed.
@MainActor final class FieldMotion {
    static let shared=FieldMotion()
    private let manager=CMMotionManager()
    private(set) var pose: SkyCompass.Pose?
    private(set) var trueNorth=false
    /// True when the compass would be steadier after a figure-eight.
    private(set) var needsCalibration=false
    var available: Bool { manager.isDeviceMotionAvailable && !CMMotionManager.availableAttitudeReferenceFrames().intersection([.xTrueNorthZVertical,.xMagneticNorthZVertical]).isEmpty }
    var running: Bool { manager.isDeviceMotionActive }
    func start() {
        guard available, !manager.isDeviceMotionActive else { return }
        MotionTilt.shared.suspend(true)
        let status=CLLocationManager().authorizationStatus
        let located=status == .authorizedWhenInUse || status == .authorizedAlways
        let frames=CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame=located && frames.contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xMagneticNorthZVertical
        trueNorth=frame == .xTrueNorthZVertical
        manager.deviceMotionUpdateInterval=1/30
        manager.startDeviceMotionUpdates(using: frame, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let q=motion.attitude.quaternion, g=motion.gravity
            let calibration=motion.magneticField.accuracy
            var accuracy: Double?
            if #available(iOS 27.0, *) { accuracy=motion.headingAccuracy }
            MainActor.assumeIsolated {
                guard let self else { return }
                // Core Motion speaks in the device's own axes; an iPad held in landscape turns the screen's.
                let measured=SkyCompass.Pose(quaternion: simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w), gravity: SIMD3(g.x, g.y, g.z)).turned(Self.quarterTurns())
                self.pose=self.pose.map { Self.smooth($0, toward: measured) } ?? measured
                if let accuracy { self.needsCalibration=accuracy<0 || accuracy>20 }
                else { self.needsCalibration=calibration == .uncalibrated || calibration == .low }
            }
        }
    }
    func stop() {
        manager.stopDeviceMotionUpdates()
        MotionTilt.shared.suspend(false)
        pose=nil
    }
    /// How far the interface is turned from the device's portrait (always 0 on iPhone, which is portrait only).
    private static func quarterTurns() -> Int {
        let scenes=UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return switch (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.effectiveGeometry.interfaceOrientation {
        case .landscapeRight: 1
        case .portraitUpsideDown: 2
        case .landscapeLeft: 3
        default: 0
        }
    }
    /// A gentle low-pass, so the sky glides rather than jitters in the hand.
    private static func smooth(_ a: SkyCompass.Pose, toward b: SkyCompass.Pose) -> SkyCompass.Pose {
        func mix(_ x: SIMD3<Double>, _ y: SIMD3<Double>) -> SIMD3<Double> { simd_normalize(x+(y-x)*0.3) }
        return SkyCompass.Pose(look: mix(a.look, b.look), up: mix(a.up, b.up))
    }
}

// MARK: What to point at

/// Everything "where to look" can show at one moment: the Moon, the Milky Way's core, the planets,
/// a shower's radiant and the brighter stars, in altitude and azimuth for the park.
nonisolated struct FieldSkyTarget: Sendable, Identifiable, Equatable {
    enum Kind: Sendable, Equatable { case moon, core, planet, radiant, star }
    let id: String
    let kind: Kind
    let name: String
    let altitude: Double
    let azimuth: Double
    let magnitude: Double
    var spoken: String { "\(name): \(SkyCompass.spoken(altitude: altitude, azimuth: azimuth))" }
    static func named(park: Park, sky: SkyConditions, at date: Date, almanac: SkyAlmanac = SkyAlmanac()) -> [FieldSkyTarget] {
        let engine=AstronomyEngine(), rad=Double.pi/180
        var targets: [FieldSkyTarget]=[]
        let moon=engine.equatorial(of: .moon, at: date), moonAt=engine.horizontal(date: date, park: park, ra: moon.ra, dec: moon.dec)
        targets.append(FieldSkyTarget(id: "moon", kind: .moon, name: String(localized: "Moon"), altitude: engine.lunarAltitude(at: date, park: park), azimuth: moonAt.azimuth, magnitude: -12))
        let core=engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec)
        targets.append(FieldSkyTarget(id: "core", kind: .core, name: String(localized: "Milky Way core"), altitude: core.altitude, azimuth: core.azimuth, magnitude: 0))
        for planet in SkyAlmanac.Planet.allCases {
            let p=almanac.position(of: planet, at: date), h=engine.horizontal(date: date, park: park, ra: p.ra, dec: p.dec)
            // Planets lost in the Sun's glare are left out, as on park detail.
            guard p.elongation>=12 else { continue }
            targets.append(FieldSkyTarget(id: planet.rawValue, kind: .planet, name: planet.name, altitude: h.altitude, azimuth: h.azimuth, magnitude: p.magnitude))
        }
        if let shower=WhatsUp.Events(park: park, sky: sky, almanac: almanac).shower, shower.hourlyRate>=2 || shower.isPeakNight {
            let h=engine.horizontal(date: date, park: park, ra: shower.shower.radiantRA*rad, dec: shower.shower.radiantDec*rad)
            targets.append(FieldSkyTarget(id: "radiant", kind: .radiant, name: String(localized: "\(shower.shower.name) radiant"), altitude: h.altitude, azimuth: h.azimuth, magnitude: 0))
        }
        return targets
    }
}

extension SkyCompass.Pose {
    /// A pose from already orthonormal axes (used for smoothing).
    nonisolated init(look: SIMD3<Double>, up: SIMD3<Double>) {
        let l=simd_normalize(look)
        let u=simd_normalize(up-simd_dot(up, l)*l)
        self.init(axes: l, u, simd_cross(l, u))
    }
}
