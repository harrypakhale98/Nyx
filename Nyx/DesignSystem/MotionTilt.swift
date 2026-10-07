import CoreMotion
import Foundation

/// How the phone is tilted, for highlights that catch the light as you move it.
/// Gravity only: no activity, no location, no permission prompt; nothing leaves the phone.
/// Runs at 30 Hz only while a view that wants it is on screen, and never under Reduce Motion
/// or Low Power Mode. Values are read inside per-frame drawing, so they are not observed.
@MainActor final class MotionTilt {
    static let shared=MotionTilt()
    private let manager=CMMotionManager()
    private var clients=0
    /// Sideways tilt, about -1 (left edge down) … 1 (right edge down). Smoothed.
    private(set) var x=0.0
    /// Forward tilt, about -1 … 1. Smoothed.
    private(set) var y=0.0

    /// Field mode's compass needs Core Motion's attitude to itself; the tilt pauses meanwhile.
    private var suspended=false
    private var wanted=false
    func suspend(_ on:Bool) {
        suspended=on
        if on { manager.stopDeviceMotionUpdates(); x=0; y=0 } else if wanted && clients>0 { begin() }
    }
    func start(reduceMotion:Bool) {
        clients+=1
        guard clients==1 else { return }
        wanted = !reduceMotion
        if wanted { begin() }
    }
    /// Low Power Mode switched on or off while a view wants tilt.
    func powerChanged() {
        if PowerState.shared.lowPower { manager.stopDeviceMotionUpdates(); x=0; y=0 }
        else if wanted && clients>0 { begin() }
    }
    private func begin() {
        guard !suspended,!manager.isDeviceMotionActive,!PowerState.shared.lowPower,manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval=1/30
        manager.startDeviceMotionUpdates(to:.main) { [weak self] motion,_ in
            guard let gravity=motion?.gravity else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.x+=(max(-1,min(1,gravity.x))-self.x)*0.2
                self.y+=(max(-1,min(1,gravity.y+0.6))-self.y)*0.2
            }
        }
    }
    func stop() {
        clients=max(0,clients-1)
        guard clients==0 else { return }
        wanted=false
        manager.stopDeviceMotionUpdates()
        x=0; y=0
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
