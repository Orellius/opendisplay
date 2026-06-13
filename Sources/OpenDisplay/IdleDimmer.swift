// Idle dimming for the external panel - BetterDisplay #3966 / #2161. macOS dims the
// built-in display before lock but leaves third-party externals at full brightness;
// this dims after a configurable idle and restores on the next input. It uses a
// translucent black overlay rather than the gamma path, so it composes with manual
// brightness, warmth, and the night schedule instead of fighting them, and can go
// darker than the gamma floor. A 1-second poll of the combined input-idle time drives
// it; mouse or keyboard activity undims within that second.
// Public surface: enabled + minutes + level (persisted), self-driving.

import AppKit

final class IdleDimmer: ObservableObject {
    @Published var enabled: Bool { didSet { persist(); reschedule() } }
    @Published var minutes: Int { didSet { persist() } }
    @Published var level: Double { didSet { persist() } }

    private let anyInput = CGEventType(rawValue: ~0)!
    private var timer: Timer?
    private var overlay: NSWindow?
    private var dimmed = false
    private var ready = false

    init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "idle.enabled")
        minutes = d.object(forKey: "idle.minutes") as? Int ?? 3
        level = d.object(forKey: "idle.level") as? Double ?? 0.7
        ready = true
        reschedule()
    }

    deinit { timer?.invalidate() }

    private func persist() {
        guard ready else { return }
        let d = UserDefaults.standard
        d.set(enabled, forKey: "idle.enabled")
        d.set(minutes, forKey: "idle.minutes")
        d.set(level, forKey: "idle.level")
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard enabled else { undim(); return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle >= Double(minutes * 60) { dim() } else { undim() }
    }

    private func dim() {
        guard !dimmed else { return }
        dimmed = true
        let w = overlay ?? makeOverlay()
        if !w.isVisible { w.alphaValue = 0 }
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.8
            w.animator().alphaValue = CGFloat(level)
        }
    }

    private func undim() {
        guard dimmed, let w = overlay else { dimmed = false; return }
        dimmed = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            w.animator().alphaValue = 0
        }, completionHandler: { w.orderOut(nil) })
    }

    private func makeOverlay() -> NSWindow {
        let frame = NSScreen.main?.frame ?? .zero
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .black
        w.alphaValue = 0
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.hasShadow = false
        overlay = w
        return w
    }
}
