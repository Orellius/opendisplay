// Observable state for one display: its available HiDPI modes, the active choice,
// and persistence. Restores the saved choice on launch and on display reconnect.

import Cocoa
import Combine

final class DisplayModel: ObservableObject {
    @Published private(set) var modes: [DisplayMode] = []
    @Published private(set) var currentLooksW: Int = 0   // 0 means native

    let displayID: CGDirectDisplayID
    private let nativeMode: CGDisplayMode?

    init(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        self.displayID = displayID
        self.nativeMode = CGDisplayCopyDisplayMode(displayID)
        refresh()
        let saved = UserDefaults.standard.integer(forKey: Self.key(displayID))
        if saved > 0 { apply(looksW: saved) }
    }

    private static func key(_ id: CGDirectDisplayID) -> String { "looksW.\(id)" }

    func refresh() {
        modes = SkyLight.hidpiModes(for: displayID)
        detectCurrent()
    }

    private func detectCurrent() {
        guard let cur = CGDisplayCopyDisplayMode(displayID) else { currentLooksW = 0; return }
        currentLooksW = cur.pixelWidth > cur.width ? cur.width : 0
    }

    func apply(looksW: Int) {
        guard SkyLight.applyHiDPI(looksW: looksW, to: displayID) else { return }
        currentLooksW = looksW
        UserDefaults.standard.set(looksW, forKey: Self.key(displayID))
    }

    func applyNative() {
        guard let nativeMode, SkyLight.setMode(nativeMode, on: displayID) else { return }
        currentLooksW = 0
        UserDefaults.standard.set(0, forKey: Self.key(displayID))
    }
}
