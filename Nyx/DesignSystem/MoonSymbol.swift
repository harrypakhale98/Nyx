import SwiftUI

/// The phase as a symbol, for Lock Screen widgets and complications where a drawn disc would be
/// too small or would lose its terminator to the host's tint. Turned for the southern sky
/// (American Samoa sees the Moon upside down). Shared by the iPhone widgets and the watch.
struct MoonSymbol: View {
    let night: Night
    var body: some View {
        Image(systemName: night.sky.moon.symbolName)
            .scaleEffect(x: night.park.latitude < 0 ? -1 : 1, y: night.park.latitude < 0 ? -1 : 1)
            .accessibilityLabel("\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded())) percent lit")
    }
}

extension MoonPhase {
    /// The SF Symbol for this phase, on the same boundaries as `name`.
    nonisolated var symbolName: String {
        switch fraction {
        case ..<0.03, 0.97...: "moonphase.new.moon"
        case ..<0.22: "moonphase.waxing.crescent"
        case ..<0.28: "moonphase.first.quarter"
        case ..<0.47: "moonphase.waxing.gibbous"
        case ..<0.53: "moonphase.full.moon"
        case ..<0.72: "moonphase.waning.gibbous"
        case ..<0.78: "moonphase.last.quarter"
        default: "moonphase.waning.crescent"
        }
    }
}
