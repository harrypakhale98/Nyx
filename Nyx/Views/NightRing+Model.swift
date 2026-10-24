import SwiftUI

extension PlanModel {
    /// A night's ring for the dial, with its best window and, while the night lasts, where it has got to.
    /// A clear stretch under a bright Moon is not lit as the best (`ClearWindow.brightest`).
    func ring(_ night: Night, now: Date = .now) -> (ring: NightRing, park: Park, spoken: String)? {
        let window=clearWindow(night)?.brightest
        guard let ring=NightRing(sky: night.sky, park: night.park, best: window, now: now) else { return nil }
        return (ring, night.park, ring.spoken(sky: night.sky, park: night.park, best: window))
    }
}
#Preview("Night ring • moonlit") {
    let m=PlanModel()
    if let p=m.park("jotr") { let n=m.night(p,on:Date(timeIntervalSince1970:1792800000)); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyxReduceMotion,true).frame(height:300).background(.black) }
}
#Preview("Night ring • new moon") {
    let m=PlanModel()
    if let p=m.park("jotr") { let n=m.night(p,on:Date(timeIntervalSince1970:1794700000)); CelestialGauge(score:n.score.value,night:m.ring(n)).frame(height:300).background(.black) }
}
#Preview("Night ring • Alaska June, no true darkness") {
    let m=PlanModel()
    if let p=m.park("dena") { let n=m.night(p,on:Date(timeIntervalSince1970:1813564800)); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyxReduceMotion,true).frame(height:300).background(.black) }
}
#Preview("Night ring • night vision • AX5") {
    let m=PlanModel()
    if let p=m.park("grba") { let n=m.night(p); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).dynamicTypeSize(.accessibility5).background(.black) }
}
