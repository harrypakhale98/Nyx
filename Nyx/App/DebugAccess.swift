#if DEBUG
import UIKit

/// UI tests only: activates an accessibility element exactly as VoiceOver, Voice Control and Switch
/// Control do (`accessibilityActivate()`), which XCTest cannot: its `tap()` is a real touch.
/// Finds the element by its label anywhere in the app's windows.
enum DebugAccessibility {
    static func activate(label: String) -> Bool {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                if let element=find(label, in: window, depth: 0) { return element.accessibilityActivate() }
            }
        }
        return false
    }
    private static func find(_ label: String, in object: NSObject, depth: Int) -> NSObject? {
        guard depth<80 else { return nil }
        if object.isAccessibilityElement, object.accessibilityLabel == label { return object }
        var children: [Any]=[]
        if let elements=object.accessibilityElements { children+=elements }
        else {
            let count=object.accessibilityElementCount()
            if count != NSNotFound, count>0 { for i in 0..<count { if let element=object.accessibilityElement(at: i) { children.append(element) } } }
        }
        if let view=object as? UIView { children+=view.subviews }
        for child in children {
            if let child=child as? NSObject, let found=find(label, in: child, depth: depth+1) { return found }
        }
        return nil
    }
}
#endif
