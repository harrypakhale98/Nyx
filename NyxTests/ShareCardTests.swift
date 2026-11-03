import Foundation
import Testing
import SwiftUI
import UIKit
@testable import Nyx

/// The share card: its spoken summary carries everything the picture shows, the exported image is
/// drawn in starlight whatever the app's palette, and small Moons keep a visible limb.
@MainActor @Suite struct ShareCardTests {
    let engine=AstronomyEngine()
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
        #expect(summary.contains("Score range across forecast models: 88 to 97."))
        #expect(summary.contains("Moon-free for 70% of true darkness."))
        // The basis line always travels, so a shared number is never more certain than the app.
        #expect(summary.contains("Cloud forecast included"))
        #expect(card.message.contains(summary))
        #expect(ShareCard.rangeLine(88...97)=="Score range across forecast models: 88–97")
        let plain=ShareCard(night:night).summary
        #expect(!plain.contains("Forecast models"))
    }
    @Test func summaryNamesTheMoonAsDrawn() throws {
        let jotr=try park("jotr")
        // A crescent well past 5% is drawn, and the summary gives its phase and light.
        let crescent=try night(jotr,"2026-10-16")
        #expect(!crescent.sky.moon.negligible)
        let card=ShareCard(night:crescent)
        #expect(card.summary.contains("\(crescent.sky.moon.name), \(crescent.sky.moon.litText)."))
        #expect(card.dateLine==jotr.dayLabel(crescent.id))
        // At new moon no disc is drawn; the date line and the summary say it in words.
        let new=try night(jotr,"2026-10-10")
        #expect(new.sky.moon.negligible)
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
        /// The card's pixels: those drawn brighter than its dark ground, and those clearly amber or
        /// white (bright red and bright green together). Under heavy load the renderer can time out on
        /// the Moon's shader and hand back nothing or a blank, so a blank draw is tried again (up to three
        /// times) rather than read as a palette; whatever comes back is attached when a check fails.
        func tally(_ artwork:ShareArtwork) throws -> (image:UIImage,drawn:Int,amber:Int) {
            var last:(image:UIImage,drawn:Int,amber:Int)?
            for _ in 0..<3 {
                guard let image=artwork.image(), let cg=image.cgImage else { continue }
                let w=cg.width, h=cg.height
                let context=try #require(CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
                let pixels=try #require(context.data).assumingMemoryBound(to:UInt8.self)
                var drawn=0, amber=0
                for i in stride(from:0,to:w*h*4,by:4) {
                    if max(pixels[i],pixels[i+1],pixels[i+2])>120 { drawn+=1 }
                    if pixels[i]>180 && pixels[i+1]>130 { amber+=1 }
                }
                last=(image,drawn,amber)
                if drawn>200 { break }
            }
            return try #require(last,"The card was never drawn")
        }
        let exported=try tally(export), previewed=try tally(preview)
        #expect(exported.amber>200)
        #expect(previewed.drawn>200)
        #expect(previewed.amber==0)
        if exported.amber<=200 { Attachment.record(exported.image,named:"export") }
        if previewed.drawn<=200 || previewed.amber != 0 { Attachment.record(previewed.image,named:"preview") }
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

    /// "New moon" in words comes from the phase itself, never from comparing its display name.
    @Test func newMoonWordingFollowsThePhase() throws {
        for fraction in [0.0,0.01,0.029,0.97,0.995] {
            let phase=MoonPhase(fraction:fraction)
            #expect(phase.isNew)
            #expect(phase.name==String(localized:"New moon"))
        }
        for fraction in [0.03,0.25,0.5,0.75,0.969] { #expect(!MoonPhase(fraction:fraction).isNew) }
        let jotr=try park("jotr"), new=try night(jotr,"2026-10-10")
        #expect(new.sky.moon.isNew)
        #expect(ShareCard(night:new).dateLine.hasSuffix("New moon"))
        #expect(ShareCard(night:new).summary.contains("New moon."))
    }
    /// The Moon gives way to long words in steps, largest first, never below 80 pt on the card.
    @Test func moonShrinksInStepsBeforeTheWordsMove() {
        for shape in ShareCard.Format.allCases {
            let sides=ShareCard.moonSides(shape)
            #expect(sides==sides.sorted(by:>))
            #expect((sides.last ?? 0)>=80)
        }
        #expect(ShareCard.moonSides(.card).first==120)
    }
    /// A draw that comes back empty is tried again, and only a drawing is kept: a failure is never
    /// handed out again, and a later share of the same night draws afresh.
    @Test func failedDrawIsRetriedAndNeverKept() throws {
        let picture=Data([1,2,3]), key=UUID().uuidString
        var draws=0
        let first=try ShareArtwork.png(key:key) { draws+=1; return draws<2 ? nil : picture }
        #expect(first==picture && draws==2)
        // Kept: the same night is not drawn again.
        #expect(try ShareArtwork.png(key:key) { draws+=1; return nil }==picture && draws==2)
        let other=UUID().uuidString
        draws=0
        #expect(throws:(any Error).self) { try ShareArtwork.png(key:other) { draws+=1; return nil } }
        #expect(draws==3)
        // The failure was not kept: the next share draws, and keeps what it draws.
        #expect(try ShareArtwork.png(key:other) { draws+=1; return picture }==picture && draws==4)
    }
}
