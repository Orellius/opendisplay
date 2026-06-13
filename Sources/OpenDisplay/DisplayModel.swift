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
    @Published var hardwareDDC: Bool = false             // also drive DDC when set
    @Published private(set) var favorites: Set<Int> = [] // starred looks-like widths
    @Published private(set) var virtualActive = false    // headless virtual display on
    @Published private(set) var presets: [TonePreset?] = [nil, nil, nil]

    var hardwareAvailable: Bool { Brightness.hardwareAvailable }

    let displayID: CGDirectDisplayID
    let canRotate: Bool
    private let nativeMode: CGDisplayMode?
    private let virtual = VirtualDisplay()
    private(set) var schedule: NightSchedule!
    let idle = IdleDimmer()

    init(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        self.displayID = displayID
        self.nativeMode = CGDisplayCopyDisplayMode(displayID)
        self.canRotate = Rotation.canRotate(displayID)
        refresh()
        let saved = UserDefaults.standard.integer(forKey: Self.key(displayID))
        if saved > 0 { apply(looksW: saved) }

        brightness = (UserDefaults.standard.object(forKey: Self.brightKey(displayID)) as? Double) ?? 100
        warmth = (UserDefaults.standard.object(forKey: Self.warmthKey(displayID)) as? Double) ?? 0
        favorites = Set((UserDefaults.standard.array(forKey: Self.favKey(displayID)) as? [Int]) ?? [])
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
                Brightness.apply(brightness: b / 100, warmth: w / 100, on: self.displayID)
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
    private static func favKey(_ id: CGDirectDisplayID) -> String { "favorites.\(id)" }

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

    func isFavorite(_ looksW: Int) -> Bool { favorites.contains(looksW) }

    func toggleFavorite(_ looksW: Int) {
        if favorites.contains(looksW) { favorites.remove(looksW) } else { favorites.insert(looksW) }
        UserDefaults.standard.set(Array(favorites), forKey: Self.favKey(displayID))
    }

    private func applyTone() {
        Brightness.apply(brightness: brightness / 100.0, warmth: warmth / 100.0, on: displayID)
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
        applyNative()
        setBrightness(100)
        setWarmth(0)
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
        modes = SkyLight.hidpiModes(for: displayID)
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
        if virtual.start(looksW: looksW, looksH: looksH) { virtualActive = true }
    }

    func stopVirtual() {
        virtual.stop()
        virtualActive = false
    }
}
