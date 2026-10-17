import Foundation
import Testing
@testable import Nyx

/// Answers every forecast and air-quality request with one series for each coordinate it carries.
actor PerPointHTTP: HTTPTransport {
    var urls: [URL]=[]
    func get(_ url: URL) async throws -> Data {
        urls.append(url)
        let items=URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let count=(items.first { $0.name == "latitude" }?.value ?? "").split(separator: ",").count
        let one=url.path == "/v1/air-quality"
            ? "{\"hourly\":{\"time\":[1790000000,1790003600],\"aerosol_optical_depth\":[0.6,0.7],\"pm2_5\":[40,40],\"dust\":[1,1]}}"
            : "{\"hourly\":{\"time\":[1790000000,1790003600],\"cloud_cover\":[10,20]}}"
        return Data((count == 1 ? one : "["+Array(repeating: one, count: count).joined(separator: ",")+"]").utf8)
    }
}

/// Smoke at world catalogue places: asked for by the clouds' own whole tiles, within the browsing
/// budget, only once a place's page has been opened, and never with the switch off.
struct CatalogSmokeTests {
    private static let kruger="wd:Q24451"
    private static let airHost="air-quality-api.open-meteo.com"
    private static func values(_ url: URL, _ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value ?? "").split(separator: ",").map(String.init)
    }
    private static func requests() throws -> (kruger: Park, requests: [[Park]]) {
        let catalog=try CatalogData.load()
        let kruger=try #require(catalog.first { $0.id == Self.kruger })
        return (kruger, CatalogForecast.Regions(catalog).plan(wanted: [kruger]))
    }

    /// The same coordinates as the tiles' cloud requests, in parts of at most 250, naming nothing.
    @Test func smokeAbroadGoesByTheCloudsWholeTiles() async throws {
        let (_, requests)=try Self.requests()
        #expect(!requests.isEmpty)
        let http=PerPointHTTP()
        let service=ForecastDetailService(transport: http, persist: false)
        let result=await service.catalogAir(requests, network: true, force: true)
        let urls=await http.urls
        #expect(!urls.isEmpty && urls.allSatisfy { $0.host == Self.airHost && $0.path == "/v1/air-quality" })
        let clouds=requests.compactMap { CatalogForecast.url(for: $0) }
        #expect(urls.flatMap { Self.values($0, "latitude") } == clouds.flatMap { Self.values($0, "latitude") })
        #expect(urls.flatMap { Self.values($0, "longitude") } == clouds.flatMap { Self.values($0, "longitude") })
        #expect(urls.allSatisfy { Self.values($0, "latitude").count <= ForecastDetailService.catalogAirChunk })
        for exact in ["wd", "Q24451", "Kruger", "Limpopo"] { #expect(urls.allSatisfy { !$0.absoluteString.contains(exact) }) }
        #expect(Set(result.keys) == Set(requests.joined().map(\.id)))
        #expect(result[Self.kruger]?.air?.values["aerosol_optical_depth"] == [0.6, 0.7])
        // Fresh: not asked again. Offline: what is kept still comes back.
        _=await service.catalogAir(requests, network: true, force: false)
        #expect(await http.urls.count == urls.count)
        #expect(await service.catalogAir(requests, network: false, force: false).count == result.count)
    }
    /// Without the network nothing is asked.
    @Test func offlineAsksNothing() async throws {
        let (_, requests)=try Self.requests()
        let http=PerPointHTTP()
        let result=await ForecastDetailService(transport: http, persist: false).catalogAir(requests, network: false, force: true)
        #expect(result.isEmpty)
        #expect(await http.urls.isEmpty)
    }
    /// Browsing the world spends the browsing budget, so the parks' own smoke keeps its room.
    @Test func catalogueSmokeStaysInTheBrowsingBudget() async throws {
        let (_, requests)=try Self.requests()
        let http=PerPointHTTP()
        let tight=CallBudget(essential: CallBudget.standard.essential, browsing: CallBudget.Caps(minute: 1, hour: 1, day: 1))
        // A call already counted this minute: the first request of an empty window always goes.
        let ledger=CallLedger(file: nil)
        #expect(ledger.reserve(Self.airHost, calls: 1, caps: CallBudget.standard.essential) != nil)
        let service=ForecastDetailService(transport: http, persist: false, ledger: ledger, budget: tight)
        #expect(await service.catalogAir(requests, network: true, force: true).isEmpty)
        #expect(await http.urls.isEmpty)
        let parks=Array(try ParkData.load().prefix(2))
        let parksSmoke=await service.details(for: parks, weather: false, smoke: true, force: true)
        #expect(await http.urls.count == 1)
        #expect(parksSmoke.count == 2)
    }
    /// Tonight's list asks only clouds; a place's page abroad adds its tile's smoke, never the parks'
    /// points; switched off, nothing more is asked and the kept smoke stops counting.
    @MainActor @Test func aPlacePageAbroadAsksForItsTilesSmoke() async throws {
        let (kruger, _)=try Self.requests()
        let http=PerPointHTTP()
        let model=PlanModel(weather: WeatherService(transport: http, persist: false), parkStore: ParkStore(transport: http, persist: false),
                            detail: ForecastDetailService(transport: http, persist: false), defaults: isolatedDefaults())
        await model.catalogReady()
        await model.refresh([kruger], parkUpdates: false)
        #expect(await http.urls.allSatisfy { $0.host != Self.airHost })
        #expect(model.details[Self.kruger]?.air == nil)

        await model.refresh([kruger], parkUpdates: false, page: true)
        let air=await http.urls.filter { $0.host == Self.airHost }
        #expect(!air.isEmpty)
        #expect(model.details[Self.kruger]?.air != nil)
        let curated=Set(model.parks.map { String($0.forecastPoint.latitude) })
        #expect(air.allSatisfy { curated.isDisjoint(with: Self.values($0, "latitude")) })

        model.smokeEnabled=false
        #expect(model.details[Self.kruger]?.air == nil)
        await model.refresh([kruger], force: true, parkUpdates: false, page: true)
        #expect(await http.urls.filter { $0.host == Self.airHost }.count == air.count)
        #expect(model.details[Self.kruger]?.air == nil)
    }
}
