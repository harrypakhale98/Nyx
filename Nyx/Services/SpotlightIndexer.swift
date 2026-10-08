import AppIntents
import CoreSpotlight
import CryptoKit
import UniformTypeIdentifiers

/// The parks in Spotlight. Each item is also the park's `ParkEntity` (iOS 18+), so semantic search
/// and Siri treat it as the same park; on iOS 27 the item names its entity directly.
@MainActor enum SpotlightIndexer {
    static let domain="com.harrypakhale.nyx.parks"
    static func index(_ parks:[Park]) async throws {
        try await CSSearchableIndex.default().indexSearchableItems(items(parks))
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
