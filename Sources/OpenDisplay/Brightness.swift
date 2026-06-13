// Brightness control. Software dimming scales the display's gamma transfer and
// is visible on any panel (it darkens the rendered output). Hardware DDC is
// offered as an opt-in, since some panels acknowledge DDC writes but ignore them.
// A floor keeps software dimming from reaching full black.

import CoreGraphics

enum Brightness {
    private static let floor = 0.25   // 0% on the slider still shows 25% luminance

    /// level: 0...1. 1.0 restores normal output.
    static func setSoftware(_ level: Double, on id: CGDirectDisplayID) {
        let clamped = max(0, min(1, level))
        let maxOut = CGGammaValue(floor + (1.0 - floor) * clamped)
        CGSetDisplayTransferByFormula(id,
                                      0, maxOut, 1.0,
                                      0, maxOut, 1.0,
                                      0, maxOut, 1.0)
    }

    /// Remove software dimming (e.g. on quit) so the panel is not left dark.
    static func restore() {
        CGDisplayRestoreColorSyncSettings()
    }

    @discardableResult
    static func setHardware(_ percent: Int) -> Bool {
        DDC.setBrightness(percent)
    }

    static var hardwareAvailable: Bool { DDC.available }
}
