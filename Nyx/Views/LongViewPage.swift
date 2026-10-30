import SwiftUI

/// "The next six months" for one place, from Plan's month: the best weekend around each new moon,
/// the Milky Way's season there, and every one of those nights into a calendar at once. For the
/// decisions made months ahead: which weekends to ask off, when to book.
struct LongViewPage: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    @State private var weekends: [DarkWeekends.Weekend]?
    @State private var season: CoreSeason??
    @State private var explaining=false
    @State private var adding=false
    @State private var outcome: CalendarWriter.Outcome?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:6) {
                    Eyebrow(text:"The next six months")
                    Text(park.shortName).font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
                    Text(weekends?.first?.best.usualCloud == nil && weekends != nil
                         ? String(localized:"Around each new moon, the weekend with the darkest night. Far ahead, this place has no usual clouds to go on, so scores rest on the Moon and the hours of true darkness, which are exact.")
                         : String(localized:"Around each new moon, the weekend with the darkest night. Far ahead, scores rest on the usual clouds for the month; the Moon and the hours of true darkness are exact."))
                        .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                Panel { VStack(alignment:.leading,spacing:0) {
                    Eyebrow(text:"Dark weekends").padding(.bottom,6)
                    if let weekends {
                        if weekends.isEmpty { Text("No weekends near a new moon in the next six months.").foregroundStyle(palette.muted) }
                        ForEach(Array(weekends.enumerated()),id:\.element.id) { index,weekend in
                            if index>0 { Divider().overlay(palette.line) }
                            row(weekend)
                        }
                    } else {
                        ProgressView().frame(maxWidth:.infinity,minHeight:120).accessibilityLabel("Working out the weekends")
                    }
                } }
                if let weekends, !weekends.isEmpty {
                    let nights=weekends.flatMap { [$0.firstNight,$0.secondNight] }
                    Button { if CalendarWriter.undecided { explaining=true } else { addAll(nights) } } label:{
                        Label("Add all to Calendar",systemImage:"calendar.badge.plus").font(.subheadline).frame(minHeight:44)
                    }
                    .secondaryAction().disabled(adding)
                    .accessibilityHint("Adds these nights to your calendar. Nyx can add events only; it never sees your calendar.")
                    .sensoryFeedback(.selection,trigger:outcome) { _,new in if case .added = new { return true }; return false }
                    if let outcome { Text(outcomeText(outcome)).font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
                    // For another calendar app, or to send to someone: the same nights as a file.
                    ShareLink(item:DarkNightsCalendar(park:park,nights:nights,closure:model.closure(park)),
                              preview:SharePreview(String(localized:"Dark weekends at \(park.shortName)"),image:Image(systemName:"calendar"))) {
                        Text("Share as a calendar file").font(.footnote).frame(minHeight:44,alignment:.leading)
                    }
                    .foregroundStyle(palette.ink)
                    .accessibilityHint("Shares an .ics file with these nights, for another calendar app or another person.")
                    .sheet(isPresented:$explaining) {
                        PermissionExplainer(symbol:"calendar.badge.plus",title:"Add these nights to your calendar",
                                            message:"Nyx adds each night as an event, from true darkness to its end, with its score. iOS will ask to let Nyx add events: it can add them, and never sees your calendar.",
                                            action:"Continue") { explaining=false; addAll(nights) }
                            .nyxPresentation()
                    }
                    // U.S. park campgrounds; elsewhere booking works too differently to say.
                    if park.nps != nil {
                        Text("Many campgrounds open reservations about six months ahead. Check the dates for yours.")
                            .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    }
                }
                Panel { VStack(alignment:.leading,spacing:10) {
                    Eyebrow(text:"Milky Way season")
                    switch season {
                    case .none: ProgressView().frame(maxWidth:.infinity,minHeight:60).accessibilityLabel("Working out the season")
                    case .some(.none): Text("The Milky Way's bright core never climbs high enough here for an hour of true darkness.").foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    case .some(.some(let season)): Text(season.sentence(park)).font(.system(.body,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    }
                    Text("Worked out on this iPhone from the sky's geometry; the days are approximate.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                } }
            }
            .padding(24).readableColumn()
        }
        .background(NightBackground(seed:park.id,park:park,veil:0.45))
        .navigationTitle(park.shortName).navigationBarTitleDisplayMode(.inline)
        .task(id:park.id) {
            let tonight=model.tonight(park)
            let moons=await Task.detached(priority:.userInitiated) { DarkWeekends.newMoons(after:tonight) }.value
            weekends=DarkWeekends.plan(park:park,newMoons:moons,tonight:tonight,closure:model.closure(park)) { model.night(park,on:$0) }
            let place=park
            season = .some(await Task.detached(priority:.utility) { CoreSeason.find(park:place,from:tonight) }.value)
        }
    }
    private func addAll(_ nights: [Night]) {
        adding=true
        Task { outcome=await CalendarWriter.add(nights,closure:model.closure(park)); adding=false }
    }
    private func outcomeText(_ outcome: CalendarWriter.Outcome) -> String {
        switch outcome {
        case .added(let count): String(localized:"Added \(count) nights to your calendar.")
        case .alreadyAdded: String(localized:"Nyx has already added these nights.")
        case .denied: String(localized:"Calendar access is off for Nyx. Turn it on in Settings, or share the nights as a calendar file.")
        case .failed: String(localized:"Nyx could not add the nights. Share them as a calendar file instead.")
        }
    }
    private func row(_ weekend: DarkWeekends.Weekend) -> some View {
        let best=weekend.best
        // The usual clouds go unsaid on a row: the page says it once above. A row the forecast reaches says so.
        let words=VStack(alignment:.leading,spacing:4) {
            Text("\(park.dayLabel(weekend.firstNight.id)) – \(park.dayLabel(weekend.secondNight.id))").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
            Text(verbatim:([DarkWeekends.newMoonLine(weekend)]+(best.basis == .usual ? [] : best.basisLabels)).joined(separator:" · ")).font(.subheadline).foregroundStyle(palette.muted)
        }.fixedSize(horizontal:false,vertical:true)
        let scores=HStack(alignment:.firstTextBaseline,spacing:6) {
            Text("\(weekend.firstNight.score.value) · \(weekend.secondNight.score.value)").scoreNumeral(.title3,accent:palette.accent)
        }
        return NavigationLink { ParkDetailView(park:park,initialDate:best.id) } label:{
            Group {
                if typeSize.isAccessibilitySize { VStack(alignment:.leading,spacing:6) { words; scores } }
                else { HStack(alignment:.firstTextBaseline,spacing:12) { words; Spacer(minLength:8); scores } }
            }.padding(.vertical,12).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(DarkWeekends.spoken(weekend))
        .accessibilityHint("Opens the darker night at the park.")
        .accessibilityAddTraits(.isButton)
    }
}

/// The way in, under the month's best stretch: one quiet row.
struct LongViewLink: View {
    @Environment(\.nyx) private var palette
    let park: Park
    var body: some View {
        NavigationLink { LongViewPage(park:park) } label:{
            HStack(alignment:.firstTextBaseline,spacing:10) {
                // Starlight, as every way onward is: amber stays with the score and light.
                Image(systemName:"calendar.badge.clock").foregroundStyle(palette.ink).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2) {
                    Text("The next six months").font(.subheadline).foregroundStyle(palette.ink)
                    Text("Dark weekends, the Milky Way season, and all of it into your calendar").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                Spacer(minLength:8)
                Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
            }
            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview("The next six months") {
    let m=PlanModel()
    if let p=m.home { NavigationStack { LongViewPage(park:p) }.environment(m).preferredColorScheme(.dark) }
}
#Preview("The next six months • AX5") {
    let m=PlanModel()
    if let p=m.home { NavigationStack { LongViewPage(park:p) }.environment(m).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Alaska (no core season)") {
    let m=PlanModel()
    if let p=m.park("gaar") { NavigationStack { LongViewPage(park:p) }.environment(m).preferredColorScheme(.dark) }
}
