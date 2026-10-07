import SwiftUI

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
            .buttonStyle(.plain).foregroundStyle(palette.accent)
            .accessibilityHint("Plays the Moon's phase as a texture: sharp, sparse taps for a new Moon, a broad swell for a full one.")
            .accessibilityInputLabels([Text("Feel the Moon"),Text("Feel")])
        }
    }
}
#Preview("Listen") { let m=PlanModel();if let p=m.home { ScrollView { Panel { NightListenView(night:m.night(p),expanded:true) }.padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Listen • AX5") { let m=PlanModel();if let p=m.home { ScrollView { Panel { NightListenView(night:m.night(p),expanded:true) }.padding() }.dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) } }
