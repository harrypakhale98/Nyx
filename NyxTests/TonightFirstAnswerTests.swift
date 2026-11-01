import Foundation
import Testing
@testable import Nyx

/// Tonight's first answer on a cold launch is the one it settles on: near a border it waits for the
/// world catalogue, and the catalogue arrives with the forecasts kept for its places in reach.
@MainActor struct TonightFirstAnswerTests {
    /// Clouds for the world catalogue: one kept forecast for every place asked about, from the files
    /// alone; nothing for the parks.
    actor KeptWeather: WeatherProviding {
        let kept: Forecast
        private(set) var asked: [Bool]=[]
        init(kept: Forecast) { self.kept=kept }
        func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
        func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
        func seed(_ cached: [String: Forecast], parks: [Park]) async {}
        func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast] {
            asked.append(network)
            return Dictionary(requests.joined().map { ($0.id, kept) }, uniquingKeysWith: { first, _ in first })
        }
    }
    static func model(home: String, weather: any WeatherProviding) throws -> PlanModel {
        let defaults=try #require(UserDefaults(suiteName: "nyx-first-answer-\(UUID().uuidString)"))
        defaults.set(home, forKey: "homePark"); defaults.set(true, forKey: "startChosen")
        let model=PlanModel(weather: weather, parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: defaults)
        model.radiusMeters=321_869
        return model
    }
    static func overcast(_ now: Date) -> Forecast {
        let start=now.timeIntervalSince1970-86400
        return Forecast(updated: now, times: (0..<(16*24)).map { start+Double($0)*3600 }, clouds: Array(repeating: 100, count: 16*24))
    }

    @Test func aReachAcrossTheUSEdgeIsKnownWithoutTheCatalogue() throws {
        let parks=try ParkData.load()
        func crosses(_ id: String) throws -> Bool {
            let park=try #require(parks.first { $0.id == id })
            return TonightReach.crossesUSEdge(latitude: park.latitude, longitude: park.longitude, radiusMeters: 321_869)
        }
        // Joshua Tree (Mexico), Big Bend (Mexico), Glacier and Voyageurs (Canada), Acadia (Canada and the sea).
        for id in ["jotr", "bibe", "glac", "voya", "acad"] { #expect(try crosses(id), "\(id)") }
        // Arches and Great Sand Dunes reach no border and no coast.
        for id in ["arch", "grsa"] { #expect(try !crosses(id), "\(id)") }
    }

    /// At Joshua Tree the first answer waits for the catalogue (Constitution 1857 in Mexico is in reach),
    /// and the catalogue arrives with its places' kept forecasts already counted, so the answer Tonight
    /// first shows is the one it keeps once a refresh reads the same files. Arches never waits.
    @Test func aCatalogueLandingAfterTheFirstRankingNamesOneAnswer() async throws {
        let weather=KeptWeather(kept: Self.overcast(.now))
        let model=try Self.model(home: "jotr", weather: weather)
        #expect(!model.catalogIsReady && model.awaitingWorld)
        await model.catalogReady()
        #expect(!model.awaitingWorld)
        let inReach=model.placesInReach().places
        let world=inReach.filter(\.isCatalogPlace)
        #expect(world.contains { $0.id == "wd:Q5164083" })
        // Every catalogue place in reach is already scored on its kept clouds, read without the network.
        #expect(world.allSatisfy { model.forecasts[$0.id] != nil })
        #expect(await weather.asked == [false])
        let first=model.ranked(model.shortlist(inReach)).first?.id
        // What a refresh reads from the same files changes nothing.
        await model.takeKeptForecasts(inReach)
        #expect(model.ranked(model.shortlist(model.placesInReach().places)).first?.id == first)
        // Overcast across the border: the answer is not a place scored on clouds it was about to lose.
        #expect(first.map { !$0.hasPrefix(Park.catalogPrefix) } == true)

        let arches=try Self.model(home: "arch", weather: KeptWeather(kept: Self.overcast(.now)))
        #expect(!arches.catalogIsReady && !arches.awaitingWorld)
    }

    /// iPhone in landscape: the dial takes what the first screen leaves under the pill, between 160 and 240 pt,
    /// or, a little short of the dial that holds its word inside, that dial when its units still show.
    @Test func theLandscapeDialFitsTheFirstScreen() {
        #expect(TonightView.dialHeight(compact: false, page: 300, top: 120) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 0, top: 0) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 330, top: 110) == 208)
        #expect(TonightView.dialHeight(compact: true, page: 600, top: 110) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 250, top: 130) == 160)
        // Short of the dial that keeps its word inside (190 pt): that dial while the first screen shows its units...
        #expect(TonightView.dialHeight(compact: true, page: 273, top: 105, inside: 190) == 190)
        #expect(TonightView.dialHeight(compact: true, page: 320, top: 105, inside: 190) == 203)
        // ...and the fitted dial, words below, when even its units would go under the tab bar.
        #expect(TonightView.dialHeight(compact: true, page: 273, top: 115, inside: 209) == 160)
        #expect(TonightView.dialHeight(compact: false, page: 273, top: 105, inside: 190) == 240)
    }
}
