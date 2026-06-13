// Entry point: a menubar agent (no dock icon). The status item offers a quick
// resolution pick and opens the SwiftUI control panel. Re-applies the saved
// choice when a display is connected or reconfigured.

import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let model = DisplayModel()
    private var panel: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack",
                                           accessibilityDescription: "OpenDisplay")
        buildMenu()
        CGDisplayRegisterReconfigurationCallback(displayReconfig, Unmanaged.passUnretained(self).toOpaque())
    }

    func buildMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open OpenDisplay…", action: #selector(openPanel), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        for mode in model.modes.prefix(6) {
            let item = NSMenuItem(title: "\(mode.looksW) × \(mode.looksH)  HiDPI",
                                  action: #selector(quickPick(_:)), keyEquivalent: "")
            item.representedObject = mode.looksW
            item.state = model.currentLooksW == mode.looksW ? .on : .off
            item.target = self
            menu.addItem(item)
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
        statusItem.menu = menu
    }

    @objc private func openPanel() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "OpenDisplay"
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
        buildMenu()
    }

    @objc private func quickNative() {
        model.applyNative()
        buildMenu()
    }

    @objc private func toggleLogin() {
        LoginItem.toggle()
        buildMenu()
    }

    func reconfigured() {
        model.refresh()
        buildMenu()
    }
}

private func displayReconfig(_ display: CGDirectDisplayID,
                             _ flags: CGDisplayChangeSummaryFlags,
                             _ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let delegate = Unmanaged<AppDelegate>.fromOpaque(ctx).takeUnretainedValue()
    if flags.contains(.addFlag) || flags.contains(.removeFlag) || flags.contains(.enabledFlag) {
        DispatchQueue.main.async { delegate.reconfigured() }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
