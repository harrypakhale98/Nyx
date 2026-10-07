import SwiftUI
import SwiftData

enum GuideMode {
    case planning,recap,learn(Essay)
    var title:String { switch self { case .planning:String(localized:"Ask Nyx");case .recap:String(localized:"Your season under the stars");case .learn:String(localized:"Another way to see it") } }
}
struct GuideView:View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Query(sort:\JournalEntry.date,order:.reverse) private var entries:[JournalEntry]
    let mode:GuideMode
    @State private var guide=OnDeviceGuide()
    @State private var question=""
    @State private var requestID=0
    private var records:[String] {
        switch mode {
        case .planning:
            guard let home=model.home else { return [] }
            let best=Array(model.ranked(model.nearby(latitude:model.location.latitude,longitude:model.location.longitude)).prefix(3))
            return best.flatMap { park in model.nights(park,from:model.tonight(park),count:3).map { night in String(localized:"\(park.shortName); \(park.dayLabel(night.id)); score \(night.score.value)/100 \(night.score.band.label); \(NightLookup.basis(night)). \(model.alertSummary(park))") } + (park.accessNote.map { [String(localized:"\(park.shortName); getting there: \($0)")] } ?? []) } + [model.location.latitude == nil ? String(localized:"Starting park: \(home.shortName). Distances are straight-line estimates.") : String(localized:"Starting point: the device location. Distances are straight-line estimates.")]
        case .recap:
            return entries.prefix(8).map { String(localized:"\(model.park($0.parkID)?.shortName ?? String(localized:"Park")); \(model.park($0.parkID)?.dateLabel($0.date) ?? $0.date.formatted(date:.abbreviated,time:.omitted)); observed Bortle \($0.observedBortle); observation: \(String($0.notes.prefix(250)))") }
        case .learn(let essay): return [String(essay.content.prefix(6500))]
        }
    }
    private var prompt:String {
        if !question.isEmpty { return question }
        switch mode { case .planning:return String(localized:"Which of these parks and nights looks most promising, and what is still uncertain?");case .recap:return String(localized:"Reflect on patterns in these observations without inventing observations.");case .learn:return String(localized:"Explain the main idea in plain language for someone new to stargazing.") }
    }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Eyebrow(text:"An on-device perspective")
            Text(mode.title).font(.system(.largeTitle,design:.serif))
            Text("This optional explanation stays on your iPhone. Check the source records before making plans.").font(.caption).foregroundStyle(palette.muted)
            TextField("What would you like to understand?",text:$question,axis:.vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
            Button("Ask using these records") { requestID+=1 }.buttonStyle(.borderedProminent).foregroundStyle(Color.black).disabled(guide.loading || records.isEmpty)
            if guide.loading { ConstellationLoader().frame(maxWidth:.infinity) }
            if !guide.text.isEmpty { Text(guide.text).font(.system(.body,design:.serif)).lineSpacing(6); Text("Sources: \(guide.citations.map{String($0+1)}.joined(separator:", "))").font(.caption).foregroundStyle(palette.muted) }
            if !guide.lookedUp.isEmpty {
                // What the model asked the engine for: computed by Nyx, numbered after the records below.
                Eyebrow(text:"What Nyx looked up")
                ForEach(guide.lookedUp,id:\.id) { record in Panel { Text("\(record.id+1). \(record.text)").font(.subheadline) } }
            }
            if let error=guide.error { Text(error).foregroundStyle(palette.muted) }
            if case .learn = mode {
                // The source is the essay the reader just left; don't print it twice.
                Text("Source: the essay you were reading.").font(.caption).foregroundStyle(palette.muted)
            } else {
                Eyebrow(text:"The original records")
                ForEach(Array(records.enumerated()),id:\.offset) { index,record in Panel { Text("\(index+1). \(record)").font(.subheadline) } }
            }
        }.padding(24).readableColumn() }.background(NightBackground()).navigationTitle(mode.title).navigationBarTitleDisplayMode(.inline)
            .task(id:requestID) {
                guard requestID>0 else { return }
                // Planning gets tools that call the engine; recaps and explainers reason over their records only.
                var lookup:NightLookup?
                if case .planning = mode { lookup=NightLookup(parks:model.parks,forecasts:model.forecasts,now:model.today,details:model.details) }
                await guide.answer(question:prompt,context:records,lookup:lookup)
                // Focus stays on the button while the answer streams in below it, so say when it is there.
                guard !Task.isCancelled else { return }
                AccessibilityNotification.Announcement(guide.error ?? String(localized:"Answer ready")).post()
            }
    }
}
