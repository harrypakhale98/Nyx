import SwiftUI

/// Park detail's "What's up" card: an eclipse or a meteor shower when there is one, then the
/// Milky Way's bright center and the planets, each as a glyph, a name, the figure to read at a
/// glance and one plain sentence. VoiceOver reads each row as those sentences.
struct WhatsUpPanel: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.headline) private var glyphSize=20.0
    let whatsUp: WhatsUp
    var isTonight=true
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Eyebrow(text:isTonight ? "What's up tonight" : "What's up this night")
            ForEach(Array(whatsUp.leading.enumerated()),id:\.element.id) { index,item in
                if index>0 { Divider().overlay(palette.line) }
                row(item)
            }
            if !whatsUp.planets.isEmpty {
                Divider().overlay(palette.line)
                planets
            }
            VStack(alignment:.leading,spacing:0) {
                NavigationLink { EssayView(essay:.milkyway) } label:{ Label("Finding the Milky Way",systemImage:"sparkle").font(.subheadline).frame(minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                if whatsUp.shower != nil {
                    NavigationLink { EssayView(essay:.meteors) } label:{
                        Label { Text("Watching a meteor shower") } icon:{ SkyGlyph(.meteors,color:palette.accent).frame(width:glyphSize*0.8) }.font(.subheadline)
                            .frame(minHeight:44,alignment:.leading).contentShape(Rectangle())
                    }
                }
            }.padding(.top,2)
            Text("Worked out on this iPhone for this park. Planets are placed within about a degree; times can be a few minutes off where hills block the horizon.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
    /// One glyph column, so every row's text starts on the same line.
    private func glyphed<Content:View>(_ kind:SkyGlyph.Kind,color:Color,@ViewBuilder content:()->Content)->some View {
        HStack(alignment:.top,spacing:14) {
            if !typeSize.isAccessibilitySize { SkyGlyph(kind,color:color).frame(width:glyphSize,height:glyphSize).padding(.top,1) }
            VStack(alignment:.leading,spacing:5) { content() }
        }
    }
    /// Events and a timed core get the amber figure; a state ("Out of the night sky") stays in starlight.
    private func row(_ item:WhatsUp.Item)->some View {
        let event=item.kind == .meteors || item.kind == .eclipse
        return glyphed(SkyGlyph.Kind(item.kind),color:palette.accent) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline,spacing:8) { heading(item,event:event).layoutPriority(1); Spacer(minLength:8); figure(item,event:event) }
                VStack(alignment:.leading,spacing:4) { heading(item,event:event); figure(item,event:event) }
            }
            Text(item.detail).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let footnote=item.footnote { Text(footnote).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,2) }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(item.spoken)
    }
    /// The planets under one heading, brightest first: a name, a word for brightness, one sentence.
    private var planets:some View {
        glyphed(.planet,color:palette.ink) {
            Text("Planets").font(.system(.headline,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
            ForEach(whatsUp.planets) { planet in
                VStack(alignment:.leading,spacing:2) {
                    HStack(alignment:.firstTextBaseline,spacing:6) {
                        Text(planet.title).font(.system(.body,design:.serif)).foregroundStyle(palette.ink)
                        if let note=planet.note { Text(note).font(.caption).foregroundStyle(palette.muted) }
                    }
                    Text(planet.detail).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                .padding(.top,6)
                .accessibilityElement(children:.ignore).accessibilityLabel(planet.spoken)
            }
        }
    }
    private func heading(_ item:WhatsUp.Item,event:Bool)->some View {
        VStack(alignment:.leading,spacing:2) {
            Text(item.title).font(.system(event ? .title3 : .headline,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            if let note=item.note { Text(note).font(.caption).foregroundStyle(event ? palette.accent : palette.muted) }
        }
    }
    @ViewBuilder private func figure(_ item:WhatsUp.Item,event:Bool)->some View {
        if let value=item.value {
            Text(value).font(.system(event ? .title3 : .body,design:.serif)).monospacedDigit()
                .foregroundStyle(item.timed ? palette.accent : palette.ink).fixedSize(horizontal:false,vertical:true)
        }
    }
}
#Preview("Geminids at Joshua Tree") {
    let m=PlanModel()
    if let p=m.park("jotr") { NavigationStack { ScrollView { Panel { WhatsUpPanel(whatsUp:m.whatsUp(m.night(p,on:Date(timeIntervalSince1970:1797192000)))) }.padding() } }.environment(m).background(.black).preferredColorScheme(.dark) }
}
#Preview("Eclipse at Everglades • AX5") {
    let m=PlanModel()
    if let p=m.park("ever") { NavigationStack { ScrollView { Panel { WhatsUpPanel(whatsUp:m.whatsUp(m.night(p,on:Date(timeIntervalSince1970:1877112000))),isTonight:false) }.padding() } }.environment(m).dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }
}
#Preview("Alaska") {
    let m=PlanModel()
    if let p=m.park("dena") { NavigationStack { ScrollView { Panel { WhatsUpPanel(whatsUp:m.whatsUp(m.night(p))) }.padding() } }.environment(m).background(.black).preferredColorScheme(.dark) }
}
