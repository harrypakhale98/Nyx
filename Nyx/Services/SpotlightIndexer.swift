import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

/// The parks in Spotlight. Each item is also the park's `ParkEntity` (iOS 18+), so semantic search
/// and Siri treat it as the same park; on iOS 27 the item names its entity directly.
@MainActor enum SpotlightIndexer {
    static let domain="com.harrypakhale.nyx.parks"
    static func index(_ parks:[Park]) async throws {
        try await CSSearchableIndex.default().indexSearchableItems(items(parks))
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
