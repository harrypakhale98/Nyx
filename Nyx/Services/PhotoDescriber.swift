import Foundation
import CoreGraphics
import FoundationModels
import Vision

/// "Suggest a description" for a journal photo: one plain line the person reads, edits or ignores.
/// It is never saved by itself and it says it was suggested on this iPhone. Where the on-device
/// model is ready, can see images (iOS 27) and speaks the person's language, it writes a sentence,
/// told not to name sky facts it cannot know from a photo (stars, planets, how dark it was).
/// Otherwise (iOS 26, no Apple Intelligence, or the model writes nothing usable) Vision's image classification gives a starting
/// line of what it is sure of, "Night sky, mountains, tent" (`PhotoLabels`), in Nyx's own words,
/// offered only where those words are the person's language. Without either, the button isn't there.
enum PhotoDescriber {
    static var available: Bool {
        if DebugScenario.isEnabled("suggest-fixture") { return true }
        if modelAvailable { return true }
        return PhotoLabels.available
    }
    /// The on-device model's sentence first; `no-ai` (DEBUG) stands for a device without it.
    private static var modelAvailable: Bool {
        guard !DebugScenario.isEnabled("no-ai") else { return false }
        if #available(iOS 27.0, *) { return VisionDescriber.available }
        return false
    }
    /// One line, or nil if nothing usable came back.
    static func suggest(_ data: Data) async -> String? {
        #if DEBUG
        if DebugScenario.isEnabled("suggest-fixture") { return "A dark ridge under a sky full of stars, with a faint band of light above it." }
        #endif
        guard available else { return nil }
        guard let image=await Task.detached(priority: .userInitiated, operation: { PhotoScaling.image(data, maxPixels: 1024) }).value else { return nil }
        if modelAvailable, #available(iOS 27.0, *), let line=await VisionDescriber.describe(image).flatMap(clean) { return line }
        // The model declined, timed out or wrote nothing usable: Vision's labels, where they are the person's language.
        guard PhotoLabels.available else { return nil }
        return await PhotoLabels.line(for: image)
    }
    /// One sentence, trimmed, without quotes; nil when nothing usable came back.
    nonisolated static func clean(_ text: String) -> String? {
        var line=text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let end=line.firstIndex(of: "\n") { line=String(line[..<end]) }
        line=line.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” ")).replacingOccurrences(of: "!", with: ".")
        guard line.count>=8 else { return nil }
        return String(line.prefix(160))
    }
}

@available(iOS 27.0, *)
private enum VisionDescriber {
    static var available: Bool {
        let model=SystemLanguageModel.default
        return model.availability == .available && model.capabilities.contains(.vision) && model.supportsLocale(.current)
    }
    static func describe(_ image: CGImage) async -> String? {
        let session=LanguageModelSession(model: SystemLanguageModel.default, instructions: "You write alt text for a person's own night-sky journal photo, for someone who cannot see it. One plain sentence under 20 words. Describe only what is visible: the land, the light, any people or things. Never name stars, planets, constellations or places, never guess dates, the weather or how dark the sky was. Write in \(OnDeviceGuide.yourLanguage). No exclamation marks.")
        let options=GenerationOptions(temperature: 0.2, maximumResponseTokens: 60)
        do {
            return try await session.respond(options: options) {
                "Describe this photo."
                Attachment(image)
            }.content
        } catch { return nil }
    }
}

