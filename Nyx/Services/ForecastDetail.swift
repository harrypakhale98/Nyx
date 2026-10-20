import Foundation

/// The rules every hourly forecast in Nyx follows, so a window is only described when every
/// moment of it is covered. A partial forecast is never treated as full, and a missing hour is
/// never filled in as clear.
nonisolated enum HourlyWindow {
    /// What moment an hourly value describes, as Open-Meteo's docs give it: most variables
    /// (clouds, temperature, dew point, visibility, aerosols) are instant values at their
    /// timestamp, so each stands for the half hour either side of it; gusts are the preceding
    /// hour's maximum.
    enum Timing: Sendable { case instant, precedingHour }
    /// Each hour that overlaps the window with a valid value, weighted by its overlap in seconds;
    /// nil unless the hours are a clean hourly series that covers the whole window.
    static func samples(times: [Double], values: [Double?], from start: Date, to end: Date,
                        valid: ClosedRange<Double>, timing: Timing = .instant) -> [(value: Double, weight: Double)]? {
        guard end>start, !times.isEmpty, times.count==values.count, times.allSatisfy(\.isFinite),
              zip(times,times.dropFirst()).allSatisfy({ abs($1-$0-3600)<0.1 }) else { return nil }
        var found: [(value: Double, weight: Double)] = []
        let (before,after): (Double,Double) = timing == .instant ? (1800,1800) : (3600,0)
        for (t,value) in zip(times,values) {
            let overlap=min(end.timeIntervalSince1970,t+after)-max(start.timeIntervalSince1970,t-before)
            if overlap>0, let value, value.isFinite, valid.contains(value) { found.append((value,overlap)) }
        }
        guard found.reduce(0,{ $0+$1.weight }) >= end.timeIntervalSince(start)-1 else { return nil }
        return found
    }
    static func mean(times: [Double], values: [Double?], from start: Date, to end: Date, valid: ClosedRange<Double>) -> Double? {
        guard let found=samples(times:times,values:values,from:start,to:end,valid:valid) else { return nil }
        let weight=found.reduce(0) { $0+$1.weight }
        // A window under a second long can pass the coverage check with no hour in it: no mean, never 0/0.
        guard weight>0 else { return nil }
        return found.reduce(0) { $0+$1.value*$1.weight }/weight
    }
}

/// One request's hourly values for one park, keyed by Open-Meteo's variable names, with the
/// moment they arrived. Each request keeps its own series so each refreshes and expires alone.
nonisolated struct HourlySeries: Codable, Sendable, Equatable {
    let updated: Date
    let times: [Double]
    let values: [String: [Double?]]
    /// Forecasts older than 36 hours are not described, as with clouds.
    func usable(now: Date) -> Bool { now.timeIntervalSince(updated)<36*3600 }
    func samples(_ key: String, from start: Date, to end: Date, valid: ClosedRange<Double>, timing: HourlyWindow.Timing = .instant) -> [(value: Double, weight: Double)]? {
        guard let series=values[key] else { return nil }
        return HourlyWindow.samples(times:times,values:series,from:start,to:end,valid:valid,timing:timing)
    }
    func mean(_ key: String, from start: Date, to end: Date, valid: ClosedRange<Double>) -> Double? {
        guard let series=values[key] else { return nil }
        return HourlyWindow.mean(times:times,values:series,from:start,to:end,valid:valid)
    }
}

