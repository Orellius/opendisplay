// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius - https://github.com/Orellius/opendisplay
// The "Keep these display settings?" box, the same safety net Windows puts behind a
// resolution change: the new mode is provisional until the user accepts it, and a
// countdown puts the old one back on its own if nobody does. That covers the case the
// whole feature is dangerous for, which is a change that leaves the screen unreadable
// or black, where there is nothing left to click.
//
// Deliberately NOT an NSAlert. runModal() spins its own event loop and starves the
// scheduled Timer that does the reverting, so the dialog would sit there forever on a
// dead screen. This is an ordinary floating panel with a live timer behind it.
//
// Public surface: ConfirmRevert.shared.ask(...), .dismiss().
// NOT responsible for: performing the revert (the caller's onRevert closure does that,
// and ScaledResolution keeps its own longer backstop timer in case this never appears).

import Cocoa
import SwiftUI

final class CountdownState: ObservableObject {
    @Published var remaining = 0
    @Published var headline = ""
    @Published var detail = ""
}

final class ConfirmRevert {
    static let shared = ConfirmRevert()

    private var panel: NSPanel?
    private var ticker: Timer?
    private var onKeep: (() -> Void)?
    private var onRevert: (() -> Void)?
    private let state = CountdownState()

    private init() {}

    var isShowing: Bool { panel != nil }

    /// Put the box on screen and start counting. `onRevert` fires if the countdown runs
    /// out or the user declines; `onKeep` fires only on an explicit accept.
    func ask(headline: String,
             detail: String,
             seconds: Int,
             onKeep: @escaping () -> Void,
             onRevert: @escaping () -> Void) {
        dismiss()
        self.onKeep = onKeep
        self.onRevert = onRevert
        state.headline = headline
        state.detail = detail
        state.remaining = seconds

        let view = ConfirmRevertView(state: state,
                                     keep: { [weak self] in self?.finish(keep: true) },
                                     revert: { [weak self] in self?.finish(keep: false) })
        let host = NSHostingController(rootView: view)
        let win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 178),
                          styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                          backing: .buffered,
                          defer: false)
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.title = ""
        win.contentViewController = host
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        // Above normal windows and above a fullscreen app, on every Space. A resolution
        // change that goes wrong often happens while a game or a fullscreen editor owns
        // the screen, and a panel buried under that is the same as no panel at all.
        win.level = .modalPanel
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel = win
        recenter()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)

        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.state.remaining -= 1
            if self.state.remaining <= 0 { self.finish(keep: false) }
        }
    }

    func dismiss() {
        ticker?.invalidate()
        ticker = nil
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        panel?.orderOut(nil)
        panel = nil
        onKeep = nil
        onRevert = nil
    }

    private func finish(keep: Bool) {
        let keepAction = onKeep
        let revertAction = onRevert
        dismiss()
        if keep { keepAction?() } else { revertAction?() }
    }

    // The mode change resizes the screen out from under the panel, so put it back in the
    // middle of whatever the screen became.
    @objc private func screensChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.recenter() }
    }

    private func recenter() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = panel.frame
        let v = screen.visibleFrame
        let origin = NSPoint(x: v.midX - f.width / 2, y: v.midY - f.height / 2)
        panel.setFrameOrigin(origin)
    }
}

private struct ConfirmRevertView: View {
    @ObservedObject var state: CountdownState
    let keep: () -> Void
    let revert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.headline).font(.headline)
            Text(state.detail)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("Reverting in \(state.remaining)s")
                    .monospacedDigit()
            }
            .font(.callout)
            .foregroundStyle(.orange)
            Spacer(minLength: 0)
            HStack {
                // Escape reverts, which is the safe direction for a key pressed blind.
                Button("Revert Now", action: revert)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Keep", action: keep)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360, height: 178, alignment: .topLeading)
    }
}
