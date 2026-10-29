import SwiftUI

/// Liquid Glass for what floats over the sky, one rule everywhere: the system's glass normally, and
/// a solid panel with the card hairline (`line` at half the palette's stroke) wherever glass would cost
/// contrast: Reduce Transparency, Increase Contrast and night vision (`solid`). Each role keeps its tint.
struct NyxGlass<S: Shape>: ViewModifier {
    enum Role {
        /// A floating control (the sky's buttons and panels): glass lightly tinted with the panel.
        case control
        /// The park pill, its list and the Ask Nyx bar: tinted more, so a name keeps its contrast over a
        /// bright stretch of the Milky Way, and interactive, so it answers the finger.
        case pill
    }
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    let role: Role
    /// A pill's glass id, so the list grows out of the pill (`glassEffectID`).
    var id: String?=nil
    var namespace: Namespace.ID?=nil
    /// Where glass gives way to a solid panel.
    static func solid(_ palette: NyxPalette, reduceTransparency: Bool) -> Bool { reduceTransparency || palette.nightVision || palette.highContrast }
    @ViewBuilder func body(content: Content) -> some View {
        if Self.solid(palette,reduceTransparency:reduceTransparency) {
            content.background(shape.fill(palette.panel)).overlay(shape.stroke(palette.line,lineWidth:0.5*palette.stroke))
        } else if let id, let namespace {
            content.glassEffect(glass,in:shape).glassEffectID(id,in:namespace).glassEffectTransition(.matchedGeometry)
        } else {
            content.glassEffect(glass,in:shape)
        }
    }
    private var glass: Glass {
        switch role {
        case .control: .regular.tint(palette.panel.opacity(0.35))
        case .pill: .regular.tint(palette.panel.opacity(0.5)).interactive()
        }
    }
}
extension View {
    /// `NyxGlass`: system glass, or a solid panel where glass would cost contrast.
    func nyxGlass<S: Shape>(_ shape: S, role: NyxGlass<S>.Role = .control, id: String?=nil, in namespace: Namespace.ID?=nil) -> some View {
        modifier(NyxGlass(shape:shape,role:role,id:id,namespace:namespace))
    }
}

/// A choice among a few, segmented where its segments fit the width and a native menu where they do
/// not (a long place name, a narrow column, large text), decided by the layout rather than by a guess
/// or a hidden copy measured on the side. Always the menu at accessibility sizes, whose label wraps.
struct FittingPicker<Segmented: View, Menu: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let segmented: Segmented
    @ViewBuilder let menu: Menu
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { menu }
            else { ViewThatFits(in:.horizontal) { segmented; menu } }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

#Preview("Glass • control and pill") {
    VStack(spacing:20) {
        Label("Facing south",systemImage:"location.north.line").padding(14).nyxGlass(RoundedRectangle(cornerRadius:26))
        Text(verbatim:"Joshua Tree").padding(.horizontal,18).padding(.vertical,10).nyxGlass(Capsule(),role:.pill)
    }.padding(30).background(NyxPalette.indigo).preferredColorScheme(.dark)
}
#Preview("Glass • solid (Increase Contrast)") {
    VStack(spacing:20) {
        Label("Facing south",systemImage:"location.north.line").padding(14).nyxGlass(RoundedRectangle(cornerRadius:26))
        Text(verbatim:"Joshua Tree").padding(.horizontal,18).padding(.vertical,10).nyxGlass(Capsule(),role:.pill)
    }.padding(30).background(NyxPalette.indigo).environment(\.nyx,NyxPalette(nightVision:false,highContrast:true)).preferredColorScheme(.dark)
}
private struct FittingPreview: View {
    @State private var choice=0
    var body: some View {
        FittingPicker {
            Picker("Sky drawn",selection:$choice) { Text(verbatim:"Here · Class 3").tag(0); Text(verbatim:"City · Class 8").tag(1) }.pickerStyle(.segmented)
        } menu:{
            Menu { Picker("Sky drawn",selection:$choice) { Text(verbatim:"Here (Class 3, estimated)").tag(0); Text(verbatim:"From a city (Class 8)").tag(1) } } label:{ Text(verbatim:choice == 0 ? "Here (Class 3, estimated)" : "From a city (Class 8)") }
        }.padding().background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Fitting picker") { FittingPreview() }
#Preview("Fitting picker • narrow") { FittingPreview().frame(width:200) }
#Preview("Fitting picker • AX5") { FittingPreview().dynamicTypeSize(.accessibility5) }
