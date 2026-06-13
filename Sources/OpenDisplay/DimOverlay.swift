// A reusable translucent black overlay window for darkening the screen below what the
// gamma transfer alone can reach (its floor is 25% luminance). Both the idle dimmer
// and the brightness control's deep-dim range drive their own instance of this. The
// window is borderless, click-through, and floats above everything at the screen-saver
// level; setAlpha animates it and hides it at zero. Re-reads the main screen frame on
// each show so it still covers the screen after a resolution change.
// NOT responsible for: deciding WHEN to dim (callers own that) or gamma.

import AppKit

final class DimOverlay {
    private var window: NSWindow?

    /// 0 hides the overlay; >0 shows a black overlay at that alpha. duration is the
    /// fade time, so callers can fade slowly (idle) or track a slider (deep-dim).
    func setAlpha(_ alpha: Double, duration: Double = 0.2) {
        let a = max(0, min(1, alpha))
        if a <= 0.001 { hide(duration: duration); return }
        let w = window ?? makeWindow()
        w.setFrame(NSScreen.main?.frame ?? w.frame, display: false)
        if !w.isVisible { w.alphaValue = 0; w.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            w.animator().alphaValue = CGFloat(a)
        }
    }

    func hide(duration: Double = 0.3) {
        guard let w = window, w.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            w.animator().alphaValue = 0
        }, completionHandler: { w.orderOut(nil) })
    }

    private func makeWindow() -> NSWindow {
        let frame = NSScreen.main?.frame ?? .zero
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .black
        w.alphaValue = 0
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.hasShadow = false
        window = w
        return w
    }
}
