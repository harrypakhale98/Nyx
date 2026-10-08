import Foundation
import CoreGraphics
import FoundationModels

/// "Suggest a description" for a journal photo: on iOS 27, where the on-device model is ready and
/// can see images, one plain line the person reads, edits or ignores. It is never saved by itself,
/// it says it was suggested on this iPhone, and it is told not to name sky facts it cannot know
/// from a photo (stars, planets, how dark it was). Without the model the button simply isn't there.
enum PhotoDescriber {
    static var available: Bool {
        guard !DebugScenario.isEnabled("no-ai") else { return false }
        if DebugScenario.isEnabled("suggest-fixture") { return true }
        if #available(iOS 27.0, *) { return VisionDescriber.available }
        return false
    }
    /// One line, or nil if the model declined or failed.
    static func suggest(_ data: Data) async -> String? {
        #if DEBUG
        if DebugScenario.isEnabled("suggest-fixture") { return "A dark ridge under a sky full of stars, with a faint band of light above it." }
        #endif
        guard #available(iOS 27.0, *), VisionDescriber.available else { return nil }
        guard let image=await Task.detached(priority: .userInitiated, operation: { PhotoScaling.image(data, maxPixels: 1024) }).value else { return nil }
        return await VisionDescriber.describe(image).flatMap(clean)
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
        return model.availability == .available && model.capabilities.contains(.vision)
    }
    static func describe(_ image: CGImage) async -> String? {
        let session=LanguageModelSession(model: SystemLanguageModel.default, instructions: "You write alt text for a person's own night-sky journal photo, for someone who cannot see it. One plain sentence under 20 words. Describe only what is visible: the land, the light, any people or things. Never name stars, planets, constellations or places, never guess dates, the weather or how dark the sky was. No exclamation marks.")
        let options=GenerationOptions(temperature: 0.2, maximumResponseTokens: 60)
        do {
            return try await session.respond(options: options) {
                "Describe this photo."
                Attachment(image)
            }.content
        } catch { return nil }
    }
}
