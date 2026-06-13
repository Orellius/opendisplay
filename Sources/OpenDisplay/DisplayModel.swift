// Observable state for one display: its available HiDPI modes, the active choice,
// and persistence. Restores the saved choice on launch and on display reconnect.

import Cocoa
import Combine

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

    var hardwareAvailable: Bool { Brightness.hardwareAvailable }

    let displayID: CGDirectDisplayID
    let canRotate: Bool
    private let nativeMode: CGDisplayMode?

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
        applyTone()
    }

    private static func key(_ id: CGDirectDisplayID) -> String { "looksW.\(id)" }
    private static func brightKey(_ id: CGDirectDisplayID) -> String { "brightness.\(id)" }
    private static func warmthKey(_ id: CGDirectDisplayID) -> String { "warmth.\(id)" }
    private static func favKey(_ id: CGDirectDisplayID) -> String { "favorites.\(id)" }

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

    func nudgeBrightness(_ delta: Double) { setBrightness(min(100, max(0, brightness + delta))) }
    func nudgeWarmth(_ delta: Double) { setWarmth(min(100, max(0, warmth + delta))) }

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
        refreshRates = currentLooksW > 0 ? SkyLight.refreshRates(for: displayID, looksW: currentLooksW) : []
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
        guard currentLooksW > 0 else { return }
        if SkyLight.applyHiDPI(looksW: currentLooksW, hz: hz, to: displayID) { detectCurrent() }
    }

    func rotate(to degrees: Int) {
        guard Rotation.rotate(displayID, to: degrees) else { return }
        // Orientation change is async and reshapes the mode list; resettle shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refresh() }
    }
}
