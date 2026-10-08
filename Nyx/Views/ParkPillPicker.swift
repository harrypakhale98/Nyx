import SwiftUI

/// Tonight's answer as a glass pill (the park; a tap opens it), joined to a small glass button
/// that opens the other parks in reach. The list grows out of the pill's glass and folds back into
/// it (`GlassEffectContainer`, `glassEffectID`, iOS 26), so choosing another park is one gesture on
/// the same piece of glass. Solid black capsules and a plain list in night vision, under Reduce
/// Transparency and with Increase Contrast, where glass costs contrast.
struct ParkPillPicker: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let park: Park
    /// The other parks in reach, best first.
    let others: [Park]
    let score: (Park) -> Int
    let zoom: Namespace.ID
    /// `-nyx-pill-open` (DEBUG captures) opens it.
    @State private var open=DebugScenario.isEnabled("pill-open")
    @Namespace private var glass
    private var solid: Bool { palette.nightVision || reduceTransparency || palette.highContrast }
    var body: some View {
        Group {
            if solid { stack } else { GlassEffectContainer(spacing:10) { stack } }
        }
        .animation(reduceMotion || forcedReduceMotion ? nil : NyxMotion.spring,value:open)
    }
    private var stack: some View {
        VStack(spacing:10) {
            HStack(spacing:6) {
                NavigationLink(value:park) {
                    HStack { Text(park.shortName).font(.system(.title2,design:.serif)); Image(systemName:"arrow.up.right").font(.subheadline).accessibilityHidden(true) }
                        .padding(.vertical,14).padding(.horizontal,22)
                        .modifier(PillGlass(solid:solid,shape:Capsule(),id:"pill",namespace:glass))
                }
                .buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom).hoverEffect(.lift)
                if !others.isEmpty {
                    Button { open.toggle() } label:{
                        Image(systemName:"chevron.down").font(.subheadline.weight(.semibold))
                            .rotationEffect(.degrees(open ? 180 : 0)).accessibilityHidden(true)
                            // The whole 44 pt circle is the target, for the finger and for accessibility, not the glyph.
                            .frame(width:44,height:44).contentShape(Circle())
                            .modifier(PillGlass(solid:solid,shape:Circle(),id:"toggle",namespace:glass))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Other parks within reach")
                    .accessibilityValue(open ? "Shown" : "Hidden")
                    .accessibilityHint(open ? "Hides the list." : "Shows the other parks in reach and their scores tonight.")
                    .accessibilityInputLabels([Text("Other parks"),Text("More parks")])
                }
            }
            if open {
                VStack(spacing:0) {
                    ForEach(Array(others.enumerated()),id:\.element.id) { index,other in
                        if index>0 { Divider().overlay(palette.line) }
                        NavigationLink(value:other) {
                            HStack(spacing:10) {
                                Text(other.shortName).font(.system(.body,design:.serif)).multilineTextAlignment(.leading)
                                Spacer(minLength:8)
                                Text("\(score(other))").font(.body.monospacedDigit()).foregroundStyle(palette.accent)
                                Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                            }
                            .padding(.horizontal,18).frame(minHeight:44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).matchedTransitionSource(id:other.id,in:zoom)
                        .accessibilityLabel(String(localized:"\(other.shortName), \(score(other)) tonight"))
                    }
                }
                .padding(.vertical,4)
                .frame(maxWidth:360)
                .modifier(PillGlass(solid:solid,shape:RoundedRectangle(cornerRadius:22),id:"list",namespace:glass))
                .transition(.opacity)
            }
        }
    }
}
/// Glass for the pill, its button and its list: tinted like the panels, so a name keeps its
/// contrast over a bright stretch of the Milky Way; interactive, so it answers the finger; and
/// with an id, so the list grows out of the pill. Solid black with a hairline otherwise.
private struct PillGlass<S: Shape>: ViewModifier {
    @Environment(\.nyx) private var palette
    let solid: Bool
    let shape: S
    let id: String
    let namespace: Namespace.ID
    @ViewBuilder func body(content: Content) -> some View {
        if solid {
            content.background(Color.black,in:shape).overlay(shape.stroke(palette.line,lineWidth:0.8))
        } else {
            content.glassEffect(.regular.tint(palette.panel.opacity(0.5)).interactive(),in:shape)
                .glassEffectID(id,in:namespace)
                .glassEffectTransition(.matchedGeometry)
        }
    }
}
#Preview("Park pill and picker") {
    @Previewable @Namespace var zoom
    let model=PlanModel()
    let parks=["jotr","deva","grba"].compactMap(model.park)
    NavigationStack {
        ZStack { Color.black.ignoresSafeArea()
            if let first=parks.first { ParkPillPicker(park:first,others:Array(parks.dropFirst()),score:{ model.night($0).score.value },zoom:zoom) }
        }
    }.environment(model).preferredColorScheme(.dark)
}
