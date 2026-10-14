import Foundation
import AVFAudio
import SwiftUI
import Accessibility
import UIKit

/// "Listen to tonight": one park's night as twelve seconds of sound, sunset to sunrise. A soft
/// tone falls as the sky darkens and rises again toward dawn; it grows quieter while the Moon is
/// up, more for a fuller Moon; a soft pulse marks moonrise (gliding up) and moonset (gliding
/// down); a small chime marks the Milky Way's core rising. Everything comes from the same
/// astronomy as the screen, and the transcript says the same night in words.
/// Rendered ahead of time into a buffer (pure Swift, no audio files), so it is testable and no
/// Swift code ever runs on the real-time audio thread.
nonisolated struct NightSonification: Sendable {
    enum Sound: String, Sendable { case none, pulseRising, pulseFalling, chime }
    struct Cue: Sendable, Equatable, Identifiable {
        var id: String { kind.rawValue }
        let kind: FieldNight.Kind
        let date: Date
        /// Seconds into the playback.
        let offset: Double
        let sound: Sound
        /// The transcript line: "Moonrise at 1:12 AM, 34% lit".
        let line: String
        /// The moment's SF Symbol, as in field mode.
        var symbol: String="circle"
    }
    let park: Park
    let window: DateInterval
    let duration: Double
    let cues: [Cue]
    /// Control curves, evenly spaced across the night. Darkness is 0 at sunset and 1 once the
    /// Sun is 18° down; moonlight is the Moon's illumination while it is up (eased in over its
    /// first 3°), else 0.
    let darkness: [Double]
    let moonlight: [Double]
    /// What the sound is, said before it plays.
    let opening: String

    init(park: Park, sky: SkyConditions, duration: Double=12, steps: Int=240) {
        self.park=park; self.duration=duration
        let window=SkyAlmanac.nightWindow(sky)
        self.window=window
        let engine=AstronomyEngine(), span=max(1,window.duration)
        let times=(0...steps).map { window.start.addingTimeInterval(span*Double($0)/Double(steps)) }
        darkness=times.map { Self.darkness(sunAltitude:engine.solarAltitude(at:$0,park:park)) }
        let lit=sky.moon.illumination
        moonlight=times.map { lit*min(1,max(0,engine.lunarAltitude(at:$0,park:park)/3)) }
        func offset(_ date: Date) -> Double { min(duration,max(0,date.timeIntervalSince(window.start)/span*duration)) }
        let percent=Int((lit*100).rounded())
        var cues: [Cue]=FieldNight(park:park,sky:sky).milestones.compactMap { milestone in
            let time=park.time(milestone.date)
            switch milestone.kind {
            case .sunset, .darkness, .dawn, .sunrise:
                return Cue(kind:milestone.kind,date:milestone.date,offset:offset(milestone.date),sound:.none,line:String(localized:"\(milestone.title) at \(time)"),symbol:milestone.symbol)
            case .moonrise:
                return Cue(kind:.moonrise,date:milestone.date,offset:offset(milestone.date),sound:.pulseRising,line:String(localized:"Moonrise at \(time), \(percent)% lit"),symbol:milestone.symbol)
            case .moonset:
                return Cue(kind:.moonset,date:milestone.date,offset:offset(milestone.date),sound:.pulseFalling,line:String(localized:"Moonset at \(time)"),symbol:milestone.symbol)
            case .coreRises:
                return Cue(kind:.coreRises,date:milestone.date,offset:offset(milestone.date),sound:.chime,line:String(localized:"Milky Way core up at \(time)"),symbol:milestone.symbol)
            default: return nil
            }
        }
        // The core may already be up when true darkness begins: it chimes then.
        if !cues.contains(where:{ $0.kind == .coreRises }), let dark=SkyAlmanac().core(for:park,sky:sky).dark, dark.duration>=600 {
            cues.append(Cue(kind:.coreRises,date:dark.start,offset:offset(dark.start),sound:.chime,line:String(localized:"Milky Way core already up at \(park.time(dark.start))"),symbol:"sparkle"))
            cues.sort { $0.date<$1.date }
        }
        self.cues=cues
        let seconds=Int(duration.rounded())
        let base=String(localized:"\(park.shortName), \(park.dayLabel(sky.evening)). \(seconds) seconds of sound, from \(park.time(window.start)) to \(park.time(window.end)).")
        opening=sky.darkHours==0 ? base+" "+SkyConditions.noDarknessMessage(tonight:false) : base
    }

    /// 0 at sunset (the Sun's upper edge on the horizon) to 1 at astronomical twilight's end.
    static func darkness(sunAltitude altitude: Double) -> Double { min(1,max(0,(-0.833-altitude)/(18-0.833))) }
    /// Darker skies sound lower: an octave from 330 Hz at sunset to 165 Hz in true darkness.
    static func frequency(darkness: Double) -> Double { 330*pow(2,-min(1,max(0,darkness))) }
    /// The Moon quiets the tone in proportion to its light: a full Moon overhead takes 60% away.
    static func gain(moonlight: Double) -> Double { 1-0.6*min(1,max(0,moonlight)) }
    /// The control values at `time` seconds into the playback, interpolated.
    func control(at time: Double) -> (frequency: Double, gain: Double) {
        let u=min(1,max(0,time/duration))*Double(darkness.count-1)
        let i=min(darkness.count-2,max(0,Int(u))), w=u-Double(i)
        let d=darkness[i]*(1-w)+darkness[i+1]*w, m=moonlight[i]*(1-w)+moonlight[i+1]*w
        return (Self.frequency(darkness:d),Self.gain(moonlight:m))
    }
    /// The full sound, mono, at `sampleRate`. Peaks stay within ±0.85.
    func render(sampleRate: Double) -> [Float] {
        let count=Int(duration*sampleRate)
        var out=[Float](repeating:0,count:count)
        var phase=0.0, fifth=0.0, sub=0.0
        let twoPi=2*Double.pi
        for n in 0..<count {
            let t=Double(n)/sampleRate
            let (f,g)=control(at:t)
            phase+=twoPi*f/sampleRate; fifth+=twoPi*f*1.5/sampleRate; sub+=twoPi*f*0.5/sampleRate
            let fade=min(1,t/0.5)*min(1,(duration-t)/0.8)
            let breath=0.9+0.1*sin(twoPi*0.45*t)
            let pad=(0.55*sin(phase)+0.25*sin(fifth)+0.2*sin(sub))*0.32*g*breath*max(0,fade)
            out[n]=Float(pad)
        }
        // Events on top: each a few tenths of a second, written into its own stretch only.
        for cue in cues where cue.sound != .none {
            let length=cue.sound == .chime ? 2.0 : 0.7
            let first=Int(cue.offset*sampleRate), last=min(count,first+Int(length*sampleRate))
            guard first<last else { continue }
            var glide=0.0
            for n in first..<last {
                let tau=Double(n-first)/sampleRate
                let value: Double
                switch cue.sound {
                case .pulseRising, .pulseFalling:
                    let rising=cue.sound == .pulseRising
                    let f=rising ? 110+55*min(1,tau/0.5) : 165-55*min(1,tau/0.5)
                    glide+=twoPi*f/sampleRate
                    value=0.3*(1-exp(-tau/0.02))*exp(-tau/0.2)*sin(glide)
                case .chime:
                    let envelope=min(1,tau/0.005)*exp(-tau/0.55)
                    value=envelope*(0.16*sin(twoPi*880*tau)+0.07*sin(twoPi*1320*tau)+0.04*sin(twoPi*1760*tau))
                case .none: value=0
                }
                out[n]=Float(max(-0.85,min(0.85,Double(out[n])+value)))
            }
        }
        return out
    }
    /// The transcript, one line per moment, earliest first.
    var transcript: [String] { [opening]+cues.map(\.line) }
    /// What each sound means, for the transcript's key.
    static var key: String {
        String(localized:"The tone falls as the sky darkens and rises toward dawn. It softens while the Moon is up, more for a fuller Moon. A rising pulse is moonrise, a falling pulse moonset, and a chime the Milky Way's core rising.")
    }
}

