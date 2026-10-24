import SwiftUI

/// The recipe of the Darkness Score: the dial as every park shows it (the night from sunset to
/// sunrise around the score), one bar split into its four shares, lit one after another as the
/// example score counts up, then the band words. Shares, not marks: the bar is always whole.
struct ScoreAnatomy:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    let active:Bool
    @State private var filled=0
    /// The breakdown's own words (`ScoreReadout`), so the recipe and every night's score name the same four parts.
    private let parts:[(LocalizedStringKey,Int)]=[("Moonlight",40),("Clouds",25),("Sky glow",20),("True darkness",15)]
    /// Each share a step dimmer, so the four read apart without colour; gaps divide them too.
    private func shade(_ i:Int)->Double { [1,0.75,0.55,0.4][i] }
    var body:some View {
        VStack(spacing:12) {
            CelestialGauge(score:94,haptics:false,night:example).id(active).frame(height:typeSize.isAccessibilitySize ? nil : 188) // fresh, silent count-up each time the page arrives; the real answer owns the pulses. 188, not 176: room for the band word under the times at the dial's ends
            VStack(alignment:.leading,spacing:8) {
                Text("Share of the score").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                GeometryReader { proxy in
                    HStack(spacing:3) {
                        ForEach(parts.indices,id:\.self) { i in
                            Capsule().fill(i<filled ? palette.accent.opacity(shade(i)) : palette.line)
                                .frame(width:max(0,(proxy.size.width-9)*Double(parts[i].1)/100))
                        }
                    }
                }.frame(height:6)
                ViewThatFits(in:.horizontal) {
                    Grid(alignment:.leading,horizontalSpacing:18,verticalSpacing:6) {
                        GridRow { legend(0); legend(1) }
                        GridRow { legend(2); legend(3) }
                    }
                    VStack(alignment:.leading,spacing:6) { ForEach(parts.indices,id:\.self) { legend($0) } }
                }
            }.frame(maxWidth:320)
            Text("90 Pristine · 75 Excellent · 60 Good").font(.caption).foregroundStyle(palette.ink).multilineTextAlignment(.center)
            Text(example == nil ? "Example night" : "Example night. The ring runs from sunset to sunrise.").font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(example == nil ? "Example score 94 out of 100. Share of the score: moonlight 40 percent, clouds 25, sky glow 20, and true darkness 15. 90 and above is Pristine, 75 Excellent, 60 Good."
                            : "Example score 94 out of 100. The ring around it is the night, from sunset to sunrise, brightest in its best hours. Share of the score: moonlight 40 percent, clouds 25, sky glow 20, and true darkness 15. 90 and above is Pristine, 75 Excellent, 60 Good.")
        .task(id:active) {
            guard active else { filled=0; return }
            if reduceMotion { filled=parts.count; return }
            for i in 1...parts.count {
                try? await Task.sleep(for:.milliseconds(260))
                withAnimation(NyxMotion.spring) { filled=i }
            }
        }
    }
    /// The example's night, the real one the real dial would draw: the coming new Moon at the starting
    /// park, taken as clear, so all of its true darkness is the best window. Nil where the Sun does not
    /// set (a far-north summer), and the example keeps the plain score dial.
    private var example:(ring:NightRing,park:Park,spoken:String)? {
        guard let park=model.home else { return nil }
        let engine=AstronomyEngine(), now=Date.now
        let newMoon=now.addingTimeInterval((1-engine.moonPhase(at:now).fraction)*AstronomyEngine.synodicDays*86400)
        let sky=engine.conditions(for:park,on:park.evening(newMoon))
        let best=sky.darkStart.flatMap { start in sky.darkEnd.flatMap { end in end>start ? DateInterval(start:start,end:end) : nil } }
        guard let ring=NightRing(sky:sky,park:park,best:best) else { return nil }
        return (ring,park,ring.spoken(sky:sky,park:park,best:best))
    }
    private func legend(_ i:Int)->some View {
        HStack(spacing:6) {
            Capsule().fill(palette.accent.opacity(shade(i))).frame(width:10,height:4)
            Text(parts[i].0).font(.caption)
            Text("\(parts[i].1)%").font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
        }
    }
}
#Preview("Score anatomy") { ScoreAnatomy(active:true).padding().background(.black).environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Score anatomy AX5") { ScrollView { ScoreAnatomy(active:true).padding() }.background(.black).environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