/// A starting line from Vision's image classification (`ClassifyImageRequest`, iOS 18), for when
/// the on-device model can't write one. Only labels Vision is very sure of (90% precision) and that
/// mean something on a night out, at most four, in a fixed order: the sky, the land, water, then
/// what people brought. Vision's labels are English identifiers, so each is named by Nyx's own word
/// from the String Catalog, and the line is offered only where the app's language is the person's
/// own (English and Spanish today); elsewhere a list in another language would not help.
nonisolated enum PhotoLabels {
    /// Vision identifiers, in the order a line names them, with Nyx's word for each (the Moon
    /// capitalized, as everywhere in Nyx).
    static var words: [(ids: [String], word: String)] {
        [(ids:["night_sky"],word:String(localized:"night sky")),
         (ids:["aurora"],word:String(localized:"aurora")),
         (ids:["moon"],word:String(localized:"Moon")),
         (ids:["lightning"],word:String(localized:"lightning")),
         (ids:["sunset_sunrise"],word:String(localized:"sunset or sunrise")),
         (ids:["sky"],word:String(localized:"sky")),
         (ids:["cloudy"],word:String(localized:"clouds")),
         (ids:["mountain"],word:String(localized:"mountains")),
         (ids:["volcano"],word:String(localized:"volcano")),
         (ids:["glacier"],word:String(localized:"glacier")),
         (ids:["canyon"],word:String(localized:"canyon")),
         (ids:["cliff"],word:String(localized:"cliffs")),
         (ids:["hill"],word:String(localized:"hills")),
         (ids:["desert"],word:String(localized:"desert")),
         (ids:["sand_dune"],word:String(localized:"dunes")),
         (ids:["rocks"],word:String(localized:"rocks")),
         (ids:["snow"],word:String(localized:"snow")),
         (ids:["forest"],word:String(localized:"forest")),
         (ids:["tree"],word:String(localized:"trees")),
         (ids:["cactus"],word:String(localized:"cactus")),
         (ids:["grass"],word:String(localized:"grass")),
         (ids:["lake"],word:String(localized:"lake")),
         (ids:["river"],word:String(localized:"river")),
         (ids:["waterfall"],word:String(localized:"waterfall")),
         (ids:["ocean"],word:String(localized:"ocean")),
         (ids:["beach"],word:String(localized:"beach")),
         (ids:["shore"],word:String(localized:"shore")),
         (ids:["people","crowd"],word:String(localized:"people")),
         (ids:["tent"],word:String(localized:"tent")),
         (ids:["camping"],word:String(localized:"campsite")),
         (ids:["telescope"],word:String(localized:"telescope")),
         (ids:["fire"],word:String(localized:"fire")),
         (ids:["car"],word:String(localized:"car")),
         (ids:["road","dirt_road"],word:String(localized:"road")),
         (ids:["lighthouse"],word:String(localized:"lighthouse"))]
    }
    /// Below this, a label is not offered even when Vision's precision curve allows it.
    static let minimumConfidence: Float=0.5
    static let maximumWords=4
    /// The line for the labels Vision kept (identifier → confidence): its words in order, without
    /// repeats, "sky" left out beside "night sky", the first letter capitalized; nil when none apply.
    static func line(from labels: [String: Float], locale: Locale = .current) -> String? {
        let kept=Set(labels.filter { $0.value>=minimumConfidence }.keys)
        var chosen: [String]=[]
        for (ids, word) in words where !kept.isDisjoint(with: ids) && !chosen.contains(word) {
            if ids == ["sky"], kept.contains("night_sky") { continue }
            chosen.append(word)
            if chosen.count == maximumWords { break }
        }
        guard let first=chosen.first?.first else { return nil }
        let line=chosen.joined(separator: ", ")
        return String(first).uppercased(with: locale)+line.dropFirst()
    }
    /// True when the app's language is the person's first language, so Nyx's words are theirs.
    static func speaks(app: String?, preferred: [String]) -> Bool {
        guard let app, let first=preferred.first else { return false }
        return Locale.Language(identifier: app).languageCode == Locale.Language(identifier: first).languageCode
    }
    static var available: Bool { speaks(app: Bundle.main.preferredLocalizations.first, preferred: Locale.preferredLanguages) }
    /// Classifies a scaled photo off the main thread; nil when Vision fails or names nothing Nyx can.
    @concurrent static func line(for image: CGImage) async -> String? {
        guard let observations=try? await ClassifyImageRequest().perform(on: image) else { return nil }
        var labels: [String: Float]=[:]
        for observation in observations where !observation.hasPrecisionRecallCurve || observation.hasMinimumRecall(0.01, forPrecision: 0.9) {
            labels[observation.identifier]=observation.confidence
        }
        return line(from: labels)
    }
}
