// Brightness control. Software dimming scales the display's gamma transfer and
// is visible on any panel (it darkens the rendered output). Hardware DDC is
// offered as an opt-in, since some panels acknowledge DDC writes but ignore them.
// A floor keeps software dimming from reaching full black.

import CoreGraphics

enum Brightness {
    private static let floor = 0.25   // 0% on the slider still shows 25% luminance

    /// Apply brightness and warmth together in one gamma transfer so they don't
    /// overwrite each other. brightness/warmth: 0...1. warmth 0 = neutral.
    static func apply(brightness: Double, warmth: Double, on id: CGDirectDisplayID) {
        let lin = max(0, min(1, brightness))
        let b = floor + (1.0 - floor) * lin
        let w = max(0, min(1, warmth))
        // Steepen the transfer curve as brightness drops so deep dimming keeps perceived
        // contrast rather than washing out (BetterDisplay #4065). Neutral 1.0 at full bright.
        let gamma = CGGammaValue(1.0 + 0.45 * (1.0 - lin))
        let red = CGGammaValue(b)
        let green = CGGammaValue(b * (1.0 - 0.12 * w))
        let blue = CGGammaValue(b * (1.0 - 0.45 * w))
        CGSetDisplayTransferByFormula(id, 0, red, gamma, 0, green, gamma, 0, blue, gamma)
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
