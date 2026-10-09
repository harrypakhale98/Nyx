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
    nonisolated init(night: FieldNight, score: Int, band: String, closure: String?=nil) {
        let window=SkyAlmanac.nightWindow(night.sky)
        let ranked=night.milestones.filter { $0.kind != .sunset && $0.kind != .sunrise }
            .sorted { (Self.priority.firstIndex(of: $0.kind) ?? 99, $0.date)<(Self.priority.firstIndex(of: $1.kind) ?? 99, $1.date) }
        let kept=ranked.prefix(Self.maximumMilestones).sorted { $0.date<$1.date }
        self.init(parkID: night.park.id, parkName: night.park.shortName, score: score, band: band,
                  dusk: night.sky.sunset ?? window.start, dawn: night.sky.sunrise ?? window.end,
                  darkStart: night.sky.darkStart, darkEnd: night.sky.darkEnd,
                  milestones: kept.map { Milestone(title: $0.title, date: $0.date, symbol: $0.symbol) }, timeZoneID: night.park.timeZoneID,
                  nightID: night.sky.evening, closure: closure)
    }
    /// About eight hours: how long iOS keeps a Live Activity running before it ends it (Apple's
    /// documentation; the SDK says only "the maximum duration for Live Activities"). It then stays
    /// on the Lock Screen, ended, for up to four hours more (the SDK's "four-hour window").
    nonisolated static let activeLimit: TimeInterval=8*3600
    /// When a followed night begins on the Lock Screen by itself: half an hour before sunset, so
    /// the drive and the last light are covered, but never so early that the system's limit ends
    /// it before an hour past the middle of true darkness (long winter nights start a little later).
    nonisolated static func followStart(_ sky: SkyConditions) -> Date {
        let window=sky.cloudWindow
        let middle=window.start.addingTimeInterval(window.end.timeIntervalSince(window.start)/2)
        let dusk=sky.sunset ?? SkyAlmanac.nightWindow(sky).start
        return max(dusk.addingTimeInterval(-1800), middle.addingTimeInterval(3600-activeLimit))
    }
    /// The alert that announces a followed night when it begins: "Tonight at Joshua Tree",
    /// "True darkness at 7:42 PM". Park time, as everywhere in Nyx.
    nonisolated static func followAlert(park: Park, sky: SkyConditions) -> (title: String, body: String) {
        let title=String(localized: "Tonight at \(park.shortName)")
        if let dark=sky.darkStart { return (title, String(localized: "True darkness at \(park.time(dark))")) }
        if let sunset=sky.sunset { return (title, String(localized: "No true darkness tonight. Sunset at \(park.time(sunset)).")) }
        return (title, SkyConditions.noDarknessMessage(tonight: true))
    }
}

