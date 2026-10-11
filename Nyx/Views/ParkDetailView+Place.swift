import SwiftUI

extension ParkDetailView {
    // MARK: The place

    @ViewBuilder var placeChapter: some View {
        chapterHeading(.place,detail:eyebrow)
        // Sky glow: what city light takes (an illustration), where this park's comes from, and what anyone can do.
        // DEBUG `-nyx-glow-compare city` opens the comparison on the city's sky for captures; nil in Release.
        SkyGlowPanel(park:park,comparison:DebugScenario.text("-nyx-glow-compare") == "city" ? .city : .here).id("glow")
        Panel { ViewingSpots(park:park) }.id("spots")
        // Where to stay draws its own panel; campgrounds come from the same all-parks NPS data, kept a week.
        WhereToStayPanel(park:park).id("stay")
        Panel { VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Ranger night-sky programs")
            if let data=model.enrichments[park.id] {
                let programs=data.programs.filter{$0.date>=park.isoDay(model.today)}
                if programs.isEmpty && data.programsUpdated == nil { Text("Programs could not be checked in the last update. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
                else if programs.isEmpty { Text("No upcoming programs in the last update. Ask at the visitor center.").foregroundStyle(palette.muted) }
                ForEach(programs) { program in ProgramCard(park:park,program:program) }
            } else { Text("Programs are not checked yet. Ask at the visitor center for current night-sky programs.").foregroundStyle(palette.muted) }
        } }.id("programs")
        if !park.description.isEmpty {
            VStack(alignment:.leading,spacing:8) {
                Eyebrow(text:"From the National Park Service")
                ClampedText(text:park.description,lines:4)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        AboutDataLink().font(.subheadline)
    }
}
/// A ranger program: title, when and where, then NPS's description clamped to three lines.
private struct ProgramCard: View {
    @Environment(\.nyx) private var palette
    let park: Park
    let program: RangerProgram
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(program.title).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            Label([park.programDate(program.date),program.time].compactMap { $0 }.joined(separator:" · "),systemImage:"calendar").font(.footnote).foregroundStyle(palette.ink)
            if let location=program.location { Label(location,systemImage:"mappin.and.ellipse").font(.footnote).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            ClampedText(text:program.description,lines:3)
            TranslateButton(text:[program.title,program.description].joined(separator:"\n\n"))
        }
    }
}
