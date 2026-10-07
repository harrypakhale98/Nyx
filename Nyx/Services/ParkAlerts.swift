import Foundation

/// What an NPS alert means for someone driving to a park at night, most serious first. A closure
/// is a road, trail, campground, area or the park itself shut; amenity notices (fuel, phones,
/// water, a visitor center's hours) never stand beside the score, however NPS files them.
nonisolated enum AlertKind: Int, Comparable, Sendable {
    case closure, danger, caution, notice
    static func < (a: Self, b: Self) -> Bool { a.rawValue<b.rawValue }
}
extension ParkAlert {
    /// Keyword rules with NPS's own category. They lean toward calling something a closure: the
    /// worst outcome is a long drive to a closed road, so anything that reads as a closure of a
    /// place counts, and so does anything NPS files as "Park Closure" unless it is only about an
    /// amenity ("No Water or Bathrooms at Kīpahulu", "Gas Pumps … Closed at Night").
    nonisolated var kind: AlertKind {
        let text = " " + Park.folded(title) + " "
        func has(_ words: [String]) -> Bool { words.contains { text.contains(" \($0) ") } }
        let reopened=has(["reopened","reopens","reopen","reopening"]) && !has(["closed","closure","closures"])
        let closing = !reopened && has(Self.closureWords)
        let amenityOnly=has(Self.amenityWords) && !has(Self.placeWords)
        let category=category.lowercased()
        if (closing || category.contains("closure")) && !amenityOnly { return .closure }
        if category.contains("danger") { return .danger }
        if category.contains("caution") { return .caution }
        return .notice
    }
    private nonisolated static let closureWords=["closed","closure","closures","closes","closing","shut","shutdown","inaccessible","impassable",
        "no access","out of service","washed out","not accessible"]
    private nonisolated static let amenityWords=["gas","fuel","pump","pumps","store","shop","gift","restaurant","cafe","dining","food","lodging","lodge",
        "phone","phones","wifi","internet","cell","water","potable","bathroom","bathrooms","restroom","restrooms","toilet","toilets","shower","showers",
        "laundry","elevator","charging","charger","ev","museum","exhibit","gallery","theater","bookstore","rental","rentals","tour","tours","ticket",
        "tickets","fee","fees","cashless","shuttle","shuttles","visitor center","contact station","ranger station"]
    private nonisolated static let placeWords=["road","roads","rd","highway","hwy","drive","route","sr","bridge","trail","trails","trailhead","trailheads",
        "path","towpath","boardwalk","campground","campgrounds","camping","camp","camps","campsite","campsites","backcountry","area","areas","section",
        "park","entrance","gate","loop","pass","overlook","viewpoint","vista","island","islands","key","beach","lake","river","creek","wash","canyon",
        "basin","dunes","district","unit","summit","ferry","launch","landing","dock","harbor","corridor","wilderness","zone","site","sites"]
    /// The headline as Nyx shows it: NPS's Title Case turned into a sentence, names kept.
    nonisolated func displayTitle(park: Park) -> String { AlertText.sentenceCase(title, names: AlertText.names(park)) }
}
nonisolated enum AlertRanking {
    /// Closures first, then danger, caution and notices; NPS's order within each.
    static func ranked(_ alerts: [ParkAlert]) -> [ParkAlert] {
        alerts.enumerated().sorted { ($0.element.kind, $0.offset)<($1.element.kind, $1.offset) }.map(\.element)
    }
    /// The one alert that stands beside the score: a true closure, never an amenity notice.
    static func closure(_ alerts: [ParkAlert]) -> ParkAlert? { alerts.first { $0.kind == .closure } }
}
/// NPS headlines are mostly Title Case ("Notch Trail Closure for Repairs"); Nyx's voice is
/// sentence case. Only words known to be ordinary are lowered, so names survive: anything
/// unfamiliar, the park's own names, acronyms, words before a number, and place words that
/// continue a name ("Hoh River Bridge"). A headline already in sentence case, or in capitals
/// throughout, is left exactly as NPS wrote it.
nonisolated enum AlertText {
    static func names(_ park: Park) -> Set<String> {
        let phrases=[park.name, park.shortName]+(Park.aliases[park.id] ?? [])+park.viewingSpots.map(\.name)
        // Generic words in park names ("National Park", "and") are not names on their own.
        return Set(phrases.flatMap { Park.folded($0).split(separator: " ").map(String.init) }).subtracting(["national","park","parks","and","of","the","preserve","state","visitor","center"])
    }
    static func sentenceCase(_ title: String, names: Set<String> = []) -> String {
        let tokens=title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        func core(_ token: String) -> String { token.trimmingCharacters(in: CharacterSet.letters.union(.decimalDigits).inverted) }
        guard title.contains(where: \.isLowercase) else { return title }
        let later=tokens.dropFirst().map(core).filter { $0.count>=4 }
        let capitalised=later.filter { $0.first?.isUppercase == true }.count
        guard later.count>=2, Double(capitalised)>=0.75*Double(later.count) else { return title }
        var out: [String]=[]
        var name=false
        for (index, token) in tokens.enumerated() {
            let word=core(token), lower=Park.folded(word)
            let previous=index>0 ? tokens[index-1] : ""
            let clause=index==0 || [":",";",".","?","!"].contains { previous.hasSuffix($0) } || previous=="-" || previous=="–"
            let nextIsNumber=tokens.indices.contains(index+1) && tokens[index+1].first?.isNumber == true
            guard let first=word.first, first.isUppercase else { out.append(token); name=false; continue }
            if clause || word.count>=2 && word==word.uppercased() || word.contains(where: \.isNumber) || nextIsNumber
                || names.contains(lower) || properNouns.contains(lower) {
                out.append(token); name = !common.contains(lower) || names.contains(lower) || properNouns.contains(lower); continue
            }
            if placeNouns.contains(lower) && name { out.append(token); continue }
            let parts=word.split(separator: "-").map { Park.folded(String($0)) }
            if parts.allSatisfy({ common.contains($0) || placeNouns.contains($0) }) { out.append(token.lowercased()); name=false; continue }
            out.append(token); name=true
        }
        return out.joined(separator: " ")
    }
    /// Words that end a name ("Glacier Point Road"): kept after a name, lowered otherwise.
    private static let placeNouns: Set<String>=["road","trail","bridge","highway","drive","route","campground","trailhead","boardwalk","overlook","loop",
        "path","island","islands","lake","river","creek","wash","canyon","mountain","mountains","beach","dunes","basin","pass","falls","springs","point",
        "peak","valley","key","cove","volcano","glacier","lagoon","harbor","landing","entrance","gate","center","station","district","unit","area","park"]
    private static let properNouns: Set<String>=["january","february","march","april","june","july","august","september","october","november",
        "december","monday","tuesday","wednesday","thursday","friday","saturday","sunday","moon","sun","milky","way","national","american","native"]
    /// Ordinary words that NPS headlines capitalise. Anything not here is treated as a name.
    private static let common: Set<String>=Set("""
        closed closure closures close closes closing open opens opened reopen reopens reopened reopening partial partially temporary temporarily \
        seasonal seasonally due to for and or of the a an at in on by from with without near past beyond until through after before during between \
        is are be been may will now currently current all some most other new recent recently only not no remains remain still repairs repair \
        construction work maintenance project projects improvements improvement rehabilitation replacement damage damaged flood flooding floods \
        storm storms rain rains snow ice fire fires wildfire wildfires smoke hazard hazards hazardous conditions condition alert alerts update \
        updates notice warning caution danger dangerous safety safe access accessible inaccessible limited restricted restrictions restriction \
        delays delay traffic expect expected long lines waits wait high low heavy visitation parking lot lots areas section sections side end \
        north south east west northern southern eastern western upper lower entire road roads trail trails bridge highway drive route campground \
        campgrounds camping camp campsite sites site trailhead trailheads boardwalk overlook park entrance gate loop path district unit island \
        lake river creek wash canyon mountain beach dunes basin pass gas fuel pumps pump station store shop gift restaurant lodging phones phone \
        water bathrooms restrooms restroom elevator charging service services unavailable available out down visitor center centers hours fees fee \
        cashless tickets ticket required permit permits reservation reservations rentals rental tour tours night nights day days week weekday \
        weekdays weekend weekends daily overnight tree trees removal cattle guard second first third scheduled vehicle vehicles large small rv \
        trailer trailers pets pet bear bears activity wildlife increased elevated levels toxic algae algal bloom blooms harmful heat hot \
        excessive humidity burn ban stage volcanic unrest eruption rockfall landslide washout washed crossing crossings deep stream \
        temperatures forecast higher than more less please use aware stay away report contact crews responding moved moves fully collection \
        infrastructure planning ahead transportation ride share prepared being backcountry primitive developed burned critical inner outer \
        main scenic tips trip entry timed footwear items worn used caves allowed boat boats launch dock docks ferry ferries landing landings \
        boater boaters paddling navigation break ins break-ins theft vehicle-break warning warnings watch information info other multiple \
        tent tents corridor zone wilderness summit sunrise sunset season status get your you we our this that these those them their \
        repaired repairing closing reopening approved trailheads shoulder speed limits limit much inside surrounding highways risk \
        flash debris area-wide rabies tests positive urged potential health advisory e coli emergency drought shutoff shutoffs suspended
        """.split(whereSeparator: \.isWhitespace).map(String.init))
}
