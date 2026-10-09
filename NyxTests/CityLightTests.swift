import Foundation
import Testing
@testable import Nyx

/// Stars arriving as eyes adapt in the sky view, what city light takes on a park's page, and the
/// sourced essay "A sky worth protecting".
struct CityLightTests {
    let parks: [Park]
    init() throws { parks=try ParkData.load() }
    func park(_ id:String) throws -> Park { try #require(parks.first { $0.id==id }) }
    func spanish(_ key:String) throws -> String {
        let path=try #require(Bundle.main.path(forResource:"es",ofType:"lproj"))
        let bundle=try #require(Bundle(path:path))
        return bundle.localizedString(forKey:key,value:"<missing>",table:nil)
    }

    // MARK: Eyes adapting

    /// At 0 no star is drawn (Sirius is −1.46), at 1 the sky's own limit; brighter stars always
    /// arrive before fainter ones, and adaptation never draws more than the sky allows.
    @Test func brightestStarsArriveFirst() {
        let limit=6.8
        #expect(PanoramaCanvas.adaptedLimit(limit,adaptation:0) == -1.5)
        #expect(PanoramaCanvas.adaptedLimit(limit,adaptation:1)==limit)
        #expect(PanoramaCanvas.adaptedLimit(limit,adaptation:2)==limit)
        #expect(PanoramaCanvas.adaptedLimit(limit,adaptation:-1) == -1.5)
        var previous = -10.0
        for step in 0...20 {
            let value=PanoramaCanvas.adaptedLimit(limit,adaptation:Double(step)/20)
            #expect(value>=previous)
            #expect(value<=limit)
            previous=value
        }
        // Halfway, the bright stars are in and the faint ones are not.
        let half=PanoramaCanvas.adaptedLimit(limit,adaptation:0.5)
        #expect(half>1 && half<3)
        // A twilit or moonlit sky (a low limit) is never brightened by adaptation.
        #expect(PanoramaCanvas.adaptedLimit(-2,adaptation:0.5) == -2)
    }
    /// The Milky Way gathers last: nothing until 0.7, all of it at 1, smoothly between.
    @Test func milkyWayGathersLast() {
        #expect(PanoramaCanvas.milkyWayGathered(0)==0)
        #expect(PanoramaCanvas.milkyWayGathered(0.7)==0)
        #expect(PanoramaCanvas.milkyWayGathered(1)==1)
        let middle=PanoramaCanvas.milkyWayGathered(0.85)
        #expect(abs(middle-0.5)<0.001)
        #expect(PanoramaCanvas.milkyWayGathered(0.8)<PanoramaCanvas.milkyWayGathered(0.9))
    }
    /// The reveal is eased, takes about four seconds, starts from the 0.3 floor (the brightest
    /// stars and planets already out, continuing from the lit card) and lands whole.
    @MainActor @Test func revealTiming() {
        #expect(SkyAdaptation.duration==4)
        #expect(SkyAdaptation.floor==0.3 && SkyAdaptation.landingHold==3)
        #expect(SkyAdaptation.eased(0)==0)
        #expect(SkyAdaptation.eased(1)==1)
        #expect(SkyAdaptation.eased(-1)==0 && SkyAdaptation.eased(3)==1)
        let start=Date(timeIntervalSince1970:1_000)
        #expect(SkyAdaptation.progress(since:nil,now:start)==0.3)
        #expect(SkyAdaptation.progress(since:start,now:start)==0.3)
        #expect(abs(SkyAdaptation.progress(since:start,now:start.addingTimeInterval(2))-0.65)<1e-12)
        #expect(SkyAdaptation.progress(since:start,now:start.addingTimeInterval(5))==1)
        // At the floor a Bortle 3 sky shows only its brightest points: about magnitude 1.
        let limit=PanoramaCanvas.adaptedLimit(BortleScale.limitingMagnitude(3),adaptation:SkyAdaptation.floor)
        #expect(limit>0.5 && limit<1.2)
    }
    /// Once per park and night: another night, or another park, is a new reveal.
    @Test func revealKeyIsParkAndNight() {
        let night=Date(timeIntervalSince1970:1_790_000_000)
        #expect(SkyAdaptation.key(parkID:"jotr",night:night)==SkyAdaptation.key(parkID:"jotr",night:night))
        #expect(SkyAdaptation.key(parkID:"jotr",night:night) != SkyAdaptation.key(parkID:"deva",night:night))
        #expect(SkyAdaptation.key(parkID:"jotr",night:night) != SkyAdaptation.key(parkID:"jotr",night:night.addingTimeInterval(86_400)))
    }

    // MARK: What city light takes

    /// Every park darker than a city shows the comparison; a park already under a city's glow
    /// (estimated class 7 or brighter) does not, since the two skies would match.
    @MainActor @Test func comparisonOnlyWhereItDiffers() throws {
        for park in parks { #expect(CityLightFigure.compares(park)==(park.bortleEstimate<=6),"\(park.id)") }
        #expect(CityLightFigure.compares(try park("deva")))
        #expect(parks.filter(CityLightFigure.compares).count>=60)
    }
    /// The figure draws a night with true darkness: the summer new moon, or the winter one where
    /// July has none (Alaska), so the Milky Way is there to be taken away.
    @MainActor @Test func figureNightHasTrueDarkness() throws {
        #expect(CityLightFigure.night(try park("jotr"))==BortleFigure.summer)
        #expect(CityLightFigure.night(try park("gaar"))==BortleFigure.winter)
        for park in parks where CityLightFigure.compares(park) {
            let night=CityLightFigure.night(park)
            let sky=BortleFigure.sky(park,night:night)
            #expect(sky.dark,"\(park.id) has no true darkness on the figure's night")
        }
    }
    /// Drawn at class 8, fewer stars pass the limit and the Milky Way is gone.
    @MainActor @Test func cityClassTakesTheFaintStars() {
        #expect(BortleScale.milkyWay(CityLightFigure.cityClass)==0)
        #expect(BortleScale.milkyWay(2)>0.5)
        #expect(BortleScale.limitingMagnitude(CityLightFigure.cityClass)<BortleScale.limitingMagnitude(2)-2)
    }

    // MARK: A sky worth protecting

    /// The essay quotes both abstracts exactly, ends its body with Globe at Night, and closes with
    /// its sources; a "%" stays a "%" (the essay is read without formatting).
    @MainActor @Test func essayQuotesItsSources() {
        let text=Essay.darkness.content
        #expect(text.hasPrefix("A sky worth protecting\n\n"))
        #expect(text.contains("“The Milky Way is hidden from more than one-third of humanity, including 60% of Europeans and nearly 80% of North Americans.”"))
        #expect(text.contains("“The number of visible stars decreased by an amount that can be explained by an increase in sky brightness of 7 to 10% per year in the human visible band.”"))
        #expect(text.contains("Las Vegas"))
        // Not every park: 5 of 63 have a light dome with no town named, and the brightest shows no comparison.
        #expect(!text.contains("Each park's page"))
        #expect(text.contains("Most parks' pages"))
        #expect(text.contains("For every park darker than a city"))
        #expect(parks.contains { !CityLightFigure.compares($0) })
        #expect(!text.contains("!"))
        let paragraphs=text.components(separatedBy:"\n\n")
        let last=paragraphs.last ?? ""
        #expect(Essay.isSources(last))
        #expect(last.contains("Falchi") && last.contains("Science Advances") && last.contains("Kyba") && last.contains("Science 379"))
        #expect(paragraphs.dropLast().last?.contains("Globe at Night")==true)
        #expect(paragraphs.dropLast().allSatisfy { !Essay.isSources($0) })
    }
    /// The Spanish draft carries the same numbers and the same sources.
    @Test func spanishEssayCarriesTheSameNumbers() throws {
        let text=try spanish("essay.darkness")
        for number in ["60%","80%","7 y 10%","51,351","2011","2022","2016","2023"] { #expect(text.contains(number),"\(number)") }
        #expect(text.components(separatedBy:"\n\n").last?.hasPrefix("Fuentes:")==true)
        #expect(text.contains("la mayoría de los parques"))
        #expect(!text.contains("La página de cada parque"))
        #expect(try spanish("Sources")=="Fuentes")
    }
}
