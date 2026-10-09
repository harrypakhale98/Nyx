import Foundation

/// The Vision Pro sky's words for a named star, on its name card and for VoiceOver. Tonight's sky
/// on iPhone says where a star is in its own words (`PanoramaCanvas.summary`).
extension SkyLore {
    /// Where to look, in words: "high in the west", "low in the northeast", "nearly overhead".
    nonisolated static func direction(altitude: Double, azimuth: Double) -> String {
        if altitude >= 75 { return String(localized: "nearly overhead") }
        let compass = Compass.name(azimuth)
        return altitude >= 30 ? String(localized: "high in the \(compass)") : altitude < 15 ? String(localized: "low in the \(compass)") : String(localized: "in the \(compass)")
    }
    /// A star's brightness in words, for the name card.
    nonisolated static func brightness(_ magnitude: Double) -> String {
        magnitude < 0.5 ? String(localized: "one of the brightest stars")
            : magnitude < 1.5 ? String(localized: "a bright star")
            : magnitude < 2.5 ? String(localized: "easy to see")
            : String(localized: "easy to see from a dark site")
    }
}
