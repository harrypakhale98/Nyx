import CoreMotion
import Foundation
import SwiftUI

/// How the phone is tilted, for highlights that catch the light as you move it.
/// Gravity only: no activity, no location, no permission prompt; nothing leaves the phone.
/// Runs only while a view that wants it is on screen, and never under Reduce Motion
/// or Low Power Mode. Values are read inside per-frame drawing, so they are not observed.
@MainActor final class MotionTilt {
    static let shared=MotionTilt()
    /// Samples a second: 30 for the sky's parallax (about 0.1 pt a frame), and 60 while a view that
    /// draws at the display's rate wants it (the dial's glint, `motionTilt(_:fast:)`).
    nonisolated static let sampleRate=30.0, fastRate=60.0
    /// How far each sample at `rate` moves the smoothed tilt: the same time constant at any rate.
    nonisolated static func smoothing(rate:Double)->Double { 1-pow(0.8,30/rate) }
    /// The rate now: fast while any view that wants it fast is on screen.
    private var rate: Double { fastClients>0 ? Self.fastRate : Self.sampleRate }
    /// Of `clients`, those that want the fast rate.
    private var fastClients=0
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
    func start(fast:Bool=false) {
        clients+=1
        if fast { fastClients+=1; if fastClients==1 { manager.deviceMotionUpdateInterval=1/rate } }
        if clients==1 { begin() }
    }
    /// Low Power Mode switched on or off while a view wants tilt.
    func powerChanged() {
        if PowerState.shared.lowPower { manager.stopDeviceMotionUpdates(); x=0; y=0 }
        else if clients>0 { begin() }
    }
    private func begin() {
        guard !suspended,!manager.isDeviceMotionActive,!PowerState.shared.lowPower,manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval=1/rate
        samples=0
        manager.startDeviceMotionUpdates(to:.main) { [weak self] motion,_ in
            guard let gravity=motion?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let rate=self.rate, smoothing=Self.smoothing(rate:rate)
                if self.samples%Int(rate/2)==0 { self.turns=self.interfaceTurns?() ?? 0 }
                self.samples+=1
                let screen=Self.screenGravity(x:gravity.x,y:gravity.y,quarterTurns:self.turns)
                self.x+=(max(-1,min(1,screen.x))-self.x)*smoothing
                self.y+=(max(-1,min(1,screen.y+0.6))-self.y)*smoothing
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
    func stop(fast:Bool=false) {
        guard clients>0 else { return }
        clients-=1
        if fast, fastClients>0 { fastClients-=1; if fastClients==0 { manager.deviceMotionUpdateInterval=1/rate } }
        guard clients==0 else { return }
        manager.stopDeviceMotionUpdates()
        x=0; y=0
    }
}
extension View {
    /// Holds a claim on the tilt while this view is on screen and `wanted` is true, and lets it go
    /// when the view leaves or stops wanting it (Reduce Motion turned on, scrolled away), so every
    /// view counts on its own and a change of setting takes effect without leaving the screen.
    /// `fast`: this view draws at the display's rate and wants tilt at `MotionTilt.fastRate`.
    func motionTilt(_ wanted:Bool,fast:Bool=false)->some View { modifier(MotionTiltClient(wanted:wanted,fast:fast)) }
}
private struct MotionTiltClient: ViewModifier {
    let wanted: Bool
    let fast: Bool
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
        if want { MotionTilt.shared.start(fast:fast) } else { MotionTilt.shared.stop(fast:fast) }
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
/// orbiting stars and glint, the starfield, the real sky behind each screen). The full-screen skies
/// redraw at most `rate` times a second; what visibly travels (the dial's stars, the loading sweep)
/// runs at the display's own rate, `movingInterval`. None of it redraws while it is held still
/// (Reduce Motion, reduced resources), covered (a full-screen sky over the page, `skyResting`), out
/// of view (scrolled away, Nyx in the background), while a finger moves the page (`DecorationHold`),
/// in Low Power Mode, or while the device is hot (thermal state serious or critical). Resting keeps
/// the frame on screen; it only stops redrawing it.
@MainActor enum Decoration {
    /// 30 Hz for a full screen of stars: twinkle is a change of brightness and the parallax moves about
    /// 0.1 pt a frame, so both read as continuous, at a quarter of ProMotion's frames.
    static let rate=30.0
    static var interval: Double { 1/rate }
    /// Nil is the display's own best rate: 120 Hz on ProMotion, 60 Hz elsewhere. For small things that
    /// travel far enough to show their steps at 30 Hz (the dial's stars move up to 1.2 pt a frame there).
    static let movingInterval: Double?=nil
    static func rests(still:Bool,covered:Bool=false,offscreen:Bool=false)->Bool {
        rests(still:still,covered:covered || DecorationHold.shared.holding,offscreen:offscreen,lowPower:PowerState.shared.lowPower,hot:PowerState.shared.thermalSerious)
    }
    /// The time decoration is drawn at: it stops while held, so a star picks up where it left off.
    static func time(_ date:Date)->Double { DecorationHold.shared.time(at:date) }
    /// The rule itself, from its inputs (tested).
    nonisolated static func rests(still:Bool,covered:Bool,offscreen:Bool,lowPower:Bool,hot:Bool)->Bool {
        still || covered || offscreen || lowPower || hot
    }
}

/// Decoration's clock, which stops while any page is being moved. Twinkle is worked out from the time,
/// so with an ordinary clock every star would change brightness at once as the page came to rest.
nonisolated struct DecorationClock {
    private var holds=0
    private var since: Date?
    private var held=0.0
    var holding: Bool { holds>0 }
    mutating func hold(at date:Date) {
        holds+=1
        if holds==1 { since=date }
    }
    mutating func release(at date:Date) {
        guard holds>0 else { return }
        holds-=1
        guard holds==0, let since else { return }
        held+=max(0,date.timeIntervalSince(since))
        self.since=nil
    }
    func time(at date:Date)->Double { min(date,since ?? date).timeIntervalSinceReferenceDate-held }
}
/// A finger moving a page (a scroll, a fling, a scrub of the time river) holds decoration still, so
/// each of ProMotion's 8 ms frames goes to what is under the finger, not to redrawing the stars.
@MainActor @Observable final class DecorationHold {
    static let shared=DecorationHold()
    private(set) var holding=false
    @ObservationIgnored private var clock=DecorationClock()
    func hold() { clock.hold(at:.now); holding=clock.holding }
    func release() { clock.release(at:.now); holding=clock.holding }
    func time(at date:Date)->Double { clock.time(at:date) }
}
extension View {
    /// Holds decoration while `active` and this view is on screen; let go when either ends, so a view
    /// torn down in the middle of a move never leaves the stars stopped.
    func restsDecoration(while active:Bool)->some View { modifier(DecorationHoldClient(active:active)) }
    /// Holds decoration while the first scroll view in this hierarchy is moving.
    func restsDecorationWhileScrolling()->some View { modifier(ScrollDecorationHold()) }
}
private struct DecorationHoldClient: ViewModifier {
    let active: Bool
    @State private var onScreen=false
    @State private var claimed=false
    func body(content:Content)->some View {
        content
            .onAppear { onScreen=true; sync(onScreen:true,active:active) }
            .onDisappear { onScreen=false; sync(onScreen:false,active:active) }
            .onChange(of:active) { _,now in sync(onScreen:onScreen,active:now) }
    }
    private func sync(onScreen:Bool,active:Bool) {
        let want=onScreen && active
        guard want != claimed else { return }
        claimed=want
        if want { DecorationHold.shared.hold() } else { DecorationHold.shared.release() }
    }
}
private struct ScrollDecorationHold: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var scrolling=false
    func body(content:Content)->some View {
        content
            .onScrollPhaseChange { _,phase in scrolling=phase.isScrolling }
            // No phase arrives for a scroll that ended out of sight: it must not hold on return.
            .onDisappear { scrolling=false }
            .onChange(of:scenePhase) { _,phase in if phase == .background { scrolling=false } }
            .restsDecoration(while:scrolling)
    }
}
