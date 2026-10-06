import SwiftUI

struct NightCell: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let night:Night
    var highlighted:Bool=false
    var isTonight:Bool=false
    var isPast:Bool=false
    /// A visible lunar eclipse or a notable shower's peak; at most one per night.
    var marker:WhatsUp.Events.Marker?=nil
    /// Larger on a wide iPad, where the month has the room.
    var scale=1.0
    /// The night shown beside the month on a wide iPad.
    var selected=false
    var body:some View {
        VStack(spacing:5) {
            Text("\(night.park.calendar.component(.day,from:night.id))").font((scale>1 ? Font.callout : Font.caption).monospacedDigit().weight(isTonight ? .bold : .regular))
                .foregroundStyle(isTonight ? palette.accent : isPast ? palette.muted : palette.ink)
                // Past nights are dimmer; without colour, a line through the date says so.
                .strikethrough(access.differentiate && isPast,color:palette.muted)
                .overlay(alignment:.bottom) { if isTonight { Capsule().fill(palette.accent).frame(width:12,height:2).offset(y:4) } }
                // The night's event beside its date: a reason to go that is not part of the score.
                .overlay(alignment:.topTrailing) { if let marker { SkyGlyph(SkyGlyph.Kind(marker.glyph),color:palette.ink.opacity(isPast ? 0.5 : 1)).frame(width:12,height:12).offset(x:15,y:-3) } }
            Canvas { context,size in
                // Size follows the score on a curve, so a 95 night reads clearly larger than a 70.
                let center=CGPoint(x:size.width/2,y:size.height/2),radius=(1.5+8*pow(Double(night.score.value)/100,1.5))*scale
                if highlighted {
                    let ring=12.5*scale, halo=9*scale
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-ring,y:center.y-ring,width:2*ring,height:2*ring)),with:.color(palette.accent.opacity(0.65)),lineWidth:0.7)
                    // A soft halo: the new-moon window glows a little, like a dark sky does.
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius:5*scale))
                        glow.fill(Path(ellipseIn:CGRect(x:center.x-halo,y:center.y-halo,width:2*halo,height:2*halo)),with:.color(palette.accent.opacity(0.22*access.glow*(isPast ? 0.35 : 1))))
                    }
                }
                let mark=NightMark.mark(score:night.score.value,hasForecast:night.score.hasForecast,differentiate:access.differentiate)
                let circle=mark.path(center:center,radius:radius)
                // Past nights fade their dot only; their text keeps full legibility.
                let fade=isPast ? 0.35 : 1.0
                if mark.filled { context.fill(circle,with:.color(palette.accent.opacity((0.45+Double(night.score.value)/200)*fade))) }
                else { context.stroke(circle,with:.color(palette.accent.opacity(fade)),lineWidth:1.1) }
            }.frame(height:28*scale).accessibilityHidden(true)
            if let cloud=night.cloudCover,cloud>75 { Image(systemName:"cloud.fill").font(.caption2).foregroundStyle(palette.muted) }
            else { Text("\(night.score.value)").font(.caption2.monospacedDigit()).foregroundStyle(palette.muted) }
        }.frame(maxWidth:.infinity,minHeight:78*scale)
            .background { if selected { RoundedRectangle(cornerRadius:14).fill(palette.accent.opacity(palette.nightVision ? 0.2 : 0.12)).overlay(RoundedRectangle(cornerRadius:14).stroke(palette.accent.opacity(0.5),lineWidth:0.8)) } }
            .contentShape(.hoverEffect,RoundedRectangle(cornerRadius:14)).contentShape(Rectangle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(spoken)
    }
    private var spoken:String {
        var parts=[isTonight ? String(localized:"Tonight, \(night.park.dayLabel(night.id))") : night.park.dayLabel(night.id),
                   String(localized:"\(night.score.value), \(night.score.band.label)")]
        if let cloud=night.cloudCover { parts.append(String(localized:"Clouds \(Int(cloud.rounded())) percent")) }
        else { parts.append(String(localized:"No cloud forecast")) }
        if highlighted { parts.append(String(localized:"In the five-night moon window")) }
        if let marker { parts.append(marker.name) }
        if isPast { parts.append(String(localized:"Past night")) }
        return parts.joined(separator:". ")
    }
}
/// The long-press preview: one night at a glance.
struct NightPeek: View {
    @Environment(\.nyx) private var palette
    let night:Night
    var isTonight=false
    /// The night's eclipse or shower peak, when it has one.
    var event:WhatsUp.Item?=nil
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(alignment:.center,spacing:16) {
                MoonView(geometry:AstronomyEngine().moon(for:night).geometry).frame(width:56,height:56)
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
            if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.subheadline).foregroundStyle(palette.ink) }
            else { Text("True darkness \(night.park.time(night.sky.darkStart)) – \(night.park.time(night.sky.darkEnd))").font(.subheadline).foregroundStyle(palette.ink) }
            Text(night.cloudCover.map { String(localized:"Clouds \(Int($0.rounded()))% on average") } ?? String(localized:"Moon and darkness only. Clouds unknown.")).font(.caption).foregroundStyle(palette.muted)
            if let event {
                Divider().overlay(palette.line)
                HStack(alignment:.top,spacing:12) {
                    SkyGlyph(item:event.kind,color:palette.accent).frame(width:18,height:18)
                    VStack(alignment:.leading,spacing:3) {
                        Text([event.title,event.value].compactMap { $0 }.joined(separator:" · ")).font(.subheadline.weight(.medium)).foregroundStyle(palette.ink)
                        Text(event.detail).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    }
                }
            }
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
    @Environment(\.nyxAccess) private var access
    @State private var parkID=""
    @State private var monthOffset=0
    @State private var chosen:Night?
    @State private var peeking=false
    @State private var forward=true
    /// The night shown beside the month on a wide iPad; tonight (or the month's first night) until one is chosen.
    @State private var focusedID:Date?
    @State private var width=0.0
    private var park:Park? { model.park(parkID) ?? model.home }
    /// A wide iPad shows the chosen night's breakdown beside a larger month, instead of in a sheet.
    private var wide:Bool { !typeSize.isAccessibilitySize && WideLayout.columns(width:width,largeText:false)==2 }
    /// Everything one month's page draws, worked out once per render.
    private struct Month {
        let date:Date
        let nights:[Night]
        let lead:Int
        let tonight:Date
        let window:ArraySlice<Night>
        let windowInMonth:Bool
        let inWindow:Set<Date>
    }
    private func month(_ park:Park)->Month {
        let base=park.calendar.date(from:park.calendar.dateComponents([.year,.month],from:model.today)) ?? model.today
        let month=park.calendar.date(byAdding:.month,value:monthOffset,to:base) ?? base
        let count=park.calendar.range(of:.day,in:.month,for:month)?.count ?? 30
        let nights=model.nights(park,from:month,count:count)
        let lead=(park.calendar.component(.weekday,from:month)-park.calendar.firstWeekday+7)%7
        let tonight=park.evening(model.tonight(park))
        // The window may reach into the neighbouring months: a new moon on the 1st still gets five nights.
        let found=bestWindow(model.nights(park,from:park.date(month,addingDays:-4),count:count+38),month:nights,after:tonight)
        return Month(date:month,nights:nights,lead:lead,tonight:tonight,window:found.nights,windowInMonth:found.inMonth,inWindow:found.inMonth ? Set(found.nights.map(\.id)) : [])
    }
    private func focused(_ data:Month)->Night? {
        data.nights.first { $0.id==focusedID } ?? data.nights.first { $0.id==data.tonight } ?? data.nights.first
    }
    var body: some View {
        ScrollView {
            if let park {
                let data=month(park)
                if wide {
                    HStack(alignment:.top,spacing:28) {
                        VStack(alignment:.leading,spacing:24) { heading(park); monthBar(park,data); grid(park,data,scale:1.3); windowPanel(park,data); legend }
                            .frame(maxWidth:640)
                        if let night=focused(data) { aside(night) }
                    }.padding(24).clipped()
                } else {
                    VStack(alignment:.leading,spacing:24) {
                        heading(park); monthBar(park,data)
                        if typeSize.isAccessibilitySize { list(park,data) } else { grid(park,data,scale:1) }
                        windowPanel(park,data); legend
                    }.padding(24).clipped().readableColumn()
                }
            }
        }.background(NightBackground(seed:park?.id ?? "nyx",park:park))
            .measuringWidth($width)
            .task(id:park?.id) { if let park { await model.refresh([park]) } }.navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
            .onChange(of:model.calendarRequest,initial:true) { _,request in if let request { show(request) } }
            .sheet(item:$chosen,onDismiss:{peeking=false}) { night in NavigationStack { if peeking { ParkDetailView(park:night.park,initialDate:night.id) } else { ScoreBreakdownView(night:night,isTonight:night.id==model.tonight(night.park)) } }.nyxPresentation() }
            // iPad keyboard: ⌘← and ⌘→ move the chosen night, turning the month at its edges.
            .nightKeys(enabled:wide && chosen == nil) { delta in step(delta) }
    }
    @ViewBuilder private func heading(_ park:Park)->some View {
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
    }
    private func monthBar(_ park:Park,_ data:Month)->some View {
        HStack {
            Button { move(-1) } label:{ Image(systemName:"chevron.left").frame(width:44,height:44) }.accessibilityLabel("Previous month").accessibilityInputLabels([Text("Previous month"),Text("Previous")])
                .hoverEffect(.highlight)
            Spacer(minLength:0)
            // The month's name carries its Audio Graph: the darkness of every night, as a tone.
            Text(park.monthLabel(data.date)).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint("An audio graph of this month's nights is available.")
                .nightChart { [nights=data.nights,events=monthEvents(data.nights,park:park),title=String(localized:"Darkness score by night, \(park.monthLabel(data.date))")] in NightChart.nights(nights,title:title,events:events) }
            Spacer(minLength:0)
            Button { move(1) } label:{ Image(systemName:"chevron.right").frame(width:44,height:44) }.accessibilityLabel("Next month").accessibilityInputLabels([Text("Next month"),Text("Next")])
                .hoverEffect(.highlight)
        }
    }
    private func list(_ park:Park,_ data:Month)->some View {
        LazyVStack(alignment:.leading,spacing:20) { ForEach(data.nights) { night in
            Button { chosen=night } label:{
                VStack(alignment:.leading,spacing:8) {
                    Text(park.dayLabel(night.id)).font(.headline)
                    Text("\(night.score.value) · \(night.score.band.label)").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                    Text(night.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown.")).font(.caption).foregroundStyle(palette.muted)
                    if let marker=model.events(night).marker(park:park) { Text(marker.name).font(.caption).foregroundStyle(palette.ink) }
                }.fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,14)
            }.buttonStyle(.plain).accessibilityElement(children:.ignore)
                .accessibilityLabel("\(park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown."))\(model.events(night).marker(park:park).map { ". "+$0.name } ?? "")")
                .accessibilityHint(data.inWindow.contains(night.id) ? "In the five-night moon window. Opens score breakdown." : "Opens score breakdown.")
                .accessibilityAction(named:"Open this night") { chosen=night;peeking=true }
                .contextMenu {
                    Button("Open this night",systemImage:"arrow.up.right") { chosen=night;peeking=true }
                    Button("Why this score",systemImage:"chart.bar") { chosen=night }
                }
                .accessibilityInputLabels(Self.spokenNames(night))
        } }
        .accessibilityRotor(Text("Best nights"),entries:Self.bestNights(data.nights,after:data.tonight),entryID:\.id,entryLabel:\.label)
    }
    /// `scale` enlarges each night's little sky on a wide iPad.
    private func grid(_ park:Park,_ data:Month,scale:Double)->some View {
        let focusedNight=wide ? focused(data)?.id : nil
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:6) {
            ForEach(0..<7,id:\.self) { i in Text(park.calendar.veryShortWeekdaySymbols[(i+park.calendar.firstWeekday-1)%7]).font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true) }
            ForEach(0..<data.lead,id:\.self) { _ in Color.clear.frame(height:78*scale) }
            ForEach(data.nights) { night in
                let events=model.events(night)
                Button { choose(night) } label:{ NightCell(night:night,highlighted:data.inWindow.contains(night.id),isTonight:night.id==data.tonight,isPast:night.id<data.tonight,marker:events.marker(park:park),scale:scale,selected:night.id==focusedNight) }.buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityAddTraits(night.id==focusedNight ? .isSelected : [])
                    .accessibilityInputLabels(Self.spokenNames(night))
                    .contextMenu {
                        Button("Open this night",systemImage:"arrow.up.right") { chosen=night;peeking=true }
                        Button("Why this score",systemImage:"chart.bar") { chosen=night }
                    } preview: { NightPeek(night:night,isTonight:night.id==data.tonight,event:events.item(park:park,sky:night.sky,isTonight:night.id==data.tonight)).environment(\.nyx,palette).modifier(NightVisionFilter(enabled:palette.nightVision)) }
            }
        }
        .accessibilityRotor(Text("Best nights"),entries:Self.bestNights(data.nights,after:data.tonight),entryID:\.id,entryLabel:\.label)
        .accessibilityRotor(Text("Moon window"),entries:Self.rotor(data.window.filter { data.inWindow.contains($0.id) }),entryID:\.id,entryLabel:\.label)
        .id(monthOffset)
        .transition(reduceMotion || access.crossFade ? .opacity : .asymmetric(insertion:.move(edge:forward ? .trailing : .leading).combined(with:.opacity),removal:.move(edge:forward ? .leading : .trailing).combined(with:.opacity)))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:30).onEnded { drag in
            guard abs(drag.translation.width)>abs(drag.translation.height)*1.5 else { return }
            move(drag.translation.width<0 ? 1 : -1)
        })
    }
    private func windowPanel(_ park:Park,_ data:Month)->some View {
        Panel { VStack(alignment:.leading,spacing:10) {
            Label(data.windowInMonth || data.window.isEmpty ? String(localized:"Five nights near the new moon") : String(localized:"The next five nights near the new moon"),systemImage:"circle.circle").font(.subheadline)
            if let first=data.window.first,let last=data.window.last {
                Text("\(park.dayLabel(first.id)) – \(park.dayLabel(last.id))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                Text(data.windowInMonth ? String(localized:"The ring marks the five nights with the least moonlight. Clouds and access may change the best choice.") : String(localized:"The darkest stretch this month has passed or falls just beyond it. Look ahead to plan it.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("These nights have passed. Look ahead to the next new moon.").font(.caption).foregroundStyle(palette.muted)
            }
        } }
    }
    @ViewBuilder private var legend: some View {
        Text("Solid: full forecast. Hollow: moon and darkness only. Dot size follows the score; a cloud marks overcast skies. A small streak marks a meteor shower's peak, a shaded Moon a lunar eclipse you can see; neither changes the score.").font(.caption).foregroundStyle(palette.muted)
        if access.differentiate { Text(NightMark.legend+" "+String(localized:"A line through the date marks a night that has passed.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
    }
    /// The chosen night beside the month: its breakdown, and the way into the park on that night.
    private func aside(_ night:Night)->some View {
        Panel { VStack(alignment:.leading,spacing:18) {
            ScoreBreakdownView(night:night,isTonight:night.id==model.tonight(night.park),inline:true)
            Button { chosen=night;peeking=true } label:{ Label("Open this night",systemImage:"arrow.up.right") }.buttonStyle(.bordered)
        } }
        .frame(maxWidth:560)
        .id(night.id)
        .transition(.opacity)
    }
    /// A tap: beside the month on a wide iPad, in a sheet otherwise.
    private func choose(_ night:Night) {
        if wide { withAnimation(reduceMotion ? nil : NyxMotion.spring) { focusedID=night.id } } else { chosen=night }
    }
    private func step(_ delta:Int) {
        guard let park else { return }
        let data=month(park)
        guard let current=focused(data) else { return }
        let next=park.date(current.id,addingDays:delta)
        let calendar=park.calendar
        let base=calendar.date(from:calendar.dateComponents([.year,.month],from:model.today)) ?? model.today
        let target=calendar.date(from:calendar.dateComponents([.year,.month],from:next)) ?? next
        let offset=calendar.dateComponents([.month],from:base,to:target).month ?? monthOffset
        if offset != monthOffset { move(offset-monthOffset) }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { focusedID=next }
    }
    /// One rotor stop per night: the day, its score and band.
    struct RotorNight: Identifiable { let id: Date; let label: String }
    static func rotor(_ nights:some Sequence<Night>)->[RotorNight] {
        nights.map { RotorNight(id:$0.id,label:String(localized:"\($0.park.dayLabel($0.id)), \($0.score.value), \($0.score.band.label)")) }
    }
    /// The "Best nights" rotor: tonight onward, Excellent or better; if none, the three best. Date order.
    static func bestNights(_ nights:[Night],after tonight:Date)->[RotorNight] {
        let ahead=nights.filter { $0.id>=tonight }
        let excellent=ahead.filter { $0.score.value>=75 }
        let chosen=excellent.isEmpty ? Array(ahead.sorted { $0.score.value>$1.score.value }.prefix(3)) : excellent
        return rotor(chosen.sorted { $0.id<$1.id })
    }
    /// What Voice Control accepts for a night: its day number, or weekday and day ("Tap 17", "Tap Friday 17").
    static func spokenNames(_ night:Night)->[Text] {
        var format=Date.FormatStyle.dateTime.weekday(.wide).day()
        format.timeZone=night.park.timeZone
        return [Text(verbatim:"\(night.park.calendar.component(.day,from:night.id))"),Text(verbatim:night.id.formatted(format))]
    }
    private func monthEvents(_ nights:[Night],park:Park)->[Date:String] {
        Dictionary(nights.compactMap { night in model.events(night).marker(park:park).map { (night.id,$0.name) } },uniquingKeysWith:{ first,_ in first })
    }
    /// A `nyx://calendar` link: that park, and that month (this month when the link names none).
    private func show(_ request:CalendarRequest) {
        model.calendarRequest=nil
        guard let target=model.park(request.parkID) else { return }
        parkID=target.id
        let calendar=target.calendar, now=calendar.dateComponents([.year,.month],from:model.today)
        let months=request.year.flatMap { y in request.month.map { m in (y-(now.year ?? y))*12+(m-(now.month ?? m)) } } ?? 0
        forward=months>=monthOffset; monthOffset=months
    }
    private func move(_ offset:Int) { forward=offset>0; withAnimation(reduceMotion ? nil : NyxMotion.spring) { monthOffset+=offset } }
    /// The five consecutive nights with the least moonlight, ignoring nights already past. A window
    /// only counts if it really sits near a new moon (some night under 12% lit): late in a month the
    /// few windows left may be bright, and those are never called "near the new moon". When no such
    /// window touches this month, the next one ahead is returned with `inMonth` false.
    private func bestWindow(_ nights:[Night],month:[Night],after tonight:Date)->(nights:ArraySlice<Night>,inMonth:Bool) {
        guard let first=month.first?.id,let last=month.last?.id else { return ([],false) }
        let starts=nights.indices.filter { i in i+5<=nights.count && nights[i].id>=tonight }
        func light(_ i:Int)->Double { nights[i..<(i+5)].reduce(0) { $0+$1.sky.moon.illumination } }
        func nearNew(_ i:Int)->Bool { nights[i..<(i+5)].contains { $0.sky.moon.illumination<0.12 } }
        let touching=starts.filter { nights[$0].id<=last && nights[$0+4].id>=first && nearNew($0) }
        if let best=touching.min(by:{ light($0)<light($1) }) { return (nights[best..<(best+5)],true) }
        let ahead=starts.filter { nights[$0+4].id>last && nearNew($0) }
        guard let next=ahead.min(by:{ light($0)<light($1) }) else { return ([],false) }
        return (nights[next..<(next+5)],false)
    }
}
#Preview("Calendar") { NavigationStack { CalendarView() }.environment(PlanModel()).preferredColorScheme(.dark) }

#Preview("Night cell • forecast / unknown / moon window") { let m=PlanModel();if let p=m.home { let n=m.night(p);HStack { NightCell(night:n);NightCell(night:n,highlighted:true) }.frame(width:150).padding().background(.black) } }
