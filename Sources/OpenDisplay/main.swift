// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Entry point: a menubar agent (no dock icon). The status item offers a quick
// resolution pick and opens the SwiftUI control panel. Re-applies the saved
// choice when a display is connected or reconfigured.

import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let model = DisplayModel()
    private var panel: NSWindow?
    private var hotkeys: Hotkeys?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                           accessibilityDescription: "OpenDisplay")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        hotkeys = Hotkeys(model: model)
        CGDisplayRegisterReconfigurationCallback(displayReconfig, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
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
    }

    // Rebuilt each time the menu opens so favorites and the active mode stay current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(disabledItem(model.effectiveName))
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open OpenDisplay…", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if !SkyLight.available {
            menu.addItem(disabledItem("HiDPI unavailable on this macOS"))
        } else if model.modes.isEmpty {
            menu.addItem(disabledItem("No HiDPI scaling on this display"))
        } else {
            let favorites = model.modes.filter { model.isFavorite($0.looksW) }
            let quick = favorites.isEmpty ? Array(model.modes.prefix(6)) : favorites
            for mode in quick { menu.addItem(resItem(mode, starred: !favorites.isEmpty)) }

            if model.modes.count > quick.count {
                let all = NSMenuItem(title: "All Resolutions", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for mode in model.modes { sub.addItem(resItem(mode, starred: false)) }
                all.submenu = sub
                menu.addItem(all)
            }
        }

        menu.addItem(.separator())
        let native = NSMenuItem(title: "Native", action: #selector(quickNative), keyEquivalent: "")
        native.target = self
        native.state = model.currentLooksW == 0 ? .on : .off
        menu.addItem(native)
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OpenDisplay",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func resItem(_ mode: DisplayMode, starred: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "\(mode.looksW) × \(mode.looksH)  HiDPI",
                              action: #selector(quickPick(_:)), keyEquivalent: "")
        if starred { item.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil) }
        item.representedObject = mode.looksW
        item.state = model.currentLooksW == mode.looksW ? .on : .off
        item.target = self
        return item
    }

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

    @objc private func quickPick(_ sender: NSMenuItem) {
        guard let looksW = sender.representedObject as? Int else { return }
        model.apply(looksW: looksW)
        if let mode = model.modes.first(where: { $0.looksW == looksW }) {
            OSD.resolution(mode.looksW, mode.looksH)
        }
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