/// Everything Nyx knows about a park's coming nights beyond the score's own cloud forecast:
/// three forecast models' clouds, cloud layers, cold, dew, wind, visibility, rain, fog and water
/// vapour (Open-Meteo, seven days), and aerosol optical depth and dust (CAMS global via
/// Open-Meteo, about five days).
/// None of it changes the score. It is context, and every part is optional.
nonisolated struct ForecastDetail: Codable, Sendable, Equatable {
    /// `hourly=cloud_cover&models=gfs_seamless,ecmwf_ifs025,icon_seamless`
    var models: HourlySeries?
    /// `hourly=cloud_cover_low,cloud_cover_mid,cloud_cover_high,temperature_2m,dew_point_2m,wind_gusts_10m,visibility`,
    /// plus `layerExtras`.
    var layers: HourlySeries?
    /// `hourly=aerosol_optical_depth,pm2_5` from the air-quality host, plus `airExtras`.
    var air: HourlySeries?
    static let modelKeys=["cloud_cover_gfs_seamless","cloud_cover_ecmwf_ifs025","cloud_cover_icon_seamless"]
    static let layerKeys=["cloud_cover_low","cloud_cover_mid","cloud_cover_high","temperature_2m","dew_point_2m","wind_gusts_10m","visibility"]
    static let airKeys=["aerosol_optical_depth","pm2_5"]
    /// What a place's answer must hold to be kept: what the score reads. A summit above the inversion
    /// is scored from its mid and high cloud, and smoke from aerosol optical depth; the rest of the
    /// layers and fine particles are context, kept when they come whole. So if Open-Meteo renamed a
    /// context field, the score's part still arrives. The models are kept only all three together:
    /// their agreement needs every one.
    static let layerRequired=["cloud_cover_mid","cloud_cover_high"]
    static let airRequired=["aerosol_optical_depth"]
    /// This detail with each of `fresh`'s parts that is newer (by `updated`) or missing here: what
    /// a service hands on can land out of order, and an older part must never replace a newer one.
    func newer(_ fresh: ForecastDetail) -> ForecastDetail {
        func pick(_ kept: HourlySeries?, _ other: HourlySeries?) -> HourlySeries? {
            guard let other else { return kept }
            return kept.map { $0.updated>other.updated ? $0 : other } ?? other
        }
        return ForecastDetail(models: pick(models, fresh.models), layers: pick(layers, fresh.layers), air: pick(air, fresh.air))
    }
    /// Asked for with the layers and kept when they come back whole, but never required: a series
    /// without them is still a series. Ten variables in all, so the request still counts as one
    /// Open-Meteo call per place.
    static let layerExtras=["precipitation_probability","weather_code","total_column_integrated_water_vapour"]
    /// Dust near the ground (µg/m³), to tell dust from smoke when the air is hazy.
    static let airExtras=["dust"]
    /// What Nyx on Vision Pro has for a night: a summit's cloud layers (`SummitLayerService`) and the
    /// aerosol forecast (`ForecastDetailService`, asked for smoke only); nil with neither. The same
    /// parts the iPhone's detail gives `NightPlanner.night` for the score, so both score alike.
    static func vision(layers: HourlySeries?, air: HourlySeries?) -> ForecastDetail? {
        layers == nil && air == nil ? nil : ForecastDetail(layers: layers, air: air)
    }

    /// What the detail says about one night's window. `scoreRange` is filled in by the caller,
    /// which owns the score engine.
    func outlook(from start: Date, to end: Date, now: Date = .now) -> NightOutlook {
        var outlook=NightOutlook()
        if let models, models.usable(now:now) {
            let means=Self.modelKeys.compactMap { models.mean($0,from:start,to:end,valid:0...100) }
            // All three or none: the copy promises three models, and two cannot show a spread honestly.
            if means.count==Self.modelKeys.count, let low=means.min(), let high=means.max() { outlook.agreement=ModelAgreement(low:low,high:high) }
        }
        if let layers, layers.usable(now:now) {
            if let low=layers.mean("cloud_cover_low",from:start,to:end,valid:0...100),
               let mid=layers.mean("cloud_cover_mid",from:start,to:end,valid:0...100),
               let high=layers.mean("cloud_cover_high",from:start,to:end,valid:0...100) { outlook.layers=CloudLayers(low:low,mid:mid,high:high) }
            if let temperatures=layers.values["temperature_2m"],
               let found=HourlyWindow.samples(times:layers.times,values:temperatures,from:start,to:end,valid:-90...60),
               let coldest=found.map(\.value).min() {
                outlook.coldest=coldest
                // When the coldest reading falls inside the window, for "by 5 AM": its timestamp,
                // kept within the window's ends.
                let hours=zip(layers.times,temperatures).filter { t,value in value==coldest && t+1800>start.timeIntervalSince1970 && t-1800<end.timeIntervalSince1970 }
                outlook.coldestAt=hours.first.map { min(end,max(start,Date(timeIntervalSince1970:$0.0))) }
            }
            if let temperatures=layers.values["temperature_2m"], let dew=layers.values["dew_point_2m"], temperatures.count==dew.count {
                // How close the air comes to its dew point; at 2 °C or less, glass left out collects dew.
                let margins=zip(temperatures,dew).map { t,d -> Double? in
                    guard let t,let d else { return nil }
                    return max(0,t-d)
                }
                outlook.dewMargin=HourlyWindow.samples(times:layers.times,values:margins,from:start,to:end,valid:0...150)?.map(\.value).min()
            }
            outlook.gust=layers.samples("wind_gusts_10m",from:start,to:end,valid:0...400,timing:.precedingHour)?.map(\.value).max()
            outlook.visibility=layers.mean("visibility",from:start,to:end,valid:0...200_000)
            // The chance of rain or snow in each hour, as Open-Meteo gives it: for the hour before the timestamp.
            outlook.rainChance=layers.samples("precipitation_probability",from:start,to:end,valid:0...100,timing:.precedingHour)?.map(\.value).max()
            outlook.weather=layers.samples("weather_code",from:start,to:end,valid:0...99).map { NightWeather(codes:$0.map { Int($0.value.rounded()) }) }
            outlook.waterVapour=layers.mean("total_column_integrated_water_vapour",from:start,to:end,valid:0...100)
        }
        if let air, air.usable(now:now) {
            outlook.aerosol=air.mean("aerosol_optical_depth",from:start,to:end,valid:0...10)
            outlook.dust=air.mean("dust",from:start,to:end,valid:0...20_000)
            outlook.fineParticles=air.mean("pm2_5",from:start,to:end,valid:0...20_000)
        }
        return outlook
    }
}

