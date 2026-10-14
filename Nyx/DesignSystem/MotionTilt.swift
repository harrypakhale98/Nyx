import CoreMotion
import Foundation
import SwiftUI

/// How the phone is tilted, for highlights that catch the light as you move it.
/// Gravity only: no activity, no location, no permission prompt; nothing leaves the phone.
/// Runs at 30 Hz only while a view that wants it is on screen, and never under Reduce Motion
/// or Low Power Mode. Values are read inside per-frame drawing, so they are not observed.
@MainActor final class MotionTilt {
    static let shared=MotionTilt()
    private let manager=CMMotionManager()
    /// Views on screen that want tilt now (`motionTilt(_:)`); a view under Reduce Motion never counts.
    private var clients=0
    /// Sideways tilt, about -1 (left edge down) … 1 (right edge down). Smoothed.
    private(set) var x=0.0
    /// Forward tilt, about -1 … 1. Smoothed.
    private(set) var y=0.0
    /// How far the interface is turned from the device's own portrait, in quarter turns (as field
    /// mode's compass reads it): set by the iPhone app, whose windows can turn; nil leaves the
    /// device's axes (the watch). Gravity is read in the device's axes, so without it an iPhone in
    /// landscape would tip the dial's glint and drift the stars along the wrong side of the screen.
    var interfaceTurns: (@MainActor ()->Int)?
    /// The last turn read, refreshed about twice a second rather than on every sample.
    private var turns=0
    private var samples=0

    /// Field mode's compass needs Core Motion's attitude to itself; the tilt pauses meanwhile.
    private var suspended=false
    func suspend(_ on:Bool) {
        suspended=on
        if on { manager.stopDeviceMotionUpdates(); x=0; y=0 } else if clients>0 { begin() }
    }
    /// One more view wants tilt. Called by `motionTilt(_:)`, which balances it with `stop()`.
    func start() {
        clients+=1
        if clients==1 { begin() }
    }
    /// Low Power Mode switched on or off while a view wants tilt.
    func powerChanged() {
        if PowerState.shared.lowPower { manager.stopDeviceMotionUpdates(); x=0; y=0 }
        else if clients>0 { begin() }
    }
    private func begin() {
        guard !suspended,!manager.isDeviceMotionActive,!PowerState.shared.lowPower,manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval=1/30
        samples=0
        manager.startDeviceMotionUpdates(to:.main) { [weak self] motion,_ in
            guard let gravity=motion?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.samples%15==0 { self.turns=self.interfaceTurns?() ?? 0 }
                self.samples+=1
                let screen=Self.screenGravity(x:gravity.x,y:gravity.y,quarterTurns:self.turns)
                self.x+=(max(-1,min(1,screen.x))-self.x)*0.2
                self.y+=(max(-1,min(1,screen.y+0.6))-self.y)*0.2
            }
        }
    }
    /// Gravity's device-frame x and y as the screen sees them, with the interface turned
    /// `quarterTurns` from the device's portrait (1: the device's top at the screen's left, interface
    /// landscape right; 2: upside down; 3: landscape left), the same turns as `SkyCompass.Pose.turned`.
    nonisolated static func screenGravity(x:Double,y:Double,quarterTurns:Int)->(x:Double,y:Double) {
        switch (quarterTurns%4+4)%4 {
        case 1: (-y,x)
        case 2: (-x,-y)
        case 3: (y,-x)
        default: (x,y)
        }
    }
    func stop() {
        guard clients>0 else { return }
        clients-=1
        guard clients==0 else { return }
        manager.stopDeviceMotionUpdates()
        x=0; y=0
    }
}
extension View {
    /// Holds a claim on the tilt while this view is on screen and `wanted` is true, and lets it go
    /// when the view leaves or stops wanting it (Reduce Motion turned on, scrolled away), so every
    /// view counts on its own and a change of setting takes effect without leaving the screen.
    func motionTilt(_ wanted:Bool)->some View { modifier(MotionTiltClient(wanted:wanted)) }
}
private struct MotionTiltClient: ViewModifier {
    let wanted: Bool
    @State private var onScreen=false
    @State private var claimed=false
    func body(content:Content)->some View {
        content
            .onAppear { onScreen=true; sync(onScreen:true,wanted:wanted) }
            .onDisappear { onScreen=false; sync(onScreen:false,wanted:wanted) }
            .onChange(of:wanted) { _,now in sync(onScreen:onScreen,wanted:now) }
    }
    private func sync(onScreen:Bool,wanted:Bool) {
        let want=onScreen && wanted
        guard want != claimed else { return }
        claimed=want
        if want { MotionTilt.shared.start() } else { MotionTilt.shared.stop() }
    }
}

/// Low Power Mode and the device's thermal state as they change, not only as they were when a
/// view first appeared: a sky drawn every frame stills itself the moment Low Power Mode comes on.
@MainActor @Observable final class PowerState {
    static let shared=PowerState()
    private(set) var lowPower: Bool
    /// The device is hot (serious or critical); sensors and animation should rest.
    private(set) var thermalSerious: Bool
    @ObservationIgnored private var observers: [NSObjectProtocol]=[]
    private init() {
        let info=ProcessInfo.processInfo
        lowPower=info.isLowPowerModeEnabled
        thermalSerious=Self.serious(info.thermalState)
        let center=NotificationCenter.default
        observers=[
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.update() } },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.update() } },
        ]
    }
    private func update() {
        let info=ProcessInfo.processInfo
        let low=info.isLowPowerModeEnabled, hot=Self.serious(info.thermalState)
        if low != lowPower { lowPower=low; MotionTilt.shared.powerChanged() }
        if hot != thermalSerious { thermalSerious=hot }
    }
    nonisolated static func serious(_ state: ProcessInfo.ThermalState) -> Bool { state == .serious || state == .critical }
}
/// One rule for when Nyx's decoration rests, shared by every decorative timeline (the dial's
/// orbiting stars and glint, the starfield, the real sky behind each screen): it redraws at most
/// `rate` times a second, and not at all while it is held still (Reduce Motion, reduced
/// resources), covered (a full-screen sky over the page, `skyResting`), out of view (scrolled
/// away, Nyx in the background), in Low Power Mode, or while the device is hot (thermal state
/// serious or critical). Resting keeps the frame on screen; it only stops redrawing it.
@MainActor enum Decoration {
    /// 30 Hz: twinkle and drift read as continuous at this rate, at a quarter of ProMotion's frames.
    static let rate=30.0
    static var interval: Double { 1/rate }
    static func rests(still:Bool,covered:Bool=false,offscreen:Bool=false)->Bool {
        rests(still:still,covered:covered,offscreen:offscreen,lowPower:PowerState.shared.lowPower,hot:PowerState.shared.thermalSerious)
    }
    /// The rule itself, from its inputs (tested).
    nonisolated static func rests(still:Bool,covered:Bool,offscreen:Bool,lowPower:Bool,hot:Bool)->Bool {
        still || covered || offscreen || lowPower || hot
    }
}
