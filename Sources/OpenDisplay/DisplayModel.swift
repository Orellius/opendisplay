// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Observable state for one display: its available HiDPI modes, the active choice,
// and persistence. Restores the saved choice on launch and on display reconnect.

import Cocoa
import Combine

struct TonePreset { let brightness: Double; let warmth: Double }

final class DisplayModel: ObservableObject {
    @Published private(set) var modes: [DisplayMode] = []
    @Published private(set) var currentLooksW: Int = 0   // 0 means native
    @Published private(set) var currentHz: Double = 0
    @Published private(set) var refreshRates: [Double] = []
    @Published private(set) var rotation: Int = 0        // 0/90/180/270 degrees
    @Published var brightness: Double = 100              // software dimming, 0...100
    @Published var warmth: Double = 0                    // color temperature, 0...100
    @Published var contrast: Double = 50                 // transfer spread, 0...100, 50 neutral
    @Published var hardwareDDC: Bool = false {           // also drive DDC when set
        didSet { UserDefaults.standard.set(hardwareDDC, forKey: Self.ddcKey(displayID)) }
    }
    @Published var protectConfig: Bool = false {         // re-assert saved resolution on drift
        didSet { UserDefaults.standard.set(protectConfig, forKey: Self.protectKey(displayID)) }
    }
    @Published private(set) var favorites: Set<Int> = [] // starred looks-like widths
    @Published private(set) var virtualActive = false    // headless virtual display on
    @Published private(set) var scaledOptions: [ScaledOption] = []
    @Published private(set) var scaledActive: ScaledOption?   // nil = panel on its own framebuffer
    @Published private(set) var presets: [TonePreset?] = [nil, nil, nil]
    @Published private(set) var displayName = ""          // custom override, "" = use product name

