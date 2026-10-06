import Foundation
import CoreHaptics

/// "Feel the Moon": the Moon's phase as a texture under the finger. A new Moon is a few sharp,
/// sparse taps; as it fills, the taps soften and crowd together over a broad, low hum, until a
/// full Moon is one wide, even swell. A waxing Moon's hum grows across the pattern and a waning
/// one's fades, so the direction of the phase can be felt too. Pure parameters, for tests.
nonisolated struct MoonTexture: Sendable, Equatable {
    struct Tap: Sendable, Equatable {
        let time: Double
        let intensity: Double
        let sharpness: Double
    }
    struct Hum: Sendable, Equatable {
        let duration: Double
        /// Relative intensity at the start and end, on top of `intensity`.
        let from: Double
        let to: Double
        let intensity: Double
        let sharpness: Double
    }
    let taps: [Tap]
    let hum: Hum?

    static func moon(illumination: Double, waxing: Bool, duration: Double=1.2) -> MoonTexture {
        let lit=min(1,max(0,illumination))
        let count=3+Int((9*lit).rounded())
        let taps=(0..<count).map { k in Tap(time:duration*(Double(k)+0.5)/Double(count),intensity:0.85-0.45*lit,sharpness:1-0.75*lit) }
        let hum=lit<0.05 ? nil : Hum(duration:duration,from:waxing ? 0.4 : 1,to:waxing ? 1 : 0.4,intensity:0.8*lit,sharpness:0.35-0.3*lit)
        return MoonTexture(taps:taps,hum:hum)
    }
    /// One night's detent on the river: firmer and crisper as the score rises, so the best
    /// nights click and the poor ones thud.
    static func detent(score: Int) -> Tap {
        let s=Double(min(100,max(0,score)))/100
        return Tap(time:0,intensity:0.3+0.6*s,sharpness:0.15+0.85*s)
    }
}

/// Plays `MoonTexture`s on the iPhone's Taptic Engine. Absent on hardware without haptics (the
/// simulator, some iPads), where callers keep SwiftUI's `sensoryFeedback`. Haptics only: it never
/// touches the audio session.
final class MoonHaptics {
    static let shared=MoonHaptics()
    static var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }
    /// The person's switch in Settings › Accessibility (on by default).
    static let settingKey="moonHaptics"
    static var enabled: Bool { supported && (UserDefaults.standard.object(forKey:settingKey) as? Bool ?? true) }
    private var engine: CHHapticEngine?

    func play(_ texture: MoonTexture) {
        var events=texture.taps.map { tap in
            CHHapticEvent(eventType:.hapticTransient,parameters:[
                CHHapticEventParameter(parameterID:.hapticIntensity,value:Float(tap.intensity)),
                CHHapticEventParameter(parameterID:.hapticSharpness,value:Float(tap.sharpness))],relativeTime:tap.time)
        }
        var curves:[CHHapticParameterCurve]=[]
        if let hum=texture.hum {
            events.append(CHHapticEvent(eventType:.hapticContinuous,parameters:[
                CHHapticEventParameter(parameterID:.hapticIntensity,value:Float(hum.intensity)),
                CHHapticEventParameter(parameterID:.hapticSharpness,value:Float(hum.sharpness))],relativeTime:0,duration:hum.duration))
            curves.append(CHHapticParameterCurve(parameterID:.hapticIntensityControl,controlPoints:[
                CHHapticParameterCurve.ControlPoint(relativeTime:0,value:Float(hum.from)),
                CHHapticParameterCurve.ControlPoint(relativeTime:hum.duration,value:Float(hum.to))],relativeTime:0))
        }
        play(events:events,curves:curves)
    }
    func detent(score: Int) {
        let tap=MoonTexture.detent(score:score)
        play(events:[CHHapticEvent(eventType:.hapticTransient,parameters:[
            CHHapticEventParameter(parameterID:.hapticIntensity,value:Float(tap.intensity)),
            CHHapticEventParameter(parameterID:.hapticSharpness,value:Float(tap.sharpness))],relativeTime:0)],curves:[])
    }
    private func play(events:[CHHapticEvent],curves:[CHHapticParameterCurve]) {
        guard Self.supported, let engine=ready(), let pattern=try? CHHapticPattern(events:events,parameterCurves:curves),
              let player=try? engine.makePlayer(with:pattern) else { return }
        try? player.start(atTime:CHHapticTimeImmediate)
    }
    /// The engine, started; rebuilt if the system stopped it (a call, the app in the background).
    private func ready()->CHHapticEngine? {
        if engine == nil {
            engine=try? CHHapticEngine()
            engine?.playsHapticsOnly=true
            engine?.isAutoShutdownEnabled=true
        }
        do { try engine?.start() } catch { engine=nil; return nil }
        return engine
    }
}
