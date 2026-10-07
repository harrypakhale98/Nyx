import Foundation

nonisolated protocol ScoreProviding: Sendable {
    func score(sky: SkyConditions, bortle: Int, cloud: Double?, basis: CloudBasis, aerosol: Double?) -> DarknessScore
}
extension ScoreProviding {
    /// A night scored with `cloudCover` as a forecast (nil: no cloud figure at all), no smoke cap.
    nonisolated func score(sky: SkyConditions, bortle: Int, cloudCover: Double?) -> DarknessScore {
        score(sky: sky, bortle: bortle, cloud: cloudCover, basis: cloudCover == nil ? .usual : .forecast, aerosol: nil)
    }
}
nonisolated struct ScoreEngine: ScoreProviding {
    /// Four parts are added, then the weakest link caps the sum.
    ///
    /// **Parts** (the product brief's weights): 40 moon + 25 clouds + 20 Bortle + 15 duration.
    /// - Moon: 40 × (1 − moonlight), where moonlight is the Krisciunas–Schaefer moonlight over
    ///   true darkness (`SkyConditions.moonlight`, 0 with no Moon, 1 for a full Moon high all
    ///   through it). With no true darkness there is no horizon credit: 40 × (1 − illumination).
    /// - Clouds: 25 × (1 − cloud%), where the cloud is the forecast, the park's usual clouds for
    ///   the month, or a blend by lead time (`CloudBasis`). Only when no cloud figure exists at
    ///   all are the other parts scaled by 1/0.75 (no park lacks usual clouds; kept as a guard).
    /// - Bortle: 20 × (9 − B)/8. Duration: 15 × min(1, dark hours / 10).
    ///
    /// **Caps** (the score is the lowest of the sum and each cap; `DarknessScore.limit` names the
    /// one that binds, so the breakdown can say it in plain words):
    /// - Darkness: no true darkness caps at 39 (Poor), lifting smoothly over the first three hours.
    /// - Clouds: 100 − 0.9 × cloud% (overcast 10, 80% 28, 50% 55, 30% 73, 10% 91). Additive clouds
    ///   alone could never pull a moonless desert night below Good; a cap can.
    /// - Sky glow: Bortle 1–2 100, 3 89, 4 84, 5 74, 6 59, 7 and above 39. "Pristine" needs a
    ///   Bortle 2 sky or darker.
    /// - Smoke: aerosol optical depth 0.25–0.5 caps at 74 (Good at most), 0.5 and above at 59
    ///   (Fair at most). Unknown aerosol caps nothing.
    func score(sky: SkyConditions, bortle: Int, cloud cloudCover: Double?, basis: CloudBasis, aerosol: Double?) -> DarknessScore {
        let dark = sky.darkHours>0
        let light = dark ? (sky.moonlight ?? sky.moon.illumination*(1-sky.moonBelowFraction)) : sky.moon.illumination
        let moon = 40 * (1-min(1,max(0,light)))
        let cloud = cloudCover.flatMap { $0.isFinite ? min(100,max(0,$0)) : nil }
        let cloudPoints = cloud.map { 25*(1-$0/100) }
        let glow = 20 * Double(9-min(9,max(1,bortle)))/8
        let length = 15 * min(1,max(0,sky.darkHours)/10)
        let divisor = cloudPoints == nil ? 0.75 : 1.0
        let sum = max(0, Int(((moon+(cloudPoints ?? 0)+glow+length)/divisor).rounded()))
        // In order of precedence on a tie: the darkness first, then the clouds, smoke and glow.
        let caps: [ScoreLimit] = [.darkness(Self.cap(darkHours: sky.darkHours)), cloud.map { .clouds(Self.cloudCap($0)) },
                                  aerosol.flatMap(Self.smokeCap).map { .smoke($0) }, .skyGlow(Self.glowCap(bortle: bortle))].compactMap { $0 }
        let binding = caps.filter { $0.cap<sum }.min { $0.cap<$1.cap }
        return DarknessScore(value: binding?.cap ?? sum, moonPoints: moon/divisor, cloudPoints: cloudPoints,
                             bortlePoints: glow/divisor, lengthPoints: length/divisor, basis: cloud == nil ? .usual : basis, cloudUsed: cloud, limit: binding)
    }
    /// The highest score a night can reach given its hours of true darkness.
    static func cap(darkHours: Double) -> Int {
        guard darkHours.isFinite, darkHours>0 else { return 39 }
        return min(100, Int((39 + 61*darkHours/3).rounded(.down)))
    }
    /// The highest score a night can reach under `cloud` percent cover.
    static func cloudCap(_ cloud: Double) -> Int { Int((100-0.9*min(100,max(0,cloud))).rounded()) }
    /// The highest score a park's sky glow allows, by its Bortle class.
    static func glowCap(bortle: Int) -> Int {
        switch bortle { case ...2: 100; case 3: 89; case 4: 84; case 5: 74; case 6: 59; default: 39 }
    }
    /// The highest score smoke or haze allows; nil below an aerosol optical depth of 0.25.
    static func smokeCap(_ aerosol: Double) -> Int? {
        guard aerosol.isFinite else { return nil }
        return aerosol>=0.5 ? 59 : aerosol>=0.25 ? 74 : nil
    }
}