/// Starts, refreshes and ends the night's Live Activities. Field mode runs one for tonight; a
/// night followed ahead ("Follow this night") is scheduled to start by itself before sunset, with
/// no app launch and no push server. One activity per park and night. Each ends itself at dawn
/// the next time Nyx runs (or is refreshed in the background), and iOS retires it regardless.
@MainActor enum FieldActivities {
    typealias Item=Activity<FieldActivityAttributes>
    nonisolated static var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    /// The night in progress: started and not yet ended.
    nonisolated static var current: Item? { Item.activities.first { $0.activityState == .active || $0.activityState == .stale } }
    /// Pending (scheduled), running or stale: everything that still means "followed".
    nonisolated private static var live: [Item] { Item.activities.filter { [.pending, .active, .stale].contains($0.activityState) } }
    nonisolated static func isFollowing(_ park: Park) -> Bool { current?.attributes.parkID == park.id }
    nonisolated static func isFollowing(park: Park, night: Date) -> Bool { live.contains { $0.attributes.covers(parkID: park.id, night: night) } }
    /// Field mode for tonight. A night already followed at this park becomes the field face (no
    /// longer "heading out"); other running activities end, while nights followed for later stay.
    static func start(night: FieldNight, score: DarknessScore, nightVision: Bool, closure: String?=nil, now: Date = .now) async {
        guard enabled, !night.isOver(at: now) else { return }
        let evening=night.sky.evening
        for activity in live {
            let same=activity.attributes.covers(parkID: night.park.id, night: evening)
            if same, activity.activityState != .pending {
                await activity.update(activity.attributes.content(at: now, nightVision: nightVision, heading: false))
                NightFollowing.shared.reload()
                return
            }
            if same || activity.activityState != .pending { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let attributes=FieldActivityAttributes(night: night, score: score.value, band: score.band.label, closure: closure)
        let scored=FieldActivityAttributes.Scored(score: score.value, band: score.band.label, closure: closure, at: now)
        _=try? Item.request(attributes: attributes, content: attributes.content(at: now, nightVision: nightVision, scored: scored))
        NightFollowing.shared.reload()
    }
    /// What a followed night is now, handed to `refresh` by whoever holds fresh forecasts and park
    /// alerts: its night as Nyx scores it, and the park's closure line once its alerts have been
    /// read (`closureKnown`; without them the last closure line stays, never a lifted one).
    nonisolated struct Now: Sendable {
        let night: Night
        let closure: String?
        let closureKnown: Bool
    }
    /// When a night's score was worked out, for the "as of" day: the time of the cloud forecast it
    /// rests on, or now for a night no forecast reaches (its score uses the usual clouds, or the
    /// Moon and darkness alone, which do not age).
    nonisolated static func scoredAt(_ night: Night, now: Date = .now) -> Date {
        min(now, night.forecastUpdated ?? now)
    }
    /// The score, band and closure a followed night should carry, from what it is now. Nil `now`
    /// keeps what the state already carries.
    nonisolated static func scored(_ current: Now?, attributes: FieldActivityAttributes, previous: FieldActivityAttributes.ContentState, now: Date) -> FieldActivityAttributes.Scored? {
        guard let current else { return previous.scored }
        let closure=current.closureKnown ? current.closure : attributes.closure(previous)
        return .init(score: current.night.score.value, band: current.night.score.band.label, closure: closure, at: scoredAt(current.night, now: now))
    }
    /// What a refresh does to a followed night.
    nonisolated enum Action: Equatable { case keep, update, reschedule }
    /// The decision, kept pure so it can be tested. A running night is updated when its score,
    /// band or closure changed, or when its score stops (or starts) being old enough to name its
    /// day. A scheduled one cannot be updated before it starts (ActivityKit), so when its score,
    /// band or closure changed it is ended and requested again for the same moment, with the same
    /// alert; the person sees nothing until it starts. Nothing changes without a new score.
    nonisolated static func action(pending: Bool, attributes: FieldActivityAttributes, previous: FieldActivityAttributes.ContentState,
                                   scored: FieldActivityAttributes.Scored?) -> Action {
        guard let scored else { return .keep }
        var next=previous
        next.scored=scored
        let moved=attributes.score(previous) != scored.score || attributes.band(previous) != scored.band || attributes.closure(previous) != scored.closure
        if pending { return moved ? .reschedule : .keep }
        return moved || (attributes.scoreDay(previous) == nil) != (attributes.scoreDay(next) == nil) ? .update : .keep
    }
    enum FollowResult: Equatable { case scheduled(Date), started, alreadyFollowing, unavailable, over }
    /// "Follow this night": the night's activity, scheduled for `followStart` (iOS 26), or at once
    /// when that moment has passed. Opens heading out: sunset, true darkness, the closure line.
    @discardableResult static func follow(night: Night, closure: String?, nightVision: Bool, now: Date = .now) async -> FollowResult {
        let park=night.park
        guard enabled else { return .unavailable }
        guard !FieldNight.isOver(night.sky, at: now) else { return .over }
        guard !isFollowing(park: park, night: night.id) else { return .alreadyFollowing }
        let scored=FieldActivityAttributes.Scored(score: night.score.value, band: night.score.band.label, closure: closure, at: Self.scoredAt(night, now: now))
        let start=FieldActivityAttributes.followStart(night.sky)
        defer { NightFollowing.shared.reload() }
        if start<=now.addingTimeInterval(60) {
            let attributes=FieldActivityAttributes(night: FieldNight(park: park, sky: night.sky), score: scored.score, band: scored.band, closure: closure)
            return (try? Item.request(attributes: attributes, content: attributes.content(at: now, nightVision: nightVision, heading: true, scored: scored))) == nil ? .unavailable : .started
        }
        return (try? schedule(night: night, scored: scored, start: start, nightVision: nightVision, now: now)) == nil ? .unavailable : .scheduled(start)
    }
    /// A followed night's activity, scheduled to start by itself at `start` with its alert. Opens
    /// heading out, worked out for the moment it starts; `updated` says when it was planned.
    @discardableResult private static func schedule(night: Night, scored: FieldActivityAttributes.Scored, start: Date, nightVision: Bool, now: Date) throws -> Item {
        let attributes=FieldActivityAttributes(night: FieldNight(park: night.park, sky: night.sky), score: scored.score, band: scored.band, closure: scored.closure)
        let content=attributes.content(at: start, nightVision: nightVision, heading: true, updated: now, scored: scored)
        return try Item.request(attributes: attributes, content: content, pushType: nil, style: .standard, alertConfiguration: alert(night), start: start)
    }
    private static func alert(_ night: Night) -> AlertConfiguration {
        let words=FieldActivityAttributes.followAlert(park: night.park, sky: night.sky)
        return AlertConfiguration(title: LocalizedStringResource(stringLiteral: words.title), body: LocalizedStringResource(stringLiteral: words.body), sound: .default)
    }
    /// A scheduled night whose score, band or closure changed: ended and requested again for the
    /// same start (`followStart` is astronomy only, so it gives the moment it was planned for) with
    /// the same alert. Still one activity per park and night: nothing is requested while another
    /// one covers it. If the new request is refused (the system's limit on Live Activities), the
    /// night is requested again as it was, so a refresh never unfollows a night.
    private static func reschedule(_ activity: sending Item, to current: Now, scored: FieldActivityAttributes.Scored, nightVision: Bool, now: Date) async {
        let night=current.night
        let start=FieldActivityAttributes.followStart(night.sky)
        // About to start by itself: leave it; it is brought up to date once it runs.
        guard start>now.addingTimeInterval(60) else { return }
        let id=activity.id
        let other=live.contains { $0.id != id && $0.attributes.covers(parkID: night.park.id, night: night.id) }
        let previous=activity.content.state, attributes=activity.attributes
        await activity.end(nil, dismissalPolicy: .immediate)
        guard !other else { return }
        if (try? schedule(night: night, scored: scored, start: start, nightVision: nightVision, now: now)) == nil {
            var content=previous
            content.nightVision=nightVision
            _=try? Item.request(attributes: attributes, content: ActivityContent(state: content, staleDate: nil), pushType: nil, style: .standard, alertConfiguration: alert(night), start: start)
        }
    }
    /// "Stop following": ends that night's activity, scheduled or running.
    static func unfollow(park: Park, night: Date) async {
        for activity in live where activity.attributes.covers(parkID: park.id, night: night) { await activity.end(nil, dismissalPolicy: .immediate) }
        NightFollowing.shared.reload()
    }
    /// Brings every running activity up to date and ends one whose night is over. `current` says
    /// what each followed night is now (its score, band and closure, from fresh forecasts and park
    /// alerts); without it the score each one carries stays. A scheduled one keeps its plan unless
    /// its score, band or closure changed (`action`), and ends if its night passed without it starting.
    static func refresh(nightVision: Bool, now: Date = .now, current: (@MainActor (FieldActivityAttributes) -> Now?)?=nil) async {
        for activity in Item.activities {
            let attributes=activity.attributes, previous=activity.content.state
            let found=current?(attributes)
            let scored=Self.scored(found, attributes: attributes, previous: previous, now: now)
            switch activity.activityState {
            case .pending:
                if now>=attributes.dawn { await activity.end(nil, dismissalPolicy: .immediate) }
                else if let found, let scored, Self.action(pending: true, attributes: attributes, previous: previous, scored: scored) == .reschedule {
                    await reschedule(activity, to: found, scored: scored, nightVision: nightVision, now: now)
                }
            case .active, .stale:
                let content=attributes.content(at: now, nightVision: nightVision, heading: previous.heading ?? false, scored: scored)
                if content.state.finished { await activity.end(content, dismissalPolicy: .immediate) }
                else if Self.changed(previous, content.state, attributes: attributes) || activity.activityState == .stale { await activity.update(content) }
            default: break
            }
        }
        NightFollowing.shared.reload()
    }
    /// A change worth an update: anything but the moment it was worked out and the exact time of
    /// its score, which matters only when it decides whether the face names the score's day.
    nonisolated static func changed(_ a: FieldActivityAttributes.ContentState, _ b: FieldActivityAttributes.ContentState, attributes: FieldActivityAttributes) -> Bool {
        if (attributes.scoreDay(a) == nil) != (attributes.scoreDay(b) == nil) { return true }
        var a=a, b=b
        a.updated=nil; b.updated=nil; a.scoredAt=nil; b.scoredAt=nil
        return a != b
    }
    /// Leaves field mode's night: ends what is running; nights followed for later stay scheduled.
    static func stop() async {
        for activity in Item.activities where activity.activityState != .pending { await activity.end(nil, dismissalPolicy: .immediate) }
        NightFollowing.shared.reload()
    }
}

/// What the app shows of followed nights (the park page's and calendar's "Follow this night", the
/// tab bar's night in progress). Read from ActivityKit, which is the only record: nothing else is
/// stored. Reloaded after every change Nyx makes and whenever Nyx becomes active, since a
/// scheduled activity starts, and iOS ends one, while Nyx is closed.
@MainActor @Observable final class NightFollowing {
    static let shared=NightFollowing()
    nonisolated struct Followed: Equatable, Identifiable, Sendable {
        var id: String { "\(attributes.parkID)-\(Int((attributes.nightID ?? attributes.dusk).timeIntervalSince1970))" }
        let attributes: FieldActivityAttributes
        let started: Bool
        static func == (a: Followed, b: Followed) -> Bool { a.id == b.id && a.started == b.started }
    }
    private(set) var nights: [Followed]=[]
    @ObservationIgnored private var watching=false
    func reload() {
        #if DEBUG
        if let fixture=DebugFollowing.fixture { nights=[fixture]; return }
        #endif
        let items=FieldActivities.Item.activities.filter { [.pending, .active, .stale].contains($0.activityState) }
        let next=items.map { Followed(attributes: $0.attributes, started: $0.activityState != .pending) }.sorted { $0.attributes.dusk<$1.attributes.dusk }
        if next != nights { nights=next }
        watch()
    }
    func isFollowing(park: Park, night: Date) -> Bool { nights.contains { $0.attributes.covers(parkID: park.id, night: night) } }
    /// The night for the tab bar: started, or about to (from three hours before sunset), until dawn.
    func inProgress(at now: Date) -> Followed? { Self.inProgress(nights, at: now) }
    nonisolated static func inProgress(_ nights: [Followed], at now: Date) -> Followed? {
        nights.first { now<$0.attributes.dawn && ($0.started || now>=$0.attributes.dusk.addingTimeInterval(-3*3600)) }
    }
    /// A scheduled activity starting, or one ending, refreshes the list while Nyx is open.
    private func watch() {
        guard !watching else { return }
        watching=true
        Task { [weak self] in
            for await _ in FieldActivities.Item.activityUpdates { self?.reload() }
        }
    }
}

// MARK: Alarms

/// Wake-ups for the night, through AlarmKit: they ring through Silent and Focus, which a
/// notification cannot. Set on this iPhone only. AlarmKit's alert without a stop button needs
/// iOS 26.1, so alarms are offered from 26.1; on 26.0 the rows are simply absent.
enum FieldAlarmError: Error { case unsupported }
@MainActor enum FieldAlarms {
    /// Not on a Mac running the iPad app, where alarms were never designed or tried.
    static var supported: Bool { if #available(iOS 26.1, *) { !ProcessInfo.processInfo.isiOSAppOnMac } else { false } }
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
    /// "Open sky" for the Milky Way's core rising; Snooze for the others.
    nonisolated static func opensSky(_ kind: FieldNight.AlarmOption.Kind) -> Bool { kind == .core }
    static func toggle(park: Park, option: FieldNight.AlarmOption) async throws {
        let key=key(park: park, option: option)
        if let id=ledger[key].flatMap(UUID.init(uuidString:)), isSet(park: park, option: option) {
            try AlarmManager.shared.cancel(id: id)
            ledger[key]=nil
            return
        }
        // The rows are hidden below iOS 26.1 (`supported`); if one is reached anyway, say so rather than do nothing.
        guard #available(iOS 26.1, *) else { throw FieldAlarmError.unsupported }
        let id=UUID()
        // One secondary button. "Wake me" alarms snooze; the core rising opens the sky in red, so the
        // eyes go from a dark room to a dark screen rather than the bright Lock Screen.
        let opensSky=Self.opensSky(option.kind)
        let secondary=opensSky ? AlarmButton(text: "Open sky", textColor: tint, systemImageName: "scope") : AlarmButton(text: "Snooze", textColor: tint, systemImageName: "zzz")
        let alert=AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: option.alarmTitle), secondaryButton: secondary, secondaryButtonBehavior: opensSky ? .custom : .countdown)
        let attributes=AlarmAttributes(presentation: AlarmPresentation(alert: alert, countdown: AlarmPresentation.Countdown(title: "Snoozing")),
                                       metadata: FieldAlarmMetadata(parkName: park.shortName, kind: option.kind.rawValue), tintColor: tint)
        let snoozeFor=opensSky ? nil : Alarm.CountdownDuration(preAlert: nil, postAlert: 9*60)
        let openSky=opensSky ? OpenSkyIntent(parkID: park.id) : nil
        let configuration: AlarmManager.AlarmConfiguration<FieldAlarmMetadata>
        if #available(iOS 27.0, *) {
            // Siri and the system can then name the park the alarm belongs to.
            configuration=AlarmManager.AlarmConfiguration(countdownDuration: snoozeFor, schedule: .fixed(option.fire), attributes: attributes,
                                                          appEntityIdentifier: EntityIdentifier(for: ParkEntity.self, identifier: park.id), secondaryIntent: openSky)
        } else {
            configuration=AlarmManager.AlarmConfiguration(countdownDuration: snoozeFor, schedule: .fixed(option.fire), attributes: attributes, secondaryIntent: openSky)
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
    /// Never on a Mac running the iPad app: the compass is for a device held up to the sky.
    var available: Bool { !ProcessInfo.processInfo.isiOSAppOnMac && manager.isDeviceMotionAvailable && !CMMotionManager.availableAttitudeReferenceFrames().intersection([.xTrueNorthZVertical,.xMagneticNorthZVertical]).isEmpty }
    var running: Bool { manager.isDeviceMotionActive }
    /// A view wants attitude updates.
    private var wanted=false
    /// Resting while the phone is hot (thermal state serious or critical).
    private(set) var resting=false
    /// Stops the sensor while the phone is hot and starts it again once it cools; the pose stays
    /// where it was, so the sky view holds still rather than going blank.
    func rest(_ on: Bool) {
        guard on != resting else { return }
        resting=on
        if on { manager.stopDeviceMotionUpdates() } else if wanted { begin() }
    }
    func start() {
        wanted=true
        begin()
    }
    private func begin() {
        guard available, !resting, !manager.isDeviceMotionActive else { return }
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
        wanted=false
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
            targets.append(FieldSkyTarget(id: "radiant", kind: .radiant, name: String(localized: "\(shower.shower.localizedName) radiant"), altitude: h.altitude, azimuth: h.azimuth, magnitude: 0))
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
