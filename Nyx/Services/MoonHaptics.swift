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

/// "Feel tonight": the night from sunset to sunrise as about twenty-four seconds of touch, for the
/// hand rather than the eyes or ears. A low hum strengthens as the sky darkens (and eases while
/// the Moon is up, more for a fuller Moon), then fades toward dawn; a sharp tap marks moonrise and
/// moonset; a slow swell marks the Milky Way's core rising. Built from the same night as "Listen to
/// tonight", so the two always agree. Pure parameters, for tests.
nonisolated struct NightTouch: Sendable {
    struct Swell: Sendable, Equatable { let time: Double; let duration: Double }
    struct Line: Sendable, Equatable { let offset: Double; let text: String }
    let duration: Double
    /// The hum's strength at evenly spaced moments across `duration`, 0 to 1.
    let hum: [Double]
    /// Moonrise and moonset.
    let taps: [MoonTexture.Tap]
    /// The core rising (or already up when true darkness begins).
    let swells: [Swell]
    /// What is felt and when, in words, for the transcript and VoiceOver.
    let opening: String
    let lines: [Line]

    init(_ sound: NightSonification, duration: Double=24, points: Int=48) {
        self.duration=duration
        let scale=duration/sound.duration
        hum=(0..<points).map { k in
            let i=Int((Double(k)/Double(points-1)*Double(sound.darkness.count-1)).rounded())
            return NightTouch.strength(darkness: sound.darkness[i], moonlight: sound.moonlight[i])
        }
        taps=sound.cues.filter { $0.sound == .pulseRising || $0.sound == .pulseFalling }.map { MoonTexture.Tap(time: $0.offset*scale, intensity: 1, sharpness: 1) }
        swells=sound.cues.filter { $0.sound == .chime }.map { Swell(time: max(0, min(duration-3, $0.offset*scale)), duration: 3) }
        lines=sound.cues.filter { $0.sound != .none || $0.kind == .darkness }.map { Line(offset: $0.offset*scale, text: $0.line) }
        let seconds=Int(duration.rounded())
        opening=String(localized: "\(sound.park.shortName), \(sound.park.dayLabel(sound.window.start)). \(seconds) seconds of touch, from \(sound.park.time(sound.window.start)) to \(sound.park.time(sound.window.end)).")
    }
    /// The hum: faint at dusk and dawn, strongest in true darkness, softened by moonlight (a full
    /// Moon overhead takes half of it away).
    static func strength(darkness: Double, moonlight: Double) -> Double {
        0.12+0.88*min(1, max(0, darkness))*(1-0.5*min(1, max(0, moonlight)))
    }
    /// What each touch means.
    static var key: String {
        String(localized: "A low hum grows as the sky darkens and fades toward dawn; it softens while the Moon is up. A sharp tap is moonrise or moonset. A slow swell is the Milky Way's core rising.")
    }
}

