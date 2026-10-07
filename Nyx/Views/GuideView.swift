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
        let shown=records
        ScrollViewReader { proxy in
            ScrollView { VStack(alignment:.leading,spacing:22) {
                Text("Written on this iPhone from the records below. Check them before making plans.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                if !asked.isEmpty { Text(asked).font(.headline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader) }
                if guide.loading { ConstellationLoader().frame(maxWidth:.infinity) }
                if !guide.text.isEmpty {
                    Text(guide.text).font(.system(.body,design:.serif)).lineSpacing(6).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
                    citationChips(shown,proxy:proxy)
                }
                if let error=guide.error { Text(error).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if asked.isEmpty && !guide.loading { suggestionChips }
                if case .learn = mode {
                    // The source is the essay the reader just left; don't print it twice.
                    Text("Source: the essay you were reading.").font(.caption).foregroundStyle(palette.muted)
                } else {
                    VStack(alignment:.leading,spacing:0) {
                        Eyebrow(text:"The records").padding(.bottom,8)
                        let all=shown+guide.lookedUp.map(\.text)
                        ForEach(Array(all.enumerated()),id:\.offset) { index,record in
                            GuideRecordRow(number:index+1,record:GuideRecord(record,parks:model.parks,tonight:{ model.tonight($0) }),lit:lit==index)
                                .id("record-\(index)")
                            if index<all.count-1 { Divider().overlay(palette.line) }
                        }
                    }
                }
            }.padding(24).readableColumn() }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of:lit) { _,index in
                guard let index else { return }
                withAnimation(systemReduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("record-\(index)",anchor:.center) }
            }
        }
        .safeAreaBar(edge:.bottom) { inputBar }
        .background(NightBackground()).navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
        .task(id:requestID) {
            guard requestID>0 else { return }
            // Planning gets tools that call the engine; explainers reason over their records only.
            var tools:NightLookup?
            if case .planning = mode { tools=lookup }
            await guide.answer(question:asked.isEmpty ? defaultPrompt : asked,context:records,lookup:tools)
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(guide.error ?? String(localized:"Answer ready")).post()
        }
    }
    private func ask(_ text:String) {
        let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty, !guide.loading else { return }
        asked=trimmed; question=""; typing=false; lit=nil; requestID+=1
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
    /// One chip per cited record: "1 · Arches, Fri, Oct 9". A tap finds the record below.
    private func citationChips(_ shown:[String],proxy:ScrollViewProxy)->some View {
        let all=shown+guide.lookedUp.map(\.text)
        return VStack(alignment:.leading,spacing:8) {
            Text("Sources").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
            FlowLayout(spacing:8) {
                ForEach(guide.citations,id:\.self) { id in
                    let record=all.indices.contains(id) ? GuideRecord(all[id],parks:model.parks,tonight:{ model.tonight($0) }) : nil
                    Button { lit=id; Task { try? await Task.sleep(for:.seconds(2)); if lit==id { lit=nil } } } label:{ chip(Text(record?.chip(number:id+1) ?? String(localized:"Record \(id+1)"))) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows this record below.")
                }
            }
        }
    }
    private func chip(_ text:Text)->some View {
        text.font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.leading)
            .padding(.vertical,8).padding(.horizontal,14).frame(minHeight:44)
            .background(Capsule().fill(palette.accent.opacity(palette.nightVision ? 0 : 0.1))).overlay(Capsule().stroke(palette.accent.opacity(0.35),lineWidth:0.5))
            .contentShape(Capsule())
    }
}
private extension GuideMode { var isPlanning:Bool { if case .planning = self { true } else { false } } }

/// A record as the model saw it ("Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine; …"),
/// read back into Nyx's own row: the park, the night, the score, and one line for the rest.
struct GuideRecord: Equatable {
    let park:Park?
    let night:Date?
    let score:Int?
    let band:String?
    let line:String
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
    }
    /// The chip's words: the record's number, park and night.
    func chip(number:Int)->String {
        guard let park else { return String(localized:"Record \(number)") }
        guard let night else { return "\(number) · \(park.shortName)" }
        return "\(number) · \(park.shortName), \(park.dayLabel(night))"
    }
}
/// One record as a compact row: its number (the citations name it), park and night, a score chip,
/// and one line. A record about a park's night opens that night.
struct GuideRecordRow: View {
    @Environment(\.nyx) private var palette
    let number:Int
    let record:GuideRecord
    var lit=false
    var body: some View {
        Group {
            if let park=record.park {
                NavigationLink { ParkDetailView(park:park,initialDate:record.night) } label:{ content }.buttonStyle(.plain)
                    .accessibilityHint("Opens that night at the park.")
            } else { content }
        }
        .accessibilityElement(children:.combine)
    }
    private var content:some View {
        HStack(alignment:.top,spacing:12) {
            Text("\(number)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(palette.muted)
                .frame(minWidth:24,minHeight:24).overlay(Circle().stroke(palette.line,lineWidth:0.8))
                .accessibilityLabel(String(localized:"Record \(number)"))
            VStack(alignment:.leading,spacing:4) {
                if let park=record.park {
                    Text(park.shortName).font(.system(.headline,design:.serif)).foregroundStyle(palette.ink)
                    if let night=record.night { Text(park.dayLabel(night)).font(.caption).foregroundStyle(palette.muted) }
                }
                if !record.line.isEmpty { Text(record.line).font(.subheadline).foregroundStyle(record.park == nil ? palette.ink : palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
            Spacer(minLength:8)
            if let score=record.score {
                VStack(alignment:.trailing,spacing:0) {
                    Text("\(score)").font(.system(.title2,design:.serif,weight:.light)).foregroundStyle(palette.accent)
                    if let band=record.band { Text(band).font(.caption2).foregroundStyle(palette.muted).multilineTextAlignment(.trailing) }
                }.accessibilityElement(children:.combine).accessibilityLabel(String(localized:"\(score) out of 100, \(record.band ?? "")"))
            }
        }
        .padding(.vertical,12).padding(.horizontal,8)
        .background { if lit { RoundedRectangle(cornerRadius:14).fill(palette.accent.opacity(palette.nightVision ? 0.2 : 0.12)) } }
        .contentShape(Rectangle())
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
#Preview("Ask Nyx AX5") { NavigationStack { GuideView(mode:.planning) }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
