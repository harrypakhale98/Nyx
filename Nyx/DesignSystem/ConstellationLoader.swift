import SwiftUI
struct ConstellationLoader: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @State private var reveal=false
    var body: some View {
        VStack(spacing:26) {
            Canvas { context,size in
                let points=[CGPoint(x:0.12*size.width,y:0.75*size.height),CGPoint(x:0.35*size.width,y:0.30*size.height),CGPoint(x:0.61*size.width,y:0.54*size.height),CGPoint(x:0.89*size.width,y:0.12*size.height)]
                var line=Path(); line.addLines(points)
                context.stroke(line.trimmedPath(from:0,to:reveal || reduceMotion ? 1 : 0),with:.color(palette.line),lineWidth:1)
                for p in points { context.fill(Path(ellipseIn:CGRect(x:p.x-2,y:p.y-2,width:4,height:4)),with:.color(palette.accent)) }
            }.frame(width:150,height:70).accessibilityHidden(true)
            ProgressView("Reading the night").tint(palette.accent)
        }.padding(40).task { withAnimation(reduceMotion ? nil : NyxMotion.spring) { reveal=true } }
    }
}
struct SkeletonRow: View {
    @Environment(\.nyx) private var palette
    var body: some View { HStack { RoundedRectangle(cornerRadius:8).fill(palette.line).frame(width:48,height:48); VStack(alignment:.leading) { RoundedRectangle(cornerRadius:4).fill(palette.line).frame(height:14); RoundedRectangle(cornerRadius:4).fill(palette.line).frame(width:120,height:10) }; Spacer(); ProgressView() }.padding(.vertical,12).accessibilityLabel("Loading park") }
}
#Preview("Loading") { ConstellationLoader().background(.black).preferredColorScheme(.dark) }
#Preview("Still") { ConstellationLoader().environment(\.nyxReduceMotion,true).background(.black).preferredColorScheme(.dark) }
#Preview("Row") { SkeletonRow().padding().background(.black) }
