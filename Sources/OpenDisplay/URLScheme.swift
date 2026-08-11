// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Handles the opendisplay:// URL scheme so the display can be driven from links,
// Shortcuts' "Open URL", Raycast, Alfred, etc. - the GUI counterpart to the CLI. The
// form is opendisplay://<action>[/<value>], e.g. opendisplay://brightness/50. Routes
// through the DisplayModel (not the CLI paths) so the panel and OSD reflect the change.
// Registered via CFBundleURLTypes in bundle.sh and dispatched from application(_:open:).
// NOT responsible for: scheme registration (LaunchServices owns that) or the dev binary
// (URL handling needs the .app bundle, like App Intents).

import Foundation

extension Notification.Name {
    /// Posted for opendisplay://panel. The window belongs to the AppDelegate, not the
    /// model, so this crosses the gap without handing the model a view reference.
    static let openControlPanel = Notification.Name("com.orellius.opendisplay.openControlPanel")
}

enum URLScheme {
    static func handle(_ url: URL, model: DisplayModel) {
        guard url.scheme == "opendisplay" else { return }
        let action = (url.host ?? "").lowercased()
        let raw = url.pathComponents.first { $0 != "/" }
        let int = raw.flatMap(Int.init)
        let pct = raw.flatMap(Double.init).map { min(100, max(0, $0)) }

        switch action {
        case "brightness": if let v = pct { model.setBrightness(v); OSD.brightness(model.brightness) }
        case "warmth": if let v = pct { model.setWarmth(v); OSD.warmth(model.warmth) }
        case "contrast": if let v = pct { model.setContrast(v); OSD.text("circle.lefthalf.filled", "\(Int(v))%") }
        case "res": if let v = int {
            model.apply(looksW: v)
            if let m = model.modes.first(where: { $0.looksW == v }) { OSD.resolution(m.looksW, m.looksH) }
        }
        case "native": model.applyNative(); OSD.text("rectangle.on.rectangle.angled", "Native")
        // The scaled path deliberately has no fallback: an unlisted width means the panel
        // cannot render it within the virtual display's limits, and guessing a near one
        // would change the topology to something the caller never asked for.
        case "scaled":
            if raw?.lowercased() == "off" {
                model.clearScaled()
                OSD.text("rectangle.on.rectangle.angled", "Scaling off")
            } else if let v = int,
                      let opt = model.scaledOptions.first(where: { $0.looksW == v }) {
                model.applyScaled(opt)
            }
        case "rotate": if let v = int { model.rotate(to: v) }
        case "panel": NotificationCenter.default.post(name: .openControlPanel, object: nil)
        case "reset": model.quickReset()
        case "blackout": model.toggleBlackout()
        default: break
        }
    }
}
