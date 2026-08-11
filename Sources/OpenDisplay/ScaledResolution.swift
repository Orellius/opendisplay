// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius - https://github.com/Orellius/opendisplay
// Resolutions the panel does not have. macOS offers only the modes the EDID declares,
// plus the hidden HiDPI ones SkyLight digs out; on a 1440p panel that is exactly one.
// This synthesizes the rest the way BetterDisplay does: build a CGVirtualDisplay at an
// arbitrary looks-like size with hiDPI=1 (so it renders at 2x), then mirror the real
// panel onto it. macOS draws the desktop on the oversized virtual framebuffer and the
// GPU resamples that onto the panel's grid. Above 50% of native the render is larger
// than the panel, so the downsample is true supersampling, and text lands sharper than
// any mode the panel actually enumerates.
//
// Every path here is behind a countdown: apply() arms a timer that tears the whole thing
// down unless confirm() lands first. A mirror topology that goes wrong takes the only
// monitor with it, and a black screen cannot click "undo".
//
// Public surface: options(nativeW:nativeH:), apply(_:to:onResult:), confirm(), revert().
// NOT responsible for: enumerated modes (SkyLight), or the headless remote-access
// display (VirtualDisplay, a separate instance that is never mirrored).

import Cocoa
import MPBridge

/// A looks-like size synthesized from the panel's native size, expressed as a percentage
/// of native width so the ladder reads the same on any panel.
struct ScaledOption: Identifiable, Hashable {
    let looksW: Int
    let looksH: Int
    let percent: Int
    var id: Int { looksW }
    /// The virtual display renders at 2x the looks-like size (hiDPI = 1).
    var pxW: Int { looksW * 2 }
    var pxH: Int { looksH * 2 }
}

final class ScaledResolution {
    /// Seconds a change stays provisional before it reverts itself. Windows uses 15 for
    /// its "Keep these display settings?" box; 10 is his call, and it is long enough to
    /// read a dialog on a screen that just went wrong.
    static let confirmWindow = 10

    private var handle: CGVirtualDisplay?
    private var virtualID: CGDirectDisplayID = 0
    private var realID: CGDirectDisplayID = 0
    private var restoreMode: CGDisplayMode?
    private var timer: Timer?

    private(set) var active: ScaledOption?
    private(set) var awaitingConfirm = false

    /// Fired when the countdown expires and the change is rolled back, so the UI resettles.
    var onAutoRevert: (() -> Void)?

    // The framebuffer the virtual display advertises. hiDPI = 1 doubles the looks-like
    // size, so the largest offerable option is half of this on each axis. 8K is what the
    // descriptor accepts without the private API rejecting the settings outright.
    private static let maxPxW = 7680
    private static let maxPxH = 4320

    // Percentages of native width. Below 100 the UI is larger than native (less desktop
    // space, still supersampled above 50); above 100 it is smaller, with more room.
    private static let ladder = [50, 60, 70, 75, 80, 85, 90, 100, 110, 125, 140, 150, 175, 200]

    /// The synthesized ladder for a panel, largest first, clipped to what the virtual
    /// display can actually render. Empty when the panel's native size is unknown.
    static func options(nativeW: Int, nativeH: Int) -> [ScaledOption] {
        guard nativeW > 0, nativeH > 0 else { return [] }
        let aspect = Double(nativeH) / Double(nativeW)
        var out: [ScaledOption] = []
        for p in ladder {
            // Even on both axes: an odd framebuffer axis is legal, but macOS reports some
            // odd HiDPI modes inconsistently and the 2x pair stops being exact.
            let w = (Int((Double(nativeW) * Double(p) / 100.0).rounded()) / 2) * 2
            let h = (Int((Double(w) * aspect).rounded()) / 2) * 2
            guard w >= 640, h >= 360, w * 2 <= maxPxW, h * 2 <= maxPxH else { continue }
            out.append(ScaledOption(looksW: w, looksH: h, percent: p))
        }
        return out.sorted { $0.looksW > $1.looksW }
    }

