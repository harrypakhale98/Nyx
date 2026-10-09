import SwiftUI

enum GuideMode {
    case planning,learn(Essay)
    var title:String { switch self { case .planning:String(localized:"Ask Nyx");case .learn:String(localized:"Another way to see it") } }
}
/// Ask Nyx: questions about parks and nights, answered on this iPhone by the system model from
/// records Nyx computed (and records it looks up through its tools). The records are shown as Nyx's
/// own rows; each citation is a chip that finds its record. Only offered while the model is available.
struct GuideView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let mode:GuideMode
    @State private var guide=OnDeviceGuide()
    @State private var question=""
    /// The question as it was asked, shown above its answer.
    @State private var asked=""
    @State private var requestID=0
    /// The last request answered in full, so coming back from a record's page never asks again.
    @State private var answeredID=0
    /// The records as the model saw them for the question on screen, so the citations keep
    /// pointing at the rows they cite while forecasts and the starting point move on.
    @State private var sent:[String]?
    /// The record a citation chip pointed to, briefly lit.
    @State private var lit:Int?
    @FocusState private var typing:Bool
    private var lookup:NightLookup { NightLookup(parks:model.parks,forecasts:model.forecasts,now:model.today,details:model.details) }
    private var records:[String] {
        switch mode {
        case .planning:
            guard let home=model.home else { return [] }
            let best=Array(model.ranked(model.nearby(latitude:model.location.latitude,longitude:model.location.longitude)).prefix(3))
            let lookup=lookup
            let start=model.location.latitude != nil ? String(localized:"Starting point: the device location. Distances are straight-line estimates.")
                : model.homePlace.map { String(localized:"Starting point: \($0.label). Distances are straight-line estimates.") }
                ?? String(localized:"Starting park: \(home.shortName). Distances are straight-line estimates.")
            return best.flatMap { park in model.nights(park,from:model.tonight(park),count:3).map { night in lookup.describe(night)+". "+model.alertSummary(park) } }+[start]
        case .learn(let essay): return [String(essay.content.prefix(6500))]
        }
    }
    /// Questions the tools can answer, for an empty page.
    private var suggestions:[String] {
        switch mode {
        case .planning: [String(localized:"Best night at Arches this month"),String(localized:"Darkest park within 300 mi of Denver this weekend"),String(localized:"When does the core rise at Big Bend tonight?")]
        case .learn: [String(localized:"Explain the main idea in plain language")]
        }
    }
    private var defaultPrompt:String {
        switch mode { case .planning:String(localized:"Which of these parks and nights looks most promising, and what is still uncertain?");case .learn:String(localized:"Explain the main idea in plain language for someone new to stargazing.") }
    }
    var body:some View {
        let shown=sent ?? records
        ScrollViewReader { proxy in
            ScrollView { VStack(alignment:.leading,spacing:22) {
                Text("Written on this iPhone from the records below. Check them before making plans.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                if !asked.isEmpty { Text(asked).font(.headline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader) }
                if !guide.lookups.isEmpty { GuideLookups(lines:guide.lookups) }
                // The streaming words live in their own view, so each new part redraws only the
                // answer, never the records below it.
                GuideAnswerBlock(guide:guide,shown:shown,lit:$lit)
                if let error=guide.error { Text(error).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if asked.isEmpty && !guide.loading { suggestionChips }
                if case .learn = mode {
                    // The source is the essay the reader just left; don't print it twice.
                    Text("Source: the essay you were reading.").font(.caption).foregroundStyle(palette.muted)
                } else {
                    let all=(shown+guide.lookedUp.map(\.text)).map { GuideRecord($0,parks:model.parks,tonight:{ model.tonight($0) }) }
                    let nights=all.map(night)
                    // One basis for every scored night is said once, above the records, not in each row.
                    let bases=Set(nights.compactMap { $0.map(GuideRecordRow.basis) })
                    let shared=bases.count == 1 && nights.compactMap({ $0 }).count>1 ? bases.first : nil
                    VStack(alignment:.leading,spacing:0) {
                        Eyebrow(text:"The records").padding(.bottom,shared == nil ? 8 : 4)
                        if let shared {
                            Text(GuideRecordRow.sharedCaption(shared)).font(.caption).foregroundStyle(palette.muted)
                                .fixedSize(horizontal:false,vertical:true).padding(.bottom,8)
                        }
                        ForEach(Array(all.enumerated()),id:\.offset) { index,record in
                            GuideRecordRow(number:index+1,record:record,night:nights[index],showsBasis:shared == nil,closure:record.park.flatMap { model.closure($0) },lit:lit==index)
                                .id("record-\(index)")
                            if index<all.count-1 { Divider().overlay(palette.line) }
                        }
                    }
                }
            }.padding(24).readableColumn() }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) } ?? (DebugScenario.isEnabled("bottom") ? .bottom : .top))
            .onChange(of:lit) { _,index in
                guard let index else { return }
                withAnimation(systemReduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("record-\(index)",anchor:.center) }
            }
        }
        .safeAreaBar(edge:.bottom) { inputBar }
        .background(NightBackground()).navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
        .task(id:requestID) {
            guard requestID>0, requestID != answeredID else {
                // Opening Ask Nyx makes and warms the session the first question will use.
                if requestID == 0 { guide.prepare(lookup:tools) }
                #if DEBUG
                if requestID == 0, let state=DebugScenario.state, state == "streaming" || state == "answered" { showFixture(checked:state == "answered") }
                #endif
                return
            }
            await guide.answer(question:asked.isEmpty ? defaultPrompt : asked,context:sent ?? records,lookup:tools)
            guard !Task.isCancelled else { return }
            answeredID=requestID
            // Said once, at the end: nothing is announced while the answer streams.
            AccessibilityNotification.Announcement(guide.error ?? String(localized:"Answer checked")).post()
        }
    }
    #if DEBUG
    /// `-nyx-state streaming|answered`: a question with real lookups from the engine (best nights
    /// and what's up at Arches) and sample words built from those records' own figures, as they
    /// look mid-stream (muted) or checked. DEBUG only; the model is never imitated in a build.
    private func showFixture(checked:Bool) {
        let today=TripDay(model.today).iso
        let best=lookup.bestNights(park:"Arches",from:today,nights:30,limit:3)
        let tonight=lookup.whatsUp(park:"Arches",on:today).prefix(1)
        let found=best+tonight
        let records=records
        guard let first=found.first.map({ GuideRecord($0,parks:model.parks,tonight:{ model.tonight($0) }) }), let park=first.park, let night=first.night, let score=first.score else { return }
        let words="The best of the next 30 nights at Arches is \(park.dayLabel(night)), at \(score) out of 100, \(first.band ?? ""). Check the clouds and park alerts again closer to the night."
        let shown=checked ? words : String(words.prefix(words.count*3/5))
        asked=suggestions[0]; sent=records
        guide.showFixture(text:shown,citations:[records.count],lookups:[lookup.bestNightsLookup(park:"Arches",from:today,nights:30),lookup.whatsUpLookup(park:"Arches",on:today)],
                          lookedUp:found.enumerated().map { (records.count+$0.offset,$0.element) },checked:checked)
    }
    #endif
    /// Planning gets tools that call the engine; explainers reason over their records only.
    private var tools:NightLookup? { mode.isPlanning ? lookup : nil }
    /// The night a scored park record is about, as Nyx scores it, for the row's Moon and basis.
    private func night(_ record:GuideRecord)->Night? {
        guard record.score != nil, let park=record.park, let night=record.night else { return nil }
        return model.night(park,on:night)
    }
    private func ask(_ text:String) {
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, !guide.loading else { return }
        asked=trimmed; question=""; typing=false; lit=nil; sent=records; requestID+=1
    }
    /// A glass bar floating over the night, pinned to the bottom; solid where glass would cost contrast.
    private var inputBar:some View {
        let shape=RoundedRectangle(cornerRadius:24,style:.continuous)
        let solid=reduceTransparency || palette.nightVision || palette.highContrast
        return HStack(alignment:.bottom,spacing:10) {
            TextField(mode.isPlanning ? "Ask about parks and nights" : "Ask about this essay",text:$question,axis:.vertical)
                .lineLimit(1...4).focused($typing).submitLabel(.send)
                .onSubmit { ask(question) }
                .padding(.vertical,8)
            Button { ask(question) } label:{ Image(systemName:"arrow.up.circle.fill").font(.title).foregroundStyle(palette.accent) }
                .buttonStyle(.plain).frame(minWidth:44,minHeight:44)
                .disabled(question.trimmingCharacters(in:.whitespaces).isEmpty || guide.loading || records.isEmpty)
                .accessibilityLabel("Ask").accessibilityInputLabels([Text("Ask"),Text("Send")])
        }
        .padding(.leading,18).padding(.trailing,6)
        .background { if solid { shape.fill(palette.nightVision ? Color.black : palette.panel) } }
        .glassEffect(solid ? .identity : .regular.tint(palette.panel.opacity(0.5)).interactive(),in:shape)
        .overlay(shape.stroke(palette.line,lineWidth:0.5))
        .padding(.horizontal,16).padding(.bottom,8)
        .frame(maxWidth:WideLayout.readableWidth).frame(maxWidth:.infinity)
    }
    private var suggestionChips:some View {
        VStack(alignment:.leading,spacing:10) {
            Text("Try asking").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
            FlowLayout(spacing:8) {
                ForEach(suggestions,id:\.self) { text in
                    Button { ask(text) } label:{ chip(Text(text)) }.buttonStyle(.plain).disabled(records.isEmpty)
                }
            }
        }
    }
    private func chip(_ text:Text)->some View { GuideChip(text:text) }
}
private extension GuideMode { var isPlanning:Bool { if case .planning = self { true } else { false } } }

