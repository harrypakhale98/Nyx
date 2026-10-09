import Foundation

/// "Feel the night under your finger": the sky arc explored by touch. With VoiceOver on, a double
/// tap hands the arc to the finger (`accessibilityDirectTouch`); sliding across it plays a hum
/// whose strength follows the sky at that moment, a firm click where true darkness begins and
/// ends, a light tick at moonrise and moonset, and a resting finger hears the time and the sky.
///
/// Built from the same 96 columns `SkyArc` paints, and the hum's strength is Feel tonight's own
/// (`NightTouch.strength`, from `NightSonification`'s darkness and moonlight), so the finger, the
/// played night and Listen to tonight always agree. Pure, for tests.
nonisolated enum ArcTouch {
    /// The arc's sky columns (`SkyArc.draw`).
    static let columnCount=96

    /// A moment the finger crosses.
    enum Milestone: String, Sendable, Equatable {
        case darknessBegins, darknessEnds, moonrise, moonset
        /// True darkness's edges click firmly; the Moon's only ticks.
        var firm: Bool { self == .darknessBegins || self == .darknessEnds }
    }
    /// The sky in a column, in the words the finger hears.
    enum Sky: Sendable, Equatable { case sunUp, twilight, darkness }

    struct Column: Sendable, Equatable {
        /// The column's middle, where its sky is read.
        let date: Date
        let span: DateInterval
        /// The hum, 0.12 (dusk) to 1 (true darkness, no Moon).
        let strength: Double
        let sky: Sky
        let moonUp: Bool
        /// The moments inside this column, earliest first.
        let crossings: [Milestone]
    }
    struct Sample: Sendable, Equatable {
        let column: Int
        let strength: Double
        /// The moment in the finger's column, true darkness's edges first.
        let crossing: Milestone?
        let spoken: String
    }

    /// The arc's time span: sunset minus an hour to sunrise plus an hour, or 18:00–06:00 park time
    /// when the Sun never crosses (`SkyArc` draws the same window).
    static func window(_ night: Night) -> (start: Date, end: Date) {
        if let sunset=night.sky.sunset, let sunrise=night.sky.sunrise, sunrise>sunset {
            return (sunset.addingTimeInterval(-3600), sunrise.addingTimeInterval(3600))
        }
        return (night.sky.evening.addingTimeInterval(6*3600), night.sky.evening.addingTimeInterval(18*3600))
    }

    /// Every column of the arc, worked out once when the finger lands.
    static func columns(night: Night, window: (start: Date, end: Date), engine: AstronomyEngine=AstronomyEngine()) -> [Column] {
        let park=night.park, sky=night.sky
        let duration=max(1, window.end.timeIntervalSince(window.start)), step=duration/Double(columnCount)
        let lit=sky.moon.illumination
        var moments: [(Date, Milestone)]=[]
        if let start=sky.darkStart, let end=sky.darkEnd, end>start, sky.darkHours>0 {
            moments.append((start, .darknessBegins)); moments.append((end, .darknessEnds))
        }
        if let rise=sky.moonrise { moments.append((rise, .moonrise)) }
        if let set=sky.moonset { moments.append((set, .moonset)) }
        moments.sort { $0.0<$1.0 }
        return (0..<columnCount).map { i in
            let span=DateInterval(start: window.start.addingTimeInterval(Double(i)*step), duration: step)
            let mid=span.start.addingTimeInterval(step/2)
            let sun=engine.solarAltitude(at: mid, park: park), moon=engine.lunarAltitude(at: mid, park: park)
            let strength=NightTouch.strength(darkness: NightSonification.darkness(sunAltitude: sun), moonlight: lit*min(1, max(0, moon/3)))
            let state: Sky
            if let start=sky.darkStart, let end=sky.darkEnd, sky.darkHours>0, mid>=start, mid<end { state = .darkness }
            else if sun > -0.833 { state = .sunUp }
            else { state = .twilight }
            // The last column also holds a moment landing exactly on the window's end.
            let inside=moments.filter { $0.0>=span.start && ($0.0<span.end || (i == columnCount-1 && $0.0 <= span.end)) }.map { $0.1 }
            return Column(date: mid, span: span, strength: strength, sky: state, moonUp: moon>0, crossings: inside)
        }
    }

    /// The column under a finger at `x` across an arc `width` wide.
    static func index(x: Double, width: Double) -> Int {
        guard width>0 else { return 0 }
        return min(columnCount-1, max(0, Int(x/width*Double(columnCount))))
    }

    /// What the finger feels and would hear at `x`.
    static func sample(x: Double, width: Double, night: Night, window: (start: Date, end: Date), tonight: Bool=true) -> Sample {
        sample(x: x, width: width, columns: columns(night: night, window: window), night: night, tonight: tonight)
    }
    /// The same, from columns already worked out (the gesture's fast path).
    static func sample(x: Double, width: Double, columns: [Column], night: Night, tonight: Bool=true) -> Sample {
        let i=min(columns.count-1, index(x: x, width: width))
        guard i>=0 else { return Sample(column: 0, strength: 0, crossing: nil, spoken: "") }
        let column=columns[i]
        return Sample(column: i, strength: column.strength, crossing: column.crossings.first(where: \.firm) ?? column.crossings.first, spoken: spoken(column, night: night, tonight: tonight))
    }

    /// The moments between two columns the finger passed, in the order it met them (the column it
    /// left excluded), so a quick slide still clicks at true darkness.
    static func crossed(_ columns: [Column], from: Int, to: Int) -> [Milestone] {
        guard from != to, columns.indices.contains(from), columns.indices.contains(to) else { return [] }
        let path=from<to ? Array((from+1)...to) : Array((to..<from).reversed())
        return path.flatMap { from<to ? columns[$0].crossings : columns[$0].crossings.reversed() }
    }

    /// "10:40 PM. True darkness. Moon down." Park-local, to the nearest five minutes: a fingertip
    /// covers several minutes of the arc, so a minute would claim more than the touch knows. On a
    /// night without true darkness, the arc's own sentence follows.
    static func spoken(_ column: Column, night: Night, tonight: Bool=true) -> String {
        let line=caption(column, night: night)
        return night.sky.darkHours==0 ? line+" "+SkyConditions.noDarknessMessage(tonight: tonight) : line
    }
    /// The time and the sky alone, for the label beside the finger.
    static func caption(_ column: Column, night: Night) -> String {
        let rounded=Date(timeIntervalSince1970: (column.date.timeIntervalSince1970/300).rounded()*300)
        let time=night.park.time(rounded)
        switch column.sky {
        case .darkness: return column.moonUp ? String(localized: "\(time). True darkness. Moon up.") : String(localized: "\(time). True darkness. Moon down.")
        case .twilight: return column.moonUp ? String(localized: "\(time). Twilight. Moon up.") : String(localized: "\(time). Twilight.")
        case .sunUp: return String(localized: "\(time). Sun up.")
        }
    }
}