/// How far apart three forecast models' dark-window cloud averages are.
/// Bands, in percentage points of cloud cover between the clearest and cloudiest model:
/// 15 or less agree, 35 or less roughly agree, more than that disagree. Fifteen points is
/// about what one model's run-to-run noise looks like; past 35, the night could go either way.
nonisolated struct ModelAgreement: Sendable, Equatable {
    enum Band: String, Sendable { case agree, roughly, disagree }
    let low: Double
    let high: Double
    var spread: Double { high-low }
    var band: Band { Self.band(spread:spread) }
    static func band(spread: Double) -> Band { spread<=15 ? .agree : spread<=35 ? .roughly : .disagree }
    /// The word beside the cloud meter.
    var word: String {
        switch band {
        case .agree: String(localized:"Models agree")
        case .roughly: String(localized:"Roughly agree")
        case .disagree: String(localized:"Models differ")
        }
    }
    private var range: String {
        let a=Int(low.rounded()), b=Int(high.rounded())
        // Word joiners around the dash keep "0–17%" on one line.
        return a==b ? String(localized:"about \(a)%") : String(localized:"\(a)–\(b)%").replacingOccurrences(of:"–",with:"\u{2060}–\u{2060}")
    }
    /// One calm sentence. `tonight` changes only the advice for a disagreement.
    func sentence(tonight: Bool) -> String {
        switch band {
        case .agree where high<=15: return String(localized:"Clear in all three forecast models.")
        case .agree where low>=75: return String(localized:"Cloudy in all three forecast models.")
        case .agree: return String(localized:"All three forecast models agree: \(range) cloud.")
        case .roughly: return String(localized:"Forecast models roughly agree: \(range) cloud.")
        case .disagree: return tonight ? String(localized:"Models disagree: \(range) cloud. Check again before you leave.")
            : String(localized:"Models disagree: \(range) cloud. Check again tomorrow.")
        }
    }
}

