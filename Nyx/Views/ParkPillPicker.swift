import SwiftUI

/// Tonight's answer as a glass pill (the park; a tap opens it), joined to a small glass button
/// that opens the other parks in reach. The list grows out of the pill's glass and folds back into
/// it (`GlassEffectContainer`, `glassEffectID`, iOS 26), so choosing another park is one gesture on
/// the same piece of glass. Solid black capsules and a plain list in night vision, under Reduce
/// Transparency and with Increase Contrast, where glass costs contrast.
struct ParkPillPicker: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    /// The other parks in reach, best first.
    let others: [Park]
    let score: (Park) -> Int
    let zoom: Namespace.ID
    /// The night the scores are for when it is not tonight ("Fri, Oct 30": Tonight's dial stepped on).
    var night: String?=nil
    /// Nights after tonight that `night` is, carried by the links (`ZoomRoute.offset`).
    var offset=0
    /// `-nyx-pill-open` (DEBUG captures) opens it.
    @State private var open=DebugScenario.isEnabled("pill-open")
    @Namespace private var glass
    private var solid: Bool { NyxGlass<Capsule>.solid(palette,reduceTransparency:reduceTransparency) }
    private var large: Bool { typeSize.isAccessibilitySize }
    var body: some View {
        Group {
            if solid { stack } else { GlassEffectContainer(spacing:10) { stack } }
        }
        .animation(reduceMotion ? nil : NyxMotion.spring,value:open)
    }
    private var stack: some View {
        VStack(spacing:10) {
            // At accessibility sizes the name takes the full width on a rounded rectangle, with the toggle
            // underneath: a capsule around three wrapped lines becomes an egg, and a narrow one breaks words.
            if large {
                pill
                toggle
            } else {
                HStack(spacing:6) { pill; toggle }
            }
            if open {
                VStack(spacing:0) {
                    ForEach(Array(others.enumerated()),id:\.element.id) { index,other in
                        if index>0 { Divider().overlay(palette.line) }
                        NavigationLink(value:ZoomRoute.pillList(other,offset:offset)) {
                            // At accessibility sizes the name takes the whole line and the score goes under it:
                            // beside a fixed score column, "Grand Canyon" broke inside a word on an iPhone SE.
                            let row=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:4)) : AnyLayout(HStackLayout(spacing:10))
                            row {
                                Text(other.shortName).font(.system(.body,design:.serif)).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                                if !typeSize.isAccessibilitySize { Spacer(minLength:8) }
                                HStack(spacing:10) {
                                    Text("\(score(other))").font(.body.monospacedDigit()).foregroundStyle(palette.accent)
                                    Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                                }
                            }.frame(maxWidth:.infinity,alignment:.leading)
                            .padding(.horizontal,18).frame(minHeight:44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).matchedTransitionSource(id:ZoomRoute.pillList(other).source,in:zoom)
                        .accessibilityLabel(night.map { String(localized:"\(other.shortName), \(score(other)) on \($0)") } ?? String(localized:"\(other.shortName), \(score(other)) tonight"))
                    }
                }
                .padding(.vertical,4)
                .frame(maxWidth:360)
                .nyxGlass(RoundedRectangle(cornerRadius:22),role:.pill,id:"list",in:glass)
                .transition(.opacity)
            }
        }
    }
}
extension ParkPillPicker {
    private var pill: some View {
        NavigationLink(value:ZoomRoute.pill(park,offset:offset)) {
            // A capsule while the name fits on one line; a long name ("Black Canyon of the Gunnison")
            // wraps on the rounded rectangle instead, even at default sizes, so the capsule never becomes an egg.
            if large { wrappedPill } else { ViewThatFits(in:.horizontal) { capsulePill; wrappedPill } }
        }
        .buttonStyle(.plain).matchedTransitionSource(id:ZoomRoute.pill(park).source,in:zoom).hoverEffect(.lift)
    }
    private var capsulePill: some View {
        HStack { Text(park.shortName).font(.system(.title2,design:.serif)).lineLimit(1); Image(systemName:"arrow.up.right").font(.subheadline).accessibilityHidden(true) }
            .padding(.vertical,14).padding(.horizontal,22)
            .nyxGlass(Capsule(),role:.pill,id:"pill",in:glass)
    }
    private var wrappedPill: some View {
        // The arrow rides at the end of the words, so the name has the whole width and long words stay whole.
        Text("\(Text(park.shortName).font(.system(.title2,design:.serif))) \(Text(Image(systemName:"arrow.up.right")).font(.subheadline))")
            .accessibilityLabel(park.shortName)
            // Held at the second accessibility size: larger, a long name ("Anza-Borrego Desert State Park")
            // filled a small screen alone and pushed the score below the tab bar.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            .frame(maxWidth:.infinity).padding(.vertical,14).padding(.horizontal,16)
            .nyxGlass(RoundedRectangle(cornerRadius:22,style:.continuous),role:.pill,id:"pill",in:glass)
    }
    @ViewBuilder private var toggle: some View {
        if !others.isEmpty {
            Button { open.toggle() } label:{
                Image(systemName:"chevron.down").font(.subheadline.weight(.semibold))
                    .rotationEffect(.degrees(open ? 180 : 0)).accessibilityHidden(true)
                    // The whole 44 pt circle is the target, for the finger and for accessibility, not the glyph.
                    .frame(width:44,height:44).contentShape(Circle())
                    .nyxGlass(Circle(),role:.pill,id:"toggle",in:glass)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Other parks within reach")
            .accessibilityValue(open ? "Shown" : "Hidden")
            .accessibilityHint(open ? "Hides the list." : night == nil ? "Shows the other parks in reach and their scores tonight." : "Shows the other parks in reach and their scores that night.")
            .accessibilityInputLabels([Text("Other parks"),Text("More parks")])
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
