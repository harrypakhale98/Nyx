import Foundation
import Testing
import SwiftUI
@testable import Nyx

/// Tonight's sky names: the IAU's names and the constellation figures (`SkyLore`, shared with the
/// Vision Pro sky) matched to the iPhone's catalogue, placed over a park, and the few the full
/// screen labels and VoiceOver reads.
@MainActor @Suite struct SkyLoreTests {
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ text:String) throws -> Date { try #require(try? Date(text,strategy:.iso8601)) }

    @Test func loreMatchesTheAppCatalogueAsOnVisionPro() {
        let lore=SkyLore.load(catalogue:SkyProjection.catalogue.map { (ra:$0.ra,dec:$0.dec,mag:$0.mag) })
        #expect(lore.stars.count==66)
        #expect(lore.figures.count==32)
        #expect(lore.figures.allSatisfy { !$0.lines.isEmpty })
        #expect(HorizonSkies.lore.stars.count==lore.stars.count)
        // Every name sits on a catalogue row as bright as it says.
        for star in lore.stars {
            let row=SkyProjection.catalogue[star.row]
            #expect(abs(row.mag-star.magnitude)<=SkyLore.magnitudeTolerance, "\(star.name)")
        }
        #expect(lore.stars.contains { $0.name=="Fomalhaut" } && lore.stars.contains { $0.name=="Sirius" })
        // An empty catalogue names nothing rather than guessing.
        #expect(SkyLore.load(catalogue:[]).stars.isEmpty)
    }

    /// Joshua Tree at 12:31 AM on October 9, 2026: Fomalhaut stands about 20° up in the
    /// south-southwest (by hand: declination −29.6°, latitude 34°, an hour and a half past its
    /// meridian), so VoiceOver hears "partway up", not "low".
    @Test func fomalhautOverJoshuaTreeInOctober() throws {
        let jotr=try park("jotr")
        let moment=try date("2026-10-09T07:31:00Z")
        let sky=HorizonSkies.shared.sky(park:jotr,night:jotr.evening(try date("2026-10-08T20:00:00Z")),at:moment)
        let fomalhaut=try #require(sky.named.first { $0.name=="Fomalhaut" })
        #expect((190...240).contains(fomalhaut.azimuth), "azimuth \(fomalhaut.azimuth)")
        #expect((15...25).contains(fomalhaut.altitude), "altitude \(fomalhaut.altitude)")
        let size=CGSize(width:402,height:874)
        let labelled=PanoramaCanvas.labelledStars(sky:sky,options:PanoramaOptions(facing:180,bortle:Double(jotr.bortleEstimate)),size:size)
        #expect(labelled.contains { $0.name=="Fomalhaut" })
        let summary=PanoramaCanvas.summary(sky:sky,facing:180,park:jotr,bortle:Double(jotr.bortleEstimate),size:size)
        #expect(summary.contains("Fomalhaut, a bright star, partway up in the \(Compass.name(fomalhaut.azimuth))."), "\(summary)")
    }

    @Test func onlyStarsAboveTheHorizonAreNamedAndNoMoreThanSix() throws {
        let jotr=try park("jotr")
        let night=jotr.evening(try date("2026-10-08T20:00:00Z"))
        let size=CGSize(width:402,height:874)
        for hour in stride(from:0.0,to:12,by:1.5) {
            let sky=HorizonSkies.shared.sky(park:jotr,night:night,at:try date("2026-10-09T02:00:00Z").addingTimeInterval(hour*3600))
            #expect(sky.named.allSatisfy { $0.altitude>0 && $0.magnitude<HorizonSkies.namedMagnitude })
            #expect(sky.figures.allSatisfy { $0.0.altitude>0 && $0.1.altitude>0 })
            #expect(zip(sky.named,sky.named.dropFirst()).allSatisfy { $0.magnitude<=$1.magnitude })
            for facing in stride(from:0.0,to:360,by:45) {
                let labelled=PanoramaCanvas.labelledStars(sky:sky,options:PanoramaOptions(facing:facing),size:size)
                #expect(labelled.count<=PanoramaCanvas.starLabels)
                #expect(labelled.allSatisfy { $0.altitude>0 })
                // A wide iPad view still names six at most.
                #expect(PanoramaCanvas.labelledStars(sky:sky,options:PanoramaOptions(facing:facing),size:CGSize(width:1376,height:1032)).count<=6)
            }
        }
        // Bright stars below the horizon at that moment are never named, on screen or aloud.
        let sky=HorizonSkies.shared.sky(park:jotr,night:night,at:try date("2026-10-09T07:31:00Z"))
        let below=HorizonSkies.lore.stars.filter { star in !sky.named.contains { $0.name==star.name } && star.magnitude<HorizonSkies.namedMagnitude }
        #expect(!below.isEmpty)
        let summary=PanoramaCanvas.summary(sky:sky,facing:180,park:jotr,bortle:2)
        for star in below { #expect(!summary.contains("\(star.name), a bright star")) }
    }

    /// The figures come in last as eyes adapt: none at the reveal's floor, all once adapted.
    @Test func figuresArriveLast() {
        let skyLimit=6.85
        let floorLimit=PanoramaCanvas.adaptedLimit(skyLimit,adaptation:SkyAdaptation.floor)
        #expect(PanoramaCanvas.figuresArrived(limit:floorLimit,skyLimit:skyLimit)==0)
        #expect(PanoramaCanvas.figuresArrived(limit:PanoramaCanvas.adaptedLimit(skyLimit,adaptation:0.7),skyLimit:skyLimit)==0)
        #expect(PanoramaCanvas.figuresArrived(limit:skyLimit,skyLimit:skyLimit)==1)
        #expect(PanoramaCanvas.milkyWayGathered(0.85)>0 && PanoramaCanvas.figuresArrived(limit:PanoramaCanvas.adaptedLimit(skyLimit,adaptation:0.85),skyLimit:skyLimit)<1)
    }
}
