import Foundation

/// Coordinates as people type or paste them, read on this device: decimal degrees ("34.01, -116.18"),
/// with or without degree signs and hemisphere letters ("34.01° N, 116.18° W", "N34.01 W116.18"),
/// and degrees, minutes and seconds ("34°0'45\"N 116°10'44\"W"). A minus may be a hyphen or the
/// typographic minus. With hemisphere letters the pair may come in either order; without them,
/// latitude comes first, as maps write it. A decimal comma is read where nothing else could be
/// meant: "34,01; -116,18" (a semicolon between) or "34,01 -116,18" (a space between, no points).
nonisolated enum CoordinateText {
    struct Point: Equatable, Sendable {
        let latitude: Double
        let longitude: Double
    }
    enum Axis: Sendable {
        case latitude, longitude
        var limit: Double { self == .latitude ? 90 : 180 }
    }
    /// What one field holds.
    enum Reading: Equatable, Sendable { case empty, value(Double), outOfRange, unreadable }
    /// What a whole pasted pair holds.
    enum PairReading: Equatable, Sendable { case point(Point), outOfRange, unreadable }

    /// Both coordinates from one string.
    static func pair(_ text: String) -> PairReading {
        guard let groups=groups(text), groups.count == 2 else { return .unreadable }
        let first=groups[0], second=groups[1]
        let latitude: Double, longitude: Double
        switch (first.axis, second.axis) {
        case (.latitude?, .latitude?), (.longitude?, .longitude?): return .unreadable
        case (.longitude?, _), (_, .latitude?): latitude=second.value; longitude=first.value
        default: latitude=first.value; longitude=second.value
        }
        guard abs(latitude) <= 90, abs(longitude) <= 180 else { return .outOfRange }
        return .point(Point(latitude: latitude, longitude: longitude))
    }
    /// The pair as a point, or nil when it is unreadable or out of range.
    static func point(_ text: String) -> Point? {
        if case .point(let point)=pair(text) { return point }
        return nil
    }
    /// One coordinate from its own field. A hemisphere letter must belong to the field's axis.
    static func reading(_ text: String, axis: Axis) -> Reading {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        guard let groups=groups(text), groups.count == 1, let group=groups.first, group.axis == nil || group.axis == axis else { return .unreadable }
        return abs(group.value) <= axis.limit ? .value(group.value) : .outOfRange
    }
    /// A coordinate written back for a field: up to six decimals (about 10 cm), a point for the
    /// decimal mark whatever the region, so the field reads it again exactly.
    static func field(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    // MARK: Reading

    private struct Group { let value: Double; let axis: Axis? }
    private enum Token: Equatable { case number(Double, negative: Bool), degree, minute, second, hemisphere(Character), separator }
    private enum Unit { case degree, minute, second }

    /// The coordinates in the text, each with its axis when a hemisphere letter names it; nil when
    /// anything in it cannot be read.
    private static func groups(_ text: String) -> [Group]? {
        guard let tokens=tokens(normalized(text)) else { return nil }
        var groups: [Group]=[]
        var current=Partial()
        func close() -> Bool {
            guard !current.parts.isEmpty else { current=Partial(); return true }
            guard let group=current.group() else { return false }
            groups.append(group); current=Partial(); return true
        }
        for token in tokens {
            switch token {
            case .separator:
                guard close() else { return nil }
            case .hemisphere(let letter):
                if current.parts.isEmpty {
                    guard current.prefix == nil else { return nil }
                    current.prefix=letter
                } else if current.prefix != nil {
                    // "N 34.01 W 116.18": the letter begins the next coordinate.
                    guard close() else { return nil }
                    current.prefix=letter
                } else {
                    current.suffix=letter
                    guard close() else { return nil }
                }
            case .number(let value, let negative):
                if let last=current.parts.last {
                    // After degrees or minutes, an unsigned number is the next part ("34°0 45");
                    // after a bare number or seconds, it begins the next coordinate.
                    if let unit=last.unit, unit != .second, !negative, current.parts.count < 3 {
                        current.parts.append((value, nil))
                        continue
                    }
                    guard close() else { return nil }
                }
                current.parts.append((value, nil)); current.negative=negative
            case .degree, .minute, .second:
                let unit: Unit=token == .degree ? .degree : token == .minute ? .minute : .second
                guard let index=current.parts.indices.last, current.parts[index].unit == nil else { return nil }
                let expected: Unit=index == 0 ? .degree : index == 1 ? .minute : .second
                // "34'" alone is not a coordinate, and a mark must follow the one before it.
                guard unit == expected else { return nil }
                current.parts[index].unit=unit
            }
        }
        guard close() else { return nil }
        return groups
    }
    private struct Partial {
        var parts: [(value: Double, unit: Unit?)]=[]
        var negative=false
        var prefix: Character?
        var suffix: Character?
        func group() -> Group? {
            guard let degrees=parts.first?.value else { return nil }
            var value=degrees
            if parts.count > 1 {
                // Minutes and seconds need whole degrees (and seconds whole minutes), and stay under 60.
                guard parts[0].unit == .degree, degrees == degrees.rounded() else { return nil }
                let minutes=parts[1].value
                guard minutes < 60 else { return nil }
                value+=minutes/60
                if parts.count > 2 {
                    let seconds=parts[2].value
                    guard minutes == minutes.rounded(), seconds < 60 else { return nil }
                    value+=seconds/3600
                }
            }
            let letter=prefix ?? suffix
            let axis: Axis?=letter.map { $0 == "N" || $0 == "S" ? .latitude : .longitude }
            if let letter {
                // A sign and a letter must agree, or the text says two things.
                guard !negative else { return nil }
                return Group(value: letter == "S" || letter == "W" ? -value : value, axis: axis)
            }
            return Group(value: negative ? -value : value, axis: nil)
        }
    }
    private static func normalized(_ text: String) -> String {
        var text=text.uppercased()
        for (from, to) in [("\u{2212}", "-"), ("\u{2013}", "-"), ("\u{2014}", "-"), ("\u{2010}", "-"), ("\u{2011}", "-"),
                           ("º", "°"), ("˚", "°"), ("′", "'"), ("’", "'"), ("‘", "'"), ("´", "'"), ("`", "'"),
                           ("″", "\""), ("“", "\""), ("”", "\""), ("''", "\""), ("\u{00A0}", " ")] {
            text=text.replacingOccurrences(of: from, with: to)
        }
        // A decimal comma, only where it cannot be the separator: "34,01; -116,18", or two
        // comma-decimals with a space between and no point anywhere ("34,01 -116,18").
        if text.contains(";") {
            text=text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: ";", with: ",")
        } else if !text.contains("."), text.filter({ $0 == "," }).count == 2 {
            let words=text.split(whereSeparator: \.isWhitespace)
            if words.count == 2, words.allSatisfy({ word in word.filter { $0 == "," }.count == 1 && word.last != "," && word.first != "," }) {
                text=text.replacingOccurrences(of: ",", with: ".")
            }
        }
        return text
    }
    private static func tokens(_ text: String) -> [Token]? {
        var tokens: [Token]=[]
        let characters=Array(text)
        var index=0
        while index < characters.count {
            let character=characters[index]
            if character.isWhitespace { index+=1; continue }
            if character == "," || character == ";" || character == "/" { tokens.append(.separator); index+=1; continue }
            if character == "°" { tokens.append(.degree); index+=1; continue }
            if character == "'" { tokens.append(.minute); index+=1; continue }
            if character == "\"" { tokens.append(.second); index+=1; continue }
            if "NSEW".contains(character) {
                // A letter on its own, never part of a word ("NORTH", "LAT").
                if index+1 < characters.count, characters[index+1].isLetter { return nil }
                tokens.append(.hemisphere(character)); index+=1; continue
            }
            var negative=false
            if character == "-" || character == "+" {
                negative=character == "-"
                index+=1
                guard index < characters.count, characters[index].isASCIIDigit || characters[index] == "." else { return nil }
            }
            guard characters[index].isASCIIDigit || characters[index] == "." else { return nil }
            var number=""
            while index < characters.count, characters[index].isASCIIDigit || characters[index] == "." {
                number.append(characters[index]); index+=1
            }
            guard number.filter({ $0 == "." }).count <= 1, number != ".", let value=Double(number), value.isFinite else { return nil }
            tokens.append(.number(value, negative: negative))
        }
        return tokens
    }
}
private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}

