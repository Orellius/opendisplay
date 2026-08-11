// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius, https://github.com/Orellius/opendisplay
// Forces the pointer to be drawn in software, which is what makes it visible at all
// while a scaled resolution is up.
//
// THE DEFECT THIS FIXES. A scaled resolution mirrors the real panel onto a virtual
// display. The panel is then a hardware mirror slave, and CGDisplayIsActive reports 0 for
// it. The pointer is normally not part of the picture at all: the GPU keeps it on a
// separate cursor plane and composites it at scanout, per active pipe. An inactive pipe
// composites nothing, so the pointer is simply absent from what the panel shows. It is
// worst in games, which is where a missing pointer actually stops you working, because a
// desktop pointer is at least somewhere near where you left it.
//
// THE LEVER, measured 2026-08-11 on macOS 26.5.1. The hardware cursor plane only carries
// 1x and 2x pointer bitmaps. Ask for any other scale and the window server gives up on the
// plane and draws the pointer into the framebuffer instead, which is the surface that gets
// mirrored. SLSHardwareCursorActive reports which path is live:
//
//     scale 1.0    -> hardware cursor active
//     scale 2.0    -> hardware cursor active     (the usual value on a 2x display)
//     scale 2.0001 -> SOFTWARE, composited into the framebuffer
//     scale 2.5    -> software
//     scale 3.0    -> software
//
// So the fix is to nudge the scale by an amount too small to see. 2.0001 is 0.005% larger
// than 2.0, which is under a hundredth of a pixel on a 32x32 pointer, and it moves the
// pointer onto the path that a mirror can actually show.
//
// WHAT IT COSTS. A software pointer is composited by the window server on every frame
// rather than by the display pipe, so it can lag under heavy GPU load in a way a hardware
// pointer does not. That is the trade: a pointer that sometimes lags beats no pointer.
// It is only in force while a scaled resolution is up.
//
// CRASH SAFETY. The scale is global window server state and outlives this process. If the
// app dies while a scaled mode is up, the nudged value would stay, so the original is
// written to defaults before it is touched and restored on the next launch.
//
// Public surface: force(), restore(), restoreAfterCrash().

import Foundation

enum SoftwareCursor {
    private static let savedKey = "cursorScale.saved"

    private static let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                                    RTLD_NOW)

    private typealias MainCID = @convention(c) () -> Int32
    private typealias HWActive = @convention(c) (Int32) -> Bool
    private typealias GetScale = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetScale = @convention(c) (Int32, Float) -> Int32

    private static func fn<T>(_ name: String, as type: T.Type) -> T? {
        guard let lib, let sym = dlsym(lib, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    private static var connection: Int32? {
        fn("SLSMainConnectionID", as: MainCID.self)?()
    }

    /// True while the pointer is on the GPU cursor plane, which a mirror slave cannot show.
    static var hardwareCursorActive: Bool? {
        guard let cid = connection, let active = fn("SLSHardwareCursorActive", as: HWActive.self)
        else { return nil }
        return active(cid)
    }

    static var scale: Float? {
        guard let cid = connection, let get = fn("SLSGetCursorScale", as: GetScale.self)
        else { return nil }
        var value: Float = 0
        guard get(cid, &value) == 0 else { return nil }
        return value
    }

    @discardableResult
    private static func setScale(_ value: Float) -> Bool {
        guard let cid = connection, let set = fn("SLSSetCursorScale", as: SetScale.self)
        else { return false }
        return set(cid, value) == 0
    }

    /// Move the pointer onto the software path. Returns false if the private symbols are
    /// gone or the window server refused, in which case the caller keeps its mirror and
    /// the pointer stays missing: worth reporting, never worth failing the mode change over.
    @discardableResult
    static func force() -> Bool {
        guard let current = scale else { return false }
        if hardwareCursorActive == false { return true }   // already software, leave it alone

        // Remember what to put back before touching global state, so a crash is recoverable.
        UserDefaults.standard.set(Double(current), forKey: savedKey)
        guard setScale(current + 0.0001) else {
            UserDefaults.standard.removeObject(forKey: savedKey)
            return false
        }
        // Verify rather than assume. The scale is accepted asynchronously, and a value that
        // did not actually move the pointer off the cursor plane fixes nothing.
        guard hardwareCursorActive == false else {
            restore()
            return false
        }
        return true
    }

    static func restore() {
        guard let saved = UserDefaults.standard.object(forKey: savedKey) as? Double else { return }
        setScale(Float(saved))
        UserDefaults.standard.removeObject(forKey: savedKey)
    }

    /// Called at launch. A saved value still on disk means the app died holding the nudge.
    static func restoreAfterCrash() {
        restore()
    }
}