/// Dark-window averages for each cloud layer, in percent.
nonisolated struct CloudLayers: Sendable, Equatable {
    let low: Double
    let mid: Double
    let high: Double
    /// Only when one layer clearly shapes the night; otherwise the total says enough.
    var note: String? {
        if high>=25 && low<15 && mid<15 { return String(localized:"Thin high cloud; bright stars only.") }
        if low>=25 && low>=mid && low>=high { return String(localized:"Mostly low cloud, which hides what it covers.") }
        if mid>=25 && mid>=high { return String(localized:"Mostly mid-level cloud.") }
        return nil
    }
}

/// Aerosol optical depth at 550 nm, averaged over the dark window (CAMS global via Open-Meteo,
/// CC BY 4.0). Bands: below 0.1 clean air; 0.1–0.25 light haze; 0.25–0.5 haze or smoke that
/// washes out the Milky Way; 0.5 and above heavy smoke or haze that hides faint stars.
nonisolated enum AirClarity: String, Sendable, Equatable {
    case clear, lightHaze, haze, heavy
    static func band(_ aod: Double) -> Self { aod<0.1 ? .clear : aod<0.25 ? .lightHaze : aod<0.5 ? .haze : .heavy }
    /// From 0.25 the caveat stands beside the score, like a closure.
    var isCaveat: Bool { self == .haze || self == .heavy }
    /// The short value beside "Air" on park detail. `dusty` names dust instead of smoke when dust
    /// makes most of the haze (`NightOutlook.dusty`); clean or lightly hazy air reads the same.
    func label(dusty: Bool = false) -> String {
        switch self {
        case .clear: String(localized:"Clear")
        case .lightHaze: String(localized:"Light haze")
        case .haze: dusty ? String(localized:"Dust or haze") : String(localized:"Haze or smoke")
        case .heavy: dusty ? String(localized:"Heavy dust or haze") : String(localized:"Heavy smoke or haze")
        }
    }
    func sentence(dusty: Bool = false) -> String {
        switch self {
        case .clear: String(localized:"Clear air.")
        case .lightHaze: String(localized:"Light haze.")
        case .haze: dusty ? String(localized:"Dust in the air: the Milky Way will look faint.") : String(localized:"Haze or smoke: the Milky Way will look faint.")
        case .heavy: dusty ? String(localized:"Heavy dust in the air: faint stars hidden.") : String(localized:"Heavy smoke or haze: faint stars hidden.")
        }
    }
}

/// The smoke caveat beside a score, one rule for every device (iPhone, iPad, Apple Watch, Vision Pro):
/// from the air the score itself counted, haze or smoke from 0.25 (`AirClarity.isCaveat`), whether or
/// not it is what holds the score down. Smoke's words; dust is named only in the park's air details.
nonisolated extension Night {
    var airClarity: AirClarity? { aerosol.map(AirClarity.band) }
    /// "Haze or smoke: the Milky Way will look faint." or "Heavy smoke or haze: faint stars hidden."
    var smokeCaveat: String? { airClarity.flatMap { $0.isCaveat ? $0.sentence() : nil } }
    /// "Haze or smoke" or "Heavy smoke or haze", where a line is short.
    var smokeCaveatLabel: String? { airClarity.flatMap { $0.isCaveat ? $0.label() : nil } }
}

/// What the forecast's hourly weather codes (WMO 4677, as Open-Meteo gives them) show in a window:
/// 45 and 48 fog; 51–67 and 80–82 drizzle and rain; 71–77, 85 and 86 snow; 95–99 thunderstorms.
nonisolated struct NightWeather: Sendable, Equatable {
    var fog=false, rain=false, snow=false, thunder=false
    init(codes: [Int]) {
        for code in codes {
            switch code {
            case 45, 48: fog=true
            case 51...67, 80...82: rain=true
            case 71...77, 85, 86: snow=true
            case 95...99: thunder=true
            default: break
            }
        }
    }
}

