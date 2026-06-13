// Holds an IOPMAssertion that keeps the display awake while OpenDisplay runs, so a
// desk monitor (or a headless box you VNC into) doesn't idle-sleep - BetterDisplay's
// "prevent display sleep". macOS reference-counts these assertions, so this holds
// exactly one and releases it when disabled, on quit, or on deinit. The assertion has
// no visual effect; it only suppresses the idle-display-sleep timer.
// Public surface: enabled (persisted, self-applying). NOT responsible for: system
// sleep (this targets display-idle sleep only) or the idle dimmer's own timer.

import Foundation
import IOKit.pwr_mgt

final class DisplaySleepGuard: ObservableObject {
    @Published var enabled: Bool { didSet { persist(); apply() } }

    private var assertion: IOPMAssertionID = 0
    private var held = false
    private var ready = false

    init() {
        enabled = UserDefaults.standard.bool(forKey: "preventSleep.enabled")
        ready = true
        apply()
    }

    deinit { release() }

    // Re-read after a settings import; the didSet re-applies the assertion.
    func reload() { enabled = UserDefaults.standard.bool(forKey: "preventSleep.enabled") }

    private func persist() {
        guard ready else { return }
        UserDefaults.standard.set(enabled, forKey: "preventSleep.enabled")
    }

    private func apply() { enabled ? acquire() : release() }

    private func acquire() {
        guard !held else { return }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "OpenDisplay keeping the display awake" as CFString,
                                            &assertion)
        held = (r == kIOReturnSuccess)
    }

    private func release() {
        guard held else { return }
        IOPMAssertionRelease(assertion)
        held = false
        assertion = 0
    }
}
