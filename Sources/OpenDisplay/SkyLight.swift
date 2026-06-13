// Private SkyLight bridge. macOS hides a display's HiDPI modes from the public
// CGDisplayCopyAllDisplayModes; the private SLDisplayCopyAllDisplayModes (with the
// ShowDuplicateLowResolutionModes option) exposes them, and the public
// CGConfigureDisplayWithDisplayMode applies them. No headers exist for these
// symbols, so they are resolved at runtime via dlsym and degrade gracefully if a
// future macOS renames them (see `available`).

import Cocoa

struct DisplayMode: Identifiable, Hashable {
    let id = UUID()
    let looksW: Int
    let looksH: Int
    let pxW: Int
    let pxH: Int
    let hz: Double
    var isHiDPI: Bool { pxW > looksW }
}

enum SkyLight {
    private typealias CopyFn = @convention(c) (CGDirectDisplayID, CFDictionary?) -> Unmanaged<CFArray>?
    private typealias SizeFn = @convention(c) (UnsafeRawPointer) -> Int
    private typealias DblFn  = @convention(c) (UnsafeRawPointer) -> Double
    private typealias BoolFn = @convention(c) (UnsafeRawPointer) -> Bool

    private static let lib = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    private static func fn<T>(_ name: String, _ type: T.Type) -> T? {
        guard let lib, let sym = dlsym(lib, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let copyModes = fn("SLDisplayCopyAllDisplayModes", CopyFn.self)
    private static let pxW = fn("SLDisplayModeGetPixelWidth", SizeFn.self)
    private static let pxH = fn("SLDisplayModeGetPixelHeight", SizeFn.self)
    private static let lw  = fn("SLDisplayModeGetWidth", SizeFn.self)
    private static let lh  = fn("SLDisplayModeGetHeight", SizeFn.self)
    private static let hz  = fn("SLDisplayModeGetRefreshRate", DblFn.self)
    private static let gui = fn("SLDisplayModeIsUsableForDesktopGUI", BoolFn.self)

    static var available: Bool { copyModes != nil && pxW != nil && lw != nil && hz != nil }

    private static let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary

    /// HiDPI (2x) modes, one entry per looks-like width at its max refresh, descending.
    static func hidpiModes(for id: CGDirectDisplayID, minLooksW: Int = 1280) -> [DisplayMode] {
        guard let copyModes, let pxW, let pxH, let lw, let lh, let hz,
              let arr = copyModes(id, opts)?.takeRetainedValue() else { return [] }
        var best: [Int: DisplayMode] = [:]
        for i in 0..<CFArrayGetCount(arr) {
            guard let m = CFArrayGetValueAtIndex(arr, i) else { continue }
            let a = lw(m), b = lh(m), c = pxW(m), d = pxH(m), f = hz(m)
            guard (gui?(m) ?? true), c == 2 * a, d == 2 * b, a >= minLooksW else { continue }
            if let cur = best[a], cur.hz >= f { continue }
            best[a] = DisplayMode(looksW: a, looksH: b, pxW: c, pxH: d, hz: f)
        }
        return best.values.sorted { $0.looksW > $1.looksW }
    }

    /// Re-enumerate and apply the HiDPI mode at the given looks-like width (max refresh).
    @discardableResult
    static func applyHiDPI(looksW: Int, to id: CGDirectDisplayID) -> Bool {
        guard let copyModes, let pxW, let lw, let hz,
              let arr = copyModes(id, opts)?.takeRetainedValue() else { return false }
        var chosen: UnsafeRawPointer?
        var bestHz = -1.0
        for i in 0..<CFArrayGetCount(arr) {
            guard let m = CFArrayGetValueAtIndex(arr, i) else { continue }
            if lw(m) == looksW && pxW(m) == 2 * looksW {
                let f = hz(m)
                if f > bestHz { bestHz = f; chosen = m }
            }
        }
        guard let mode = chosen else { return false }
        return setMode(unsafeBitCast(mode, to: CGDisplayMode.self), on: id)
    }

    static func setMode(_ mode: CGDisplayMode, on id: CGDirectDisplayID) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(cfg, id, mode, nil)
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }
}
