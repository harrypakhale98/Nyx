import SwiftUI

struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.nyx) private var palette
    let seed: String
    var strength: Double=0.6
    /// 0...1. Higher-scoring nights twinkle harder and a little faster.
    var twinkle: Double=0.3
    private struct Star { let x:Double; let y:Double; let radius:Double; let phase:Double }
    private let stars: [Star]
    init(seed: String, strength: Double=0.6, twinkle: Double=0.3) {
        self.seed=seed; self.strength=strength; self.twinkle=min(1,max(0,twinkle))
        var state=seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        func random()->Double { state=state &* 6364136223846793005 &+ 1442695040888963407; return Double(state>>11)/Double(UInt64(1)<<53) }
        stars=(0..<88).map { _ in Star(x:random(),y:random(),radius:0.35+random()*1.05,phase:random()*6.28) }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
            Canvas { context,size in
                let t=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let amplitude=0.12+0.3*twinkle, speed=0.45+0.7*twinkle
                // Night vision keeps stars faint: kinder to dark-adapted eyes and to the text above them.
                let strength=palette.nightVision ? strength*0.45 : strength
                for star in stars {
                    let shimmer=0.55+amplitude*sin(t*speed+star.phase)
                    let point=CGRect(x:star.x*size.width,y:star.y*size.height,width:star.radius*2,height:star.radius*2)
                    context.fill(Path(ellipseIn:point),with:.color(palette.ink.opacity(shimmer*strength)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
#Preview("Living") { Starfield(seed:"jotr").background(.black) }
#Preview("Pristine night") { Starfield(seed:"jotr",twinkle:1).background(.black) }
#Preview("Still") { Starfield(seed:"jotr").environment(\.nyxReduceMotion,true).background(.black) }

/// Same seed, same sky: a small deterministic generator for decorative stars.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: String) { state=seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) } }
    mutating func next() -> UInt64 {
        state=state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