/// One night's context. Nothing here changes the score.
nonisolated struct NightOutlook: Sendable, Equatable {
    var agreement: ModelAgreement?
    var layers: CloudLayers?
    /// °C, the coldest hour in the window, and when it begins.
    var coldest: Double?
    var coldestAt: Date?
    /// The smallest gap between temperature and dew point, °C.
    var dewMargin: Double?
    /// km/h, the strongest gust.
    var gust: Double?
    /// Metres, mean. A haze hint only: weather-model visibility is coarse.
    var visibility: Double?
    var aerosol: Double?
    /// µg/m³ near the ground, means over the window: dust, and all fine particles (smoke, haze and fine dust).
    var dust: Double?
    var fineParticles: Double?
    /// Percent, the highest hourly chance of rain or snow in the window.
    var rainChance: Double?
    /// What the forecast's weather codes show in the window.
    var weather: NightWeather?
    /// kg/m² (the same number as millimetres of water), mean: all the water vapour above the place.
    var waterVapour: Double?
    /// The score with the clearest and the cloudiest model in place of the best-match clouds,
    /// widened to hold the night's own score (`PlanModel.outlook`).
    var scoreRange: ClosedRange<Int>?
    var clarity: AirClarity? { aerosol.map(AirClarity.band) }
    var dewLikely: Bool { dewMargin.map { $0<=2 } ?? false }
    /// Dust makes most of the haze: at least 50 µg/m³ of it, more than all the fine particles together.
    /// Smoke is fine particles; desert dust is mostly coarser, so a dust storm shows as more dust than PM2.5.
    var dusty: Bool { dust.map { $0>=50 && $0>(fineParticles ?? 0) } ?? false }
    /// Visibility speaks only when the aerosol forecast cannot, only below 10 km, and not in fog,
    /// which the fog line already names.
    var hazeHint: Double? { aerosol == nil && weather?.fog != true ? visibility.flatMap { $0<10_000 ? $0 : nil } : nil }
    /// Very dry, clean, clear air: under 10 kg/m² of water vapour (desert winter is 5 to 8; a humid
    /// summer night 30 to 50), no haze in the aerosol forecast when there is one, and no more than a
    /// trace of cloud in any layer. Water vapour hardly dims starlight itself, but humid air carries
    /// haze, so this is a pointer to unusually transparent air, never part of the score. Not with
    /// dew likely or fog: the air at the ground is then near saturation, and "very dry" beside
    /// "Dew likely on lenses" would read as a contradiction even where both are true.
    var crispAir: Bool {
        guard let waterVapour, waterVapour<10, !dewLikely, weather?.fog != true else { return false }
        if let aerosol, aerosol>=0.1 { return false }
        if let layers, max(layers.low,layers.mid,layers.high)>=10 { return false }
        return true
    }
    var isEmpty: Bool { self == NightOutlook() }
}
nonisolated extension NightOutlook {
    /// One night's outlook from its park's forecast detail, with the models' range of scores: the
    /// same caps as the score itself, smoke included. Agreement is kept only beside a score that
    /// includes clouds, so the two never contradict each other. The range is widened to hold the
    /// score itself: its best-match clouds can sit just outside the three models' averages, and a
    /// range beside a score must never leave that score out. One rule for the iPhone's dial, time
    /// river, chart and every spoken sentence (`PlanModel.outlook`), and for the range the iPhone
    /// hands Apple Watch (`WatchContext.ranges`).
    static func of(_ night: Night, detail: ForecastDetail, now: Date, scoring: any ScoreProviding) -> NightOutlook? {
        let window=night.sky.cloudWindow
        var outlook=detail.outlook(from:window.start,to:window.end,now:now)
        // The smoke words describe the smoke the score counted, whatever the aerosol forecast's age.
        outlook.aerosol=night.aerosol
        if night.score.hasForecast, !night.upperCloudOnly, let agreement=outlook.agreement {
            let aerosol=night.aerosol
            let clearest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloud:agreement.low,basis:.forecast,aerosol:aerosol).value
            let cloudiest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloud:agreement.high,basis:.forecast,aerosol:aerosol).value
            let score=night.score.value
            outlook.scoreRange=min(clearest,cloudiest,score)...max(clearest,cloudiest,score)
        } else { outlook.agreement=nil }
        return outlook.isEmpty ? nil : outlook
    }
    /// The models' range a dial draws around a score: only on a night whose clouds are a full
    /// forecast, only when the models do not agree (where the time river and the Clouds tile say
    /// "Forecast models agree", the dial never shows a spread), and only when it spans more than
    /// 4 points, below which a band would read as noise around the tip.
    func dialRange(basis: CloudBasis) -> ClosedRange<Int>? {
        guard basis == .forecast, let agreement, agreement.band != .agree,
              let models=scoreRange, models.upperBound-models.lowerBound>4 else { return nil }
        return models
    }
}
extension NightOutlook {
    static func temperature(_ celsius: Double) -> String {
        Measurement(value:celsius,unit:UnitTemperature.celsius).formatted(.measurement(width:.abbreviated,usage:.weather,numberFormatStyle:.number.precision(.fractionLength(0))))
    }
    static func speed(_ kmh: Double) -> String {
        Measurement(value:kmh,unit:UnitSpeed.kilometersPerHour).formatted(.measurement(width:.abbreviated,usage:.wind,numberFormatStyle:.number.precision(.fractionLength(0))))
    }
    static func distance(_ metres: Double) -> String {
        Measurement(value:metres,unit:UnitLength.meters).formatted(.measurement(width:.abbreviated,usage:.visibility,numberFormatStyle:.number.precision(.fractionLength(0))))
    }
    var gustText: String? {
        gust.map { $0<15 ? String(localized:"Light wind") : String(localized:"Gusts to \(Self.speed($0))") }
    }
    var hazeText: String? {
        hazeHint.map { String(localized:"Visibility forecast about \(Self.distance($0)); haze is possible.") }
    }
    /// The air on park detail and in the breakdown, dust named when dust makes the haze.
    nonisolated var airLabel: String? { clarity?.label(dusty:dusty) }
    nonisolated var airSentence: String? { clarity?.sentence(dusty:dusty) }
    /// "Clean" only when the aerosol forecast says so; without one, only the dryness is known.
    nonisolated var crispText: String? {
        guard crispAir else { return nil }
        return aerosol == nil ? String(localized:"Very dry air: good for faint stars.") : String(localized:"Very dry, clean air: good for faint stars.")
    }
    /// Rain, snow or thunderstorms, as one line with its symbol: shown for any thunderstorm in the
    /// forecast, or when the chance of rain or snow reaches 25% in some hour of the window.
    nonisolated var precipitationLine: (symbol: String, text: String)? {
        let chance=rainChance.map { Int($0.rounded()) }
        let weather=weather ?? NightWeather(codes:[])
        guard weather.thunder || (chance ?? 0)>=25 || (chance == nil && (weather.snow || weather.rain)) else { return nil }
        if weather.thunder {
            guard let chance, chance>=10 else { return ("cloud.bolt",String(localized:"Thunderstorms possible")) }
            return ("cloud.bolt",String(localized:"Thunderstorms possible, up to \(chance)% chance of rain"))
        }
        if weather.snow { return ("cloud.snow",chance.map { String(localized:"Snow possible, up to \($0)% chance") } ?? String(localized:"Snow possible")) }
        return ("cloud.rain",chance.map { String(localized:"Rain possible, up to \($0)% chance") } ?? String(localized:"Rain possible"))
    }
    nonisolated var fogText: String? { weather?.fog == true ? String(localized:"Fog possible, mostly in low ground") : nil }
}
