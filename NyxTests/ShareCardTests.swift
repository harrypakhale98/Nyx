import Foundation
import Testing
import SwiftUI
@testable import Nyx

/// The share card: its spoken summary carries everything the picture shows, the exported image is
/// drawn in starlight whatever the app's palette, and small Moons keep a visible limb.
@MainActor @Suite struct ShareCardTests {
    let engine=AstronomyEngine()
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func night(_ park:Park,_ day:String,score:Int=94) throws -> Night {
        let date=try #require(try? Date(day+"T20:00:00Z",strategy:.iso8601))
        let sky=engine.conditions(for:park,on:park.evening(date))
        return Night(park:park,sky:sky,score:DarknessScore(value:score,moonPoints:36,cloudPoints:25,bortlePoints:18,lengthPoints:15),cloudCover:5,forecastUpdated:.now)
    }

    @Test func summaryCarriesScoreBandParkDateAndRange() throws {
        let jotr=try park("jotr"), night=try night(jotr,"2026-10-16")
        let card=ShareCard(night:night,why:"Moon-free for 70% of true darkness",range:88...97)
        let summary=card.summary
        #expect(summary.contains("94 out of 100"))
        #expect(summary.contains(night.score.band.label))
        #expect(summary.contains(jotr.shortName))
        #expect(summary.contains(jotr.dayLabel(night.id)))
        #expect(summary.contains("Forecast models: 88 to 97."))
        #expect(summary.contains("Moon-free for 70% of true darkness."))
        // The basis line always travels, so a shared number is never more certain than the app.
        #expect(summary.contains("Forecast included"))
        #expect(card.message.contains(summary))
        #expect(ShareCard.rangeLine(88...97)=="Forecast models: 88–97")
        let plain=ShareCard(night:night).summary
        #expect(!plain.contains("Forecast models"))
    }
    @Test func summaryNamesTheMoonAsDrawn() throws {
        let jotr=try park("jotr")
        // A crescent well past 5% is drawn, and the summary gives its phase and light.
        let crescent=try night(jotr,"2026-10-16")
        #expect(crescent.sky.moon.illumination>=ShareCard.moonDrawnFrom)
        let card=ShareCard(night:crescent)
        #expect(card.summary.contains("\(crescent.sky.moon.name), \(ShareCard.percent(crescent))% lit."))
        #expect(card.dateLine==jotr.dayLabel(crescent.id))
        // At new moon no disc is drawn; the date line and the summary say it in words.
        let new=try night(jotr,"2026-10-10")
        #expect(new.sky.moon.illumination<ShareCard.moonDrawnFrom)
        let dark=ShareCard(night:new)
        if new.sky.moon.name=="New moon" {
            #expect(dark.dateLine==jotr.dayLabel(new.id)+" · New moon")
            #expect(dark.summary.contains("New moon."))
        } else {
            #expect(dark.dateLine.hasSuffix("% lit"))
        }
    }
    /// The exported PNG is starlight even in night vision (the amber numeral keeps its green); the
    /// preview drawn in the night palette is red (no green to speak of).
    @Test func exportIsStarlightAndPreviewFollowsThePalette() throws {
        let jotr=try park("jotr"), night=try night(jotr,"2026-10-16")
        let red=NyxPalette(nightVision:true,highContrast:false)
        let export=ShareArtwork(night:night,shape:.card,why:nil,range:nil,palette:nil,scale:1)
        let preview=ShareArtwork(night:night,shape:.card,why:nil,range:nil,palette:red,scale:1)
        #expect(export.key != preview.key)
        #expect(export.key==ShareArtwork(night:night,shape:.card,why:nil,range:nil,palette:nil,scale:1).key)
        #expect(export.key != ShareArtwork(night:night,shape:.card,why:nil,range:80...94,palette:nil,scale:1).key)
        func greenest(_ artwork:ShareArtwork) throws -> Int {
            let image=try #require(artwork.image()?.cgImage)
            let w=image.width, h=image.height
            let context=try #require(CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
            let pixels=try #require(context.data).assumingMemoryBound(to:UInt8.self)
            // Pixels that are clearly amber or white: bright red and bright green together.
            var count=0
            for i in stride(from:0,to:w*h*4,by:4) where pixels[i]>180 && pixels[i+1]>130 { count+=1 }
            return count
        }
        #expect(try greenest(export)>200)
        #expect(try greenest(preview)==0)
    }
    /// The limb ring of a small Moon reaches 3:1 against black under Increase Contrast and through
    /// night vision's red (both reds), and stays faint otherwise.
    @Test func limbRingContrast() {
        let ink=SIMD3(0.961,0.945,0.902), black=SIMD3(0.0,0.0,0.0)
        let contrast=MoonView.limbOpacity(nightVision:false,highContrast:true)
        #expect(ColorVision.typical.contrast(ink*contrast,black)>=3)
        let nightOpacity=MoonView.limbOpacity(nightVision:true,highContrast:false)
        for tint in NightTint.allCases {
            #expect(ColorVision.typical.contrast(SIMD3(repeating:nightOpacity)*tint.rgb,black)>=3)
        }
        #expect(MoonView.limbOpacity(nightVision:false,highContrast:false)<contrast)
    }
    @Test func smallMoonsKeepAVisibleNightSide() throws {
        let jotr=try park("jotr")
        let new=engine.moonGeometry(for:jotr,at:try #require(try? Date("2026-10-10T12:00:00Z",strategy:.iso8601)))
        #expect(MoonView.earthshine(new,side:56)>MoonView.earthshine(new,side:280))
        #expect(abs(MoonView.earthshine(new,side:280)-0.09*(1-cos(new.phaseAngle))/2)<1e-9)
        #expect(MoonView.atlasSide>MoonView.smallSide)
    }
}
