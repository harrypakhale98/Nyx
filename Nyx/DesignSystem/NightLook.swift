import SwiftUI

// Night vision as it reaches surfaces outside the app's own windows, and the contrast arithmetic
// that keeps it legible. Apart from NyxTheme.swift (the app's views and its sky), so the widgets
// and complications compile this alone.

struct NightVisionFilter: ViewModifier {
    let enabled:Bool
    var red:NightTint = .standard
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? red.color : .white)
    }
}
/// One night look for what Nyx draws outside its own windows: the widgets, the Live Activity, the
/// alarm and Siri's cards. Night vision and the brighter-red choice come from the shared suite,
/// where the app, Control Center and field mode write them; Increase Contrast comes from the view
/// that draws, since an extension has no app root to read it once. Where nothing filters the
/// surface red (a widget, the Live Activity), `ink` and `accent` are the red itself; where Nyx
/// draws a whole card (Siri), `palette` with `NightVisionFilter` reddens it as the app does.
nonisolated struct NightLook: Equatable, Sendable {
    let nightVision: Bool
    let brighterRed: Bool
    let highContrast: Bool
    /// The night-vision switch's key in the shared defaults.
    static let nightVisionKey="nightVision"
    /// Starlight and moon-amber, gamma-encoded sRGB, from `NyxPalette`.
    static let starlight=NyxPalette.starlightRGB, amber=NyxPalette.amberRGB
    init(nightVision: Bool, brighterRed: Bool=false, highContrast: Bool=false) {
        self.nightVision=nightVision; self.brighterRed=brighterRed; self.highContrast=highContrast
    }
    /// From the shared settings. `nightVision` stands in for the stored switch on a surface that
    /// carries its own (a widget's entry, a Live Activity's state).
    init(defaults: UserDefaults=SharedSettings.defaults, contrast: ColorSchemeContrast = .standard, nightVision: Bool?=nil) {
        self.init(nightVision:nightVision ?? defaults.bool(forKey:Self.nightVisionKey),brighterRed:defaults.bool(forKey:NightTint.key),highContrast:contrast == .increased)
    }
    var palette: NyxPalette { NyxPalette(nightVision:nightVision,highContrast:highContrast,brighterRed:brighterRed) }
    /// The brighter red by choice or under Increase Contrast, as in the app.
    var red: NightTint { palette.red }
    var inkRGB: SIMD3<Double> { nightVision ? red.rgb : Self.starlight }
    var accentRGB: SIMD3<Double> { nightVision ? red.rgb : Self.amber }
    var ink: Color { Color(red:inkRGB.x,green:inkRGB.y,blue:inkRGB.z) }
    var accent: Color { Color(red:accentRGB.x,green:accentRGB.y,blue:accentRGB.z) }
    /// Secondary text. Night vision's red is already dim, so it stays near full, and full under
    /// Increase Contrast; starlight is held at 90% there, as in the app.
    var mutedOpacity: Double { nightVision ? (highContrast ? 1 : 0.9) : highContrast ? 0.9 : 0.7 }
    var muted: Color { ink.opacity(mutedOpacity) }
}
/// How text contrast holds up for the commonest colour-vision deficiencies: Machado, Oliveira and
/// Fernandes (2009) full-severity matrices, applied in linear RGB, then WCAG 2 contrast.
nonisolated enum ColorVision: String, Sendable, CaseIterable {
    case typical, protan, deutan
    private var matrix: [[Double]] {
        switch self {
        case .typical: [[1,0,0],[0,1,0],[0,0,1]]
        case .protan: [[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]]
        case .deutan: [[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]]
        }
    }
    /// Relative luminance of a gamma-encoded sRGB colour as these eyes see it.
    func luminance(_ rgb: SIMD3<Double>) -> Double {
        let l=[SRGB.linear(rgb.x),SRGB.linear(rgb.y),SRGB.linear(rgb.z)]
        let seen=matrix.map { row in min(1,max(0,zip(row,l).map(*).reduce(0,+))) }
        return 0.2126*seen[0]+0.7152*seen[1]+0.0722*seen[2]
    }
    /// WCAG contrast ratio between two colours, as these eyes see them.
    func contrast(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let x=luminance(a), y=luminance(b)
        return (max(x,y)+0.05)/(min(x,y)+0.05)
    }
}
