import SwiftUI

/// DEBUG `-nyx-vision-widget-shots`: renders the widget's faces (small, medium, simplified) for
/// tonight and a week on into the app's tmp folder, since the simulator cannot place a widget
/// from the command line. Nothing in Release.
enum VisionWidgetShots {
    static func render() {
        #if DEBUG
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "widget-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = VisionDebug.date ?? .now
        let faces: [(String, MoonWidgetFace, CGSize)] = [
            ("small", MoonWidgetFace(facts: MoonFacts(at: now), family: .systemSmall), CGSize(width: 170, height: 170)),
            ("medium", MoonWidgetFace(facts: MoonFacts(at: now), family: .systemMedium), CGSize(width: 364, height: 170)),
            ("simplified", MoonWidgetFace(facts: MoonFacts(at: now), family: .systemSmall, simplified: true), CGSize(width: 170, height: 170)),
            ("medium-week", MoonWidgetFace(facts: MoonFacts(at: now.addingTimeInterval(7*86400)), family: .systemMedium), CGSize(width: 364, height: 170)),
        ]
        for (name, face, size) in faces {
            let view = face.padding(16).frame(width: size.width, height: size.height)
                .background(MoonWidgetFace.background, in: .rect(cornerRadius: 26))
                .padding(20).background(Color(white: 0.35))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() { try? data.write(to: folder.appending(path: "\(name).png")) }
        }
        #endif
    }
}
