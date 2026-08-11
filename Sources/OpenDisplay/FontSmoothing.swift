// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius - https://github.com/Orellius/opendisplay
// Text rendering weight on a 1x panel. macOS dropped subpixel antialiasing in 10.14,
// so on a non-Retina external display every glyph is grayscale-antialiased and then
// dilated (stem darkening) to imitate the old LCD rendering. On a 108 PPI panel that
// dilation is what reads as "soft": the stems bleed into the pixels either side.
// AppleFontSmoothing is the per-host default that controls the dilation amount.
// 0 turns it off, which is the sharpest text a 1x display can produce.
// The key lives in the -currentHost global domain, so it is per Mac, not per app.
// Takes effect for an app on its next launch; the WindowServer needs a logout.
// Public surface: FontSmoothing.current, .set(_:), .clear(), .label(_:)
// NOT responsible for: per-app overrides (an app domain can still override the global).

import Foundation

enum FontSmoothing {
    private static let key = "AppleFontSmoothing" as CFString
    private static let app = kCFPreferencesAnyApplication

    /// nil means the key is unset and macOS uses its own default.
    static var current: Int? {
        guard let v = CFPreferencesCopyValue(key, app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) else { return nil }
        return (v as? NSNumber)?.intValue
    }

    @discardableResult
    static func set(_ level: Int) -> Bool {
        CFPreferencesSetValue(key, NSNumber(value: level), app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// Remove the override and go back to whatever macOS picks for this display.
    @discardableResult
    static func clear() -> Bool {
        CFPreferencesSetValue(key, nil, app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesSynchronize(app, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    static func label(_ level: Int?) -> String {
        switch level {
        case nil: return "unset (macOS default)"
        case 0?:  return "0 (no dilation, sharpest on 1x)"
        case 1?:  return "1 (light)"
        case 2?:  return "2 (medium)"
        case 3?:  return "3 (strong)"
        default:  return "\(level!) (outside the documented 0...3 range)"
        }
    }
}
