import Foundation

/// A city or town to measure distances from, when location is off or someone plans from home, and
/// the offline source of a saved spot's time zone and region (`StartingPlaces.nearest`).
/// From the bundled list (`places.json`, built by `Scripts/build_places.py`): in the US the 1,000
/// most populous incorporated places and every state capital (Census); everywhere else every place
/// of 15,000 people or more (GeoNames, CC BY 4.0), each with its own time zone. Searched on this
/// device; never fetched.
nonisolated struct StartingPlace: Codable, Hashable, Sendable, Identifiable {
    let name: String
    /// The region within the country: in the US the two-letter postal code ("IL"); elsewhere the
    /// first-level region's name ("Ontario"), empty where the country has none (Singapore).
    let state: String
    let latitude: Double
    let longitude: Double
    /// ISO 3166-1 alpha-2: "US".
    var countryCode: String = "US"
    /// The IANA zone stored with the place: "America/Chicago". Nil only for a record that has none.
    var timeZoneID: String?
    /// How many people live there, only to rank search results: GeoNames' count outside the US; for
    /// a US place GeoNames' count fitted to keep the Census order (`usPopulation` in the file). Nil
    /// for a saved record. Not part of the place's identity, and never saved.
    var population: Int? = nil
    /// A plain-letter spelling for search where folding accents is not enough: "Lodz" for "Łódź",
    /// "Diyarbakir" for "Diyarbakır". Not part of the place's identity, and never saved.
    var asciiName: String? = nil
    /// "Chicago, IL" in the US, as before; elsewhere unique across the list: same-named towns in one
    /// region are told apart by their point.
    var id: String { countryCode=="US" ? label : "\(countryCode)|\(name)|\(state)|\(latitude),\(longitude)" }
    /// "Chicago, IL"; elsewhere the country in the reader's language: "Paris, France".
    var label: String { countryCode=="US" ? "\(name), \(state)" : "\(name), \(StartingPlaces.countryName(countryCode))" }
    /// "Illinois"; "Ontario, Canada"; "Singapore".
    var regionName: String { StartingPlaces.regionName(countryCode: countryCode, region: state) }
    /// The place's own zone. A record without one (none ship) uses this device's zone, the zone
    /// of the person planning from home; a guess at another region's zone would be wrong far more often.
    var timeZone: TimeZone { timeZoneID.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// "Chicago" finds Chicago; so do "chicago il", "Chicago, Illinois", "Saint Paul" for "St. Paul",
    /// "Sao Paulo" for São Paulo and "Lodz" for Łódź.
    func matches(_ query: String) -> Bool {
        let query=StartingPlaces.Query(query)
        return !query.isEmpty && StartingPlaces.Index([self]).tier(0, query) != nil
    }
    /// Straight-line distance to a park, in meters.
    func distanceMeters(to park: Park) -> Double { park.distanceMeters(latitude:latitude,longitude:longitude) }

    /// Identity is what is saved: the name, region, point, country and zone. Population and the
    /// plain spelling only rank and find, so a saved home still equals the row the picker shows.
    static func == (a: Self, b: Self) -> Bool {
        a.name==b.name && a.state==b.state && a.latitude==b.latitude && a.longitude==b.longitude && a.countryCode==b.countryCode && a.timeZoneID==b.timeZoneID
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name); hasher.combine(state); hasher.combine(latitude); hasher.combine(longitude); hasher.combine(countryCode); hasher.combine(timeZoneID)
    }

    enum CodingKeys: String, CodingKey { case name, state, latitude, longitude, countryCode, timeZoneID }
    /// A home place saved before places carried a country and zone (`{name, state, latitude,
    /// longitude}`) reads as the bundled place of the same label, so it gains its zone and still
    /// equals the row the picker shows.
    init(from decoder: any Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        name=try c.decode(String.self,forKey:.name); state=try c.decode(String.self,forKey:.state)
        latitude=try c.decode(Double.self,forKey:.latitude); longitude=try c.decode(Double.self,forKey:.longitude)
        countryCode=try c.decodeIfPresent(String.self,forKey:.countryCode) ?? "US"
        timeZoneID=try c.decodeIfPresent(String.self,forKey:.timeZoneID)
        if timeZoneID == nil, let bundled=StartingPlaces.all.first(where: { $0.countryCode==countryCode && $0.name==name && $0.state==state }) { timeZoneID=bundled.timeZoneID }
    }
    init(name: String, state: String, latitude: Double, longitude: Double, countryCode: String = "US", timeZoneID: String? = nil, population: Int? = nil, asciiName: String? = nil) {
        self.name=name; self.state=state; self.latitude=latitude; self.longitude=longitude; self.countryCode=countryCode; self.timeZoneID=timeZoneID
        self.population=population; self.asciiName=asciiName
    }
}

