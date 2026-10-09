import SwiftUI

struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.nyx) private var palette
    @Environment(\.skyResting) private var resting
    @Environment(\.nyxAccess) private var access
    let seed: String
    var strength: Double=0.6
    /// 0...1. Higher-scoring nights twinkle harder and a little faster.
    var twinkle: Double=0.3
    private struct Star { let x:Double; let y:Double; let radius:Double; let phase:Double }
    /// The field split once, by size: all 88 stars, and the first 44 for reduced resources.
    private let faint: [Star], bright: [Star], fewerFaint: [Star], fewerBright: [Star]
    init(seed: String, strength: Double=0.6, twinkle: Double=0.3) {
        self.seed=seed; self.strength=strength; self.twinkle=min(1,max(0,twinkle))
        var state=seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        func random()->Double { state=state &* 6364136223846793005 &+ 1442695040888963407; return Double(state>>11)/Double(UInt64(1)<<53) }
        let stars=(0..<88).map { _ in Star(x:random(),y:random(),radius:0.35+random()*1.05,phase:random()*6.28) }
        let fewer=stars.prefix(44)
        faint=stars.filter { $0.radius<Self.faintRadius }; bright=stars.filter { $0.radius>=Self.faintRadius }
        fewerFaint=fewer.filter { $0.radius<Self.faintRadius }; fewerBright=fewer.filter { $0.radius>=Self.faintRadius }
    }
    var body: some View {
        // When the system asks for less, half the stars, holding still.
        let still=reduceMotion || access.reducedResources
        let faint=access.reducedResources ? fewerFaint : faint, bright=access.reducedResources ? fewerBright : bright
        TimelineView(.animation(minimumInterval:1/30,paused:still || resting || PowerState.shared.lowPower)) { timeline in
            let t=still ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // The smaller, fainter stars in their own layer: under Increase Contrast they fade out
                // (rather than pop), leaving a calmer field behind text, and then leave the tree.
                if !palette.highContrast { layer(faint,t:t).transition(.opacity) }
                layer(bright,t:t)
            }.animation(.easeInOut(duration:0.6),value:palette.highContrast)
        }.allowsHitTesting(false).accessibilityHidden(true).accessibilityIgnoresInvertColors()
    }
    /// Stars smaller than this (about half of them) stand for those fainter than about magnitude 3.
    private static let faintRadius=0.9
    private func layer(_ stars:[Star],t:Double)->some View {
        Canvas { context,size in
            let amplitude=0.12+0.3*twinkle, speed=0.45+0.7*twinkle
            // Night vision keeps stars faint: kinder to dark-adapted eyes and to the text above them.
            let strength=palette.nightVision ? strength*0.45 : strength
            for star in stars {
                let shimmer=0.55+amplitude*sin(t*speed+star.phase)
                let point=CGRect(x:star.x*size.width,y:star.y*size.height,width:star.radius*2,height:star.radius*2)
                context.fill(Path(ellipseIn:point),with:.color(palette.ink.opacity(shimmer*strength)))
            }
        }
    }
}
#Preview("Living") { Starfield(seed:"jotr").background(.black) }
#Preview("Pristine night") { Starfield(seed:"jotr",twinkle:1).background(.black) }
#Preview("Still") { Starfield(seed:"jotr").environment(\.nyxReduceMotion,true).background(.black) }
#Preview("Increase Contrast") { Starfield(seed:"jotr").environment(\.nyx,NyxPalette(nightVision:false,highContrast:true)).background(.black) }

/// Same seed, same sky: a small deterministic generator for decorative stars.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: String) { state=seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } }
    mutating func next() -> UInt64 {
        state=state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
extension EnvironmentValues {
    /// A page's own animated stars and dial rest (redraw nothing) while a full-screen sky covers
    /// them: the picture is unchanged, only its twinkle waits.
    @Entry var skyResting=false
}
