import SwiftUI

struct NightCell: View {
    @Environment(\.nyx) private var palette
    let night:Night
    var highlighted:Bool=false
    var body:some View {
        VStack(spacing:5) {
            Text("\(night.park.calendar.component(.day,from:night.id))").font(.caption.monospacedDigit())
            Canvas { context,size in
                let center=CGPoint(x:size.width/2,y:size.height/2),radius=2+Double(night.score.value)/18
                if highlighted { context.stroke(Path(ellipseIn:CGRect(x:center.x-11,y:center.y-11,width:22,height:22)),with:.color(palette.accent.opacity(0.65)),lineWidth:0.7) }
                let circle=Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:2*radius,height:2*radius))
                if night.score.hasForecast { context.fill(circle,with:.color(palette.accent.opacity(0.45+Double(night.score.value)/200))) }
                else { context.stroke(circle,with:.color(palette.accent),lineWidth:1.1) }
            }.frame(height:26).accessibilityHidden(true)
            if let cloud=night.cloudCover,cloud>75 { Image(systemName:"cloud.fill").font(.system(size:10)).foregroundStyle(palette.muted) }
            else { Text("\(night.score.value)").font(.system(size:10,design:.monospaced)).foregroundStyle(palette.muted) }
        }.frame(maxWidth:.infinity,minHeight:78).contentShape(Rectangle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(night.park.dayLabel(night.id)). \(night.score.value), \(night.score.band.label). \(highlighted ? String(localized:"In the five-night moon window.") : "") \(night.score.hasForecast ? String(localized:"Forecast included.") : String(localized:"No cloud forecast."))")
    }
}
struct CalendarView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var parkID=""
    @State private var monthOffset=0
    @State private var chosen:Night?
    @State private var peeking=false
    private var park:Park? { model.park(parkID) ?? model.home }
    var body: some View {
        ScrollView {
            if let park {
                let base=park.calendar.date(from:park.calendar.dateComponents([.year,.month],from:model.today)) ?? model.today
                let month=park.calendar.date(byAdding:.month,value:monthOffset,to:base) ?? base
                let count=park.calendar.range(of:.day,in:.month,for:month)?.count ?? 30
                let nights=model.nights(park,from:month,count:count)
                let lead=(park.calendar.component(.weekday,from:month)-park.calendar.firstWeekday+7)%7
                let bestStart=bestWindow(nights)
                VStack(alignment:.leading,spacing:24) {
                    Eyebrow(text:"Make time for the night")
                    Text("Choose your night").font(.system(.largeTitle,design:.serif))
                    Picker("Park",selection:Binding(get:{park.id},set:{parkID=$0})) { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }.pickerStyle(.menu)
                    HStack {
                        Button { move(-1) } label:{ Image(systemName:"chevron.left").frame(width:44,height:44) }.accessibilityLabel("Previous month")
                        Spacer(minLength:0)
                        Text(park.monthLabel(month)).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
                        Spacer(minLength:0)
                        Button { move(1) } label:{ Image(systemName:"chevron.right").frame(width:44,height:44) }.accessibilityLabel("Next month")
                    }
                    if typeSize.isAccessibilitySize {
                        LazyVStack { ForEach(Array(nights.enumerated()),id:\.element.id) { i,night in Button { chosen=night } label:{ HStack(alignment:.top) { Text(park.dayLabel(night.id));Spacer();Text("\(night.score.value) · \(night.score.band.label)") }.padding(.vertical,14) }.buttonStyle(.plain).accessibilityHint((bestStart..<(bestStart+5)).contains(i) ? "In the five-night moon window." : "Opens score breakdown.") } }
                    } else {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:6) {
                            ForEach(0..<7,id:\.self) { i in Text(park.calendar.veryShortWeekdaySymbols[(i+park.calendar.firstWeekday-1)%7]).font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true) }
                            ForEach(0..<lead,id:\.self) { _ in Color.clear.frame(height:78) }
                            ForEach(Array(nights.enumerated()),id:\.element.id) { i,night in
                                Button { chosen=night } label:{ NightCell(night:night,highlighted:(bestStart..<(bestStart+5)).contains(i)) }.buttonStyle(.plain)
                                    .contextMenu { Button("Peek at this night") { chosen=night;peeking=true } }
                            }
                        }
                    }
                    Panel { VStack(alignment:.leading,spacing:10) {
                        Label("Five nights near the new moon",systemImage:"circle.circle").font(.subheadline)
                        if nights.indices.contains(bestStart),nights.indices.contains(bestStart+4) { Text("\(park.dayLabel(nights[bestStart].id)) – \(park.dayLabel(nights[bestStart+4].id))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent) }
                        Text("The ring marks the five nights with the least moonlight. Clouds and access may change the best choice.").font(.caption).foregroundStyle(palette.muted)
                    } }
                    Text("Solid: full forecast. Hollow: moon and darkness only. Dot size follows the score; a cloud marks overcast skies.").font(.caption).foregroundStyle(palette.muted)
                }.padding(24).id(monthOffset).transition(.opacity)
                    .task(id:park.id) { await model.refresh([park]) }
            }
        }.background(NightBackground(seed:parkID)).navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .sheet(item:$chosen,onDismiss:{peeking=false}) { night in NavigationStack { if peeking { ParkDetailView(park:night.park,initialDate:night.id) } else { ScoreBreakdownView(night:night) } }.nyxPresentation() }
    }
    private func move(_ offset:Int) { withAnimation(reduceMotion ? nil : NyxMotion.spring) { monthOffset+=offset } }
    private func bestWindow(_ nights:[Night])->Int {
        guard nights.count>=5 else { return 0 }
        return (0...(nights.count-5)).min { a,b in nights[a..<(a+5)].reduce(0){$0+$1.sky.moon.illumination} < nights[b..<(b+5)].reduce(0){$0+$1.sky.moon.illumination} } ?? 0
    }
}
#Preview("Calendar") { NavigationStack { CalendarView() }.environment(PlanModel()).preferredColorScheme(.dark) }
