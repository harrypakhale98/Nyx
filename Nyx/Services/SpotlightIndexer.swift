import CoreSpotlight
import UniformTypeIdentifiers

@MainActor enum SpotlightIndexer {
    static func index(_ parks:[Park]) async {
        let items=parks.map { park in
            let attributes=CSSearchableItemAttributeSet(contentType:.text)
            attributes.title=park.shortName
            attributes.contentDescription=String(localized:"Plan a dark-sky night at \(park.shortName), \(park.state).")
            attributes.keywords=["stars","stargazing","national park",park.shortName]
            return CSSearchableItem(uniqueIdentifier:park.id,domainIdentifier:"com.harrypakhale.nyx.parks",attributeSet:attributes)
        }
        try? await CSSearchableIndex.default().indexSearchableItems(items)
    }
}
