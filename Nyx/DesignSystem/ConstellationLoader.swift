import SwiftUI
/// Unit-square star positions, traced in drawing order. Recognizable asterisms, simplified.
nonisolated private enum Asterism: CaseIterable {
    case dipper, cassiopeia, cygnus
    var points:[CGPoint] {
        switch self {
        case .dipper: [CGPoint(x:0.02,y:0.30),CGPoint(x:0.20,y:0.22),CGPoint(x:0.36,y:0.30),CGPoint(x:0.50,y:0.42),CGPoint(x:0.56,y:0.78),CGPoint(x:0.86,y:0.86),CGPoint(x:0.96,y:0.50),CGPoint(x:0.50,y:0.42)]
        case .cassiopeia: [CGPoint(x:0.02,y:0.28),CGPoint(x:0.26,y:0.74),CGPoint(x:0.48,y:0.40),CGPoint(x:0.72,y:0.82),CGPoint(x:0.98,y:0.20)]
        case .cygnus: [CGPoint(x:0.50,y:0.02),CGPoint(x:0.50,y:0.48),CGPoint(x:0.50,y:0.98),CGPoint(x:0.50,y:0.48),CGPoint(x:0.08,y:0.36),CGPoint(x:0.50,y:0.48),CGPoint(x:0.92,y:0.60)]
        }
    }
    /// Each star once; the traced path revisits some of them.
    var stars:[CGPoint] { points.reduce(into:[]) { result,point in if !result.contains(point) { result.append(point) } } }
}
nonisolated private struct AsterismLines: Shape {
    let points:[CGPoint]
    func path(in rect:CGRect)->Path {
        var path=Path()
        path.addLines(points.map { CGPoint(x:rect.minX+$0.x*rect.width,y:rect.minY+$0.y*rect.height) })
        return path
    }
}
struct ConstellationLoader: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @State private var progress=0.0
    @State private var asterism=Asterism.dipper
    var body: some View {
        VStack(spacing:26) {
            ZStack {
                AsterismLines(points:asterism.points).trim(from:0,to:reduceMotion ? 1 : progress)
                    .stroke(palette.ink.opacity(0.55),style:StrokeStyle(lineWidth:1,lineCap:.round,lineJoin:.round))
                GeometryReader { proxy in
                    ForEach(asterism.stars.indices,id:\.self) { index in
                        Circle().fill(palette.accent).frame(width:4,height:4)
                            .position(x:asterism.stars[index].x*proxy.size.width,y:asterism.stars[index].y*proxy.size.height)
                    }
                }
            }.frame(width:150,height:70).accessibilityHidden(true)
            ProgressView("Reading the night").tint(palette.accent)
        }.padding(40)
            .task {
                guard !reduceMotion else { return }
                // Trace a figure, hold it, then move on to the next one.
                while !Task.isCancelled {
                    withAnimation(.spring(response:1.4,dampingFraction:1)) { progress=1 }
                    try? await Task.sleep(for:.seconds(2.2))
                    var still=Transaction(); still.disablesAnimations=true
                    withTransaction(still) {
                        progress=0
                        let all=Asterism.allCases
                        asterism=all[((all.firstIndex(of:asterism) ?? 0)+1)%all.count]
                    }
                    try? await Task.sleep(for:.milliseconds(250))
                }
            }
    }
}
struct SkeletonRow: View {
    @Environment(\.nyx) private var palette
    var body: some View { HStack { RoundedRectangle(cornerRadius:8).fill(palette.line).frame(width:48,height:48); VStack(alignment:.leading) { RoundedRectangle(cornerRadius:4).fill(palette.line).frame(height:14); RoundedRectangle(cornerRadius:4).fill(palette.line).frame(width:120,height:10) }; Spacer(); ProgressView() }.padding(.vertical,12).accessibilityLabel("Loading park") }
}
#Preview("Loading") { ConstellationLoader().background(.black).preferredColorScheme(.dark) }
#Preview("Still") { ConstellationLoader().environment(\.nyxReduceMotion,true).background(.black).preferredColorScheme(.dark) }
#Preview("Row") { SkeletonRow().padding().background(.black) }
