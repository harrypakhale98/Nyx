import SwiftUI

struct Starfield: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.nyx) private var palette
    let seed: String
    var strength: Double=0.6
    private struct Star { let x:Double; let y:Double; let radius:Double; let phase:Double }
    private var stars: [Star] {
        var state=seed.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        func random()->Double { state=state &* 6364136223846793005 &+ 1442695040888963407; return Double(state>>11)/Double(UInt64(1)<<53) }
        return (0..<88).map { _ in Star(x:random(),y:random(),radius:0.35+random()*1.05,phase:random()*6.28) }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval:1/20,paused:reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)) { timeline in
            Canvas { context,size in
                let t=reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                for star in stars {
                    let shimmer=0.55+0.22*sin(t*0.55+star.phase)
                    let point=CGRect(x:star.x*size.width,y:star.y*size.height,width:star.radius*2,height:star.radius*2)
                    context.fill(Path(ellipseIn:point),with:.color(palette.ink.opacity(shimmer*strength)))
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
#Preview("Living") { Starfield(seed:"jotr").background(.black) }
#Preview("Still") { Starfield(seed:"jotr").environment(\.nyxReduceMotion,true).background(.black) }