nonisolated enum StartingPlaces {
    /// Every bundled place: the US first in Census order, then the rest of the world, largest first.
    /// About 31,500 places; decoding takes a few tens of milliseconds, so `prepare()` does it early.
    static let all: [StartingPlace] = file.places
    /// US places the Census list leaves out, for `nearest` only (never searched), so a spot near the
    /// Canadian or Mexican border finds a US town before a foreign one.
    static let nearbyOnly: [StartingPlace] = file.nearbyOnly
    private static let file: File = loadFile()
    /// `all` and `nearbyOnly` together, for `nearest`.
    static let locatable: [StartingPlace] = all+nearbyOnly
    /// The search index over `all`, built once, on first use.
    static let index = Index(all)
    /// `all` bucketed by whole degrees, for `nearest`, built once, on first use.
    static let grid = Grid(locatable)
    /// The US places alone, for a point inside the United States (`nearest`).
    static let usLocatable: [StartingPlace] = locatable.filter { $0.countryCode=="US" }
    static let usGrid = Grid(usLocatable)
    /// Decodes the list and builds the search index and grid away from the main thread, so the
    /// first keystroke in a search does not wait for them. Safe to call more than once.
    static func prepare() {
        Task.detached(priority: .utility) { _ = index; _ = grid; _ = usGrid }
    }
    static func load(bundle: Bundle = .main) -> [StartingPlace] { loadFile(bundle: bundle).places }
    private static func loadFile(bundle: Bundle = .main) -> File {
        guard let url=bundle.url(forResource:"places",withExtension:"json"), let data=try? Data(contentsOf:url),
              let file=try? JSONDecoder().decode(File.self,from:data) else { return File(places: [], nearbyOnly: []) }
        return file
    }

    // MARK: Search

    /// The best matches for a search, best first. An exact name (or name and region) first, then a
    /// name that starts with the query, then a word in the name that does ("York" in "New York"),
    /// then any name containing it; within each, the most populous first, then the file's order
    /// (Census order in the US). "St." reads as "Saint".
    static func search(_ query: String, in places: [StartingPlace] = all, limit: Int = 20) -> [StartingPlace] {
        let query=Query(query)
        guard !query.isEmpty, limit>0 else { return [] }
        let index=isBundled(places) ? self.index : Index(places)
        return index.search(query, limit: limit).map { places[$0] }
    }
    /// The one place a name means, for Ask Nyx: an exact name (with or without its region) first,
    /// else the most populous place that starts with it. Nil for an empty or unknown name.
    static func named(_ text: String, in places: [StartingPlace] = all) -> StartingPlace? {
        let query=Query(text)
        guard !query.isEmpty else { return nil }
        let index=isBundled(places) ? self.index : Index(places)
        guard let best=index.search(query, limit: 1).first, let tier=index.tier(best, query), tier<=Index.namePrefix else { return nil }
        return places[best]
    }
    /// Folded for search as `Park.folded` folds (case, accents and width; words split on anything
    /// not a letter or digit; "&" is "and"), with the usual abbreviations spelled out: "St." is
    /// "Saint", "Ft." "Fort", "Mt." "Mount". Curly and spacing apostrophes go, as straight ones and
    /// the ʻokina do: "Xi’an" is "xian". Places and queries fold the same way, so they always meet.
    static func normalized(_ text: String) -> String { Index.fold(text) }
    /// True when `places` is the bundled list itself (or a copy of it), whose index is kept.
    private static func isBundled(_ places: [StartingPlace]) -> Bool {
        places.count==all.count && places.withUnsafeBufferPointer { mine in all.withUnsafeBufferPointer { $0.baseAddress==mine.baseAddress } }
    }

    // MARK: Nearest place

    /// The bundled place nearest a point, for a saved spot's region and, offline, its time zone.
    /// Searches the whole-degree cells around the point outward and stops once no unsearched cell
    /// can hold anything closer, so it reads a few dozen places, not 31,500.
    /// Limits: this is the nearest *town*, not the zone map. A spot near a time-zone or national
    /// border can take the neighbouring town's zone and country (an hour wrong on one side of the
    /// Indiana or Arizona lines, for example), and far from any town of 15,000 (the open ocean,
    /// Antarctica, the high Arctic) the nearest one can be hundreds of kilometres away; `within`
    /// caps that distance. Open-Meteo's zone for the point, when a forecast has arrived, is better.
    static func nearest(latitude: Double, longitude: Double, within meters: Double = .infinity) -> StartingPlace? {
        guard latitude.isFinite, longitude.isFinite else { return nil }
        // Inside the United States, only a US town: the nearest town of 15,000 in northern Maine can be
        // in New Brunswick, an hour ahead. The outline is the Census boundary (simplified), so a spot
        // within a few kilometres of the border may still be read as either side.
        let (places,cells)=USOutline.contains(latitude: latitude, longitude: longitude) ? (usLocatable,usGrid) : (locatable,grid)
        guard let found=cells.nearest(latitude: latitude, longitude: longitude, in: places), found.meters<=meters else { return nil }
        return places[found.index]
    }
    /// The zone of the nearest bundled place (see `nearest` for its limits); nil when there is none
    /// within `within` metres.
    static func nearestZone(latitude: Double, longitude: Double, within meters: Double = .infinity) -> TimeZone? {
        nearest(latitude: latitude, longitude: longitude, within: meters)?.timeZoneID.flatMap(TimeZone.init(identifier:))
    }

    // MARK: Names

    /// The name to show for a place's region: a US state's full name ("Illinois"); elsewhere the
    /// region with the country in the reader's language ("Ontario, Canada"), or the country alone
    /// when there is no region or the region is the country ("Reunion" in Réunion).
    static func regionName(countryCode: String, region: String) -> String {
        if countryCode.uppercased()=="US" { return stateNames[region] ?? region }
        return regionName(region: region, country: countryName(countryCode))
    }
    fileprivate static func regionName(region: String, country: String) -> String {
        region.isEmpty || region==country || Park.folded(region)==Park.folded(country) ? country : "\(region), \(country)"
    }
    /// The country in the reader's language: "France". Never stored, so it follows the language.
    static func countryName(_ code: String) -> String { Locale.current.localizedString(forRegionCode:code) ?? code }
    /// US states by postal code, for `regionName`.
    static let stateNames: [String:String] = [
        "AL":"Alabama","AK":"Alaska","AZ":"Arizona","AR":"Arkansas","CA":"California","CO":"Colorado","CT":"Connecticut","DE":"Delaware",
        "DC":"District of Columbia","FL":"Florida","GA":"Georgia","HI":"Hawaii","ID":"Idaho","IL":"Illinois","IN":"Indiana","IA":"Iowa",
        "KS":"Kansas","KY":"Kentucky","LA":"Louisiana","ME":"Maine","MD":"Maryland","MA":"Massachusetts","MI":"Michigan","MN":"Minnesota",
        "MS":"Mississippi","MO":"Missouri","MT":"Montana","NE":"Nebraska","NV":"Nevada","NH":"New Hampshire","NJ":"New Jersey",
        "NM":"New Mexico","NY":"New York","NC":"North Carolina","ND":"North Dakota","OH":"Ohio","OK":"Oklahoma","OR":"Oregon",
        "PA":"Pennsylvania","RI":"Rhode Island","SC":"South Carolina","SD":"South Dakota","TN":"Tennessee","TX":"Texas","UT":"Utah",
        "VT":"Vermont","VA":"Virginia","WA":"Washington","WV":"West Virginia","WI":"Wisconsin","WY":"Wyoming",
    ]

    // MARK: The file

    /// `{"usPopulation":[…],"places":[…]}`, compact rows, each part largest first:
    /// US `["Chicago","IL",41.837,-87.685,"America/Chicago"]` (exactly as before G3; a sixth element,
    /// when present, is the country code) and elsewhere
    /// `["Paris","Île-de-France",48.853,2.349,"Europe/Paris","FR",2138551]`, with an eighth element,
    /// a plain-letter spelling, only where folding accents is not enough. `usPopulation` holds one
    /// number per row that has no population, in order.
    private struct File: Decodable {
        let places: [StartingPlace]
        let nearbyOnly: [StartingPlace]
        init(places: [StartingPlace], nearbyOnly: [StartingPlace]) { self.places=places; self.nearbyOnly=nearbyOnly }
        enum Keys: String, CodingKey { case places, usPopulation, nearbyOnly }
        init(from decoder: any Decoder) throws {
            let container=try decoder.container(keyedBy:Keys.self)
            let usPopulation=try container.decodeIfPresent([Int].self,forKey:.usPopulation) ?? []
            var rows=try container.nestedUnkeyedContainer(forKey:.places)
            var list:[StartingPlace]=[]
            list.reserveCapacity(rows.count ?? 0)
            var unranked=0
            while !rows.isAtEnd {
                var row=try rows.nestedUnkeyedContainer()
                let name=try row.decode(String.self), state=try row.decode(String.self), latitude=try row.decode(Double.self), longitude=try row.decode(Double.self)
                let zone=row.isAtEnd ? nil : try row.decode(String.self)
                let country=row.isAtEnd ? "US" : try row.decode(String.self)
                var population=row.isAtEnd ? nil : try row.decode(Int.self)
                let ascii=row.isAtEnd ? nil : try row.decode(String.self)
                if population == nil {
                    population=unranked<usPopulation.count ? usPopulation[unranked] : nil
                    unranked+=1
                }
                list.append(StartingPlace(name:name,state:state,latitude:latitude,longitude:longitude,countryCode:country,timeZoneID:zone,population:population,asciiName:ascii))
            }
            places=list
            var extra:[StartingPlace]=[]
            if container.contains(.nearbyOnly) {
                var near=try container.nestedUnkeyedContainer(forKey:.nearbyOnly)
                while !near.isAtEnd {
                    var row=try near.nestedUnkeyedContainer()
                    let name=try row.decode(String.self), state=try row.decode(String.self), latitude=try row.decode(Double.self), longitude=try row.decode(Double.self)
                    let zone=try row.decode(String.self), country=try row.decode(String.self), population=try row.decode(Int.self)
                    extra.append(StartingPlace(name:name,state:state,latitude:latitude,longitude:longitude,countryCode:country,timeZoneID:zone,population:population,asciiName:nil))
                }
            }
            nearbyOnly=extra
        }
    }

    // MARK: Index

    /// A query folded once per keystroke: the whole needle, and each way to read its last words as
    /// a region ("springfield illinois" is Springfield in Illinois).
    struct Query {
        let needle: [UInt8]
        /// (the name part, the region part) for every split at a space, the region part one or more words.
        let splits: [(city: [UInt8], region: String)]
        var isEmpty: Bool { needle.isEmpty }
        init(_ text: String) {
            let folded=StartingPlaces.normalized(text)
            needle=Array(folded.utf8)
            let words=folded.split(separator:" ")
            splits=words.count<2 ? [] : (1..<words.count).map { cut in (Array(words[..<cut].joined(separator:" ").utf8), words[cut...].joined(separator:" ")) }
        }
    }

    /// Every place's searchable names, folded once into one byte buffer, and the regions each can
    /// be narrowed by. A search compares bytes (UTF-8, so a match is a match of whole characters)
    /// and never folds a place's name again.
    final class Index: Sendable {
        static let exact=0, regionPrefix=1, namePrefix=2, wordPrefix=3, contains=4
        private let text: [UInt8]
        /// Per place: the folded name, then the plain spelling (empty when none), as offsets into `text`.
        private let bounds: [(name: Range<Int>, ascii: Range<Int>)]
        /// Per place: the ids of the regions it can be narrowed by (`regionIDs`), a range into `regionRefs`.
        private let regionRanges: [Range<Int>]
        private let regionRefs: [Int32]
        private let regionIDs: [String: Int32]
        private let population: [Int]

        init(_ places: [StartingPlace]) {
            var text:[UInt8]=[], bounds:[(name: Range<Int>, ascii: Range<Int>)]=[], ranges:[Range<Int>]=[], refs:[Int32]=[], ids:[String:Int32]=[:]
            // Regions and countries repeat thousands of times; each is folded once.
            var regionsOf:[String:[Int32]]=[:], countries:[String:(name: String, keys: [String])]=[:]
            text.reserveCapacity(places.count*12); bounds.reserveCapacity(places.count); ranges.reserveCapacity(places.count)
            func append(_ string: String) -> Range<Int> { let start=text.count; text.append(contentsOf:string.utf8); return start..<text.count }
            for place in places {
                let name=append(Index.fold(place.name))
                let ascii=place.asciiName.map { append(Index.fold($0)) } ?? text.count..<text.count
                bounds.append((name,ascii))
                let key=place.countryCode+"|"+place.state
                var regions=regionsOf[key] ?? []
                if regionsOf[key]==nil {
                    let country=countries[place.countryCode] ?? Index.country(place.countryCode)
                    countries[place.countryCode]=country
                    for region in Index.regionKeys(place, country: country) {
                        if ids[region]==nil { ids[region]=Int32(ids.count) }
                        if let id=ids[region] { regions.append(id) }
                    }
                    regionsOf[key]=regions
                }
                let start=refs.count; refs.append(contentsOf:regions); ranges.append(start..<refs.count)
            }
            self.text=text; self.bounds=bounds; regionRanges=ranges; regionRefs=refs; regionIDs=ids
            population=places.map { $0.population ?? 0 }
        }

        /// Place indices, best first.
        func search(_ query: Query, limit: Int) -> [Int] {
            let regions=query.splits.map { regionIDs[$0.region] }
            var hits:[(tier: Int, population: Int, index: Int)]=[]
            text.withUnsafeBufferPointer { text in
                query.needle.withUnsafeBufferPointer { needle in
                    for index in bounds.indices {
                        if let tier=tier(index, query, regions, text, needle) { hits.append((tier, population[index], index)) }
                    }
                }
            }
            hits.sort { ($0.tier, -$0.population, $0.index) < ($1.tier, -$1.population, $1.index) }
            return hits.prefix(limit).map(\.index)
        }
        /// How well one place matches; lower is better, nil for no match.
        func tier(_ index: Int, _ query: Query) -> Int? {
            let regions=query.splits.map { regionIDs[$0.region] }
            return text.withUnsafeBufferPointer { text in query.needle.withUnsafeBufferPointer { needle in tier(index, query, regions, text, needle) } }
        }
        private func tier(_ index: Int, _ query: Query, _ regions: [Int32?], _ text: UnsafeBufferPointer<UInt8>, _ needle: UnsafeBufferPointer<UInt8>) -> Int? {
            let (name, ascii)=bounds[index]
            var best=Self.tier(text, name, needle)
            if !ascii.isEmpty, let other=Self.tier(text, ascii, needle) { best=min(best ?? other, other) }
            if best==Self.exact { return best }
            // "Springfield Illinois", "Toronto Canada", "Lodz Poland": a name, then its region.
            let own=regionRefs[regionRanges[index]]
            for (split, region) in zip(query.splits, regions) {
                guard let region, own.contains(region) else { continue }
                for range in [name, ascii] where !range.isEmpty {
                    split.city.withUnsafeBufferPointer { city in
                        if Self.starts(text, range, city) { best=min(best ?? Int.max, range.count==city.count ? Self.exact : Self.regionPrefix) }
                    }
                }
            }
            return best
        }
        private static func starts(_ text: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, _ prefix: UnsafeBufferPointer<UInt8>) -> Bool {
            guard prefix.count<=range.count, let base=text.baseAddress, let other=prefix.baseAddress else { return prefix.isEmpty }
            return memcmp(base+range.lowerBound, other, prefix.count)==0
        }
        private static func tier(_ text: UnsafeBufferPointer<UInt8>, _ range: Range<Int>, _ needle: UnsafeBufferPointer<UInt8>) -> Int? {
            guard !needle.isEmpty, needle.count<=range.count, let base=text.baseAddress, let little=needle.baseAddress else { return nil }
            if starts(text, range, needle) { return needle.count==range.count ? exact : namePrefix }
            var from=range.lowerBound+1, found=false
            while from+needle.count<=range.upperBound, let hit=memmem(base+from, range.upperBound-from, little, needle.count) {
                let at=UnsafeRawPointer(base).distance(to:UnsafeRawPointer(hit))
                if text[at-1]==0x20 { return wordPrefix }
                found=true; from=at+1
            }
            return found ? contains : nil
        }
        /// `normalized`: a byte loop for plain ASCII text (most names), and Foundation's folding
        /// for the rest. Both give what `Park.folded` gives, with the abbreviations and apostrophes.
        static func fold(_ text: String) -> String {
            var out:[UInt8]=[], word:[UInt8]=[]
            out.reserveCapacity(text.utf8.count)
            func flush() {
                guard !word.isEmpty else { return }
                if !out.isEmpty { out.append(0x20) }
                switch word { case [0x73,0x74]: out.append(contentsOf:"saint".utf8); case [0x66,0x74]: out.append(contentsOf:"fort".utf8)
                case [0x6d,0x74]: out.append(contentsOf:"mount".utf8); default: out.append(contentsOf:word) }
                word.removeAll(keepingCapacity:true)
            }
            for byte in text.utf8 {
                switch byte {
                case 0x80...: return foldUnicode(text)
                case 0x27, 0x60: continue
                case 0x26: flush(); word.append(contentsOf:"and".utf8); flush()
                case 0x41...0x5a: word.append(byte+0x20)
                case 0x61...0x7a, 0x30...0x39: word.append(byte)
                default: flush()
                }
            }
            flush()
            return String(decoding:out,as:UTF8.self)
        }
        private static let apostrophes:Set<Unicode.Scalar>=["'","`","ʻ","’","‘","´"]
        private static let options:String.CompareOptions=[.caseInsensitive,.diacriticInsensitive,.widthInsensitive]
        private static func foldUnicode(_ text: String) -> String {
            var kept=String.UnicodeScalarView()
            for scalar in text.unicodeScalars where !apostrophes.contains(scalar) {
                if scalar=="&" { kept.append(contentsOf:" and ".unicodeScalars) } else { kept.append(scalar) }
            }
            let letters=CharacterSet.alphanumerics
            return String(kept).folding(options:options,locale:nil).unicodeScalars.split { !letters.contains($0) }
                .map { word in let word=String(String.UnicodeScalarView(word)); return ["st":"saint","ft":"fort","mt":"mount"][word] ?? word }
                .joined(separator:" ")
        }
        /// A country in the reader's language, and as it can be typed, folded: in that language, in
        /// English, and by its code ("canada", "ca").
        private static func country(_ code: String) -> (name: String, keys: [String]) {
            let name=StartingPlaces.countryName(code), english=Locale(identifier:"en").localizedString(forRegionCode:code) ?? code
            return (name, [fold(name), fold(english), code.lowercased()])
        }
        /// What a place's region can be typed as, folded as a query is: in the US the postal code
        /// and the state's name ("il", "illinois"); elsewhere the region, the region with its
        /// country, and the country ("ontario", "ontario canada", "canada", "ca").
        private static func regionKeys(_ place: StartingPlace, country: (name: String, keys: [String])) -> [String] {
            let keys:[String]
            if place.countryCode=="US" {
                keys=[fold(place.state), fold(StartingPlaces.stateNames[place.state] ?? place.state)]
            } else {
                keys=[fold(place.state), fold(StartingPlaces.regionName(region: place.state, country: country.name))]+country.keys
            }
            var seen=Set<String>()
            return keys.filter { !$0.isEmpty && seen.insert($0).inserted }
        }
    }

    // MARK: Grid

    /// Places bucketed by whole degrees of latitude and longitude.
    struct Grid: Sendable {
        private let cells: [Int: [Int32]]
        init(_ places: [StartingPlace]) {
            var cells:[Int:[Int32]]=[:]
            for (index, place) in places.enumerated() where place.latitude.isFinite && place.longitude.isFinite {
                cells[Self.key(Self.row(place.latitude), Self.column(place.longitude)), default:[]].append(Int32(index))
            }
            self.cells=cells
        }
        private static func row(_ latitude: Double) -> Int { min(89, max(-90, Int(latitude.rounded(.down)))) }
        private static func column(_ longitude: Double) -> Int {
            let wrapped=(longitude+180).truncatingRemainder(dividingBy:360)
            return Int((wrapped<0 ? wrapped+360 : wrapped).rounded(.down))%360-180
        }
        private static func key(_ row: Int, _ column: Int) -> Int { (row+90)*360+(column+180) }
        /// Rings of cells outward from the point's own. After ring `r`, every unsearched place is at
        /// least `r` degrees away in latitude or in longitude; the nearer of those two distances on
        /// the sphere (a meridian `r`° away is asin(cos φ · sin r) away) bounds anything left. Past
        /// 45 rings (only near the poles or far out at sea) it reads every place.
        func nearest(latitude: Double, longitude: Double, in places: [StartingPlace]) -> (index: Int, meters: Double)? {
            var best:(index: Int, meters: Double)?
            func consider(_ index: Int32) {
                let place=places[Int(index)]
                let meters=Park.distance(latitude, longitude, place.latitude, place.longitude)
                if best.map({ meters<$0.meters || (meters==$0.meters && Int(index)<$0.index) }) ?? true { best=(Int(index), meters) }
            }
            let row=Self.row(latitude), column=Self.column(longitude), radian=Double.pi/180, earth=6_371_008.8
            for ring in 0...45 {
                for dRow in -ring...ring {
                    let r=row+dRow
                    guard (-90...89).contains(r) else { continue }
                    let step=abs(dRow)==ring ? 1 : 2*ring
                    for dColumn in stride(from:-ring, through:ring, by:max(1,step)) {
                        let c=((column+dColumn+180)%360+360)%360-180
                        for index in cells[Self.key(r, c)] ?? [] { consider(index) }
                    }
                }
                let alongMeridian=Double(ring)*radian*earth
                let acrossMeridians=asin(min(1, cos(latitude*radian)*sin(Double(min(ring,90))*radian)))*earth
                if let best, best.meters<=min(alongMeridian, acrossMeridians) { return best }
            }
            for index in places.indices { consider(Int32(index)) }
            return best
        }
    }
}

