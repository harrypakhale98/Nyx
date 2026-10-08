import Foundation
import AVFAudio
import CoreMotion
import Accessibility
import UIKit

/// "Where to look by sound": in field mode's compass, a soft tone placed in the headphones toward
/// one thing in the sky (the Milky Way's core, a planet, the Moon), so it can be found with the
/// screen dark or without looking. The tone sits where the target is relative to where you face:
/// your iPhone's direction, or your head's with AirPods that track it. The pulse quickens and
/// brightens as you turn toward it. Pure geometry here, for tests; playback below.
nonisolated enum BeaconGeometry {
    /// The target relative to the listener, in AVAudio's frame (x right, y up, the listener facing
    /// −z), `distance` metres away. Azimuths are degrees from north through east.
    static func position(targetAltitude: Double, targetAzimuth: Double, facingAzimuth: Double, facingAltitude: Double=0, distance: Double=2) -> SIMD3<Double> {
        let rad=Double.pi/180
        let relative=(targetAzimuth-facingAzimuth)*rad, alt=targetAltitude*rad, pitch=max(-80,min(80,facingAltitude))*rad
        // Turned to face the target's azimuth: x right, y up, z behind.
        let x=sin(relative)*cos(alt), y=sin(alt), z = -cos(relative)*cos(alt)
        // Then tipped by the listener's own pitch (looking up brings a high target forward).
        let y2=y*cos(pitch)+z*sin(pitch), z2 = -y*sin(pitch)+z*cos(pitch)
        return SIMD3(x, y2, z2)*distance
    }
    /// Degrees between where you face and the target, 0 to 180.
    static func offAxis(targetAltitude: Double, targetAzimuth: Double, facingAzimuth: Double, facingAltitude: Double=0) -> Double {
        let p=position(targetAltitude: targetAltitude, targetAzimuth: targetAzimuth, facingAzimuth: facingAzimuth, facingAltitude: facingAltitude, distance: 1)
        return acos(max(-1,min(1,-p.z)))*180/Double.pi
    }
    /// The tone: a soft G, low enough to sit under VoiceOver's voice.
    static let frequency=392.0
    /// Playback rate: 1 when facing away, up to 1.8 facing it, so the pulse quickens as you turn toward it.
    static func rate(offAxis: Double) -> Double { 1+0.8*pow(max(0,1-min(180,offAxis)/180),2) }
    /// The target the tone follows when the person has not chosen one: the Milky Way's core while
    /// it is up, else the brightest planet up, else the Moon if it is up.
    static func automatic(_ targets: [FieldSkyTarget]) -> FieldSkyTarget? {
        let up=targets.filter { $0.altitude>0 }
        return up.first { $0.kind == .core } ?? up.filter { $0.kind == .planet }.min { $0.magnitude<$1.magnitude } ?? up.first { $0.kind == .moon }
    }
    /// One pulse of the tone, mono: a soft bell for 0.35 s, then silence to fill `length` seconds.
    static func pulse(frequency: Double, sampleRate: Double, length: Double=0.9) -> [Float] {
        let count=Int(length*sampleRate)
        return (0..<count).map { n in
            let t=Double(n)/sampleRate
            guard t<0.35 else { return 0 }
            let envelope=min(1,t/0.01)*exp(-t/0.11)
            return Float(0.32*envelope*(sin(2*Double.pi*frequency*t)+0.25*sin(4*Double.pi*frequency*t)))
        }
    }
}

/// Plays the beacon while the compass is open. Off by default; switched on from the compass, after
/// an explainer. Uses `.playback` mixed with other audio, like "Listen to tonight": it is sound the
/// person asked for, so Silent mode does not mute it. Head tracking starts only with headphones
/// that report motion; iOS asks once for motion access, and the motion never leaves this iPhone.
@MainActor @Observable final class SkyBeacon {
    static let shared=SkyBeacon()
    /// Not on a Mac running the iPad app, where there is no sky to point at.
    static var supported: Bool { !ProcessInfo.processInfo.isiOSAppOnMac }
    /// The explainer has been read once on this iPhone.
    static var explained: Bool {
        get { UserDefaults.standard.bool(forKey: "skyBeaconExplained") }
        set { UserDefaults.standard.set(newValue, forKey: "skyBeaconExplained") }
    }
    private(set) var isOn=false
    /// The target chosen by the person; nil follows `BeaconGeometry.automatic`.
    var chosenID: String?
    /// What the tone points to now, and the targets it could point to.
    private(set) var target: FieldSkyTarget?
    private(set) var choices: [FieldSkyTarget]=[]
    /// AirPods (or other headphones) are reporting head motion.
    private(set) var headTracking=false
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var player: AVAudioPlayerNode?
    @ObservationIgnored private var environment: AVAudioEnvironmentNode?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private let head=CMHeadphoneMotionManager()
    /// The phone's azimuth and the head's yaw when tracking began: the head turns from there.
    @ObservationIgnored private var headReference: (azimuth: Double, yaw: Double)?
    @ObservationIgnored private var headPose: (yaw: Double, pitch: Double)?
    nonisolated static let sampleRate=24_000.0

