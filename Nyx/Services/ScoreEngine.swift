import Foundation

nonisolated protocol ScoreProviding: Sendable {
    func score(sky: SkyConditions, bortle: Int, cloudCover: Double?) -> DarknessScore
}
nonisolated struct ScoreEngine: ScoreProviding {
    /// 40 moon + 25 clouds + 20 Bortle + 15 duration. Moon darkness starts at
    /// 1-illumination; regain the lost illumination in proportion to the dark
    /// window with the Moon below the horizon. Bortle 1 -> 1, Bortle 9 -> 0.
    /// No clouds: divide by 0.75; never substitute a clear-sky forecast.
    /// Zero true darkness: no length / horizon bonus and cap the final score
    /// at 39 (Poor), avoiding a 'Pristine' polar summer despite a new moon.
    func score(sky: SkyConditions, bortle: Int, cloudCover: Double?) -> DarknessScore {
        let below = sky.darkHours>0 ? sky.moonBelowFraction : 0
        let moon = 40 * (1-sky.moon.illumination + sky.moon.illumination*below)
        let cloud = cloudCover.flatMap { $0.isFinite ? 25*(1-min(100,max(0,$0))/100) : nil }
        let light = 20 * Double(9-min(9,max(1,bortle)))/8
        let length = 15 * min(1,max(0,sky.darkHours)/10)
        let divisor = cloud == nil ? 0.75 : 1.0
        let raw = Int(((moon+(cloud ?? 0)+light+length)/divisor).rounded())
        return DarknessScore(value: min(sky.darkHours>0 ? 100 : 39,max(0,raw)), moonPoints: moon/divisor,
            cloudPoints: cloud.map { $0/divisor }, bortlePoints: light/divisor, lengthPoints: length/divisor)
    }
}
