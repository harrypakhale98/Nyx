import SwiftUI

extension ParkDetailView {
    // MARK: The sky

    func chapterHeading(_ chapter:ParkChapter,detail:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Eyebrow(text:"\(detail)",meta:true)
            Text(chapter.title).font(.system(.title,design:.serif)).foregroundStyle(palette.ink).accessibilityAddTraits(.isHeader)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
    }
    /// The sky chapter shows `skyNight`: the river's night, held while it is scrubbed (`heldNight`).
    @ViewBuilder var skyChapter: some View {
        let night=skyNight, isTonight=night.id==model.tonight(park), outlook=model.outlook(night)
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
                    let options=FieldNight.alarmOptions(park:park,sky:night.sky,at:model.present)
                    if !options.isEmpty { Divider().overlay(palette.line); FieldAlarmRows(park:park,options:options,showsHeading:true) }
                }
            }
        }.id("whatsup")
        Panel {
            VStack(alignment:.leading,spacing:18) {
                Eyebrow(text:"Moonlight")
                MoonHero(night:night) { delta in step(delta) }
                // The glance words: the full sentence is the verdict's, under the dial.
                if night.sky.darkHours>0, case let line=night.sky.moonShort(park:park) {
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
            if let air=outlook?.airLabel {
                VStack(alignment:.leading,spacing:6) {
                    LabeledContent("Air",value:air)
                    if let crisp=outlook?.crispText { Text(crisp).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                    Text("Smoke, dust and haze forecast from Copernicus (CAMS), the European atmosphere service. Thick smoke, dust or haze caps the score.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            } else {
                if let crisp=outlook?.crispText { Text(crisp).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                if let haze=outlook?.hazeText { Text(haze).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
            // The credit Open-Meteo's licence asks for, as a link beside its data.
            if let updated=night.forecastUpdated { OpenMeteoCredit(updated:park.timestamp(updated)) }
            if !nightItself.isEmpty {
                Divider().overlay(palette.line)
                VStack(alignment:.leading,spacing:10) {
                    Eyebrow(text:"The night itself")
                    ForEach(nightItself,id:\.text) { line in
                        Label { Text(line.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:line.symbol).foregroundStyle(palette.ink).accessibilityHidden(true) }
                            .font(.subheadline).foregroundStyle(palette.ink)
                    }
                }
            }
        } }
    }
    /// Agreement and the cloud layer, under the cloud figure.
    private var cloudContext:[String] {
        let night=skyNight
        guard let outlook=model.outlook(night) else { return [] }
        return [outlook.agreement?.sentence(tonight:night.id==model.tonight(park)),night.upperCloudOnly ? nil : outlook.layers?.note].compactMap { $0 }
    }
    /// The cloud figure beside "Clouds": the forecast's average, else the park's usual cloud.
    private var cloudValue:String {
        let night=skyNight
        if let cloud=night.cloudCover { return String(localized:"\(Int(cloud.rounded()))% average") }
        if let usual=night.usualCloud { return String(localized:"Usually \(Int(usual.rounded()))%") }
        return String(localized:"Unavailable")
    }
    /// What to expect and bring, one short line each: rain, snow or storms, fog, the coldest hour,
    /// dew on optics, and wind. Lines with no data are left out; with none, the section is not shown.
    private var nightItself:[(symbol:String,text:String)] {
        // Past the forecast's hourly detail: the month's usual night (ERA5), said as usual, never as a forecast.
        guard let outlook=model.outlook(skyNight), outlook.coldest != nil else {
            let month=park.calendar.component(.month,from:skyNight.id)
            guard let usual=NightClimate.shared.lines(park,month:month) else { return [] }
            return [("thermometer.low",usual.temperatures)]+(usual.dew.map { [("drop",$0)] } ?? [])
        }
        let cold=outlook.coldest.map { cold in
            outlook.coldestAt.map { String(localized:"Down to \(NightOutlook.temperature(cold)) around \(park.time($0))") } ?? String(localized:"Down to \(NightOutlook.temperature(cold))")
        }
        let lines:[(String,String?)]=[(outlook.precipitationLine?.symbol ?? "cloud.rain",outlook.precipitationLine?.text),("cloud.fog",outlook.fogText),
                                      ("thermometer.low",cold),("drop",outlook.dewLikely ? String(localized:"Dew likely on lenses") : nil),("wind",outlook.gustText)]
        return lines.compactMap { symbol,text in text.map { (symbol,$0) } }
    }
}