/// The name a new spot is offered before the person types one.
nonisolated enum SpotNaming {
    /// A town farther than this says little about where the spot is: the coordinates name it instead.
    static let nearReach: Double=50_000
    /// "Near Twentynine Palms" within `nearReach` of the nearest town on Nyx's list, else its
    /// coordinates ("34.01° N, 116.18° W").
    static func defaultName(latitude: Double, longitude: Double, nearest: StartingPlace?) -> String {
        if let town=nearest, Park.distance(latitude, longitude, town.latitude, town.longitude) <= nearReach {
            return String(localized: "Near \(town.name)")
        }
        return coordinates(latitude: latitude, longitude: longitude)
    }
    /// With the nearest town looked up in the bundled list (on this device).
    static func defaultName(latitude: Double, longitude: Double) -> String {
        defaultName(latitude: latitude, longitude: longitude, nearest: StartingPlaces.nearest(latitude: latitude, longitude: longitude, within: nearReach))
    }
    /// "34.01° N, 116.18° W": two decimals, about a kilometre, enough to tell spots apart by name.
    static func coordinates(latitude: Double, longitude: Double) -> String {
        "\(hemisphere(latitude, axis: .latitude)), \(hemisphere(longitude, axis: .longitude))"
    }
    private static func hemisphere(_ value: Double, axis: CoordinateText.Axis) -> String {
        let degrees=abs(value).formatted(.number.precision(.fractionLength(2)))
        switch axis {
        case .latitude: return value < 0 ? String(localized: "\(degrees)° S") : String(localized: "\(degrees)° N")
        case .longitude: return value < 0 ? String(localized: "\(degrees)° W") : String(localized: "\(degrees)° E")
        }
    }
    /// The name a spot is saved under: what the person typed, trimmed, else the offered name.
    static func finalName(typed: String, offered: String) -> String {
        let trimmed=typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? offered : String(trimmed.prefix(maxLength))
    }
    /// Long enough for any place name; short enough for a widget and a Siri answer.
    static let maxLength=60
}
