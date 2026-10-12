import SwiftUI
/// The constellation loader itself, shared by the iPhone and iPad (`ConstellationLoader`, which
/// reads Nyx's palette and Reduce Motion override from the environment) and Apple Vision Pro
/// (which passes its own palette). SwiftUI and `NyxMotion` only, so every target can compile it.
struct ConstellationTrace: View {
    let ink: Color
    let accent: Color
    let reduceMotion: Bool
    @State private var progress=0.0
    @State private var asterism=Asterism.dipper
    /// The whole figure fades away before the next one is traced, so a figure is never cut off.
    @State private var shown=1.0
    var body: some View {
        VStack(spacing:26) {
            LoaderFigure(points:asterism.points,progress:reduceMotion ? 1 : progress,line:ink.opacity(0.55),star:accent)
                .opacity(shown)
                .frame(width:150,height:70).accessibilityHidden(true)
            // The traced figure is the progress: no spinner beside it, two indicators at once read as
            // noise. Under Reduce Motion the figure stands still, so the system spinner says it is working.
            if reduceMotion { ProgressView("Reading the night").tint(accent) }
            else { ProgressView("Reading the night").progressViewStyle(LoaderWords(ink:ink)) }
        }.padding(40)
            .task(id:reduceMotion) {
                guard !reduceMotion else { progress=1; shown=1; return }
                // Trace a figure, its stars arriving as the line reaches them; hold it; let it fade; then the next.
                while !Task.isCancelled {
                    withAnimation(NyxMotion.trace) { progress=1 }
                    try? await Task.sleep(for:.seconds(2.2))
                    withAnimation(NyxMotion.spring) { shown=0 }
                    try? await Task.sleep(for:.milliseconds(450))
                    var still=Transaction(); still.disablesAnimations=true
                    withTransaction(still) {
                        progress=0; shown=1
                        let all=Asterism.allCases
                        asterism=all[((all.firstIndex(of:asterism) ?? 0)+1)%all.count]
                    }
                    try? await Task.sleep(for:.milliseconds(250))
                }
            }
    }
}
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
/// The loader's words alone, centred under the figure; still a progress view to VoiceOver.
private struct LoaderWords: ProgressViewStyle {
    let ink:Color
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.body).foregroundStyle(ink).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
    }
}
/// A figure traced to `progress` (0…1 of its length), each star fading in as the line reaches it.
/// Animatable, so the stars follow the line frame by frame as the spring carries `progress`.
private struct LoaderFigure: View, Animatable {
    let points:[CGPoint]
    var progress:Double
    let line:Color
    let star:Color
    var animatableData:Double { get { progress } set { progress=newValue } }
    var body: some View {
        let stars=LoaderFigure.arrivals(points)
        ZStack {
            AsterismLines(points:points).trim(from:0,to:progress)
                .stroke(line,style:StrokeStyle(lineWidth:1,lineCap:.round,lineJoin:.round))
            GeometryReader { proxy in
                ForEach(stars.indices,id:\.self) { index in
                    Circle().fill(star).frame(width:4,height:4)
                        .opacity(LoaderFigure.arrival(progress:progress,at:stars[index].at))
                        .position(x:stars[index].point.x*proxy.size.width,y:stars[index].point.y*proxy.size.height)
                }
            }
        }
    }
    /// Each star once, with where along the traced path (0…1 of its length, in the unit square) the
    /// line first reaches it.
    nonisolated static func arrivals(_ points:[CGPoint])->[(point:CGPoint,at:Double)] {
        var lengths=[0.0]
        for i in points.indices.dropFirst() { lengths.append(lengths[i-1]+hypot(points[i].x-points[i-1].x,points[i].y-points[i-1].y)) }
        let total=max(lengths.last ?? 0,.ulpOfOne)
        var result:[(point:CGPoint,at:Double)]=[]
        for (i,point) in points.enumerated() where !result.contains(where:{ $0.point == point }) { result.append((point,lengths[i]/total)) }
        return result
    }
    /// A star's opacity as the line nears it: none until the line is within a few percent, whole once it arrives.
    nonisolated static func arrival(progress:Double,at:Double)->Double {
        let t=min(1,max(0,(progress-at+0.06)/0.06))
        return t*t*(3-2*t)
    }
}
