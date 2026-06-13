// App Intents so the display controls are scriptable from macOS Shortcuts, reusing the
// same apply paths and UserDefaults keys as the GUI and CLI. Shortcuts discovery needs
// the Metadata.appintents bundle that appintentsmetadataprocessor builds from the
// compiler's const-values; scripts/bundle.sh produces and embeds it (it builds via
// xcodebuild, which emits the const-values a plain `swift build` omits, then runs the
// processor into Contents/Resources). The CLI is the equivalent path for a raw build.
// Public surface: the intent structs + OpenDisplayShortcuts (AppShortcutsProvider).

import AppIntents
import CoreGraphics
import Foundation

private func mainID() -> CGDirectDisplayID { CGMainDisplayID() }

struct SetBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Display Brightness"
    static var description = IntentDescription("Set software brightness from 0 to 100.")

    @Parameter(title: "Brightness", default: 100)
    var level: Int

    func perform() async throws -> some IntentResult {
        let id = mainID()
        let v = max(0, min(100, level))
        let warmth = UserDefaults.standard.object(forKey: DisplayModel.warmthKey(id)) as? Double ?? 0
        Brightness.apply(brightness: Double(v) / 100, warmth: warmth / 100, on: id)
        UserDefaults.standard.set(Double(v), forKey: DisplayModel.brightKey(id))
        return .result()
    }
}

struct SetWarmthIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Display Warmth"
    static var description = IntentDescription("Set color warmth from 0 to 100.")

    @Parameter(title: "Warmth", default: 0)
    var level: Int

    func perform() async throws -> some IntentResult {
        let id = mainID()
        let v = max(0, min(100, level))
        let bright = UserDefaults.standard.object(forKey: DisplayModel.brightKey(id)) as? Double ?? 100
        Brightness.apply(brightness: bright / 100, warmth: Double(v) / 100, on: id)
        UserDefaults.standard.set(Double(v), forKey: DisplayModel.warmthKey(id))
        return .result()
    }
}

struct SetResolutionIntent: AppIntent {
    static var title: LocalizedStringResource = "Set HiDPI Resolution"
    static var description = IntentDescription("Set a hidden HiDPI mode by its looks-like width.")

    @Parameter(title: "Looks-like width", default: 1920)
    var width: Int

    func perform() async throws -> some IntentResult {
        let id = mainID()
        guard SkyLight.applyHiDPI(looksW: width, to: id) else {
            throw $width.needsValueError("No HiDPI mode at that width")
        }
        UserDefaults.standard.set(width, forKey: DisplayModel.key(id))
        return .result()
    }
}

struct RotateDisplayIntent: AppIntent {
    static var title: LocalizedStringResource = "Rotate Display"
    static var description = IntentDescription("Rotate the display to 0, 90, 180, or 270 degrees.")

    @Parameter(title: "Degrees", default: 0)
    var degrees: Int

    func perform() async throws -> some IntentResult {
        guard Rotation.rotate(mainID(), to: degrees) else {
            throw $degrees.needsValueError("Use 0, 90, 180, or 270")
        }
        return .result()
    }
}

struct OpenDisplayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SetBrightnessIntent(),
                    phrases: ["Set \(.applicationName) brightness"],
                    shortTitle: "Set Brightness", systemImageName: "sun.max")
        AppShortcut(intent: SetWarmthIntent(),
                    phrases: ["Set \(.applicationName) warmth"],
                    shortTitle: "Set Warmth", systemImageName: "thermometer.sun")
        AppShortcut(intent: SetResolutionIntent(),
                    phrases: ["Set \(.applicationName) resolution"],
                    shortTitle: "Set Resolution", systemImageName: "rectangle.on.rectangle")
        AppShortcut(intent: RotateDisplayIntent(),
                    phrases: ["Rotate \(.applicationName)"],
                    shortTitle: "Rotate Display", systemImageName: "rotate.right")
    }
}
