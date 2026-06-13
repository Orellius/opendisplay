// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// A single headless HiDPI virtual display via the private CGVirtualDisplay API.
// The point is remote access: when the always-on Mac runs with no panel attached
// (or you want a second crisp surface to VNC into), this creates a display that
// renders at 2x and exists only in the framebuffer. The CGVirtualDisplay is removed
// the moment its strong reference drops, so stop() just releases it.
// Public surface: start(looksW:looksH:hz:), stop(), isActive, displayID.

import CoreGraphics
import Foundation
import MPBridge

final class VirtualDisplay {
    private var handle: CGVirtualDisplay?
    private(set) var displayID: CGDirectDisplayID = 0

    var isActive: Bool { handle != nil }

    @discardableResult
    func start(looksW: Int, looksH: Int, hz: Double = 60) -> Bool {
        stop()
        let desc = CGVirtualDisplayDescriptor()
        desc.setDispatchQueue(.main)
        desc.name = "OpenDisplay Virtual"
        desc.maxPixelsWide = 7680
        desc.maxPixelsHigh = 4320
        desc.sizeInMillimeters = CGSize(width: 600, height: 340)
        desc.vendorID = 0x4F50      // 'OP'
        desc.productID = 0x0D15
        desc.serialNum = 0x0001
        let display = CGVirtualDisplay(descriptor: desc)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        // hiDPI=1 turns a looks-like mode into a 2x-rendered HiDPI pair (looks WxH, px 2W x 2H).
        settings.modes = [CGVirtualDisplayMode(width: UInt(looksW), height: UInt(looksH), refreshRate: hz)]
        guard display.apply(settings) else { return false }
        handle = display
        displayID = display.displayID
        // The display registers asynchronously and boots at a default 1x mode; once it
        // is online, switch it to the HiDPI variant so the remote session is crisp.
        let id = display.displayID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Self.applyHiDPIMode(id, looksW: looksW) }
        return true
    }

    func stop() {
        handle = nil
        displayID = 0
    }

    private static func applyHiDPIMode(_ id: CGDirectDisplayID, looksW: Int) {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode],
              let mode = modes.first(where: { $0.width == looksW && $0.pixelWidth == 2 * looksW }) else { return }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
        CGCompleteDisplayConfiguration(cfg, .forSession)
    }
}