/// Plays `MoonTexture`s on the iPhone's Taptic Engine. Absent on hardware without haptics (the
/// simulator, some iPads), where callers keep SwiftUI's `sensoryFeedback`. Haptics only: it never
/// touches the audio session.
final class MoonHaptics {
    static let shared=MoonHaptics()
    static var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics || DebugScenario.isEnabled("haptics") }
    /// The person's switch in Settings › Accessibility (on by default).
    static let settingKey="moonHaptics"
    static var enabled: Bool { supported && (UserDefaults.standard.object(forKey:settingKey) as? Bool ?? true) }
    private var engine: CHHapticEngine?
    /// "Feel tonight", while it plays.
    private var night: CHHapticPatternPlayer?

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
    /// Plays "Feel tonight"; a second call, or `stop()`, ends the one playing.
    func play(_ touch: NightTouch) {
        stop()
        var events=[CHHapticEvent(eventType:.hapticContinuous,parameters:[
            CHHapticEventParameter(parameterID:.hapticIntensity,value:1),
            CHHapticEventParameter(parameterID:.hapticSharpness,value:0.12)],relativeTime:0,duration:touch.duration)]
        for tap in touch.taps {
            events.append(CHHapticEvent(eventType:.hapticTransient,parameters:[
                CHHapticEventParameter(parameterID:.hapticIntensity,value:Float(tap.intensity)),
                CHHapticEventParameter(parameterID:.hapticSharpness,value:Float(tap.sharpness))],relativeTime:tap.time))
        }
        for swell in touch.swells {
            events.append(CHHapticEvent(eventType:.hapticContinuous,parameters:[
                CHHapticEventParameter(parameterID:.hapticIntensity,value:0.9),
                CHHapticEventParameter(parameterID:.hapticSharpness,value:0.45),
                CHHapticEventParameter(parameterID:.attackTime,value:1.4),
                CHHapticEventParameter(parameterID:.releaseTime,value:1.4)],relativeTime:swell.time,duration:swell.duration))
        }
        guard Self.supported, let engine=ready(), let pattern=try? CHHapticPattern(events:events,parameterCurves:Self.humCurves(touch)),
              let player=try? engine.makePlayer(with:pattern) else { return }
        try? player.start(atTime:CHHapticTimeImmediate)
        night=player
    }
    /// The hum's strength as consecutive intensity curves of at most 16 points each (Core Haptics'
    /// limit per curve), sharing their joins.
    static func humCurves(_ touch: NightTouch) -> [CHHapticParameterCurve] {
        var curves:[CHHapticParameterCurve]=[]
        let step=touch.duration/Double(max(1,touch.hum.count-1))
        var start=0
        while start<touch.hum.count-1 {
            let end=min(touch.hum.count-1,start+15)
            let points=(start...end).map { CHHapticParameterCurve.ControlPoint(relativeTime:Double($0-start)*step,value:Float(touch.hum[$0])) }
            curves.append(CHHapticParameterCurve(parameterID:.hapticIntensityControl,controlPoints:points,relativeTime:Double(start)*step))
            start=end
        }
        return curves
    }
    func stop() {
        try? night?.stop(atTime:CHHapticTimeImmediate)
        night=nil
    }
    /// The sky arc under a finger (`ArcTouch`): one long, low hum whose strength follows the finger,
    /// with a firm click at true darkness's edges and a light tick at moonrise and moonset. Starts
    /// only with the Moon-haptics switch on and a Taptic Engine; `endArcTouch()` on lift.
    private var arc: CHHapticAdvancedPatternPlayer?
    func beginArcTouch(strength: Double) {
        endArcTouch()
        // Core Haptics caps one continuous event at 30 s; the player loops it for a longer rest.
        let hum=CHHapticEvent(eventType:.hapticContinuous,parameters:[
            CHHapticEventParameter(parameterID:.hapticIntensity,value:1),
            CHHapticEventParameter(parameterID:.hapticSharpness,value:0.12)],relativeTime:0,duration:30)
        guard Self.enabled, let engine=ready(), let pattern=try? CHHapticPattern(events:[hum],parameterCurves:[]),
              let player=try? engine.makeAdvancedPlayer(with:pattern) else { return }
        player.loopEnabled=true
        do { try player.start(atTime:CHHapticTimeImmediate) } catch { return }
        arc=player
        followArcTouch(strength:strength,crossings:[])
    }
    /// The finger moved to a new column: the hum takes its strength, and each moment crossed
    /// (at most two, 40 ms apart, so a quick slide stays distinct) clicks or ticks.
    func followArcTouch(strength: Double, crossings: [ArcTouch.Milestone]) {
        guard let arc else { return }
        try? arc.sendParameters([CHHapticDynamicParameter(parameterID:.hapticIntensityControl,value:Float(min(1,max(0,strength))),relativeTime:0)],atTime:CHHapticTimeImmediate)
        let events=crossings.prefix(2).enumerated().map { k,moment in
            CHHapticEvent(eventType:.hapticTransient,parameters:[
                CHHapticEventParameter(parameterID:.hapticIntensity,value:moment.firm ? 1 : 0.5),
                CHHapticEventParameter(parameterID:.hapticSharpness,value:moment.firm ? 0.8 : 0.55)],relativeTime:Double(k)*0.04)
        }
        if !events.isEmpty { play(events:events,curves:[]) }
    }
    func endArcTouch() {
        try? arc?.stop(atTime:CHHapticTimeImmediate)
        arc=nil
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