    /// The custom name when set, otherwise the panel's real product name.
    var effectiveName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? productName : trimmed
    }

    var hardwareAvailable: Bool { Brightness.hardwareAvailable }

    let displayID: CGDirectDisplayID
    let canRotate: Bool
    let nativeW: Int
    let nativeH: Int
    let productName: String
    private let nativeMode: CGDisplayMode?
    private let virtual = VirtualDisplay()
    private let scaled = ScaledResolution()
    private(set) var schedule: NightSchedule!
    let idle = IdleDimmer()
    let sleepGuard = DisplaySleepGuard()

    // Gamma bottoms out at 25% luminance (the floor in Brightness). Below this slider
    // value the overlay ramps in on top of the gamma floor for true deep dimming; at or
    // above it the overlay is off and brightness is pure gamma (so CLI/Shortcuts, which
    // can't hold a window, match the GUI for the whole normal range).
    private let deepDim = DimOverlay()
    private static let deepDimFloor = 20.0
    private static let deepDimMaxAlpha = 0.88

    init(displayID: CGDirectDisplayID = PhysicalDisplay.main()) {
        self.displayID = displayID
        self.nativeMode = CGDisplayCopyDisplayMode(displayID)
        self.canRotate = Rotation.canRotate(displayID)
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let native = (CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode])?
            .filter { $0.pixelWidth == $0.width }.max { $0.pixelWidth < $1.pixelWidth }
        self.nativeW = native?.width ?? 0
        self.nativeH = native?.height ?? 0
        self.productName = DisplayInfo.gather(displayID).name
        self.scaledOptions = ScaledResolution.options(nativeW: nativeW, nativeH: nativeH)
        refresh()
        scaled.onAutoRevert = { [weak self] in
            guard let self else { return }
            self.scaledActive = nil
            self.detectCurrent()
            OSD.text("arrow.uturn.backward", "Reverted")
        }
        let saved = UserDefaults.standard.integer(forKey: Self.key(displayID))
        if saved > 0 { apply(looksW: saved) }

        brightness = (UserDefaults.standard.object(forKey: Self.brightKey(displayID)) as? Double) ?? 100
        warmth = (UserDefaults.standard.object(forKey: Self.warmthKey(displayID)) as? Double) ?? 0
        contrast = (UserDefaults.standard.object(forKey: Self.contrastKey(displayID)) as? Double) ?? 50
        displayName = UserDefaults.standard.string(forKey: Self.nameKey(displayID)) ?? ""
        favorites = Set((UserDefaults.standard.array(forKey: Self.favKey(displayID)) as? [Int]) ?? [])
        hardwareDDC = UserDefaults.standard.bool(forKey: Self.ddcKey(displayID))
        protectConfig = UserDefaults.standard.bool(forKey: Self.protectKey(displayID))
        presets = (0 ..< 3).map { i in
            guard UserDefaults.standard.bool(forKey: "preset.\(i).set") else { return nil }
            return TonePreset(brightness: UserDefaults.standard.double(forKey: "preset.\(i).b"),
                              warmth: UserDefaults.standard.double(forKey: "preset.\(i).w"))
        }
        applyTone()
        // The schedule, when enabled, drives brightness/warmth live (without touching the
        // manual saved values); when disabled it restores them. Created last so its
        // closures capture a fully-initialized model.
        schedule = NightSchedule(
            apply: { [weak self] b, w in
                guard let self else { return }
                self.brightness = b
                self.warmth = w
                self.applyTone()
            },
            restore: { [weak self] in
                guard let self else { return }
                self.brightness = (UserDefaults.standard.object(forKey: Self.brightKey(self.displayID)) as? Double) ?? 100
                self.warmth = (UserDefaults.standard.object(forKey: Self.warmthKey(self.displayID)) as? Double) ?? 0
                self.applyTone()
            })
    }

    static func key(_ id: CGDirectDisplayID) -> String { "looksW.\(id)" }
    static func brightKey(_ id: CGDirectDisplayID) -> String { "brightness.\(id)" }
    static func warmthKey(_ id: CGDirectDisplayID) -> String { "warmth.\(id)" }
    static func contrastKey(_ id: CGDirectDisplayID) -> String { "contrast.\(id)" }
    static func nameKey(_ id: CGDirectDisplayID) -> String { "name.\(id)" }
    private static func favKey(_ id: CGDirectDisplayID) -> String { "favorites.\(id)" }

    // Keep the raw text live so spaces can be typed; persist trimmed (effectiveName trims).
    func setDisplayName(_ value: String) {
        displayName = value
        UserDefaults.standard.set(value.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: Self.nameKey(displayID))
    }
    private static func ddcKey(_ id: CGDirectDisplayID) -> String { "hardwareDDC.\(id)" }
    private static func protectKey(_ id: CGDirectDisplayID) -> String { "protectConfig.\(id)" }

    // BetterDisplay's "configuration protection": if something changed the resolution out
    // from under us (a game, an app, a macOS reshuffle), put the saved one back. Re-applies
    // only on real drift, so re-asserting (which itself fires a reconfig) settles in one pass.
    func reassertIfProtected() {
        guard protectConfig else { return }
        // Mirroring fires reconfig events of its own. Re-asserting the saved mode into a
        // live scaled topology would fight it and could tear the mirror down mid-change.
        guard scaledActive == nil else { return }
        let saved = UserDefaults.standard.integer(forKey: Self.key(displayID))
        detectCurrent()
        guard saved != currentLooksW else { return }
        if saved > 0 { apply(looksW: saved) } else { applyNative() }
    }

    // BetterDisplay #1976: save the current brightness+warmth to a slot, recall it later.
    func savePreset(_ i: Int) {
        guard presets.indices.contains(i) else { return }
        presets[i] = TonePreset(brightness: brightness, warmth: warmth)
        UserDefaults.standard.set(true, forKey: "preset.\(i).set")
        UserDefaults.standard.set(brightness, forKey: "preset.\(i).b")
        UserDefaults.standard.set(warmth, forKey: "preset.\(i).w")
    }

    func applyPreset(_ i: Int) {
        guard presets.indices.contains(i), let p = presets[i] else { return }
        setBrightness(p.brightness)
        setWarmth(p.warmth)
        OSD.brightness(p.brightness)
    }

    // Re-read every persisted value (after a settings import) and apply it live.
    func reloadFromDefaults() {
        let d = UserDefaults.standard
        brightness = (d.object(forKey: Self.brightKey(displayID)) as? Double) ?? 100
        warmth = (d.object(forKey: Self.warmthKey(displayID)) as? Double) ?? 0
        contrast = (d.object(forKey: Self.contrastKey(displayID)) as? Double) ?? 50
        displayName = d.string(forKey: Self.nameKey(displayID)) ?? ""
        favorites = Set((d.array(forKey: Self.favKey(displayID)) as? [Int]) ?? [])
        hardwareDDC = d.bool(forKey: Self.ddcKey(displayID))
        protectConfig = d.bool(forKey: Self.protectKey(displayID))
        presets = (0 ..< 3).map { i in
            guard d.bool(forKey: "preset.\(i).set") else { return nil }
            return TonePreset(brightness: d.double(forKey: "preset.\(i).b"),
                              warmth: d.double(forKey: "preset.\(i).w"))
        }
        let savedLooks = d.integer(forKey: Self.key(displayID))
        if savedLooks > 0 { apply(looksW: savedLooks) } else { applyNative() }
        applyTone()
        schedule.reload()
        idle.reload()
        sleepGuard.reload()
    }

    func isFavorite(_ looksW: Int) -> Bool { favorites.contains(looksW) }

    func toggleFavorite(_ looksW: Int) {
        if favorites.contains(looksW) { favorites.remove(looksW) } else { favorites.insert(looksW) }
        UserDefaults.standard.set(Array(favorites), forKey: Self.favKey(displayID))
    }

    private func applyTone() {
        Brightness.apply(brightness: brightness / 100.0, warmth: warmth / 100.0,
                         contrast: contrast / 100.0, on: displayID)
        applyDeepDim()
    }

    private func applyDeepDim() {
        let alpha = brightness >= Self.deepDimFloor ? 0
            : (Self.deepDimFloor - brightness) / Self.deepDimFloor * Self.deepDimMaxAlpha
        deepDim.setAlpha(alpha)
    }

    func setBrightness(_ value: Double) {
        brightness = value
        applyTone()
        if hardwareDDC { Brightness.setHardware(Int(value)) }
        UserDefaults.standard.set(value, forKey: Self.brightKey(displayID))
    }

    func setWarmth(_ value: Double) {
        warmth = value
        applyTone()
        UserDefaults.standard.set(value, forKey: Self.warmthKey(displayID))
    }

    func setContrast(_ value: Double) {
        contrast = value
        applyTone()
        UserDefaults.standard.set(value, forKey: Self.contrastKey(displayID))
    }

    func nudgeBrightness(_ delta: Double) {
        setBrightness(min(100, max(0, brightness + delta)))
        OSD.brightness(brightness)
    }

    func nudgeWarmth(_ delta: Double) {
        setWarmth(min(100, max(0, warmth + delta)))
        OSD.warmth(warmth)
    }

    private var preBlackout: Double?

    // BetterDisplay #1448: one toggle to dim to the floor and back to where it was.
    func toggleBlackout() {
        if let prev = preBlackout {
            setBrightness(prev); preBlackout = nil
            OSD.brightness(prev)
        } else {
            preBlackout = brightness
            setBrightness(0)
            OSD.brightness(0)
        }
    }

    // BetterDisplay #1208: panic key back to a known-good state when a scaled-res
    // experiment leaves the screen unusable.
    func quickReset() {
        // The panic key exists for exactly this: a scaled experiment that left the screen
        // unusable. Drop the mirror before anything else, since nothing else is visible
        // until the panel is back on its own framebuffer.
        clearScaled()
        applyNative()
        setBrightness(100)
        setWarmth(0)
        setContrast(50)
        preBlackout = nil
        OSD.text("arrow.counterclockwise", "Reset")
    }

    // BetterDisplay #5423: gamma and the chosen mode can drop on wake; reapply them.
    func reapply() {
        let saved = UserDefaults.standard.integer(forKey: Self.key(displayID))
        if saved > 0 { apply(looksW: saved) }
        applyTone()
        detectCurrent()
    }

    func refresh() {
        // While the panel is a mirror slave its mode list describes the master's
        // framebuffer, not the panel: a scaled mode makes this 1440p display report HiDPI
        // modes it does not have, and they vanish when the mirror does. Keep the last list
        // enumerated off-mirror rather than swapping in modes that cannot be applied.
        if !PhysicalDisplay.isMirrorSlave(displayID) {
            modes = SkyLight.hidpiModes(for: displayID)
        }
        detectCurrent()
    }

    private func detectCurrent() {
        rotation = Rotation.current(displayID)
        guard let cur = CGDisplayCopyDisplayMode(displayID) else {
            currentLooksW = 0; currentHz = 0; refreshRates = []; return
        }
        currentLooksW = cur.pixelWidth > cur.width ? cur.width : 0
        currentHz = cur.refreshRate
        refreshRates = currentLooksW > 0 ? SkyLight.refreshRates(for: displayID, looksW: currentLooksW)
                                         : nativeRefreshRates(cur.width)
    }

    // 1x modes at the native width carry their own set of refresh rates, so the picker
    // works in native mode too (not only for HiDPI modes).
    private func nativeRefreshRates(_ width: Int) -> [Double] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode] else { return [] }
        let rates = modes.filter { $0.width == width && $0.pixelWidth == $0.width }.map { Int($0.refreshRate.rounded()) }
        return Set(rates).map(Double.init).sorted(by: >)
    }

    func apply(looksW: Int) {
        guard SkyLight.applyHiDPI(looksW: looksW, to: displayID) else { return }
        UserDefaults.standard.set(looksW, forKey: Self.key(displayID))
        detectCurrent()
    }

    func applyNative() {
        guard let nativeMode, SkyLight.setMode(nativeMode, on: displayID) else { return }
        UserDefaults.standard.set(0, forKey: Self.key(displayID))
        detectCurrent()
    }

    // Resolutions the panel never advertised, via a mirrored virtual display. Provisional
    // until the user accepts: ConfirmRevert counts down and puts the old mode back if the
    // change left nothing readable on screen. See ScaledResolution for the mechanism.
    func applyScaled(_ option: ScaledOption) {
        scaled.apply(option, to: displayID) { [weak self] ok in
            guard let self else { return }
            guard ok else {
                self.scaledActive = nil
                OSD.text("exclamationmark.triangle", "Scaling failed")
                return
            }
            self.scaledActive = option
            ConfirmRevert.shared.ask(
                headline: "Keep these display settings?",
                detail: "\(option.looksW) × \(option.looksH) at \(option.percent)% of native, "
                    + "rendered \(option.pxW) × \(option.pxH).",
                seconds: ScaledResolution.confirmWindow,
                onKeep: { [weak self] in self?.keepScaled(option) },
                onRevert: { [weak self] in self?.clearScaled() })
        }
    }

    private func keepScaled(_ option: ScaledOption) {
        scaled.confirm()
        UserDefaults.standard.set(option.looksW, forKey: Self.scaledKey(displayID))
        detectCurrent()
        OSD.resolution(option.looksW, option.looksH)
    }

    func clearScaled() {
        ConfirmRevert.shared.dismiss()
        scaled.revert()
        scaledActive = nil
        UserDefaults.standard.set(0, forKey: Self.scaledKey(displayID))
        detectCurrent()
    }

    static func scaledKey(_ id: CGDirectDisplayID) -> String { "scaledW.\(id)" }

    func setRefresh(_ hz: Double) {
        if currentLooksW > 0 {
            if SkyLight.applyHiDPI(looksW: currentLooksW, hz: hz, to: displayID) { detectCurrent() }
        } else {
            applyNativeRefresh(hz)
        }
    }

    private func applyNativeRefresh(_ hz: Double) {
        guard let cur = CGDisplayCopyDisplayMode(displayID) else { return }
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, opts) as? [CGDisplayMode],
              let target = modes.filter({ $0.width == cur.width && $0.pixelWidth == $0.width })
                  .min(by: { abs($0.refreshRate - hz) < abs($1.refreshRate - hz) }) else { return }
        if SkyLight.setMode(target, on: displayID) { detectCurrent() }
    }

    func rotate(to degrees: Int) {
        guard Rotation.rotate(displayID, to: degrees) else { return }
        // Orientation change is async and reshapes the mode list; resettle shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }

    func startVirtual(looksW: Int, looksH: Int) {
        guard virtual.start(looksW: looksW, looksH: looksH) else { return }
        virtualActive = true
        let d = UserDefaults.standard
        d.set(true, forKey: "virtual.enabled")
        d.set(looksW, forKey: "virtual.w")
        d.set(looksH, forKey: "virtual.h")
    }

    func stopVirtual() {
        virtual.stop()
        virtualActive = false
        UserDefaults.standard.set(false, forKey: "virtual.enabled")
    }

    // Recreate the headless display on launch if it was left on (e.g. an always-on
    // box that rebooted). Called after launch so the run loop can register it.
    func restoreVirtualIfNeeded() {
        guard UserDefaults.standard.bool(forKey: "virtual.enabled"), !virtualActive else { return }
        let w = UserDefaults.standard.object(forKey: "virtual.w") as? Int ?? 2560
        let h = UserDefaults.standard.object(forKey: "virtual.h") as? Int ?? 1440
        startVirtual(looksW: w, looksH: h)
    }
}
