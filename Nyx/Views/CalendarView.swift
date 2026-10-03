import SwiftUI

struct NightCell: View {
    @Environment(\.nyx) private var palette
    let night:Night
    var highlighted:Bool=false
    var isTonight:Bool=false
    var isPast:Bool=false
    var body:some View {
        VStack(spacing:5) {
            Text("\(night.park.calendar.component(.day,from:night.id))").font(.caption.monospacedDigit().weight(isTonight ? .bold : .regular))
                .foregroundStyle(isTonight ? palette.accent : palette.ink)
                .overlay(alignment:.bottom) { if isTonight { Capsule().fill(palette.accent).frame(width:12,height:2).offset(y:4) } }
            Canvas { context,size in
                let center=CGPoint(x:size.width/2,y:size.height/2),radius=2+Double(night.score.value)/18
                if highlighted { context.stroke(Path(ellipseIn:CGRect(x:center.x-11,y:center.y-11,width:22,height:22)),with:.color(palette.accent.opacity(0.65)),lineWidth:0.7) }
                let circle=Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:2*radius,height:2*radius))
                if night.score.hasForecast { context.fill(circle,with:.color(palette.accent.opacity(0.45+Double(night.score.value)/200))) }
                else { context.stroke(circle,with:.color(palette.accent),lineWidth:1.1) }
            }.frame(height:26).accessibilityHidden(true)
            if let cloud=night.cloudCover,cloud>75 { Image(systemName:"cloud.fill").font(.caption2).foregroundStyle(palette.muted) }
            else { Text("\(night.score.value)").font(.caption2.monospacedDigit()).foregroundStyle(palette.muted) }
        }.frame(maxWidth:.infinity,minHeight:78).contentShape(Rectangle()).opacity(isPast ? 0.4 : 1)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(spoken)
    }
    private var spoken:String {
        var parts=[isTonight ? String(localized:"Tonight, \(night.park.dayLabel(night.id))") : night.park.dayLabel(night.id),
                   String(localized:"\(night.score.value), \(night.score.band.label)")]
        if let cloud=night.cloudCover { parts.append(String(localized:"Clouds \(Int(cloud.rounded())) percent")) }
        else { parts.append(String(localized:"No cloud forecast")) }
        if highlighted { parts.append(String(localized:"In the five-night moon window")) }
        if isPast { parts.append(String(localized:"Past night")) }
        return parts.joined(separator:". ")
    }
}
/// The long-press preview: one night at a glance.
struct NightPeek: View {
    @Environment(\.nyx) private var palette
    let night:Night
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:16) {
                MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0).frame(width:56,height:56)
                VStack(alignment:.leading,spacing:4) {
                    Text(night.park.dayLabel(night.id)).font(.headline).foregroundStyle(palette.ink)
                    Text(night.sky.moon.name).font(.subheadline).foregroundStyle(palette.muted)
                }
                Spacer(minLength:12)
                VStack(alignment:.trailing,spacing:2) {
                    Text("\(night.score.value)").font(.system(size:44,weight:.light,design:.serif)).foregroundStyle(palette.accent)
                    Text(night.score.hasForecast ? night.score.band.label : String(localized:"Estimate")).font(.caption).foregroundStyle(palette.muted)
                }
            }
            if night.sky.darkHours==0 { Text("No true darkness tonight at this latitude.").font(.subheadline).foregroundStyle(palette.ink) }
            else { Text("True darkness \(night.park.time(night.sky.darkStart)) – \(night.park.time(night.sky.darkEnd))").font(.subheadline).foregroundStyle(palette.ink) }
            Text(night.cloudCover.map { String(localized:"Clouds \(Int($0.rounded()))% on average") } ?? String(localized:"Moon and darkness only. Clouds unknown.")).font(.caption).foregroundStyle(palette.muted)
        }.padding(20).frame(width:320).background(Color.black)
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
    @State private var forward=true
    private var park:Park? { model.park(parkID) ?? model.home }
    var body: some View {
        ScrollView {
            if let park {
                let base=park.calendar.date(from:park.calendar.dateComponents([.year,.month],from:model.today)) ?? model.today
                let month=park.calendar.date(byAdding:.month,value:monthOffset,to:base) ?? base
                let count=park.calendar.range(of:.day,in:.month,for:month)?.count ?? 30
                let nights=model.nights(park,from:month,count:count)
                let lead=(park.calendar.component(.weekday,from:month)-park.calendar.firstWeekday+7)%7
                let tonight=park.evening(model.tonight(park))
                let firstFuture=nights.firstIndex { $0.id>=tonight } ?? nights.count
                let bestStart=bestWindow(nights,from:firstFuture)
                VStack(alignment:.leading,spacing:24) {
                    if !typeSize.isAccessibilitySize { Eyebrow(text:"Make time for the night") }
                    Text("Choose your night").font(.system(typeSize.isAccessibilitySize ? .title2 : .largeTitle,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    if typeSize.isAccessibilitySize {
                        Menu {
                            Picker("Park",selection:Binding(get:{park.id},set:{parkID=$0})) { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }
                        } label: {
                            HStack(alignment:.firstTextBaseline) {
                                Text(park.shortName).font(.body).fixedSize(horizontal:false,vertical:true)
                                Spacer(minLength:8)
                                Image(systemName:"chevron.up.chevron.down").font(.title3)
                            }.padding(.vertical,8).foregroundStyle(palette.accent)
                        }.accessibilityLabel("Park").accessibilityValue(park.shortName)
                    } else {
                        Picker("Park",selection:Binding(get:{park.id},set:{parkID=$0})) { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }.pickerStyle(.menu)
                    }
                    HStack {
                        Button { move(-1) } label:{ Image(systemName:"chevron.left").frame(width:44,height:44) }.accessibilityLabel("Previous month")
                        Spacer(minLength:0)
                        Text(park.monthLabel(month)).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
                        Spacer(minLength:0)
                        Button { move(1) } label:{ Image(systemName:"chevron.right").frame(width:44,height:44) }.accessibilityLabel("Next month")
                    }
                    if typeSize.isAccessibilitySize {
                        LazyVStack(alignment:.leading,spacing:20) { ForEach(Array(nights.enumerated()),id:\.element.id) { i,night in
                            Button { chosen=night } label:{
                                VStack(alignment:.leading,spacing:8) {
                                    Text(park.dayLabel(night.id)).font(.headline)
                                    Text("\(night.score.value) · \(night.score.band.label)").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                                    Text(night.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown.")).font(.caption).foregroundStyle(palette.muted)
                                }.fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,14)
                            }.buttonStyle(.plain).accessibilityElement(children:.ignore)
                                .accessibilityLabel("\(park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown."))")
                                .accessibilityHint((bestStart..<(bestStart+5)).contains(i) ? "In the five-night moon window. Opens score breakdown." : "Opens score breakdown.")
                        } }
                    } else {
                        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:6) {
                            ForEach(0..<7,id:\.self) { i in Text(park.calendar.veryShortWeekdaySymbols[(i+park.calendar.firstWeekday-1)%7]).font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true) }
                            ForEach(0..<lead,id:\.self) { _ in Color.clear.frame(height:78) }
                            ForEach(Array(nights.enumerated()),id:\.element.id) { i,night in
                                Button { chosen=night } label:{ NightCell(night:night,highlighted:(bestStart..<(bestStart+5)).contains(i),isTonight:night.id==tonight,isPast:night.id<tonight) }.buttonStyle(.plain)
                                    .contextMenu {
                                        Button("Open this night",systemImage:"arrow.up.right") { chosen=night;peeking=true }
                                        Button("Why this score",systemImage:"chart.bar") { chosen=night }
                                    } preview: { NightPeek(night:night).environment(\.nyx,palette) }
                            }
                        }
                        .id(monthOffset)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion:.move(edge:forward ? .trailing : .leading).combined(with:.opacity),removal:.move(edge:forward ? .leading : .trailing).combined(with:.opacity)))
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:30).onEnded { drag in
                            guard abs(drag.translation.width)>abs(drag.translation.height)*1.5 else { return }
                            move(drag.translation.width<0 ? 1 : -1)
                        })
                    }
                    Panel { VStack(alignment:.leading,spacing:10) {
                        Label("Five nights near the new moon",systemImage:"circle.circle").font(.subheadline)
                        if nights.indices.contains(bestStart),nights.indices.contains(bestStart+4) {
                            Text("\(park.dayLabel(nights[bestStart].id)) – \(park.dayLabel(nights[bestStart+4].id))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                            Text("The ring marks the five nights with the least moonlight. Clouds and access may change the best choice.").font(.caption).foregroundStyle(palette.muted)
                        } else {
                            Text("Fewer than five nights remain this month. Look ahead to the next new moon.").font(.caption).foregroundStyle(palette.muted)
                        }
                    } }
                    Text("Solid: full forecast. Hollow: moon and darkness only. Dot size follows the score; a cloud marks overcast skies.").font(.caption).foregroundStyle(palette.muted)
                }.padding(24).clipped()
            }
        }.background(NightBackground(seed:park?.id ?? "nyx"))
            .task(id:park?.id) { if let park { await model.refresh([park]) } }.navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .sheet(item:$chosen,onDismiss:{peeking=false}) { night in NavigationStack { if peeking { ParkDetailView(park:night.park,initialDate:night.id) } else { ScoreBreakdownView(night:night) } }.nyxPresentation() }
    }
    private func move(_ offset:Int) { forward=offset>0; withAnimation(reduceMotion ? nil : NyxMotion.spring) { monthOffset+=offset } }
    /// The five consecutive nights with the least moonlight, ignoring nights already past.
    private func bestWindow(_ nights:[Night],from start:Int)->Int {
        guard nights.count-start>=5 else { return nights.count }
        return (start...(nights.count-5)).min { a,b in nights[a..<(a+5)].reduce(0){$0+$1.sky.moon.illumination} < nights[b..<(b+5)].reduce(0){$0+$1.sky.moon.illumination} } ?? nights.count
    }
}
#Preview("Calendar") { NavigationStack { CalendarView() }.environment(PlanModel()).preferredColorScheme(.dark) }

#Preview("Night cell • forecast / unknown / moon window") { let m=PlanModel();if let p=m.home { let n=m.night(p);HStack { NightCell(night:n);NightCell(night:n,highlighted:true) }.frame(width:150).padding().background(.black) } }
