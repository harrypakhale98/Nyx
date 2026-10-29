import Foundation
import Testing
@testable import Nyx

/// Vision Pro's smoke and park alerts (since 2026-10-14) and aurora forecast (since 2026-10-15): the same hosts and switches as the
/// iPhone, smoke counted in the score through the iPhone's own service and engine, the closure
/// beside every score, and plain words when a switch is off or nothing has arrived (`ScoreInputs`).
struct VisionSmokeAlertsTests {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private static func source(_ path: String) throws -> String { try String(contentsOf: root.appending(path: path), encoding: .utf8) }
    private static func park(_ id: String) throws -> Park { try #require(try ParkData.load().first { $0.id == id }) }
    /// One hour apart from a day before `start`, six days on: the reach of a smoke forecast.
    private static func times(from start: Date) -> [Double] {
        let first = (start.timeIntervalSince1970/3600).rounded(.down)*3600-86400
        return (0..<168).map { first+Double($0)*3600 }
    }
    private static func airBody(_ times: [Double], aerosol: Double) -> String {
        func list(_ values: [Double]) -> String { "["+values.map { String($0) }.joined(separator: ",")+"]" }
        return "{\"latitude\":34,\"longitude\":-116,\"hourly\":{\"time\":\(list(times)),\"aerosol_optical_depth\":\(list(times.map { _ in aerosol })),\"pm2_5\":\(list(times.map { _ in 40 }))}}"
    }
    private static let closure = ParkAlert(id: "a1", title: "Keys View Road Closed", description: "", category: "Park Closure")

    // MARK: Hosts

    /// Vision Pro compiles the same host table as the iPhone (no visionOS branch any more), and its
    /// target carries both network files and the iPhone's NPS key setting, nothing else that can ask.
    @Test func visionReachesTheSameThreeHostsBehindTheSameSwitches() throws {
        #expect(SafeHTTP.preferences == Dictionary(uniqueKeysWithValues: NetworkService.allCases.map { ($0.host, $0.key) }))
        let client = try Self.source("Nyx/Services/CloudForecastClient.swift")
        #expect(!client.contains("#if os(visionOS)"))
        let hosts = Set((client+(try Self.source("Nyx/Services/DataServices.swift"))).matches(of: /host="([^"]+)"/).map { String($0.output.1) })
        #expect(hosts == SafeHTTP.hosts)
        let spec = try Self.source("project.yml")
        let vision = try #require(spec.firstRange(of: "\n  NyxVision:\n").map { String(spec[$0.upperBound...]) }?.components(separatedBy: "\n  NyxVisionWidgets:\n").first)
        for file in ["CloudForecastClient.swift", "DataServices.swift", "ParkAlerts.swift", "ScoreInputs.swift"] { #expect(vision.contains("Nyx/Services/\(file)")) }
        #expect(vision.contains("NPS_API_KEY: \"$(NPS_API_KEY)\"") && vision.contains("Config/Nyx.xcconfig"))
        // The privacy manifest's comment names the four hosts and nothing else.
        let manifest = try Self.source("NyxVision/Resources/PrivacyInfo.xcprivacy")
        let comments = manifest.matches(of: /<!--(.*?)-->/.dotMatchesNewlines()).map { String($0.output.1) }.joined(separator: " ")
        let named = Set(comments.matches(of: /[a-z-]+(?:\.[a-z-]+)*\.(?:gov|com)/).map { String($0.output) })
        #expect(named == SafeHTTP.hosts)
    }

    // MARK: Smoke

    /// The headset asks forecast detail for smoke only (one request, the air-quality host), and the
    /// night it scores with that smoke is the iPhone's exactly: same score, cap and words.
    @Test func visionCountsSmokeAsTheIPhone() async throws {
        let jotr = try Self.park("jotr"), now = try Date("2026-10-10T21:00:00Z", strategy: .iso8601)
        let sky = AstronomyEngine().conditions(for: jotr, on: jotr.currentNight(at: now))
        let times = Self.times(from: now)
        let http = RoutedHTTP(air: Self.airBody(times, aerosol: 0.6))
        let fetched = await ForecastDetailService(transport: http, persist: false, clock: { now }).details(for: [jotr], weather: false, smoke: true)
        #expect(await http.urls.map(\.host) == ["air-quality-api.open-meteo.com"])
        let air = try #require(fetched[jotr.id]?.air)
        let clear = Forecast(updated: now, times: times, clouds: times.map { _ in 0 })
        let vision = NightPlanner.night(park: jotr, sky: sky, forecast: clear, detail: ForecastDetail.vision(layers: nil, air: air), now: now)
        // The iPhone: the same smoke inside full forecast detail (models and layers beside it).
        var spread: [String: [Double?]] = [:]
        for key in ForecastDetail.modelKeys { spread[key] = times.map { _ in 0 } }
        let layers = HourlySeries(updated: now, times: times, values: Dictionary(uniqueKeysWithValues: ForecastDetail.layerKeys.map { ($0, times.map { _ in 0 }) }))
        let iPhone = NightPlanner.night(park: jotr, sky: sky, forecast: clear, detail: ForecastDetail(models: HourlySeries(updated: now, times: times, values: spread), layers: layers, air: air), now: now)
        #expect(vision.score.value == iPhone.score.value && vision.score.limit == iPhone.score.limit && vision.basis == iPhone.basis && vision.aerosol == iPhone.aerosol)
        #expect(vision.score.isSmokeLimited && vision.score.value <= 59)
        #expect(vision.bandWithBasis == iPhone.bandWithBasis && vision.bandWithBasis.hasSuffix(String(localized: "haze or smoke")))
        #expect(vision.smokeSentence(tonight: true) == iPhone.smokeSentence(tonight: true))
        // Without the smoke the same night scores higher: the headset no longer shows a clean sky.
        let unsmoked = NightPlanner.night(park: jotr, sky: sky, forecast: clear, detail: ForecastDetail.vision(layers: nil, air: nil), now: now)
        #expect(unsmoked.score.value > vision.score.value)
        #expect(ForecastDetail.vision(layers: nil, air: nil) == nil)
    }

    // MARK: Closures

    /// The closure beside each score on the headset is the iPhone's: the same alert chosen, the
    /// same headline, the same "Closure alert:" line, said first in a spoken answer.
    @Test func closureStandsBesideTheScore() throws {
        let jotr = try Self.park("jotr"), arch = try Self.park("arch"), now = Date.now
        let jotrCode = try #require(jotr.nps), archCode = try #require(arch.nps)
        let notice = ParkAlert(id: "n1", title: "Visitor Center Hours Change", description: "", category: "Information")
        let cache = ParkAlertsCache(updated: now, alerts: [jotrCode: [notice, Self.closure], archCode: []])
        let inputs = ScoreInputs(smokeKnown: [jotr.id, arch.id], alerts: cache)
        let expected = Self.closure.displayTitle(park: jotr)
        #expect(inputs.closure(jotr) == expected && cache.closure(for: jotr) == AlertRanking.closure([notice, Self.closure])?.displayTitle(park: jotr))
        #expect(inputs.closure(arch) == nil)
        // The row's spoken words: the closure, and nothing about smoke (it is counted).
        #expect(inputs.spoken(jotr, night: nil) == [Sentences.end(String(localized: "Closure alert: \(expected)"))])
        #expect(inputs.spoken(arch, night: nil).isEmpty)
        // No second line under a closure; where none stands, the iPhone's park-page line.
        #expect(inputs.accessNote(jotr) == nil)
        #expect(inputs.accessNote(arch) == String(localized: "No alerts in the last park update. Confirm access before travel."))
        #expect(inputs.listNote([jotr, arch]) == nil)
        // Siri on either device: the closure first.
        let body = "Joshua Tree: 59 out of 100, Fair."
        #expect(ClosureLine.first(body, closure: expected).hasPrefix(String(localized: "Closure alert: \(expected)")))
        #expect(ClosureLine.first(body, closure: nil) == body)
    }
    /// The park-page line is one function on both devices: a danger alert, a notice only, nothing.
    @Test func alertSummaryIsShared() throws {
        let zion = try Self.park("zion")
        let danger = ParkAlert(id: "d1", title: "Flash Flood Warning", description: "", category: "Danger")
        let notice = ParkAlert(id: "n1", title: "Shuttle Schedule", description: "", category: "Information")
        #expect(AlertRanking.summary([notice, danger], park: zion) == danger.displayTitle(park: zion))
        #expect(AlertRanking.summary([notice], park: zion) == String(localized: "No closures in the last park update. Check all park alerts before you go."))
        #expect(AlertRanking.summary([notice, Self.closure], park: zion) == Self.closure.displayTitle(park: zion))
    }
    /// Without a key nothing is asked of the Park Service (an unexpanded build setting counts as
    /// none), and the headset says closures are not checked.
    @Test func noKeyMeansNoRequestAndSaysSo() async throws {
        let parks = try ParkData.load()
        for key in ["", "$(NPS_API_KEY)"] {
            let http = StubHTTP([:])
            let update = await ParkStore(transport: http, persist: false).alerts(for: parks, key: key, network: true)
            #expect(update.cache == nil && !update.busy)
            #expect(await http.urls.isEmpty)
        }
        let jotr = try Self.park("jotr")
        let inputs = ScoreInputs(smokeKnown: [jotr.id])
        #expect(inputs.unchecked(jotr))
        #expect(inputs.accessNote(jotr) == String(localized: "Access not checked. Confirm closures with the park."))
        #expect(inputs.spoken(jotr, night: nil) == [String(localized: "Closures not checked.")])
    }

    // MARK: What is said when an input is missing

    /// A switch off, smoke not here yet, or the Park Service busy: each said in its own words
    /// beside the score, in the short row words, and once above the list.
    @Test func missingInputsAreSaid() throws {
        let jotr = try Self.park("jotr")
        let smokeOff = String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.")
        let smokeNotYet = String(localized: "No smoke forecast on this device yet, so smoke is not counted.")
        let alertsOff = String(localized: "Park alerts are off in Your privacy, so closures are not checked.")
        let off = ScoreInputs(smokeOn: false, smokeKnown: [jotr.id], alertsOn: false)
        #expect(off.smokeNote(jotr, night: nil) == smokeOff)
        #expect(off.accessNote(jotr) == alertsOff)
        #expect(off.spoken(jotr, night: nil) == [String(localized: "Closures not checked."), String(localized: "Smoke not counted.")])
        #expect(off.listNote([jotr]) == Sentences.join([smokeOff, alertsOff]))
        let notYet = ScoreInputs()
        #expect(notYet.smokeNote(jotr, night: nil) == smokeNotYet)
        #expect(notYet.listNote([jotr]) == Sentences.join([smokeNotYet, String(localized: "Access not checked. Confirm closures with the park.")]))
        let busy = ScoreInputs(smokeKnown: [jotr.id], alertsBusy: true)
        #expect(busy.smokeNote(jotr, night: nil) == nil)
        #expect(busy.accessNote(jotr) == String(localized: "Park alerts are busy. Check current conditions on nps.gov."))
        // Switched off with a park update already here: its closures still stand, as on the iPhone.
        let code = try #require(jotr.nps)
        let kept = ScoreInputs(smokeKnown: [jotr.id], alertsOn: false, alerts: ParkAlertsCache(updated: .now, alerts: [code: [Self.closure]]))
        #expect(kept.closure(jotr) != nil && kept.accessNote(jotr) == nil && kept.listNote([jotr]) == nil)
    }
}
