import Foundation

/// The usual temperatures of a month's nights, for planning past the forecast: from ERA5 (Copernicus
/// Climate Change Service, CC BY 4.0), monthly averages by hour of day over 2015–2024. For the curated
/// parks (`night-climate.json`) at the main viewing spot's own elevation; elsewhere from the bundled
/// world grid (`SkyGrid.nightTemperatures`), at the grid cell's model terrain where a place's
/// elevation is unknown. "Before dawn" is the coldest of the two hours before sunrise: a usual value,
/// about 1–3 °C warmer than the average nightly low, so it is never called the low. Checked against
/// NOAA's 1991–2020 normals at 31 park-area stations (bias 0.1 °C, typical error 1.4 °C on the same
/// definition); a valley floor can run 2–4 °C colder on clear winter nights than said.
nonisolated struct NightClimate: Sendable {
    nonisolated struct Months: Codable, Sendable, Equatable {
        let dawn: [Double]
        let evening: [Double]
        let dewSpread: [Double]
    }
    nonisolated struct Usual: Sendable, Equatable {
        let dawn: Double
        let evening: Double
        let dewSpread: Double
    }
    let parks: [String: Months]
    static let shared: NightClimate = load() ?? NightClimate(parks: [:])
    static func load(bundle: Bundle = .main) -> NightClimate? {
        guard let url = bundle.url(forResource: "night-climate", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let parks: [String: Months] }
        return (try? JSONDecoder().decode(File.self, from: data)).map { NightClimate(parks: $0.parks.filter { $0.value.dawn.count == 12 && $0.value.evening.count == 12 && $0.value.dewSpread.count == 12 }) }
    }
    /// A place's usual night in a month (1–12): a curated park's own figures, else the world grid's;
    /// nil where neither has one.
    func usual(_ park: Park, month: Int, grid: SkyGrid? = .shared) -> Usual? {
        guard (1...12).contains(month) else { return nil }
        if let months = parks[park.id] { return Usual(dawn: months.dawn[month-1], evening: months.evening[month-1], dewSpread: months.dewSpread[month-1]) }
        guard let grid else { return nil }
        return grid.nightTemperatures(latitude: park.latitude, longitude: park.longitude, month: month).map { Usual(dawn: $0.dawn, evening: $0.evening, dewSpread: $0.dewSpread) }
    }
    /// Within this many degrees of its dew point before dawn, the air usually leaves dew on glass.
    static let dewSpread = 2.0
    /// "Usually about 12 °C two hours after dark and 4 °C before dawn in October." in the reader's
    /// units, and whether dew is usual; nil without figures. The same words on iPhone and Vision Pro.
    func lines(_ park: Park, month: Int, grid: SkyGrid? = .shared) -> (temperatures: String, dew: String?)? {
        guard let usual = usual(park, month: month, grid: grid) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.locale = .current
        let name = calendar.standaloneMonthSymbols[month-1]
        func degrees(_ celsius: Double) -> String {
            Measurement(value: celsius, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
        // The usual night mixes cloudy nights with clear ones; a clear night, the kind worth going out on,
        // loses more heat, and valleys pool cold air the 31 km record cannot see. Said every time.
        let temperatures = Sentences.join([String(localized: "Usually about \(degrees(usual.evening)) two hours after dark and \(degrees(usual.dawn)) before dawn in \(name)."),
                                           String(localized: "Clear nights, the ones worth going out on, are often several degrees colder.")])
        let dew = usual.dewSpread <= Self.dewSpread ? String(localized: "The air is usually near its dew point before dawn this month: expect dew on lenses.") : nil
        return (temperatures, dew)
    }
}
