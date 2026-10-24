import SwiftUI

extension ParkDetailView {
    // MARK: The place

    @ViewBuilder var placeChapter: some View {
        chapterHeading(.place,detail:eyebrow)
        // A saved spot: where it is, whose clock it keeps, Rename and Delete, in place of the parks' viewing spots.
        if park.isSavedSpot { SpotPanel(spot:park).id("spots") }
        // Sky glow: what city light takes (an illustration), where this park's comes from, and what anyone can do.
        // DEBUG `-nyx-glow-compare city` opens the comparison on the city's sky for captures; nil in Release.
        SkyGlowPanel(park:park,comparison:DebugScenario.text("-nyx-glow-compare") == "city" ? .city : .here).id("glow")
        // Viewing spots are hand-checked from nps.gov: the curated parks only (none for a place abroad yet).
        if !park.isSavedSpot, !park.isCatalogPlace { Panel { ViewingSpots(park:park) }.id("spots") }
        // The Park Service's night and seasonal access, and its busy and quiet months: the curated parks only.
        if park.curated, !park.isSavedSpot, !park.isCatalogPlace {
            let month=park.calendar.component(.month,from:skyNight.id)
            AfterDarkPanel(park:park,month:month).id("afterdark")
            BusyMonthsPanel(park:park,month:month)
        }
        // Campgrounds and ranger programs are the National Park Service's: only where it runs the place.
        if park.nps != nil {
            // Where to stay draws its own panel; campgrounds come from the same all-parks NPS data, kept a week.
            WhereToStayPanel(park:park).id("stay")
            programsPanel
        }
        // A spot's own words are on its panel; the Park Service's are only for its parks.
        if !park.description.isEmpty, !park.isSavedSpot {
            VStack(alignment:.leading,spacing:8) {
                // The programs' gap under its heading, so the two sections read alike.
                Eyebrow(text:"From the National Park Service").padding(.bottom,6)
                ClampedText(text:park.description,lines:4)
                // The Park Service writes in English: translated by iOS on this device, as alerts and programs are.
                TranslateButton(text:park.description)
            }.frame(maxWidth:.infinity,alignment:.leading)
        }
        if park.isCatalogPlace { worldSource }
        AboutDataLink().font(.subheadline)
    }
    /// Where a place abroad comes from, said plainly: the Wikidata item (linked), and a Bortle class
    /// estimated from satellite data rather than checked by hand as the curated parks' are.
    private var worldSource: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("Its Bortle class is estimated from satellite data, not measured here. Nyx has no viewing spots or ranger programs for it yet.")
                .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let url=park.wikidataURL {
                Link(destination:url) { Label("From Wikidata",systemImage:"safari").font(.subheadline).frame(minHeight:44).contentShape(Rectangle()) }
                    .foregroundStyle(palette.ink)
                    .accessibilityHint("Opens this place's Wikidata entry in Safari.")
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private var programsPanel: some View {
        Panel { VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Ranger night-sky programs")
            if let data=model.rangerPrograms(park) {
                let programs=data.programs.filter{$0.date>=park.isoDay(model.today)}
                if programs.isEmpty && data.updated == nil { Text("Programs could not be checked in the last update. Ask at the visitor center for current night-sky programs.").font(.subheadline).foregroundStyle(palette.muted) }
                else if programs.isEmpty { Text("No upcoming programs in the last update. Ask at the visitor center.").font(.subheadline).foregroundStyle(palette.muted) }
                ForEach(programs) { program in ProgramCard(park:park,program:program) }
            } else { Text("Programs are not checked yet. Ask at the visitor center for current night-sky programs.").font(.subheadline).foregroundStyle(palette.muted) }
        } }.id("programs")
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
