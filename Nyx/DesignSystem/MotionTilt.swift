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

    func start(reduceMotion:Bool) {
        clients+=1
        guard clients==1,!reduceMotion,!ProcessInfo.processInfo.isLowPowerModeEnabled,manager.isDeviceMotionAvailable else { return }
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
        manager.stopDeviceMotionUpdates()
        x=0; y=0
    }
}