/// The United States' outline (Census cartographic boundary, public domain; `us-outline.json`, the same
/// file the journal's map draws), as a point-in-polygon test for `StartingPlaces.nearest`.
nonisolated enum USOutline {
    private struct File: Decodable { let regions: [String: [[[Double]]]] }
    /// Rings of (longitude, latitude), with their bounding boxes.
    private static let rings: [(box: (minLon: Double, maxLon: Double, minLat: Double, maxLat: Double), points: [(Double, Double)])] = {
        guard let url=Bundle.main.url(forResource:"us-outline",withExtension:"json"), let data=try? Data(contentsOf:url),
              let file=try? JSONDecoder().decode(File.self,from:data) else { return [] }
        return file.regions.values.flatMap { $0 }.compactMap { ring in
            let points=ring.compactMap { $0.count>=2 ? ($0[0],$0[1]) : nil }
            guard points.count>=3 else { return nil }
            let lons=points.map(\.0), lats=points.map(\.1)
            return ((lons.min() ?? 0, lons.max() ?? 0, lats.min() ?? 0, lats.max() ?? 0), points)
        }
    }()
    static func contains(latitude: Double, longitude: Double) -> Bool {
        rings.contains { ring in
            guard (ring.box.minLon...ring.box.maxLon).contains(longitude), (ring.box.minLat...ring.box.maxLat).contains(latitude) else { return false }
            var inside=false, j=ring.points.count-1
            for i in ring.points.indices {
                let (xi,yi)=ring.points[i], (xj,yj)=ring.points[j]
                if (yi>latitude) != (yj>latitude), longitude < (xj-xi)*(latitude-yi)/(yj-yi)+xi { inside.toggle() }
                j=i
            }
            return inside
        }
    }
}
