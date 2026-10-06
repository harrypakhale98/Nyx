import Foundation
import Testing
@testable import Nyx

/// NASA night lights and step-free access: every park and spot joins, and the words stay honest.
struct SkyGlowTests {
    let parks=(try? ParkData.load()) ?? []
    let glow=(try? SkyGlow.load()) ?? SkyGlow(parks:[:])
    let access=(try? AccessData.load()) ?? AccessData(spots:[])

    @Test func everyParkAndSpotHasItsSkyGlow() throws {
        #expect(parks.count==63)
        #expect(glow.parks.count==63)
        for park in parks {
            let site=try #require(glow.park(park.id),"\(park.id)")
            #expect(site.glow>0 && site.profile.count==36 && site.trend != nil)
            #expect(site.domes.allSatisfy { (0..<360).contains($0.bearing) && (0...1).contains($0.share) })
            #expect(site.spots?.count==park.viewingSpots.count,"\(park.id)")
            for spot in park.viewingSpots { #expect(glow.spot(spot.name,park:park.id) != nil,"\(park.id) \(spot.name)") }
        }
        #expect(parks.flatMap(\.viewingSpots).count==85)
    }
    @Test func everySpotHasAnAccessRecord() throws {
        #expect(access.spots.count==85)
        for park in parks { for spot in park.viewingSpots {
            let record=try #require(access.access(park:park.id,spot:spot.name),"\(park.id) \(spot.name)")
            // A claim is never made without the official page it rests on.
            if record.stepFree != .unknown { #expect(record.source?.host()=="www.nps.gov" && record.evidence?.isEmpty==false,"\(spot.name)") }
        } }
        let moro=try #require(access.access(park:"sequ",spot:"Moro Rock"))
        #expect(moro.stepFree == .no && moro.summary==String(localized:"Steps or trail") && moro.symbol=="figure.stairs")
        #expect(access.spots.filter { $0.stepFree == .unknown }.allSatisfy { $0.summary==nil })
        let yes=try #require(access.spots.first { $0.stepFree == .yes && !$0.features.isEmpty })
        #expect(yes.summary?.hasPrefix(String(localized:"Step-free")) == true)
    }
    @Test func levelsSpanTheParks() throws {
        // Gateway Arch is the brightest centre, Yellowstone among the darkest.
        let arch=try #require(glow.park("jeff")), yellowstone=try #require(glow.park("yell"))
        #expect(glow.level(arch.glow)==5)
        #expect(glow.level(yellowstone.glow)==1)
        let counts=Dictionary(grouping:parks.map { glow.level(glow.park($0.id)?.glow ?? 0) },by:{ $0 }).mapValues(\.count)
        #expect(counts.keys.sorted()==[1,2,3,4,5])
        #expect(counts.values.allSatisfy { (11...14).contains($0) })
        #expect(SkyGlow.comparison(spot:0.5,park:1)==String(localized:"Darker than the park's center"))
        #expect(SkyGlow.comparison(spot:2,park:1)==String(localized:"Brighter than the park's center"))
        #expect(SkyGlow.comparison(spot:1.1,park:1)==nil)
    }
    @Test func domeWording() {
        #expect(SkyGlow.direction(102)==String(localized:"east"))
        #expect(SkyGlow.direction(359)==String(localized:"north"))
        #expect(SkyGlow.direction(-90)==String(localized:"west"))
        let lines=SkyGlow.domeLines([.init(bearing:102,share:0.452,city:"Las Vegas"),.init(bearing:271,share:0.094,city:nil)])
        #expect(lines.count==2)
        #expect(lines[0].contains("Las Vegas") && lines[0].contains(String(localized:"east")) && lines[0].contains("45"))
        // No listed town near the light: say so plainly instead of guessing a name.
        #expect(lines[1].contains(String(localized:"a town to the \(String(localized:"west"))")))
        // One town matched to two sectors is named once.
        let acadia=SkyGlow.namedDomes([.init(bearing:132,share:0.35,city:"Bar Harbor"),.init(bearing:100,share:0.22,city:"Bar Harbor"),.init(bearing:263,share:0.2,city:nil)])
        #expect(acadia.count==2 && acadia[0].bearing==132 && acadia[1].city==nil)
        #expect(SkyGlow.domeLines([]).isEmpty)
    }
    @Test func trendIsOnlyARankAndSkipsArtifacts() {
        // Lava, flaring, Alaska and almost-unlit places are never ranked.
        for id in ["havo","cave","gumo","katm","dena","thro","npsa"] { #expect(glow.trendRank(id)==nil,"\(id)") }
        // A tiny base (Great Basin, Big Bend) is left out too.
        #expect(glow.trendRank("grba")==nil && glow.trendRank("bibe")==nil)
        #expect(glow.trendRank("grte") == .faster)
        #expect(glow.trendRank("olym") == .slower)
        let ranked=parks.compactMap { glow.trendRank($0.id) }
        #expect(ranked.filter { $0 == .faster }.count==ranked.filter { $0 == .slower }.count)
        #expect(ranked.count<parks.count*3/4)
        #expect(!SkyGlow.trendSentence(.faster).contains("%"))
    }
    @Test func stepFreeFilter() throws {
        let all=ParkFilter(), stepFree=ParkFilter(stepFreeOnly:true), both=ParkFilter(darkOnly:true,stepFreeOnly:true)
        #expect(parks.filter { all.includes($0,access:access) }.count==63)
        let kept=parks.filter { stepFree.includes($0,access:access) }
        #expect(!kept.isEmpty && kept.count<50)
        #expect(kept.allSatisfy { park in park.viewingSpots.contains { [.yes,.partial].contains(access.access(park:park.id,spot:$0.name)?.stepFree) } })
        // Sequoia's only documented spot is Moro Rock's stairs; parks without spots never pass.
        #expect(!kept.contains { $0.id=="sequ" })
        #expect(!kept.contains { $0.viewingSpots.isEmpty })
        let darkAndStepFree=parks.filter { both.includes($0,access:access) }
        #expect(darkAndStepFree.allSatisfy { $0.darkSkyDesignated })
        let deathValley=try #require(parks.first { $0.id=="deva" })
        #expect(ParkFilter(darkOnly:true).includes(deathValley,access:access))
    }
    @MainActor @Test func domesRiseInTheRealSky() throws {
        let projection=SkyProjection.shared
        let previous=projection.lightSources
        defer { projection.lightSources=previous }
        projection.lightSources=SkyGlow.lightSources
        // Grand Canyon's Tusayan dome is due south, where the sky faces; a summer night is dark.
        let canyon=try #require(parks.first { $0.id=="grca" })
        let f=DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm"; f.timeZone=canyon.timeZone
        let july=try #require(f.date(from:"2026-07-15 12:00"))
        let sky=projection.sky(for:canyon,night:july)
        let dome=try #require(sky.domes.first)
        // 190° is 10° west of south: just right of centre when facing south, rising above its foot.
        #expect(dome.base.x>0.1 && dome.base.x<0.3)
        #expect(dome.top.y>dome.base.y && dome.intensity>0.5)
        #expect(dome.horizon.count>=12)
        projection.lightSources=SkyProjection.noLight
        #expect(projection.sky(for:canyon,night:july).domes.isEmpty)
    }
}
