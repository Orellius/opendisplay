// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Entry point: a menubar agent (no dock icon). The status item offers a quick
// resolution pick and opens the SwiftUI control panel. Re-applies the saved
// choice when a display is connected or reconfigured.

import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let model = DisplayModel()
    private var panel: NSWindow?
    private var hotkeys: Hotkeys?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                           accessibilityDescription: "OpenDisplay")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let dropdown = MenuPanel(model: model,
                                 onOpenPanel: { [weak self] in
                                     self?.popover.performClose(nil)
                                     self?.openPanel()
                                 },
                                 onQuit: { NSApp.terminate(nil) })
        let host = NSHostingController(rootView: dropdown)
        // Without this the popover keeps whatever size the controller reported when it was
        // built, which is before the model has modes or scaled options, so the panel grows
        // past its own frame and the top section is clipped away.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = false
        hotkeys = Hotkeys(model: model)
        CGDisplayRegisterReconfigurationCallback(displayReconfig, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(openPanel), name: .openControlPanel, object: nil)
        model.restoreVirtualIfNeeded()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLScheme.handle(url, model: model) }
    }

    @objc private func didWake() {
        // The display takes a moment to settle after wake before it accepts a reapply.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.reapply() }
    }

    func applicationWillTerminate(_ note: Notification) {
        Brightness.restore()   // don't leave the panel dimmed after quit
        // The virtual display dies with this process. Unmirror first, or the panel is
        // left mirroring a display that no longer exists and the screen goes with it.
        model.clearScaled()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        model.refresh()   // favorites and the active mode go stale between openings
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // A transient popover from a status item does not take key focus on its own,
        // which leaves the brightness slider needing two clicks: one to focus, one to drag.
        popover.contentViewController?.view.window?.makeKey()
    }

    // Right-click keeps a real menu, for the few things that are faster as one line.
    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Control Panel", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        let native = NSMenuItem(title: "Native", action: #selector(quickNative), keyEquivalent: "")
        native.target = self
        native.state = model.currentLooksW == 0 && model.scaledActive == nil ? .on : .off
        menu.addItem(native)
        let reset = NSMenuItem(title: "Reset Display", action: #selector(quickResetAction), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenDisplay",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func quickResetAction() { model.quickReset() }

    @objc private func openPanel() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = ""   // full-size content draws under the titlebar; even hidden, a non-empty title bleeds through over the pane heading
            window.contentViewController = NSHostingController(rootView: ControlPanel(model: model))
            window.center()
            window.isReleasedWhenClosed = false
            panel = window
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func quickNative() {
        model.applyNative()
        OSD.text("rectangle.on.rectangle.angled", "Native")
    }

    @objc private func toggleLogin() {
        LoginItem.toggle()
    }

    func reconfigured() {
        model.refresh()
    }

    func modeChanged() {
        model.reassertIfProtected()
    }
}

private func displayReconfig(_ display: CGDirectDisplayID,
                             _ flags: CGDisplayChangeSummaryFlags,
                             _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
    if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
        DispatchQueue.main.async { delegate.reconfigured() }
    } else if flags.contains(.setModeFlag) {
        DispatchQueue.main.async { delegate.modeChanged() }
    }
}

// The project's single copyright/attribution notice and a launch-time guard. OpenDisplay
// is AGPL-3.0: forks must stay open and must preserve this attribution (AGPL section 7 /
// section 5(d) Appropriate Legal Notices). enforce() refuses to start if the notice has
// been stripped, so a copy that removes the credit will not run. The UI footer renders
// `author`, so the visible credit and the guarded constant are one source of truth. This
// is a deterrent coupled to the license, not protection against patching the binary.
enum Attribution {
    static let author = "Orellius (Orel Ohayon)"  // allow-personal: the protected license attribution
    static let line = "OpenDisplay © 2026 \(author) · AGPL-3.0"
    static let url = "https://github.com/Orellius/opendisplay"

    static func enforce() {
        guard line.contains("Orellius"), line.contains("AGPL"), line.contains("OpenDisplay") else {
            FileHandle.standardError.write(Data(
                "OpenDisplay: the copyright notice has been removed. This violates the AGPL-3.0 license; the app will not run. See \(url)\n".utf8))
            exit(70)
        }
    }
}

// Refuse to run a copy whose attribution has been stripped (before any other work).
Attribution.enforce()

// CLI subcommands apply and exit (or, for `virtual`, hold). No subcommand -> GUI.
_ = CLI.run(CommandLine.arguments)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
