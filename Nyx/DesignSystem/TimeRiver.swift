import SwiftUI

struct TimeRiver: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let nights: [Night]
    @Binding var selected: Date
    @State private var detent=0
    private var index:Int { nights.firstIndex(where:{$0.park.calendar.isDate($0.id,inSameDayAs:selected)}) ?? 0 }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Follow the darker nights")
            if !typeSize.isAccessibilitySize {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing:2) {
                        ForEach(Array(nights.enumerated()),id:\.element.id) { offset,night in
                            Button { choose(offset) } label: {
                                VStack(spacing:7) {
                                    Text("\(night.park.calendar.component(.day,from:night.id))").font(.caption)
                                    Canvas { context,size in
                                        let y=size.height*(1-Double(night.score.value)/110)
                                        let center=CGPoint(x:size.width/2,y:y)
                                        var line=Path();line.move(to:CGPoint(x:center.x,y:size.height));line.addLine(to:center)
                                        context.stroke(line,with:.color(palette.line),style:StrokeStyle(lineWidth:1,dash:night.score.hasForecast ? [] : [2,3]))
                                        let r=offset==index ? 5.0 : 2.8
                                        let path=Path(ellipseIn:CGRect(x:center.x-r,y:y-r,width:2*r,height:2*r))
                                        if night.score.hasForecast { context.fill(path,with:.color(palette.accent)) } else { context.stroke(path,with:.color(palette.accent),lineWidth:1.2) }
                                    }.frame(width:42,height:72)
                                    Text("\(night.score.value)").font(.caption2.monospacedDigit()).foregroundStyle(offset==index ? palette.accent : palette.muted)
                                }.padding(.vertical,8).frame(minWidth:44)
                                    .background(offset==index ? palette.panel : .clear,in:RoundedRectangle(cornerRadius:14))
                            }.buttonStyle(.plain).id(offset)
                                .accessibilityLabel("\(night.park.dayLabel(night.id)), score \(night.score.value), \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Forecast included") : String(localized:"No cloud forecast"))")
                                .accessibilityAddTraits(offset==index ? .isSelected : [])
                        }
                    }.simultaneousGesture(DragGesture(minimumDistance:10).onChanged { gesture in
                        choose(min(max(0,Int(gesture.location.x/46)),max(0,nights.count-1)))
                    })
                }.scrollIndicators(.hidden)
                    .onChange(of:index) { _,new in withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo(new,anchor:.center) } }
            }
            }
            Stepper(value:Binding(get:{index},set:choose),in:0...max(0,nights.count-1)) {
                Text(nights.isEmpty ? String(localized:"No nights available") : String(localized:"\(nights.first?.park.dayLabel(selected) ?? "") · \(nights.indices.contains(index) ? nights[index].score.value : 0)/100")).font(.subheadline).foregroundStyle(palette.ink)
            }.tint(palette.controlTint).foregroundStyle(palette.ink,palette.muted,palette.controlTint).disabled(nights.isEmpty).accessibilityLabel("Selected night").accessibilityValue("\(nights.first?.park.dayLabel(selected) ?? ""), \(nights.indices.contains(index) ? nights[index].score.value : 0) out of 100").accessibilityHint("Adjust to move one night at a time.")
            Text(typeSize.isAccessibilitySize ? (nights.indices.contains(index) && nights[index].score.hasForecast ? String(localized:"Forecast included") : String(localized:"Moon and darkness only. Clouds unknown.")) : String(localized:"Hollow stars: moon and darkness only.")).font(.caption).foregroundStyle(palette.muted)
        }.sensoryFeedback(.selection,trigger:detent)
    }
    private func choose(_ value:Int) { guard nights.indices.contains(value) else { return }; withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=nights[value].id };detent=value }
}
#Preview("River") { if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { let m=PlanModel();TimeRiver(nights:m.nights(p,from:.now,count:30),selected:.constant(.now)).padding().background(.black) } }

#Preview("Empty river") { TimeRiver(nights:[],selected:.constant(.now)).padding().background(.black) }
