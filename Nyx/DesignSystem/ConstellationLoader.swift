import SwiftUI
/// The full-screen loader and AI streaming's mark: a constellation traced star by star
/// (`ConstellationTrace`, shared with Apple Vision Pro) in Nyx's palette, still under Reduce Motion.
struct ConstellationLoader: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    var body: some View {
        ConstellationTrace(ink:palette.ink,accent:palette.accent,reduceMotion:systemReduceMotion || forcedReduceMotion)
    }
}
/// A row still loading: the row's shapes in the hairline colour, with a soft light passing over them
/// (held still under Reduce Motion, and resting by `Decoration.rests`). No spinner per row: the
/// shimmer already says it is on its way, and five spinners at once read as noise.
struct SkeletonRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var shapes: some View {
        HStack { RoundedRectangle(cornerRadius:8).frame(width:48,height:48); VStack(alignment:.leading) { RoundedRectangle(cornerRadius:4).frame(height:14); RoundedRectangle(cornerRadius:4).frame(width:120,height:10) }; Spacer() }
    }
    var body: some View {
        let still=systemReduceMotion || forcedReduceMotion
        shapes.foregroundStyle(palette.line)
            .overlay {
                if !still {
                    TimelineView(.animation(minimumInterval:Decoration.interval,paused:Decoration.rests(still:false))) { timeline in
                        GeometryReader { proxy in
                            let phase=SkeletonRow.sweep(timeline.date.timeIntervalSinceReferenceDate)
                            LinearGradient(colors:[.clear,palette.ink.opacity(0.12),.clear],startPoint:.leading,endPoint:.trailing)
                                .frame(width:proxy.size.width*0.45)
                                .offset(x:(phase*1.45-0.45)*proxy.size.width)
                        }
                    }
                    .mask(shapes)
                }
            }
            .padding(.vertical,12)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("Loading park")
    }
    /// Where the light is, 0…1 across the row, `t` seconds in: a 1.8 s pass that slows at each end
    /// (half a cosine), then the next.
    nonisolated static func sweep(_ t:Double)->Double {
        let u=t.truncatingRemainder(dividingBy:1.8)/1.8
        return 0.5-0.5*cos(Double.pi*u)
    }
}
#Preview("Loading") { ConstellationLoader().background(.black).preferredColorScheme(.dark) }
#Preview("Still") { ConstellationLoader().environment(\.nyxReduceMotion,true).background(.black).preferredColorScheme(.dark) }
#Preview("Row") { SkeletonRow().padding().background(.black) }
#Preview("Row • still") { SkeletonRow().environment(\.nyxReduceMotion,true).padding().background(.black) }
