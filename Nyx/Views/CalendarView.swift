import SwiftUI

struct NightCell: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let night:Night
    var highlighted:Bool=false
    /// What the ring means, for VoiceOver: "In the best stretch" or "In the darkest moon stretch".
    var stretchName:String?=nil
    var isTonight:Bool=false
    /// A night that has passed: the date dimmed, a faint dot, no ring and no score.
    var isPast:Bool=false
    /// A visible lunar eclipse or a notable shower's peak; at most one per night.
    var marker:WhatsUp.Events.Marker?=nil
    /// Larger on a wide iPad, where the month has the room.
    var scale=1.0
    /// The night shown beside the month on a wide iPad.
    var selected=false
    /// The score line's height, held open on a past night so its date lines up with the rest of the week.
    @ScaledMetric(relativeTo:.caption2) private var scoreLine=13.33
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
                // A past night is one quiet mark, whatever its forecast was: it can no longer be chosen.
                if isPast {
                    let dot=1.6*scale
                    context.fill(Path(ellipseIn:CGRect(x:center.x-dot,y:center.y-dot,width:2*dot,height:2*dot)),with:.color(palette.muted.opacity(0.45)))
                    return
                }
                if highlighted {
                    let ring=12.5*scale, halo=9*scale
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-ring,y:center.y-ring,width:2*ring,height:2*ring)),with:.color(palette.accent.opacity(0.65)),lineWidth:0.7)
                    // A soft halo: the new-moon window glows a little, like a dark sky does.
                    context.drawLayer { glow in
                        glow.addFilter(.blur(radius:5*scale))
                        glow.fill(Path(ellipseIn:CGRect(x:center.x-halo,y:center.y-halo,width:2*halo,height:2*halo)),with:.color(palette.accent.opacity(0.22*access.glow*(isPast ? 0.35 : 1))))
                    }
                }
                let mark=NightMark.mark(night,differentiate:access.differentiate)
                // Past nights fade their dot only; their text keeps full legibility.
                let fade=isPast ? 0.35 : 1.0
                mark.draw(in:&context,center:center,radius:radius,fill:night.basis.fill,color:palette.accent.opacity(fade),fillOpacity:0.45+Double(night.score.value)/200)
            }.frame(height:28*scale).accessibilityHidden(true)
            // Space, not hidden text: a hidden placeholder stretched the date's text frame over the whole cell.
            if isPast { Color.clear.frame(height:scoreLine) }
            else if let cloud=night.cloudCover,cloud>75 { Image(systemName:"cloud.fill").font(.caption2).foregroundStyle(palette.muted) }
            // Medium weight: at 11 pt the thin diagonals of a regular "7" fade into the sky.
            else { Text("\(night.score.value)").font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(palette.muted) }
        }.frame(maxWidth:.infinity,minHeight:78*scale)
            .background { if selected { RoundedRectangle(cornerRadius:14).fill(palette.accent.opacity(palette.nightVision ? 0.2 : 0.12)).overlay(RoundedRectangle(cornerRadius:14).stroke(palette.accent.opacity(0.5),lineWidth:0.8)) } }
            .contentShape(.hoverEffect,RoundedRectangle(cornerRadius:14)).contentShape(Rectangle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(spoken)
    }
    private var spoken:String {
        if isPast { return [night.park.dayLabel(night.id),String(localized:"Past night")].joined(separator:". ") }
        var parts=[isTonight ? String(localized:"Tonight, \(night.park.dayLabel(night.id))") : night.park.dayLabel(night.id),
                   String(localized:"\(night.score.value), \(night.score.band.label)")]
        if let label=night.basisLabel { parts.append(label) }
        if let cloud=night.cloudCover { parts.append(String(localized:"Clouds \(Int(cloud.rounded())) percent")) }
        if highlighted, let stretchName { parts.append(stretchName) }
        if let marker { parts.append(marker.name) }
        return parts.joined(separator:". ")
    }
}
/// The long-press preview: one night at a glance.
struct NightPeek: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.largeTitle) private var scoreSize=44.0
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
                    Text("\(night.score.value)").font(.system(size:min(scoreSize,72),weight:.light,design:.serif)).foregroundStyle(palette.accent)
                    Text(night.compactBandLabel).font(.caption).foregroundStyle(palette.muted)
                }
            }
            if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.subheadline).foregroundStyle(palette.ink) }
            else { Text("True darkness \(night.park.time(night.sky.darkStart)) – \(night.park.time(night.sky.darkEnd))").font(.subheadline).foregroundStyle(palette.ink) }
            Text(night.basisCaption(typical:true) ?? night.cloudCover.map { String(localized:"Clouds \(Int($0.rounded()))% on average") } ?? "").font(.caption).foregroundStyle(palette.muted)
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
        }.padding(20).frame(width:typeSize.isAccessibilitySize ? 380 : 320).background(Color.black)
    }
}
struct CalendarView: View {
    /// Plan's switch between one park and My free nights, pinned under the bar. It sits inside the month so the inspector's column never runs beneath it.
    var bar:AnyView?=nil
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyxAccess) private var access
    /// Kept for the window, so switching Plan to "My free nights" and back returns to this park.
    @SceneStorage("planPark") private var parkID=""
    @State private var monthOffset=0
    @State private var chosen:Night?
    @State private var peeking=false
    /// A night being added to Calendar from its context menu (no calendar permission: the system editor).
    @State private var calendarNight:Night?
    @State private var forward=true
    /// The night in the inspector on a wide iPad; tonight (or the month's first night) until one is
    /// chosen. Kept for the window, like its park.
    @SceneStorage("planNight") private var focusedID:Date?
    /// Whether the breakdown stands beside the month where there is room; closing it is remembered.
    @SceneStorage("planInspector") private var inspectorWanted=true
    /// The breakdown in a trailing inspector, right now.
    @State private var inspector=false
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The month's own width (an open inspector is not part of it).
    @State private var width=0.0
    private var park:Park? { model.park(parkID) ?? model.home }
    /// A wide iPad window shows the chosen night's breakdown in a trailing inspector beside a larger
    /// month, and a tap chooses the night; otherwise a tap opens the breakdown in a sheet.
    private var wide:Bool { inspector }
    /// Room for the inspector (`WideLayout.inspector`), whether or not it is open.
    private var inspectorRoom:Bool { WideLayout.inspector(width:width,open:inspector,regular:sizeClass == .regular,largeText:typeSize.isAccessibilitySize) }
    /// Everything one month's page draws, worked out once per render.
    private struct Month {
        let date:Date
        let nights:[Night]
        let lead:Int
        let tonight:Date
        let stretch:Stretch
        let inWindow:Set<Date>
    }
    private func month(_ park:Park)->Month {
        // Tonight's month, not the clock's: at 1 AM on the 1st, tonight is still last month's last night.
        let base=park.calendar.date(from:park.calendar.dateComponents([.year,.month],from:model.tonight(park))) ?? model.today
        let month=park.calendar.date(byAdding:.month,value:monthOffset,to:base) ?? base
        let count=park.calendar.range(of:.day,in:.month,for:month)?.count ?? 30
        let nights=model.nights(park,from:month,count:count)
        let lead=(park.calendar.component(.weekday,from:month)-park.calendar.firstWeekday+7)%7
        let tonight=park.evening(model.tonight(park))
        // The stretch may reach into the neighbouring months: a new moon on the 1st still gets five nights.
        let found=Self.stretch(model.nights(park,from:park.date(month,addingDays:-4),count:count+38),month:nights,after:tonight)
        return Month(date:month,nights:nights,lead:lead,tonight:tonight,stretch:found,inWindow:found.inMonth ? Set(found.nights.map(\.id)) : [])
    }
    private func focused(_ data:Month)->Night? {
        data.nights.first { $0.id==focusedID } ?? data.nights.first { $0.id==data.tonight } ?? data.nights.first
    }
    var body: some View {
        ScrollView {
            if let park {
                let data=month(park)
                VStack(alignment:.leading,spacing:24) {
                    heading(park); monthBar(park,data)
                    if typeSize.isAccessibilitySize { list(park,data) } else { grid(park,data,scale:wide && width>=640 ? 1.3 : 1) }
                    windowPanel(park,data); legend
                }.padding(24).clipped().readableColumn(wide ? 760 : WideLayout.readableWidth)
            }
        }.background(NightBackground(seed:park?.id ?? "nyx",park:park))
            .safeAreaBar(edge:.top,spacing:0) { if let bar { bar } }
            .measuringWidth($width)
            .inspector(isPresented:Binding(get:{ inspector },set:{ open in inspector=open; if !open { inspectorWanted=false } })) {
                if let park, let night=focused(month(park)) { aside(night) }
            }
            .toolbar {
                if inspectorRoom {
                    ToolbarItem(placement:.topBarTrailing) {
                        Button { withAnimation(reduceMotion ? nil : NyxMotion.spring) { inspectorWanted.toggle() } } label:{
                            Label(inspector ? "Hide the breakdown" : "Show the breakdown",systemImage:"sidebar.trailing")
                        }.help(inspector ? "Hide the breakdown" : "Show the breakdown")
                        .accessibilityInputLabels([Text("Breakdown"),Text("Score breakdown")])
                    }
                }
            }
            .onChange(of:width,initial:true) { _,_ in syncInspector() }
            .onChange(of:sizeClass) { _,_ in syncInspector() }
            .onChange(of:typeSize) { _,_ in syncInspector() }
            .onChange(of:inspectorWanted) { _,_ in syncInspector() }
            .task(id:park?.id) { if let park { await model.refresh([park]) } }
            .onChange(of:model.calendarRequest,initial:true) { _,request in if let request { show(request) } }
            .sheet(item:$calendarNight) { night in CalendarEditor(draft:CalendarDraft(night:night,closure:model.closure(night.park))) { calendarNight=nil }.ignoresSafeArea() }
            .sheet(item:$chosen,onDismiss:{peeking=false}) { night in NavigationStack { if peeking { ParkDetailView(park:night.park,initialDate:night.id) } else { ScoreBreakdownView(night:night,isTonight:night.id==model.tonight(night.park)) } }.nyxPresentation()
                .onAppear { ReviewPrompt.noteNightViewed(score:night.score.value) } }
            // iPad keyboard: ⌘← and ⌘→ move the chosen night, turning the month at its edges.
            .nightKeys(enabled:wide && chosen == nil) { delta in step(delta) }
    }
    /// The park whose month this is, as the page's title: its state and Dark Sky status above it
    /// (data, not a slogan), and the name itself the menu that changes it.
    @ViewBuilder private func heading(_ park:Park)->some View {
        VStack(alignment:.leading,spacing:6) {
            let states=park.state.replacingOccurrences(of:",",with:" · ")
            Eyebrow(text:park.darkSkyDesignated ? "\(states) · International Dark Sky Park" : LocalizedStringKey(states))
            Menu {
                Picker("Park",selection:Binding(get:{park.id},set:{parkID=$0})) { ForEach(model.parks) { Text($0.shortName).tag($0.id) } }
            } label: {
                HStack(alignment:.firstTextBaseline,spacing:10) {
                    Text(park.shortName).font(.system(typeSize.isAccessibilitySize ? .title2 : .largeTitle,design:.serif)).foregroundStyle(palette.ink).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                    Image(systemName:"chevron.up.chevron.down").font(.title3).foregroundStyle(palette.accent).accessibilityHidden(true)
                    Spacer(minLength:0)
                }.frame(minHeight:44).contentShape(Rectangle())
            }.accessibilityLabel("Park").accessibilityValue(park.shortName).accessibilityInputLabels([Text("Park"),Text("Choose park"),Text(park.shortName)])
        }
    }
    private func monthBar(_ park:Park,_ data:Month)->some View {
        HStack {
            Button { move(-1) } label:{ Image(systemName:"chevron.backward").frame(width:44,height:44) }.accessibilityLabel("Previous month").accessibilityInputLabels([Text("Previous month"),Text("Previous")])
                .hoverEffect(.highlight)
            Spacer(minLength:0)
            // The month's name carries its Audio Graph: the darkness of every night, as a tone.
            Text(park.monthLabel(data.date)).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint("An audio graph of this month's nights is available.")
                .nightChart { [nights=data.nights,events=monthEvents(data.nights,park:park),title=String(localized:"Darkness score by night, \(park.monthLabel(data.date))")] in NightChart.nights(nights,title:title,events:events) }
            Spacer(minLength:0)
            Button { move(1) } label:{ Image(systemName:"chevron.forward").frame(width:44,height:44) }.accessibilityLabel("Next month").accessibilityInputLabels([Text("Next month"),Text("Next")])
                .hoverEffect(.highlight)
        }
    }
    /// Accessibility sizes: one night per row, starting at tonight. Nights already past fold away
    /// under one line, dimmed and without scores, as in the month grid.
    private func list(_ park:Park,_ data:Month)->some View {
        let past=data.nights.filter { $0.id<data.tonight }
        return LazyVStack(alignment:.leading,spacing:20) {
            if !past.isEmpty {
                DisclosureGroup {
                    VStack(alignment:.leading,spacing:12) { ForEach(past) { night in
                        Text(park.dayLabel(night.id)).font(.body).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                            .accessibilityLabel("\(park.dayLabel(night.id)). Past night")
                    } }.padding(.top,10)
                } label:{ Text("Past nights · \(past.count)").font(.headline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                .tint(palette.muted)
            }
            ForEach(data.nights.filter { $0.id>=data.tonight }) { night in
            Button { choose(night) } label:{
                VStack(alignment:.leading,spacing:8) {
                    Text(park.dayLabel(night.id)).font(.headline)
                    Text("\(night.score.value) · \(night.score.band.label)").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                    Text(night.basisCaption(typical:true) ?? String(localized:"Forecast included")).font(.caption).foregroundStyle(palette.muted)
                    if let marker=model.events(night).marker(park:park) { Text(marker.name).font(.caption).foregroundStyle(palette.ink) }
                }.fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,14)
            }.buttonStyle(.plain).accessibilityElement(children:.ignore)
                .accessibilityLabel("\(park.dayLabel(night.id)), \(night.score.value) out of 100, \(night.score.band.label). \(night.basisCaption(typical:true) ?? String(localized:"Forecast included"))\(model.events(night).marker(park:park).map { ". "+$0.name } ?? "")")
                .accessibilityHint(data.inWindow.contains(night.id) ? data.stretch.kind.spokenHint : String(localized:"Opens the score breakdown."))
                .accessibilityAction(named:"Open this night") { chosen=night;peeking=true }
                .contextMenu {
                    Button("Open this night",systemImage:"arrow.up.right") { chosen=night;peeking=true }
                    Button("Why this score",systemImage:"chart.bar") { chosen=night }
                    if night.id>=data.tonight { Button("Add to Calendar",systemImage:"calendar.badge.plus") { calendarNight=night }; FollowNightMenuItem(night:night) }
                }
                .accessibilityInputLabels(Self.spokenNames(night))
        } }
        .accessibilityRotor(Text("Best nights"),entries:Self.bestNights(data.nights,after:data.tonight),entryID:\.id,entryLabel:\.label)
        .accessibilityRotor(Text(data.stretch.kind.title),entries:Self.rotor(data.stretch.nights.filter { data.inWindow.contains($0.id) }),entryID:\.id,entryLabel:\.label)
    }
    /// `scale` enlarges each night's little sky on a wide iPad.
    private func grid(_ park:Park,_ data:Month,scale:Double)->some View {
        let focusedNight=wide ? focused(data)?.id : nil
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:2),count:7),spacing:6) {
            ForEach(0..<7,id:\.self) { i in Text(park.calendar.veryShortWeekdaySymbols[(i+park.calendar.firstWeekday-1)%7]).font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true) }
            ForEach(0..<data.lead,id:\.self) { _ in Color.clear.frame(height:78*scale) }
            ForEach(data.nights) { night in
                let events=model.events(night)
                Button { choose(night) } label:{ NightCell(night:night,highlighted:data.inWindow.contains(night.id),stretchName:data.stretch.kind.spoken,isTonight:night.id==data.tonight,isPast:night.id<data.tonight,marker:events.marker(park:park),scale:scale,selected:night.id==focusedNight) }.buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityAddTraits(night.id==focusedNight ? .isSelected : [])
                    .accessibilityInputLabels(Self.spokenNames(night))
                    .contextMenu {
                        Button("Open this night",systemImage:"arrow.up.right") { chosen=night;peeking=true }
                        Button("Why this score",systemImage:"chart.bar") { chosen=night }
                        if night.id>=data.tonight { Button("Add to Calendar",systemImage:"calendar.badge.plus") { calendarNight=night }; FollowNightMenuItem(night:night) }
                    } preview: { NightPeek(night:night,isTonight:night.id==data.tonight,event:events.item(park:park,sky:night.sky,isTonight:night.id==data.tonight)).environment(\.nyx,palette).modifier(NightVisionFilter(enabled:palette.nightVision,red:palette.red)) }
            }
        }
        .accessibilityRotor(Text("Best nights"),entries:Self.bestNights(data.nights,after:data.tonight),entryID:\.id,entryLabel:\.label)
        .accessibilityRotor(Text(data.stretch.kind.title),entries:Self.rotor(data.stretch.nights.filter { data.inWindow.contains($0.id) }),entryID:\.id,entryLabel:\.label)
        .id(monthOffset)
        .transition(reduceMotion || access.crossFade ? .opacity : .asymmetric(insertion:.move(edge:forward ? .trailing : .leading).combined(with:.opacity),removal:.move(edge:forward ? .leading : .trailing).combined(with:.opacity)))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:30).onEnded { drag in
            guard abs(drag.translation.width)>abs(drag.translation.height)*1.5 else { return }
            move(drag.translation.width<0 ? 1 : -1)
        })
    }
    /// What the ring marks, said once: the best stretch while forecasts reach it, else the darkest Moon.
    private func windowPanel(_ park:Park,_ data:Month)->some View {
        let stretch=data.stretch
        return Panel { VStack(alignment:.leading,spacing:10) {
            Label(stretch.kind == .moon && !stretch.inMonth && !stretch.nights.isEmpty ? String(localized:"The next darkest moon stretch") : stretch.kind.title,systemImage:"circle.circle").font(.subheadline)
            if let first=stretch.nights.first,let last=stretch.nights.last {
                Text("\(park.dayLabel(first.id)) – \(park.dayLabel(last.id))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent)
                Text(stretch.kind == .best ? String(localized:"The ring marks the five nights in a row with the highest scores while forecasts reach them. A closure can still change the best choice.")
                     : stretch.inMonth ? String(localized:"Past the forecasts, the ring marks the five nights with the least moonlight. Their clouds are not known yet.")
                     : String(localized:"The darkest stretch this month has passed or falls just beyond it. Look ahead to plan it.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            } else {
                Text("These nights have passed. Look ahead to the next new moon.").font(.caption).foregroundStyle(palette.muted)
            }
        } }
    }
    @ViewBuilder private var legend: some View {
        Text("Solid: full forecast. Half-filled: an early look, the forecast eased toward the usual clouds. Hollow: no cloud forecast yet, so the park's usual clouds. Dot size follows the score; a cloud marks overcast skies. Past nights keep only a faint dot. A small streak marks a meteor shower's peak, a shaded Moon a lunar eclipse you can see; neither changes the score.").font(.caption).foregroundStyle(palette.muted)
        if access.differentiate { Text(NightMark.legend+" "+String(localized:"A line through the date marks a night that has passed.")).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
    }
    /// The chosen night beside the month: its breakdown, and the ways into that night (the park's
    /// page here or in a window of its own, and Calendar for nights still ahead).
    private func aside(_ night:Night)->some View {
        NightInspector(night:night,isTonight:night.id==model.tonight(night.park),close:nil) {
            VStack(alignment:.leading,spacing:12) {
                Button { chosen=night;peeking=true } label:{ Label("Open this night",systemImage:"arrow.up.right") }.buttonStyle(.bordered)
                OpenParkWindowButton(park:night.park,night:night.id).buttonStyle(.bordered)
                if night.id>=model.tonight(night.park) { AddNightToCalendar(night:night) }
            }
        }
    }
    /// Opens or closes the inspector as the window's room and the person's choice allow.
    private func syncInspector() {
        let show=inspectorWanted && inspectorRoom
        if show != inspector { inspector=show }
    }
    /// A tap: in the inspector on a wide iPad (opening it again if it was closed), in a sheet otherwise.
    private func choose(_ night:Night) {
        if inspectorRoom {
            withAnimation(reduceMotion ? nil : NyxMotion.spring) { focusedID=night.id; inspectorWanted=true }
            ReviewPrompt.noteNightViewed(score:night.score.value)
        } else { chosen=night }
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
        let chosen=excellent.isEmpty ? Array(NightPlanner.ranked(ahead).prefix(3)) : excellent
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
    /// The five nights the ring marks.
    struct Stretch {
        enum Kind {
            /// The best five nights in a row by score, while a forecast (or an early look) reaches all five.
            case best
            /// Beyond the forecasts: the five nights with the least moonlight near a new moon.
            case moon
            var title:String { self == .best ? String(localized:"Best stretch") : String(localized:"Darkest moon stretch") }
            /// What VoiceOver adds to a ringed night.
            var spoken:String { self == .best ? String(localized:"In the best stretch") : String(localized:"In the darkest moon stretch") }
            var spokenHint:String { self == .best ? String(localized:"In the best stretch. Opens the score breakdown.") : String(localized:"In the darkest moon stretch. Opens the score breakdown.") }
        }
        let kind:Kind
        let nights:ArraySlice<Night>
        /// False when the stretch shown is the next one, beyond this month.
        let inMonth:Bool
    }
    /// The ring, ignoring nights already past. While forecasts exist, it marks the five consecutive
    /// nights with the highest total score (earliest on a tie), so the ring and the numbers beside it
    /// always agree. Where no five forecast nights touch the month, it falls back to the five
    /// consecutive nights with the least moonlight; such a stretch only counts if it really sits near
    /// a new moon (some night under 12% lit), since late in a month the few left may be bright. When
    /// no moon stretch touches this month, the next one ahead is returned with `inMonth` false.
    static func stretch(_ nights:[Night],month:[Night],after tonight:Date)->Stretch {
        guard let first=month.first?.id,let last=month.last?.id else { return Stretch(kind:.moon,nights:[],inMonth:false) }
        let starts=nights.indices.filter { i in i+5<=nights.count && nights[i].id>=tonight }
        func touches(_ i:Int)->Bool { nights[i].id<=last && nights[i+4].id>=first }
        func total(_ i:Int)->Int { nights[i..<(i+5)].reduce(0) { $0+$1.rankScore } }
        let forecast=starts.filter { i in touches(i) && nights[i..<(i+5)].allSatisfy { $0.basis != .usual } }
        if let best=forecast.max(by:{ a,b in total(a) != total(b) ? total(a)<total(b) : a>b }) { return Stretch(kind:.best,nights:nights[best..<(best+5)],inMonth:true) }
        func light(_ i:Int)->Double { nights[i..<(i+5)].reduce(0) { $0+$1.sky.moon.illumination } }
        func nearNew(_ i:Int)->Bool { nights[i..<(i+5)].contains { $0.sky.moon.illumination<0.12 } }
        let touching=starts.filter { touches($0) && nearNew($0) }
        if let best=touching.min(by:{ light($0)<light($1) }) { return Stretch(kind:.moon,nights:nights[best..<(best+5)],inMonth:true) }
        let ahead=starts.filter { nights[$0+4].id>last && nearNew($0) }
        guard let next=ahead.min(by:{ light($0)<light($1) }) else { return Stretch(kind:.moon,nights:[],inMonth:false) }
        return Stretch(kind:.moon,nights:nights[next..<(next+5)],inMonth:false)
    }
}
#Preview("Calendar") { NavigationStack { CalendarView() }.environment(PlanModel()).preferredColorScheme(.dark) }

#Preview("Night cell • forecast / unknown / moon window") { let m=PlanModel();if let p=m.home { let n=m.night(p);HStack { NightCell(night:n);NightCell(night:n,highlighted:true) }.frame(width:150).padding().background(.black) } }
