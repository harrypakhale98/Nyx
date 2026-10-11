import AppIntents
import CoreSpotlight
import CryptoKit
import UniformTypeIdentifiers

/// The parks in Spotlight. Each item is also the park's `ParkEntity` (iOS 18+), so semantic search
/// and Siri treat it as the same park; on iOS 27 the item names its entity directly.
///
/// With the world catalogue (G4): the 63 curated parks, and the places abroad a person has opened or
/// followed, at most `limit` items in all; never the whole catalogue of 3,400 places, which would
/// crowd Spotlight with places no one here asked about. Saved spots are never indexed: a spot can be
/// someone's home, and Spotlight shows its results to anyone holding the unlocked phone.
@MainActor enum SpotlightIndexer {
    static let domain="com.harrypakhale.nyx.parks"
    /// Curated parks and remembered places together.
    static let limit=200
    /// Places abroad opened or followed, oldest first (`remember`).
    static let rememberedKey="spotlightRemembered"
    static func index(_ parks:[Park]) async throws {
        try await CSSearchableIndex.default().indexSearchableItems(items(parks))
    }
    /// A place abroad that has just been opened or followed joins Spotlight; past `limit`, the place
    /// remembered longest ago that is not followed leaves it. Curated parks are always there already,
    /// and a saved spot is never indexed.
    static func remember(_ place:Park,followed:Set<String>,defaults:UserDefaults = .standard) async {
        guard place.isCatalogPlace else { return }
        let room=limit-((try? ParkData.load().count) ?? 0)
        let (kept,evicted)=Self.remembered(defaults.stringArray(forKey:rememberedKey) ?? [],adding:place.id,followed:followed,room:room)
        defaults.set(kept,forKey:rememberedKey)
        let index=CSSearchableIndex.default()
        try? await index.indexSearchableItems(items([place]))
        if !evicted.isEmpty { try? await index.deleteSearchableItems(withIdentifiers:evicted) }
    }
    /// The remembered list with `id` as its newest, and what must leave Spotlight to keep it within
    /// `room`: the oldest that are not followed. Followed places stay even past it.
    nonisolated static func remembered(_ list:[String],adding id:String,followed:Set<String>,room:Int)->(kept:[String],evicted:[String]) {
        var kept=list.filter { $0 != id }+[id], evicted:[String]=[]
        while kept.count>max(room,0), let oldest=kept.firstIndex(where:{ $0 != id && !followed.contains($0) }) { evicted.append(kept.remove(at:oldest)) }
        return (kept,evicted)
    }
    /// The places abroad Spotlight holds, read back for a full re-index (where the app bundles the catalogue).
    static func rememberedPlaces(defaults:UserDefaults = .standard)->[Park] {
        let snapshot=SharedSettings.read()
        return (defaults.stringArray(forKey:rememberedKey) ?? []).compactMap { ParkLibrary.place($0,snapshot:snapshot) }
    }
    /// Everything Spotlight should hold, for iOS's request to rebuild the index (`NyxIntents`): the
    /// curated parks and the remembered places abroad.
    static func reindexAll() async throws { try await index(ParkData.load()+rememberedPlaces()) }
    /// The same for some identifiers only.
    static func reindex(_ identifiers:[String]) async throws {
        let wanted=Set(identifiers)
        try await index((ParkData.load()+rememberedPlaces()).filter { wanted.contains($0.id) })
    }
    static let markerKey="spotlightIndexed"
    /// At launch: the parks are indexed again only when what Spotlight holds could differ (another
    /// version of Nyx, language or iOS, or changed park data), not on every launch. Spotlight's own
    /// requests to re-index (`NyxIntents`) always index.
    static func indexIfNeeded(_ parks:[Park],defaults:UserDefaults = .standard) async throws {
        let current=marker(parks)
        guard defaults.string(forKey:markerKey) != current else { return }
        try await index(parks)
        defaults.set(current,forKey:markerKey)
    }
    static func marker(_ parks:[Park])->String {
        let info=Bundle.main.infoDictionary
        let encoder=JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest=(try? encoder.encode(parks)).map { SHA256.hash(data:$0).map { String(format:"%02x",$0) }.joined() } ?? ""
        return [info?["CFBundleShortVersionString"] as? String ?? "",info?["CFBundleVersion"] as? String ?? "",Bundle.main.preferredLocalizations.first ?? "",
                String(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),digest].joined(separator:"|")
    }
    static func items(_ parks:[Park])->[CSSearchableItem] {
        parks.map { park in
            let entity=ParkEntity(park)
            let attributes=entity.attributeSet
            // Dark Sky Parks rank a little higher: they are what Nyx is for.
            attributes.associateAppEntity(entity,priority:park.darkSkyDesignated ? 1 : 0)
            let item=CSSearchableItem(uniqueIdentifier:park.id,domainIdentifier:domain,attributeSet:attributes)
            if #available(iOS 27.0,*) { item.relatedAppEntityIdentifier=EntityIdentifier(for:entity) }
            return item
        }
    }
}
