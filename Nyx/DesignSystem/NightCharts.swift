import SwiftUI
import Accessibility

/// Audio Graphs for Nyx's drawn charts. VoiceOver's rotor offers "Audio Graph" on the time river,
/// the calendar's month and the shape of the night: a tone that rises and falls with the data,
/// plus a spoken summary and each point's label. The data is mapped here, plainly, so tests can
/// check it; `NightChartDescriptor` hands it to the system.
nonisolated struct NightChart: Sendable {
    struct Point: Sendable, Equatable {
        let x: Double
        let y: Double?
        let label: String?
    }
    struct Series: Sendable, Equatable {
        let name: String
        let continuous: Bool
        let points: [Point]
    }
    struct Axis: Sendable {
        let title: String
        let range: ClosedRange<Double>
        let gridlines: [Double]
        let describe: @Sendable (Double) -> String
    }
    let title: String
    let summary: String
    let x: Axis
    let y: Axis
    let series: [Series]

    // MARK: Nights

    /// Darkness score by night: the river's thirty nights or a calendar month. Nights without a
    /// cloud forecast are labelled as estimates; where three forecast models disagree, two more
    /// series give the clearest and cloudiest models' scores, so the spread can be heard too.
    static func nights(_ nights:[Night],title:String,outlooks:[Date:NightOutlook]=[:],events:[Date:String]=[:])->NightChart {
        let labels=nights.map { $0.park.dayLabel($0.id) }
        let points=nights.indices.map { i in
            let night=nights[i]
            var parts=[night.score.hasForecast ? night.score.band.label : String(localized:"Estimate, moon and darkness only")]
            if let event=events[night.id] { parts.append(event) }
            return Point(x:Double(i),y:Double(night.score.value),label:parts.joined(separator:". "))
        }
        var series=[Series(name:String(localized:"Darkness score"),continuous:true,points:points)]
        let ranged=nights.indices.compactMap { i in outlooks[nights[i].id]?.scoreRange.flatMap { $0.upperBound>$0.lowerBound ? (i,$0) : nil } }
        if !ranged.isEmpty {
            series.append(Series(name:String(localized:"Clearest forecast model"),continuous:false,points:ranged.map { Point(x:Double($0.0),y:Double($0.1.upperBound),label:nil) }))
            series.append(Series(name:String(localized:"Cloudiest forecast model"),continuous:false,points:ranged.map { Point(x:Double($0.0),y:Double($0.1.lowerBound),label:nil) }))
        }
        return NightChart(title:title,summary:summary(nights),
            x:Axis(title:String(localized:"Night"),range:0...Double(max(1,nights.count-1)),gridlines:stride(from:0,to:Double(nights.count),by:7).map { $0 }) { value in
                let i=Int(value.rounded()); return labels.indices.contains(i) ? labels[i] : ""
            },
            y:Axis(title:String(localized:"Darkness score, out of 100"),range:0...100,gridlines:[40,60,75,90]) { value in
                String(localized:"\(Int(value.rounded())) out of 100")
            },
            series:series)
    }
    /// The best night, how many are estimates, and the best band reached.
    static func summary(_ nights:[Night])->String {
        guard let best=nights.max(by:{ $0.score.value<$1.score.value || ($0.score.value==$1.score.value && $0.id>$1.id) }) else { return String(localized:"No nights available") }
        let estimates=nights.filter { !$0.score.hasForecast }.count
        let first=String(localized:"Best night: \(best.park.dayLabel(best.id)), \(best.score.value) out of 100, \(best.score.band.label).")
        let second=estimates==0 ? String(localized:"Every night includes a cloud forecast.")
            : estimates==nights.count ? String(localized:"No night has a cloud forecast yet; scores are moon and darkness only.")
            : String(localized:"\(estimates) of \(nights.count) nights have no cloud forecast yet.")
        return first+" "+second
    }

    // MARK: The shape of the night

    /// The Sun, the Moon and the Milky Way's core, in degrees above or below the horizon, from an
    /// hour before sunset to an hour after sunrise, every 15 minutes, in park-local time.
    static func sky(_ night:Night,window:(start:Date,end:Date),step:TimeInterval=900,summary:String)->NightChart {
        let engine=AstronomyEngine(), park=night.park, start=window.start
        let span=max(step,window.end.timeIntervalSince(start))
        let times=stride(from:0,through:span,by:step).map { start.addingTimeInterval($0) }
        func hours(_ date:Date)->Double { date.timeIntervalSince(start)/3600 }
        let sun=times.map { Point(x:hours($0),y:engine.solarAltitude(at:$0,park:park).rounded(),label:nil) }
        let moon=times.map { Point(x:hours($0),y:engine.lunarAltitude(at:$0,park:park).rounded(),label:nil) }
        let core=times.map { Point(x:hours($0),y:engine.horizontal(date:$0,park:park,ra:SkyAlmanac.coreRA,dec:SkyAlmanac.coreDec).altitude.rounded(),label:nil) }
        let lit=Int((night.sky.moon.illumination*100).rounded())
        return NightChart(title:String(localized:"Sun, Moon and Milky Way core heights, \(park.dayLabel(night.id))"),summary:summary,
            x:Axis(title:String(localized:"Time in \(park.timeZoneName)"),range:0...span/3600,gridlines:stride(from:0,through:span/3600,by:3).map { $0 }) { value in
                park.time(start.addingTimeInterval(value*3600))
            },
            y:Axis(title:String(localized:"Height above the horizon, degrees"),range:-90...90,gridlines:[-18,0,30,60]) { value in
                let degrees=Int(value.rounded())
                return degrees>=0 ? String(localized:"\(degrees)° up") : String(localized:"\(-degrees)° below the horizon")
            },
            series:[Series(name:String(localized:"Sun"),continuous:true,points:sun),
                    Series(name:String(localized:"Moon, \(lit)% lit"),continuous:true,points:moon),
                    Series(name:String(localized:"Milky Way core"),continuous:true,points:core)])
    }
}

/// Hands a `NightChart` to VoiceOver, built only when VoiceOver asks for it.
nonisolated struct NightChartDescriptor: AXChartDescriptorRepresentable {
    let make: @Sendable ()->NightChart
    func makeChartDescriptor()->AXChartDescriptor {
        let chart=make()
        let x=AXNumericDataAxisDescriptor(title:chart.x.title,range:chart.x.range,gridlinePositions:chart.x.gridlines,valueDescriptionProvider:chart.x.describe)
        let y=AXNumericDataAxisDescriptor(title:chart.y.title,range:chart.y.range,gridlinePositions:chart.y.gridlines,valueDescriptionProvider:chart.y.describe)
        let series=chart.series.map { series in
            AXDataSeriesDescriptor(name:series.name,isContinuous:series.continuous,dataPoints:series.points.map { AXDataPoint(x:$0.x,y:$0.y,label:$0.label) })
        }
        return AXChartDescriptor(title:chart.title,summary:chart.summary,xAxis:x,yAxis:y,additionalAxes:[],series:series)
    }
}
extension View {
    /// An Audio Graph for VoiceOver; `make` runs only when VoiceOver asks for the chart.
    func nightChart(_ make:@escaping @Sendable ()->NightChart)->some View { accessibilityChartDescriptor(NightChartDescriptor(make:make)) }
}
