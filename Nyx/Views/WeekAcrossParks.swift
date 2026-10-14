import SwiftUI

/// Tonight and the six nights after it at the parks in reach: the "when" beside Tonight's "where",
/// for a wide window with room to spare. Rows are parks, darkest week first: ordered by their
/// darkest night of the week (the sky alone, `NightPlanner.better`); columns are nights. The ring
/// marks the week's best night, where a closure counts against its park as wherever a best night is
/// picked (`NightPlanner.better(_:_:closures:)`); a closed park's row says so. Pure, so it is tested.
nonisolated struct WeekAcrossParks: Sendable {
    struct Row: Identifiable, Sendable {
        var id: String { park.id }
        let park: Park
        let nights: [Night]
    }
    struct Cell: Hashable, Sendable { let row: Int; let night: Int }
    static let nights=7
    static let rowLimit=8
    let rows: [Row]
    /// Every park in reach, when more than the rows shown.
    let total: Int
    /// The week's best night among the rows shown, marked with the calendar's ring.
    let best: Cell?
    /// Each row's park's closure from the last park update, said beside its name.
    var closures: [String: String] = [:]
    /// `weeks`: each park's next seven nights, starting tonight, in the order to keep on a tie
    /// (Tonight passes them darkest tonight first). `closures` count against their parks' nights
    /// for the ring only, as wherever a best night is picked; the rows stay darkest first.
    static func make(_ weeks:[[Night]],closures:[String:String]=[:],limit:Int=rowLimit)->WeekAcrossParks {
        let usable=weeks.filter { !$0.isEmpty }
        func better(_ a:Night,_ b:Night)->Bool { NightPlanner.better(a,b,closures:closures) }
        func top(_ week:[Night])->Night? { week.min { NightPlanner.better($0,$1) } }
        let ordered=usable.enumerated().sorted { a,b in
            guard let x=top(a.element), let y=top(b.element) else { return a.offset<b.offset }
            if NightPlanner.better(x,y) { return true }
            if NightPlanner.better(y,x) { return false }
            return a.offset<b.offset
        }.map(\.element)
        let rows=ordered.prefix(max(0,limit)).compactMap { week in week.first.map { Row(park:$0.park,nights:Array(week.prefix(nights))) } }
        var best:Cell?, bestNight:Night?
        for (r,row) in rows.enumerated() {
            for (n,night) in row.nights.enumerated() where bestNight.map({ better(night,$0) }) ?? true {
                best=Cell(row:r,night:n); bestNight=night
            }
        }
        let shown=Set(rows.map(\.park.id))
        return WeekAcrossParks(rows:rows,total:usable.count,best:best,closures:closures.filter { shown.contains($0.key) })
    }
    /// What VoiceOver says for one cell: the row and the column, as a table would, then the night.
    static func spoken(_ night:Night,isBest:Bool,closure:String?=nil)->String {
        var parts=[night.park.shortName,night.park.dayLabel(night.id),String(localized:"\(night.score.value), \(night.score.band.label)")]
        parts+=night.basisLabels
        if let closure { parts.append(String(localized:"Closure: \(closure)")) }
        if isBest { parts.append(String(localized:"The best night this week")) }
        return parts.joined(separator:". ")
    }
}
/// The week as a compact grid on Tonight (wide windows): each night drawn as the calendar draws it
/// (dot size by score; solid, half or hollow by forecast), its score beneath, the week's best ringed.
/// A tap opens the park on that night.
struct WeekAcrossParksPanel: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let week: WeekAcrossParks
    /// "within 200 mi of Chicago", said in the heading's caption.
    let reach: String
    @Namespace private var rotor
    var body: some View {
        Panel { VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:4) {
                Eyebrow(text:"The next 7 nights in reach")
                Text(week.total>week.rows.count ? String(localized:"The \(week.rows.count) parks with the darkest nights this week, of \(week.total) \(reach).") : String(localized:"Every park \(reach), darkest week first."))
                    .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            // Rows of stacks, not a Grid: every night column shares what is left after the park's name,
            // and the panel never asks for more width than its window has.
            VStack(spacing:2) {
                HStack(spacing:2) {
                    Color.clear.frame(width:150,height:1).accessibilityHidden(true)
                    if let first=week.rows.first {
                        ForEach(Array(first.nights.enumerated()),id:\.offset) { index,night in header(night,tonight:index==0) }
                    }
                }
                ForEach(Array(week.rows.enumerated()),id:\.element.id) { r,row in
                    HStack(spacing:2) {
                        // A closed park's name carries the closure mark; its cells say the closure.
                        HStack(alignment:.firstTextBaseline,spacing:4) {
                            Text(row.park.shortName).font(.system(.subheadline,design:.serif)).foregroundStyle(palette.ink)
                            if week.closures[row.park.id] != nil { Image(systemName:"exclamationmark.triangle").font(.caption).foregroundStyle(palette.accent).accessibilityHidden(true) }
                        }
                        .fixedSize(horizontal:false,vertical:true).frame(width:150,alignment:.leading)
                        .accessibilityElement(children:.combine).accessibilityAddTraits(.isHeader)
                        ForEach(Array(row.nights.enumerated()),id:\.offset) { n,night in
                            cell(night,at:WeekAcrossParks.Cell(row:r,night:n))
                        }
                    }
                    .accessibilityElement(children:.contain)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children:.contain)
            .accessibilityLabel("The next 7 nights in reach")
            .accessibilityRotor("Best nights this week") {
                ForEach(rotorCells,id:\.self) { cell in
                    let night=week.rows[cell.row].nights[cell.night]
                    AccessibilityRotorEntry(Text(WeekAcrossParks.spoken(night,isBest:week.best == cell,closure:week.closures[night.park.id])),id:cell,in:rotor)
                }
            }
            Text(access.differentiate ? "\(NightMark.legend) The ring marks the week's best night." : "Solid: forecast. Half-filled: an early look. Hollow: usual clouds. The ring marks the week's best night.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        } }
    }
    /// The nights scoring Excellent or better, best first (a closure counting against its park, so
    /// the ringed night leads); at least the week's three best.
    private var rotorCells:[WeekAcrossParks.Cell] {
        let all=week.rows.enumerated().flatMap { r,row in row.nights.indices.map { WeekAcrossParks.Cell(row:r,night:$0) } }
        let sorted=all.sorted { NightPlanner.better(week.rows[$0.row].nights[$0.night],week.rows[$1.row].nights[$1.night],closures:week.closures) }
        let excellent=sorted.filter { week.rows[$0.row].nights[$0.night].score.value>=75 }
        return excellent.count>=3 ? excellent : Array(sorted.prefix(3))
    }
    private func header(_ night:Night,tonight:Bool)->some View {
        var weekday=Date.FormatStyle.dateTime.weekday(.abbreviated); weekday.timeZone=night.park.timeZone
        var day=Date.FormatStyle.dateTime.day(); day.timeZone=night.park.timeZone
        return VStack(spacing:1) {
            Text(tonight ? String(localized:"Tonight") : night.id.formatted(weekday)).font(.caption.weight(tonight ? .semibold : .regular))
                .foregroundStyle(tonight ? palette.accent : palette.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(night.id.formatted(day)).font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
        }
        .frame(maxWidth:.infinity).padding(.bottom,4)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(tonight ? String(localized:"Tonight, \(night.park.dayLabel(night.id))") : night.park.dayLabel(night.id))
        .accessibilityAddTraits(.isHeader)
    }
    private func cell(_ night:Night,at position:WeekAcrossParks.Cell)->some View {
        let isBest=week.best == position
        return NavigationLink { ParkDetailView(park:night.park,initialDate:night.id) } label:{
            VStack(spacing:4) {
                Canvas { context,size in
                    let center=CGPoint(x:size.width/2,y:size.height/2), radius=1.5+8*pow(Double(night.score.value)/100,1.5)
                    if isBest {
                        let ring=12.5
                        context.stroke(Path(ellipseIn:CGRect(x:center.x-ring,y:center.y-ring,width:2*ring,height:2*ring)),with:.color(palette.accent.opacity(0.75)),lineWidth:0.8*palette.stroke)
                    }
                    NightMark.mark(night,differentiate:access.differentiate).draw(in:&context,center:center,radius:radius,fill:night.basis.fill,color:palette.accent,fillOpacity:palette.markOpacity(score:night.score.value),stroke:palette.stroke)
                }.frame(width:28,height:28).accessibilityHidden(true)
                if let cloud=night.cloudCover,cloud>75 { Image(systemName:"cloud.fill").font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true) }
                else { Text("\(night.score.value)").font(.caption.monospacedDigit()).foregroundStyle(isBest ? palette.accent : palette.ink) }
            }
            .frame(maxWidth:.infinity,minHeight:58)
            .background { if isBest { RoundedRectangle(cornerRadius:12).fill(palette.accent.opacity(palette.nightVision ? 0.18 : 0.1)) } }
            .contentShape(.hoverEffect,RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverEffect(.highlight)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(WeekAcrossParks.spoken(night,isBest:isBest,closure:week.closures[night.park.id]))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens that night at the park.")
        .accessibilityRotorEntry(id:position,in:rotor)
        .accessibilityInputLabels([Text(verbatim:"\(night.park.shortName) \(night.park.dayLabel(night.id))")])
    }
}
#Preview("Week across parks") {
    let model=PlanModel()
    let parks=model.ranked(model.nearby(latitude:nil,longitude:nil,radiusMeters:SearchRadius.wider()))
    NavigationStack {
        ScrollView {
            WeekAcrossParksPanel(week:.make(parks.map { model.nights($0,from:model.tonight($0),count:7) }),reach:"within \(SearchRadius.label(SearchRadius.wider())) of Joshua Tree").padding(24)
        }.background(Color.black)
    }.environment(model).preferredColorScheme(.dark)
}
#Preview("Week across parks • one park") {
    let model=PlanModel()
    if let park=model.home {
        NavigationStack { WeekAcrossParksPanel(week:.make([model.nights(park,from:model.tonight(park),count:7)]),reach:"within 100 mi of Joshua Tree").padding(24).background(Color.black) }
            .environment(model).preferredColorScheme(.dark)
    }
}