/// The answer as it arrives: the constellation loader until the first checked words, the words
/// muted while they stream, then starlight with "Checked against the records" and one chip per
/// cited record. It reads the guide's streaming text itself, so only this view redraws with each
/// new part, never the records.
private struct GuideAnswerBlock: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let guide:OnDeviceGuide
    let shown:[String]
    @Binding var lit:Int?
    var body: some View {
        if guide.loading && guide.text.isEmpty { ConstellationLoader().frame(maxWidth:.infinity) }
        if !guide.text.isEmpty {
            // Muted while it streams, each part already checked against the records; starlight
            // once the whole answer has passed. VoiceOver reads it only then, and no live region
            // speaks the words as they come.
            Text(guide.text).font(.system(.body,design:.serif)).lineSpacing(6).foregroundStyle(guide.checked ? palette.ink : palette.muted)
                .fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                .accessibilityHidden(!guide.checked)
                .animation(systemReduceMotion ? nil : NyxMotion.spring,value:guide.checked)
            if guide.checked || guide.loading { status }
            if guide.checked { citationChips }
        }
    }
    /// Where the answer stands, for every reader: still being checked while it streams (the one
    /// thing VoiceOver finds then, never announced), checked once it has passed. In night vision,
    /// where muted and starlight are the same red, this line is how the answer shows its work.
    private var status:some View {
        HStack(alignment:.center,spacing:6) {
            if guide.checked { Image(systemName:"checkmark.seal").foregroundStyle(palette.accent) }
            else { ProgressView().controlSize(.mini).tint(palette.muted) }
            Text(guide.checked ? "Checked against the records" : "Checking the answer against the records")
                .fixedSize(horizontal:false,vertical:true)
        }
        .font(.caption).foregroundStyle(palette.muted)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(guide.checked ? Text("Checked against the records") : Text("Checking the answer against the records"))
    }
    /// One chip per cited record: "1 · Arches, Fri, Oct 9". A tap finds the record below.
    private var citationChips:some View {
        let all=shown+guide.lookedUp.map(\.text)
        return VStack(alignment:.leading,spacing:8) {
            Text("Sources").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
            FlowLayout(spacing:8) {
                ForEach(guide.citations,id:\.self) { id in
                    let record=all.indices.contains(id) ? GuideRecord(all[id],parks:model.parks,tonight:{ model.tonight($0) }) : nil
                    Button { lit=id; Task { try? await Task.sleep(for:.seconds(2)); if lit==id { lit=nil } } } label:{ GuideChip(text:Text(record?.chip(number:id+1) ?? String(localized:"Record \(id+1)"))) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows this record below.")
                }
            }
        }
    }
}
/// A suggestion or citation chip: accent words in a hairline capsule, at least 44 pt tall.
private struct GuideChip: View {
    @Environment(\.nyx) private var palette
    let text:Text
    var body: some View {
        text.font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.leading)
            .padding(.vertical,8).padding(.horizontal,14).frame(minHeight:44)
            .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
            .contentShape(Capsule())
    }
}
/// A record as the model saw it ("Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine; …"),
/// read back into Nyx's own row: the park, the night, the score, and one line for the rest.
struct GuideRecord: Equatable {
    let park:Park?
    let night:Date?
    let score:Int?
    let band:String?
    let line:String
    /// A "parks near" record's distance ("220 miles straight-line from Denver, CO"): its second
    /// part, after "Arches, UT". Nil for every other record.
    let detail:String?
    init(_ text:String,parks:[Park],tonight:(Park)->Date) {
        let parts=text.components(separatedBy:"; ").map { $0.trimmingCharacters(in:.whitespaces) }
        // The longest name the record starts with, so "Sequoia" never claims "Sequoia and Kings Canyon".
        let park=parks.filter { text.hasPrefix($0.shortName) }.max { $0.shortName.count<$1.shortName.count }
        self.park=park
        let iso=text.firstMatch(of:/\d{4}-\d{2}-\d{2}/).map { String($0.output) }
        if let park, let day=iso.flatMap(TripDay.init(iso:)) { night=day.evening(in:park) }
        else if let park, text.contains("tonight") || text.contains("Tonight") { night=tonight(park) }
        else { night=nil }
        let scored=text.firstMatch(of:/(\d{1,3})\/100 ?([^;.]*)/)
        score=scored.flatMap { Int($0.output.1) }
        band=scored.map { String($0.output.2).trimmingCharacters(in:.whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let rest=parts.enumerated().filter { index,part in
            // The park's own name (or "Arches, UT") is the row's title, not part of its line.
            if index==0 && park != nil && !part.contains(":") { return false }
            if part.contains("/100") { return false }
            if index==1 && (iso.map { part.contains($0) } ?? false) { return false }
            return true
        }.map(\.element)
        line=rest.joined(separator:" · ")
        detail=park != nil && parts.count>1 && parts[0].contains(",") && !parts[1].contains("/100") ? parts[1] : nil
    }
    /// The chip's words: the record's number, park and night.
    func chip(number:Int)->String {
        guard let park else { return String(localized:"Record \(number)") }
        guard let night else { return "\(number) · \(park.shortName)" }
        return "\(number) · \(park.shortName), \(park.dayLabel(night))"
    }
}
/// One record as a compact row: its number (the citations name it), park and night, a score chip,
/// and one line. A park's scored night speaks Nyx: what its clouds rest on (unless every record
/// shares it, said once above the records), the Moon's phase and how much of it is lit, and the
/// park's closure. The model's own wording of the record stays the model's input, never the row.
/// Other records (a starting point, a sky event) keep their line. A record about a park's night
/// opens that night.
struct GuideRecordRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let number:Int
    let record:GuideRecord
    var night:Night?=nil
    var showsBasis=true
    var closure:String?=nil
    var lit=false
    /// What a night's clouds rest on, in the app's short words.
    static func basis(_ night:Night)->String {
        switch night.basis {
        case .forecast: String(localized:"\(Int((night.cloudCover ?? 0).rounded()))% cloud forecast")
        case .blended: String(localized:"\(Int((night.cloudCover ?? 0).rounded()))% cloud forecast, an early look")
        case .usual: String(localized:"No cloud forecast yet")
        }
    }
    /// The Moon beside its percentage. Below 5% lit the phase symbol's crescent would read as a
    /// third of the disc beside "2% lit", so the row draws the new Moon's outline there.
    /// Turned for the southern sky, as `MoonSymbol` is.
    static func moonGlyph(_ night:Night)->some View {
        let moon=night.sky.moon
        let south=night.park.latitude<0 ? -1.0 : 1.0
        return Image(systemName:Int((moon.illumination*100).rounded())<5 ? "moonphase.new.moon" : moon.symbolName).scaleEffect(x:south,y:south)
    }
    /// The basis said once above the records.
    static func sharedCaption(_ basis:String)->String {
        basis == String(localized:"No cloud forecast yet") ? String(localized:"No cloud forecast yet · usual clouds for the month") : basis
    }
    var body: some View {
        Group {
            if let park=record.park {
                NavigationLink { ParkDetailView(park:park,initialDate:record.night) } label:{ content }.buttonStyle(.plain)
                    .accessibilityHint("Opens that night at the park.")
            } else { content }
        }
        .accessibilityElement(children:.combine)
    }
    /// Side by side at most sizes; at accessibility sizes the number, the lines and the score
    /// stack, so a park's name and its band are never broken mid-word.
    private var content:some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:6) {
                    badge
                    lines
                    if let score=record.score {
                        HStack(alignment:.firstTextBaseline,spacing:8) { scoreNumeral(score); bandLabel }
                            .accessibilityElement(children:.combine).accessibilityLabel(String(localized:"\(score) out of 100, \(record.band ?? "")"))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
            } else {
                HStack(alignment:.top,spacing:12) {
                    badge
                    lines
                    Spacer(minLength:8)
                    if let score=record.score {
                        VStack(alignment:.trailing,spacing:0) { scoreNumeral(score); bandLabel.multilineTextAlignment(.trailing) }
                            .accessibilityElement(children:.combine).accessibilityLabel(String(localized:"\(score) out of 100, \(record.band ?? "")"))
                    }
                }
            }
        }
        .padding(.vertical,12).padding(.horizontal,8)
        .background { if lit { RoundedRectangle(cornerRadius:14).fill(palette.accent.opacity(palette.nightVision ? 0.2 : 0.12)) } }
        .contentShape(Rectangle())
    }
    private var badge:some View {
        Text("\(number)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(palette.muted)
            .frame(minWidth:24,minHeight:24).padding(.horizontal,typeSize.isAccessibilitySize ? 8 : 0)
            .overlay(Capsule().stroke(palette.line,lineWidth:0.8)).fixedSize()
            .accessibilityLabel(String(localized:"Record \(number)"))
    }
    private var lines:some View {
        VStack(alignment:.leading,spacing:4) {
            if let park=record.park {
                Text(park.shortName).font(.system(.headline,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                if let night=record.night { Text(park.dayLabel(night)).font(.caption).foregroundStyle(palette.muted) }
            }
            if let night { nightLines(night) }
            else if !record.line.isEmpty { Text(record.line).font(.subheadline).foregroundStyle(record.park == nil ? palette.ink : palette.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 3).fixedSize(horizontal:false,vertical:true) }
        }
    }
    private func scoreNumeral(_ score:Int)->some View {
        Text("\(score)").font(.system(.title2,design:.serif,weight:.light)).foregroundStyle(palette.accent)
    }
    @ViewBuilder private var bandLabel:some View {
        if let band=record.band { Text(band).font(.caption2).foregroundStyle(palette.muted) }
    }
    /// A scored night: a "parks near" record's distance (its second part, the only thing the row
    /// cannot work out itself), the Moon and the basis, the closure, and how to get there.
    @ViewBuilder private func nightLines(_ night:Night)->some View {
        if let distance=record.detail { Text(distance).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
        let lit=Int((night.sky.moon.illumination*100).rounded())
        let line=showsBasis ? "\(String(localized:"\(lit)% lit")) · \(Self.basis(night))" : String(localized:"\(lit)% lit")
        Label { Text(line).fixedSize(horizontal:false,vertical:true) } icon:{ Self.moonGlyph(night).accessibilityHidden(true) }
            .font(.subheadline).foregroundStyle(palette.muted).labelStyle(GuideLineLabelStyle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(showsBasis ? "\(String(localized:"\(night.sky.moon.name), \(lit)% lit")). \(Self.basis(night))" : String(localized:"\(night.sky.moon.name), \(lit)% lit"))
        if let closure {
            Label { Text(closure).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:"exclamationmark.triangle").accessibilityHidden(true) }
                .font(.subheadline.weight(.medium)).foregroundStyle(palette.accent).labelStyle(GuideLineLabelStyle())
        }
        if let park=record.park { AccessNoteLabel(park:park) }
    }
}
/// An icon and its line on one baseline, the icon in a fixed column so lines align.
private struct GuideLineLabelStyle: LabelStyle {
    @ScaledMetric(relativeTo:.subheadline) private var column=18
    func makeBody(configuration:Configuration)->some View {
        HStack(alignment:.firstTextBaseline,spacing:6) { configuration.icon.frame(width:column); configuration.title }
    }
}
/// What Ask Nyx looked up for this answer, one line per lookup as it happens, in the tool's own
/// terms: "Best nights · Arches · 30 nights from Oct 9". One VoiceOver element whose value grows,
/// never a new stop for each lookup.
struct GuideLookups: View {
    @Environment(\.nyx) private var palette
    let lines:[String]
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("Looked up").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
            ForEach(Array(lines.enumerated()),id:\.offset) { _,line in
                Label { Text(line).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:"magnifyingglass") }
                    .font(.footnote).foregroundStyle(palette.muted).labelStyle(GuideLineLabelStyle())
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(Text("Looked up"))
        .accessibilityValue(lines.joined(separator:". "))
    }
}
/// Chips that wrap onto as many lines as they need, left to right.
struct FlowLayout: Layout {
    var spacing:Double=8
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let rows=arrange(width:proposal.width ?? .infinity,subviews:subviews)
        return CGSize(width:rows.map(\.width).max() ?? 0,height:rows.reduce(0) { $0+$1.height }+spacing*Double(max(0,rows.count-1)))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        var y=bounds.minY
        for row in arrange(width:bounds.width,subviews:subviews) {
            var x=bounds.minX
            for index in row.items {
                let size=subviews[index].sizeThatFits(ProposedViewSize(width:bounds.width,height:nil))
                subviews[index].place(at:CGPoint(x:x,y:y),proposal:ProposedViewSize(width:min(size.width,bounds.width),height:size.height))
                x+=min(size.width,bounds.width)+spacing
            }
            y+=row.height+spacing
        }
    }
    private struct Row { var items:[Int]=[]; var width=0.0; var height=0.0 }
    private func arrange(width:Double,subviews:Subviews)->[Row] {
        var rows:[Row]=[Row()]
        for index in subviews.indices {
            let size=subviews[index].sizeThatFits(ProposedViewSize(width:width,height:nil)), w=min(size.width,width)
            if !rows[rows.count-1].items.isEmpty, rows[rows.count-1].width+spacing+w>width { rows.append(Row()) }
            var row=rows[rows.count-1]
            row.width+=(row.items.isEmpty ? 0 : spacing)+w; row.height=max(row.height,size.height); row.items.append(index)
            rows[rows.count-1]=row
        }
        return rows.filter { !$0.items.isEmpty }
    }
}
#Preview("Ask Nyx") { NavigationStack { GuideView(mode:.planning) }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Lookups") {
    GuideLookups(lines:["Best nights · Arches · 30 nights from Oct 9","What's up · Arches · Oct 9","Parks near · Joshua Tree · within 200 mi"]).padding().background(.black).preferredColorScheme(.dark)
}
#Preview("Ask Nyx AX5") { NavigationStack { GuideView(mode:.planning) }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
