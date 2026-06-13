// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Display rotation, thin Swift over the MPBridge ObjC shim. On Apple Silicon the
// Intel-era IOFramebuffer transform path is dead (the framebuffer is DCP-managed)
// and the CGX rotation symbols are WindowServer-internal; the working route is
// MPDisplay's orientation setter, the same one System Settings drives. The unsafe
// alloc/init against the private class lives in MPBridge so this stays trivial.
// Public surface: Rotation.degrees, canRotate(_:), current(_:), rotate(_:to:).
// NOT responsible for: persistence (macOS already persists rotation across reboots).

import CoreGraphics
import MPBridge

enum Rotation {
    static let degrees = [0, 90, 180, 270]

    /// True only if this specific panel/connection reports it can rotate (Sidecar and
    /// some externals return false, exactly as System Settings hides the control for them).
    static func canRotate(_ id: CGDirectDisplayID) -> Bool { OD_DisplayCanRotate(id) }

    static func current(_ id: CGDirectDisplayID) -> Int { Int(CGDisplayRotation(id).rounded()) }

    @discardableResult
    static func rotate(_ id: CGDirectDisplayID, to degrees: Int) -> Bool {
        degrees == 0 || Self.degrees.contains(degrees) ? OD_DisplayRotate(id, Int32(degrees)) : false
    }
}
