// A glass on-screen display, shown when brightness/warmth/resolution change from a
// hotkey or the menu bar - the cases where the panel is closed and there is otherwise
// no feedback. A borderless click-through window floats above everything at bottom
// center, fades in, and auto-dismisses. In-panel slider drags do NOT trigger it (the
// panel already shows the value), so OSD is wired only to the panel-closed entry points.
// Public surface: OSD.brightness/warmth/resolution/text. No-ops without a running app.

import AppKit
import SwiftUI

final class OSDState: ObservableObject {
    @Published var icon = "sun.max.fill"
    @Published var label = ""
    @Published var fraction: Double?
}

final class OSD {
    static let shared = OSD()
    private let state = OSDState()
    private var window: NSWindow?
    private var hide: DispatchWorkItem?

    private init() {}

    func show(icon: String, label: String, fraction: Double?) {
        guard NSApp != nil else { return }
        state.icon = icon
        state.label = label
        state.fraction = fraction
        let win = window ?? makeWindow()
        position(win)
        if !win.isVisible { win.alphaValue = 0 }
        win.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            win.animator().alphaValue = 1
        }
        scheduleHide(win)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 180),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.level = .screenSaver
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.hasShadow = false
        w.contentView = NSHostingView(rootView: OSDView(state: state))
        window = w
        return w
    }

    private func position(_ w: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        w.setFrame(NSRect(x: f.midX - 90, y: f.minY + 120, width: 180, height: 180), display: false)
    }

    private func scheduleHide(_ w: NSWindow) {
        hide?.cancel()
        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                w.animator().alphaValue = 0
            }, completionHandler: { w.orderOut(nil) })
        }
        hide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: work)
    }
}

extension OSD {
    static func brightness(_ pct: Double) {
        shared.show(icon: "sun.max.fill", label: "\(Int(pct.rounded()))%", fraction: pct / 100)
    }
    static func warmth(_ pct: Double) {
        shared.show(icon: "thermometer.sun.fill", label: "\(Int(pct.rounded()))%", fraction: pct / 100)
    }
    static func resolution(_ w: Int, _ h: Int) {
        shared.show(icon: "rectangle.on.rectangle.angled", label: "\(w) × \(h)", fraction: nil)
    }
    static func text(_ icon: String, _ label: String) {
        shared.show(icon: icon, label: label, fraction: nil)
    }
}

private struct OSDView: View {
    @ObservedObject var state: OSDState
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: state.icon)
                .font(.system(size: 40, weight: .regular))
                .symbolRenderingMode(.hierarchical)
            if let f = state.fraction {
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.16)).frame(width: 120, height: 6)
                    Capsule().fill(.primary).frame(width: max(0, min(120, 120 * f)), height: 6)
                }
            }
            Text(state.label)
                .font(.system(.title3, design: .rounded)).fontWeight(.medium)
                .monospacedDigit()
        }
        .frame(width: 180, height: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}