/// Plays a `NightSonification`. `.playback` is chosen deliberately, and only ever on a tap: the
/// sound is the content someone asked for (often with VoiceOver, where Silent mode would make the
/// button seem broken). Other audio is ducked, not stopped, and is told when Nyx is done.
@Observable final class NightListener {
    static let shared=NightListener()
    private(set) var current: NightSonification?
    /// When the sound started; nil while it is being prepared.
    private(set) var startedAt: Date?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var task: Task<Void, Never>?
    var isPlaying: Bool { current != nil }
    nonisolated static let sampleRate=24_000.0

    func play(_ night: NightSonification) {
        stop()
        current=night
        task=Task { [weak self] in
            let samples=await Task.detached(priority:.userInitiated) { night.render(sampleRate:NightListener.sampleRate) }.value
            guard let self, !Task.isCancelled else { return }
            do { try self.start(samples) } catch { self.stop(); return }
            self.startedAt = .now
            Self.announce(night.opening,priority:.default)
            // Captions for VoiceOver, quietly, as each moment plays.
            var elapsed=0.0
            for cue in night.cues {
                try? await Task.sleep(for:.seconds(max(0,cue.offset-elapsed)))
                elapsed=max(elapsed,cue.offset)
                if Task.isCancelled { return }
                if UIAccessibility.isVoiceOverRunning { Self.announce(cue.line,priority:.low) }
            }
            try? await Task.sleep(for:.seconds(max(0,night.duration-elapsed)+0.4))
            if !Task.isCancelled { self.finish() }
        }
    }
    func stop() {
        task?.cancel(); task=nil
        finish()
    }
    private func finish() {
        player?.stop(); engine?.stop()
        player=nil; engine=nil
        if current != nil { try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        current=nil; startedAt=nil
    }
    private func start(_ samples:[Float]) throws {
        let session=AVAudioSession.sharedInstance()
        try session.setCategory(.playback,mode:.default,options:[.duckOthers])
        try session.setActive(true)
        guard let format=AVAudioFormat(standardFormatWithSampleRate:Self.sampleRate,channels:1),
              let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)),
              let channel=buffer.floatChannelData?[0] else { throw CocoaError(.featureUnsupported) }
        buffer.frameLength=AVAudioFrameCount(samples.count)
        for (i,sample) in samples.enumerated() { channel[i]=sample }
        let engine=AVAudioEngine(), player=AVAudioPlayerNode()
        engine.attach(player)
        // iOS 27's connect throws instead of raising an exception on a bad format.
        if #available(iOS 27.0, *) { try engine.connectNode(player,to:engine.mainMixerNode,format:format) }
        else { engine.connect(player,to:engine.mainMixerNode,format:format) }
        try engine.start()
        player.scheduleBuffer(buffer,at:nil,options:[],completionHandler:nil)
        player.play()
        self.engine=engine; self.player=player
    }
    static func announce(_ text:String,priority:AttributeScopes.AccessibilityAttributes.AnnouncementPriorityAttribute.AnnouncementPriority) {
        var line=AttributedString(text)
        line.accessibilitySpeechAnnouncementPriority=priority
        AccessibilityNotification.Announcement(line).post()
    }
}