    /// Build the virtual display, switch it to its HiDPI mode, mirror `real` onto it, and
    /// arm the revert countdown. `onResult` fires on the main queue once the topology has
    /// settled or failed; registration is asynchronous, so this cannot be synchronous.
    func apply(_ option: ScaledOption, to real: CGDirectDisplayID, onResult: @escaping (Bool) -> Void) {
        teardown(restoringMode: true)
        realID = real
        restoreMode = CGDisplayCopyDisplayMode(real)
        // Carry the panel's refresh rate onto the virtual mode so the mirror set is not
        // pinned to 60 Hz. UNVERIFIED above 60: the private API accepts the value, but
        // whether the mirror actually runs at it has not been measured.
        let hz = CGDisplayCopyDisplayMode(real)?.refreshRate ?? 60
        let mode = CGVirtualDisplayMode(
            width: UInt(option.looksW),
            height: UInt(option.looksH),
            refreshRate: hz > 0 ? hz : 60
        )

        let desc = CGVirtualDisplayDescriptor()
        desc.setDispatchQueue(.main)
        desc.name = "OpenDisplay Scaled"
        desc.maxPixelsWide = UInt32(max(Self.maxPxW, option.pxW))
        desc.maxPixelsHigh = UInt32(max(Self.maxPxH, option.pxH))
        // Match the real panel's physical size so macOS derives a sane DPI for the mirror.
        let mm = CGDisplayScreenSize(real)
        desc.sizeInMillimeters = (mm.width > 0 && mm.height > 0) ? mm : CGSize(width: 600, height: 340)
        desc.vendorID = 0x4F50      // 'OP'
        desc.productID = 0x5CA1
        desc.serialNum = 0x0002     // distinct from the headless display's, so the two coexist

        let display = CGVirtualDisplay(descriptor: desc)
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 1
        settings.modes = [mode]
        guard display.apply(settings) else { onResult(false); return }
        handle = display
        virtualID = display.displayID

        // The display registers asynchronously and boots at a 1x mode; poll until the
        // HiDPI variant exists rather than guessing a delay that is wrong on a busy box.
        waitForHiDPI(on: display.displayID, looksW: option.looksW, tries: 12) { [weak self] found in
            guard let self else { onResult(false); return }
            guard let found, SkyLight.setMode(found, on: self.virtualID),
                  Self.mirror(self.realID, onto: self.virtualID) else {
                self.teardown(restoringMode: true)
                onResult(false)
                return
            }
            self.active = option
            self.arm()
            onResult(true)
        }
    }

    /// Keep the current scaled mode: cancels the revert countdown.
    func confirm() {
        timer?.invalidate()
        timer = nil
        awaitingConfirm = false
    }

    /// Drop the scaled mode and put the panel back on its own framebuffer.
    func revert() {
        teardown(restoringMode: true)
    }

    /// Backstop only. The visible countdown in ConfirmRevert normally reverts first; this
    /// fires a few seconds later and covers the case where the panel never made it to
    /// screen at all (WindowServer wedged by the topology change, no Space to draw on).
    /// teardown() is idempotent, so both firing is harmless.
    private func arm() {
        awaitingConfirm = true
        timer?.invalidate()
        let backstop = Double(Self.confirmWindow + 3)
        timer = Timer.scheduledTimer(withTimeInterval: backstop, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.teardown(restoringMode: true)
            self.onAutoRevert?()
        }
    }

    /// Unmirror first, then release the virtual display. The other order leaves the panel
    /// mirroring a display that no longer exists, which is exactly the black screen this
    /// whole file is built to avoid.
    private func teardown(restoringMode: Bool) {
        timer?.invalidate()
        timer = nil
        awaitingConfirm = false
        if realID != 0, handle != nil {
            Self.mirror(realID, onto: kCGNullDirectDisplay)
        }
        handle = nil
        virtualID = 0
        if restoringMode, let restoreMode, realID != 0 {
            _ = SkyLight.setMode(restoreMode, on: realID)
        }
        restoreMode = nil
        active = nil
    }

    private func waitForHiDPI(
        on id: CGDirectDisplayID,
        looksW: Int,
        tries: Int,
        then: @escaping (CGDisplayMode?) -> Void
    ) {
        if let m = Self.hidpiMode(on: id, looksW: looksW) { then(m); return }
        guard tries > 0 else { then(nil); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { then(nil); return }
            self.waitForHiDPI(on: id, looksW: looksW, tries: tries - 1, then: then)
        }
    }

    private static func hidpiMode(on id: CGDirectDisplayID, looksW: Int) -> CGDisplayMode? {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { return nil }
        return modes.filter { $0.width == looksW && $0.pixelWidth == 2 * looksW }
            .max { $0.refreshRate < $1.refreshRate }
    }

    /// `master` drives the mode; kCGNullDirectDisplay disables mirroring.
    /// .forSession, never .permanently: a bad topology must not survive a logout.
    @discardableResult
    private static func mirror(_ display: CGDirectDisplayID, onto master: CGDirectDisplayID) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        CGConfigureDisplayMirrorOfDisplay(cfg, display, master)
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }
}
