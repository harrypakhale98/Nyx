import SwiftUI

extension ParkDetailView {
    // MARK: The sky

    func chapterHeading(_ chapter:ParkChapter,detail:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Eyebrow(text:"\(detail)")
            Text(chapter.title).font(.system(.title,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
    }
    @ViewBuilder var skyChapter: some View {
        chapterHeading(.sky,detail:park.dayLabel(night.id))
        SkyWindowCard(night:night,isTonight:isTonight) { showsSky=true }
        Panel { VStack(alignment:.leading,spacing:16) {
            SkyArc(night:night,isTonight:isTonight,core:model.whatsUp(night).core)
            Divider().overlay(palette.line)
            SoundAndTouchRow(night:night,isTonight:isTonight,expanded:DebugScenario.isEnabled("listen"))
        } }.id("sky")
        Panel {
            VStack(alignment:.leading,spacing:18) {
                WhatsUpPanel(whatsUp:model.whatsUp(night),isTonight:isTonight,notes:model.skyNotes(night))
                // Tonight's wake-ups (AlarmKit), beside the moments they are for.
                if FieldAlarms.supported, isTonight {
                    let options=FieldNight.alarmOptions(park:park,sky:night.sky,at:DebugScenario.date ?? .now)
                    if !options.isEmpty { Divider().overlay(palette.line); FieldAlarmRows(park:park,options:options,showsHeading:true) }
                }
            }
        }.id("whatsup")
        Panel {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:"Moonlight")
                MoonHero(night:night) { delta in step(delta) }
                if let line=night.sky.moonBelowLine {
                    Text(line).font(.caption).foregroundStyle(palette.muted).frame(maxWidth:.infinity)
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.id("moon")
        Panel { VStack(alignment:.leading,spacing:16) {
            Eyebrow(text:"Clouds and the air")
            VStack(alignment:.leading,spacing:6) {
                LabeledContent("Clouds",value:cloudValue)
                if night.upperCloudOnly { Text("The summit sits above most low cloud, so the score counts mid and high cloud only.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                ForEach(cloudContext,id:\.self) { line in Text(line).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
            if let clarity=outlook?.clarity {
                VStack(alignment:.leading,spacing:6) {
                    LabeledContent("Air",value:clarity.label)
                    Text("Smoke and haze forecast from Copernicus (CAMS), the European atmosphere service. Not part of the score.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            } else if let haze=outlook?.hazeText { Text(haze).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let updated=night.forecastUpdated { Text("Open-Meteo · updated \(park.timestamp(updated))").font(.caption).foregroundStyle(palette.muted) }
            if !nightItself.isEmpty {
                Divider().overlay(palette.line)
                VStack(alignment:.leading,spacing:10) {
                    Eyebrow(text:"The night itself")
                    ForEach(nightItself,id:\.text) { line in
                        Label { Text(line.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:line.symbol).foregroundStyle(palette.accent).accessibilityHidden(true) }
                            .font(.subheadline).foregroundStyle(palette.ink)
                    }
                }
            }
        } }
    }
    /// Agreement and the cloud layer, under the cloud figure.
    private var cloudContext:[String] {
        guard let outlook else { return [] }
        return [outlook.agreement?.sentence(tonight:isTonight),night.upperCloudOnly ? nil : outlook.layers?.note].compactMap { $0 }
    }
    /// The cloud figure beside "Clouds": the forecast's average, else the park's usual cloud.
    private var cloudValue:String {
        if let cloud=night.cloudCover { return String(localized:"\(Int(cloud.rounded()))% average") }
        if let usual=night.usualCloud { return String(localized:"Usually \(Int(usual.rounded()))%") }
        return String(localized:"Unavailable")
    }
    /// What to bring, one short line each: the coldest hour, dew on optics, and wind. Lines with
    /// no data are left out; with none, the section is not shown.
    private var nightItself:[(symbol:String,text:String)] {
        guard let outlook else { return [] }
        let cold=outlook.coldest.map { cold in
            outlook.coldestAt.map { String(localized:"Down to \(NightOutlook.temperature(cold)) around \(park.time($0))") } ?? String(localized:"Down to \(NightOutlook.temperature(cold))")
        }
        let lines:[(String,String?)]=[("thermometer.low",cold),("drop",outlook.dewLikely ? String(localized:"Dew likely on lenses") : nil),("wind",outlook.gustText)]
        return lines.compactMap { symbol,text in text.map { (symbol,$0) } }
    }
}
