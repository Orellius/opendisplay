// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius, https://github.com/Orellius/opendisplay
// Which display the app is talking about. Every entry point used to answer that with
// CGMainDisplayID(), which was correct until this app started creating displays of its
// own: a scaled resolution mirrors the panel onto a CGVirtualDisplay, and that virtual
// display becomes the main one. From that moment CGMainDisplayID() returns something
// this app invented, and `info` describes a display that does not exist, `list`
// enumerates the wrong mode set, and quickReset(), the panic hotkey, aims at a phantom.
//
// The descriptors tag every display this app builds with vendor 0x4F50, so they can be
// told apart from real hardware with no bookkeeping and from a separate process, which
// matters because the CLI is its own process and cannot see the agent's state.
//
// Public surface: DisplayMarker.vendorID, PhysicalDisplay.main(), .isSynthetic(_:).
// NOT responsible for: creating virtual displays (VirtualDisplay/ScaledResolution).

import CoreGraphics

enum DisplayMarker {
    /// 'OP'. Stamped into every CGVirtualDisplayDescriptor this app creates.
    static let vendorID: UInt32 = 0x4F50
}

enum PhysicalDisplay {
    /// True when this display is one this app created rather than real hardware.
    static func isSynthetic(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayVendorNumber(id) == DisplayMarker.vendorID
    }

    /// The real panel the user means. Prefers the main display when it is real hardware,
    /// otherwise the first online display this app did not create. Falls back to
    /// CGMainDisplayID() so a machine whose only display is somehow synthetic still gets
    /// a usable id instead of zero.
    static func main() -> CGDirectDisplayID {
        let main = CGMainDisplayID()
        if !isSynthetic(main) { return main }
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success, count > 0 else { return main }
        // A mirror slave reports active = 0, so activity cannot be the filter here: while
        // scaling is on the real panel is precisely the inactive one.
        return ids[0 ..< Int(count)].first { !isSynthetic($0) } ?? main
    }
}
