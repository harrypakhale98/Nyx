import SwiftUI
import UIKit

/// "Listen to this night", under the shape of the night: a button that plays the night as sound,
/// what each sound means, and the transcript, whose current line brightens while it plays.
struct NightListenView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let night: Night
    var isTonight=true
    /// DEBUG and Settings: open with the transcript showing.
    var expanded=false
    @State private var showsTranscript: Bool?
    private var listener: NightListener { .shared }
    private var sound: NightSonification { NightSonification(park:night.park,sky:night.sky) }
    private var playing: Bool { listener.current.map { $0.park.id==night.park.id && $0.window.start==SkyAlmanac.nightWindow(night.sky).start } ?? false }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Button { if playing { listener.stop() } else { listener.play(sound); showsTranscript=true } } label:{
                Label(playing ? String(localized:"Stop listening") : isTonight ? String(localized:"Listen to tonight") : String(localized:"Listen to this night"),
                      systemImage:playing ? "stop.fill" : "waveform")
                    .font(.subheadline.weight(.medium)).padding(.vertical,10).padding(.horizontal,16).frame(minHeight:44)
                    .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).foregroundStyle(palette.accent)
            .accessibilityHint("Plays the night from sunset to sunrise as twelve seconds of sound.")
            .accessibilityInputLabels([Text("Listen"),Text("Listen to tonight"),Text("Stop")])
            Text(NightSonification.key).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            DisclosureGroup(isExpanded:Binding(get:{ showsTranscript ?? (expanded || playing) },set:{ showsTranscript=$0 })) { transcript } label:{
                Text("Transcript").font(.subheadline).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            }.tint(palette.muted)
            if MoonHaptics.enabled { FeelTonightView(night:night,isTonight:isTonight,expanded:expanded).padding(.top,8) }
        }
        .onDisappear { if playing { listener.stop() } }
    }
    private var transcript: some View {
        let sound=sound
        return TimelineView(.animation(minimumInterval:0.25,paused:!playing)) { context in
            let elapsed=listener.startedAt.map { context.date.timeIntervalSince($0) }
            VStack(alignment:.leading,spacing:8) {
                Text(sound.opening).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                ForEach(sound.cues) { cue in
                    let heard=playing && (elapsed ?? -1)>=cue.offset
                    HStack(alignment:.firstTextBaseline,spacing:10) {
                        // The moment's own symbol, as in field mode; amber once it has played.
                        Image(systemName:cue.symbol).font(.caption).frame(width:20).foregroundStyle(heard ? palette.accent : palette.muted).accessibilityHidden(true)
                        Text(cue.line).font(.subheadline.weight(heard ? .semibold : .regular)).foregroundStyle(heard || !playing ? palette.ink : palette.muted).fixedSize(horizontal:false,vertical:true)
                    }
                    .animation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring,value:heard)
                }
            }.padding(.top,8)
        }
    }
}