    func set(_ on: Bool, park: Park, sky: SkyConditions, now: @escaping () -> Date) {
        if on { start(park: park, sky: sky, now: now) } else { stop() }
    }
    func stop() {
        loop?.cancel(); loop=nil
        player?.stop(); engine?.stop()
        if engine != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        engine=nil; player=nil; environment=nil
        if head.isDeviceMotionActive { head.stopDeviceMotionUpdates() }
        headReference=nil; headPose=nil; headTracking=false
        isOn=false; target=nil
    }
    private func start(park: Park, sky: SkyConditions, now: @escaping () -> Date) {
        guard !isOn else { return }
        isOn=true
        startHeadTracking()
        loop=Task { [weak self] in
            var refreshed=Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                // Positions move a quarter of a degree a minute: refreshed every 20 seconds.
                if Date.now.timeIntervalSince(refreshed)>20 {
                    refreshed = .now
                    let all=FieldSkyTarget.named(park: park, sky: sky, at: now())
                    let previous=self.target?.id
                    self.choices=all.filter { $0.altitude>0 && $0.kind != .star }
                    self.target=self.choices.first { $0.id == self.chosenID } ?? BeaconGeometry.automatic(all)
                    if self.target?.id != previous { self.announce() }
                }
                self.update()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    /// The person picked a target from the compass.
    func choose(_ id: String?) {
        chosenID=id
        if let id, let picked=choices.first(where: { $0.id == id }) { target=picked } else { target=BeaconGeometry.automatic(choices) }
        announce()
    }
    /// Where the listener faces: the head with tracking headphones, else the iPhone.
    private var facing: (azimuth: Double, altitude: Double)? {
        let phone=FieldMotion.shared.pose
        if let headPose, let headReference { return (headReference.azimuth-(headPose.yaw-headReference.yaw), headPose.pitch) }
        return phone.map { ($0.azimuth, 0) }
    }
    private func update() {
        guard let target, let facing else { player?.volume=0; return }
        if engine == nil { do { try play() } catch { stop(); return } }
        let p=BeaconGeometry.position(targetAltitude: target.altitude, targetAzimuth: target.azimuth, facingAzimuth: facing.azimuth, facingAltitude: facing.altitude)
        player?.position=AVAudio3DPoint(x: Float(p.x), y: Float(p.y), z: Float(p.z))
        player?.rate=Float(BeaconGeometry.rate(offAxis: BeaconGeometry.offAxis(targetAltitude: target.altitude, targetAzimuth: target.azimuth, facingAzimuth: facing.azimuth, facingAltitude: facing.altitude)))
        player?.volume=1
    }
    private func play() throws {
        let samples=BeaconGeometry.pulse(frequency: BeaconGeometry.frequency, sampleRate: Self.sampleRate)
        guard let format=AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
              let buffer=AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel=buffer.floatChannelData?[0] else { throw CocoaError(.featureUnsupported) }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() { channel[i]=sample }
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        let engine=AVAudioEngine(), player=AVAudioPlayerNode(), environment=AVAudioEnvironmentNode()
        engine.attach(player); engine.attach(environment)
        // A mono source is what the environment places in space.
        if #available(iOS 27.0, *) {
            try engine.connectNode(player, to: environment, format: format)
            try engine.connectNode(environment, to: engine.mainMixerNode, format: nil)
        } else {
            engine.connect(player, to: environment, format: format)
            engine.connect(environment, to: engine.mainMixerNode, format: nil)
        }
        player.renderingAlgorithm = .HRTFHQ
        player.sourceMode = .pointSource
        environment.distanceAttenuationParameters.maximumDistance=4
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine=engine; self.player=player; self.environment=environment
    }
    private func startHeadTracking() {
        guard head.isDeviceMotionAvailable, CMHeadphoneMotionManager.authorizationStatus() != .denied, CMHeadphoneMotionManager.authorizationStatus() != .restricted else { return }
        head.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let yaw=motion.attitude.yaw*180/Double.pi, pitch=motion.attitude.pitch*180/Double.pi
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.headReference == nil, let phone=FieldMotion.shared.pose { self.headReference=(phone.azimuth, yaw) }
                self.headPose=(yaw, pitch); self.headTracking=self.headReference != nil
            }
        }
    }
    private func announce() {
        guard let target else { return }
        NightListener.announce(String(localized: "The tone points to \(target.spoken)."), priority: .default)
    }
}
