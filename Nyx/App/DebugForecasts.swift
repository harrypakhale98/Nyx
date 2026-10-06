#if DEBUG
import Foundation

/// Screenshot and review fixtures for the forecast's context: `-nyx-state agree`, `disagree` and
/// `smoke`. DEBUG only; Release builds never contain them and normal launches never use them.
struct DebugForecasts {
    let forecasts: [String: Forecast]
    let details: [String: ForecastDetail]
    init?(state: String, parks: [Park], now: Date) {
        guard ["agree","disagree","smoke"].contains(state) else { return nil }
        // Hours from 00:00 UTC yesterday, as the real requests return them.
        let first=(floor(now.timeIntervalSince1970/86400)-1)*86400
        let detailHours=(0..<8*24).map { first+Double($0)*3600 }
        let cloudHours=(0..<17*24).map { first+Double($0)*3600 }
        func day(_ t: Double) -> Int { Int((t-first)/86400) }
        /// Models' clouds per day: a different spread each night, so the river shows its whiskers.
        let spreads: [Double]=[4,42,26,8,52,18,34,12]
        func model(_ index: Int, _ t: Double) -> Double {
            switch state {
            case "disagree": let s=spreads[min(spreads.count-1,day(t))]; return [4, 4+s/2, 4+s][index]
            case "smoke": return [3,5,6][index]
            default: return [2,4,7][index]
            }
        }
        func base(_ t: Double) -> Double { day(t)<8 ? model(1,t) : 10 }
        func hourOfDay(_ t: Double) -> Double { (t.truncatingRemainder(dividingBy:86400))/3600 }
        var forecasts: [String: Forecast]=[:], details: [String: ForecastDetail]=[:]
        for park in parks {
            // A night that cools toward dawn, park-local.
            let offset=Double(park.timeZone.secondsFromGMT(for:now))/3600
            func temperature(_ t: Double) -> Double {
                let local=(hourOfDay(t)+offset+24).truncatingRemainder(dividingBy:24)
                let warm: Double=state=="agree" ? 9 : state=="smoke" ? 22 : 14
                return warm-8+8*cos((local-15)/24*2 * .pi)
            }
            func dew(_ t: Double) -> Double { state=="agree" ? temperature(t)-1.5 : temperature(t)-7 }
            forecasts[park.id]=Forecast(updated:now,times:cloudHours,clouds:cloudHours.map { base($0) })
            let models=HourlySeries(updated:now,times:detailHours,values:Dictionary(uniqueKeysWithValues:ForecastDetail.modelKeys.enumerated().map { index,key in
                (key,detailHours.map { Optional(model(index,$0)) })
            }))
            let high: Double=state=="disagree" ? 38 : 4
            let layers=HourlySeries(updated:now,times:detailHours,values:[
                "cloud_cover_low":detailHours.map { _ in 2 }, "cloud_cover_mid":detailHours.map { _ in 3 }, "cloud_cover_high":detailHours.map { _ in high },
                "temperature_2m":detailHours.map { temperature($0) }, "dew_point_2m":detailHours.map { dew($0) },
                "wind_gusts_10m":detailHours.map { _ in state=="agree" ? 34 : state=="smoke" ? 22 : 9 },
                "visibility":detailHours.map { _ in state=="smoke" ? 6_000 : 40_000 }
            ])
            // CAMS reaches about five and a half days; later hours are null, as in the real payload.
            let aod: Double=state=="smoke" ? 0.38 : state=="agree" ? 0.04 : 0.12
            let air=HourlySeries(updated:now,times:detailHours,values:[
                "aerosol_optical_depth":detailHours.map { $0<first+6.5*86400 ? aod : nil },
                "pm2_5":detailHours.map { $0<first+6.5*86400 ? aod*90 : nil }
            ])
            details[park.id]=ForecastDetail(models:models,layers:layers,air:air)
        }
        self.forecasts=forecasts; self.details=details
    }
}
#endif