/// "Feel the Moon": the selected night's Moon as a texture in the hand. Shown only where the
/// iPhone has a Taptic Engine and the person has not switched it off.
struct FeelMoonButton: View {
    @Environment(\.nyx) private var palette
    let moon: MoonPhase
    var body: some View {
        if MoonHaptics.enabled {
            Button { MoonHaptics.shared.play(.moon(illumination:moon.illumination,waxing:moon.waxing)) } label:{
                Label("Feel the Moon",systemImage:"hand.tap").font(.subheadline.weight(.medium)).frame(minHeight:44).contentShape(Rectangle())
            }
            .buttonStyle(.nyxAction).foregroundStyle(palette.accent)
            .accessibilityHint("Plays the Moon's phase as a texture: sharp, sparse taps for a new moon, a broad swell for a full moon.")
            .accessibilityInputLabels([Text("Feel the Moon"),Text("Feel")])
        }
    }
}
/// "Feel tonight": the night in the hand (`NightTouch`), with the screen dark or the phone in a
/// pocket. A button, what each touch means, and the moments in words; VoiceOver hears each moment
/// as it is felt.
struct FeelTonightView: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    var expanded=false
    @State private var showsMoments: Bool?
    private var feeler: NightFeeler { .shared }
    private var touch: NightTouch { NightTouch(NightSonification(park:night.park,sky:night.sky)) }
    private var playing: Bool { feeler.current.map { $0.park == night.park.id && $0.start == SkyAlmanac.nightWindow(night.sky).start } ?? false }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Button { if playing { feeler.stop() } else { feeler.play(touch,park:night.park.id,start:SkyAlmanac.nightWindow(night.sky).start) } } label:{
                Label(playing ? String(localized:"Stop") : isTonight ? String(localized:"Feel tonight") : String(localized:"Feel this night"),systemImage:playing ? "stop.fill" : "hand.tap")
                    .font(.subheadline.weight(.medium)).frame(minHeight:44)
            }
            .buttonStyle(.nyxAction).foregroundStyle(palette.accent)
            .accessibilityHint("Plays the night from sunset to sunrise as twenty-four seconds of touch.")
            .accessibilityInputLabels([Text("Feel tonight"),Text("Feel"),Text("Stop")])
            Text(NightTouch.key).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            DisclosureGroup(isExpanded:Binding(get:{ showsMoments ?? expanded },set:{ showsMoments=$0 })) {
                let touch=touch
                VStack(alignment:.leading,spacing:8) {
                    Text(touch.opening).font(.subheadline).fixedSize(horizontal:false,vertical:true)
                    // By position: two moments can share a second (true darkness and the core already up).
                    ForEach(Array(touch.lines.enumerated()),id:\.offset) { _,line in
                        Text(verbatim:"\(Int(line.offset.rounded())) s · \(line.text)").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                            .accessibilityLabel(String(localized:"At \(Int(line.offset.rounded())) seconds: \(line.text)"))
                    }
                }.padding(.top,8)
            } label:{
                Text("What you will feel").font(.subheadline).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            }.tint(palette.muted)
        }
        .onDisappear { if playing { feeler.stop() } }
    }
}
/// Plays one `NightTouch` at a time and says each moment to VoiceOver as it is felt. Haptics only:
/// it never touches the audio session, so it works in Silent mode and alongside other sound.
@Observable final class NightFeeler {
    static let shared=NightFeeler()
    /// The night being felt: its park and the start of its window.
    private(set) var current: (park:String,start:Date)?
    private var task: Task<Void,Never>?
    func play(_ touch:NightTouch,park:String,start:Date) {
        stop()
        current=(park,start)
        MoonHaptics.shared.play(touch)
        NightListener.announce(touch.opening,priority:.default)
        task=Task { [weak self] in
            var elapsed=0.0
            for line in touch.lines {
                try? await Task.sleep(for:.seconds(max(0,line.offset-elapsed)))
                elapsed=max(elapsed,line.offset)
                if Task.isCancelled { return }
                if UIAccessibility.isVoiceOverRunning { NightListener.announce(line.text,priority:.low) }
            }
            try? await Task.sleep(for:.seconds(max(0,touch.duration-elapsed)+0.3))
            if !Task.isCancelled { self?.current=nil }
        }
    }
    func stop() {
        task?.cancel(); task=nil
        if current != nil { MoonHaptics.shared.stop() }
        current=nil
    }
}
#Preview("Feel tonight") { let m=PlanModel();if let p=m.home { ScrollView { Panel { FeelTonightView(night:m.night(p),expanded:true) }.padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Listen") { let m=PlanModel();if let p=m.home { ScrollView { Panel { NightListenView(night:m.night(p),expanded:true) }.padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Listen • AX5") { let m=PlanModel();if let p=m.home { ScrollView { Panel { NightListenView(night:m.night(p),expanded:true) }.padding() }.dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) } }
