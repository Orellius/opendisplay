// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius - https://github.com/Orellius/opendisplay
// The display's ICC profile: read what macOS assigned, and replace it.
// macOS synthesises a profile for every external panel out of its EDID. That profile
// carries the panel's chromaticity, but its tone curve is a 1024-point table built from
// the single EDID gamma byte. Apple's own display profiles instead carry a parametric
// curve, which is what "matches Apple" means in practice: same primaries, same D65
// white, a clean analytic 2.2 response instead of a quantised table.
// `generate` writes exactly that profile out of the panel's measured primaries, and
// `assign` installs it as the ColorSync custom profile for this display.
// Public surface: ColorProfile.describe(_:), .generate(for:gamma:), .assign(_:to:), .reset(_:)
// NOT responsible for: measuring the panel (no colorimeter here, so the primaries are
// the ones the panel reports, not ones this tool verified).

import ColorSync
import CoreGraphics
import Foundation

enum ColorProfile {
    struct Summary {
        var name: String?
        var url: URL?
        var isCustom = false
        var white: (x: Double, y: Double)?
        var red: (x: Double, y: Double)?
        var green: (x: Double, y: Double)?
        var blue: (x: Double, y: Double)?
        var trc: String?
    }

    private static var installDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/ColorSync/Profiles", isDirectory: true)
    }

    // MARK: read

    /// Read the profile the window server is actually rendering through.
    /// This goes through CGDisplayCopyColorSpace rather than the ColorSync device
    /// registry: ColorSyncDeviceCopyDeviceInfo answers intermittently on macOS 26
    /// (measured returning nil on a display it had described minutes earlier), and
    /// the color space is the authoritative answer anyway.
    static func describe(_ id: CGDirectDisplayID) -> Summary {
        var s = Summary()
        s.url = deviceProfileURL(id, isCustom: &s.isCustom)
        guard let space = CGDisplayCopyColorSpace(id) as CGColorSpace?,
              let icc = space.copyICCData() as Data?,
              let prof = ColorSyncProfileCreate(icc as CFData, nil)?.takeRetainedValue() else { return s }
        s.name = ColorSyncProfileCopyDescriptionString(prof)?.takeRetainedValue() as String?
        s.white = xy(prof, "wtpt")
        s.red = xy(prof, "rXYZ")
        s.green = xy(prof, "gXYZ")
        s.blue = xy(prof, "bXYZ")
        s.trc = trcKind(prof)
        return s
    }

    /// Best effort only. The file path is a convenience; every reported number above
    /// comes from the live color space, so a nil here costs nothing.
    private static func deviceProfileURL(_ id: CGDirectDisplayID, isCustom: inout Bool) -> URL? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let infoRef = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid)
        else { return nil }
        let info = infoRef.takeRetainedValue() as NSDictionary
        if let custom = info[kColorSyncCustomProfiles.takeUnretainedValue() as String] as? NSDictionary,
           let url = custom.allValues.compactMap({ $0 as? URL }).first {
            isCustom = true
            return url
        }
        guard let factory = info[kColorSyncFactoryProfiles.takeUnretainedValue() as String] as? NSDictionary else { return nil }
        for v in factory.allValues {
            guard let d = v as? NSDictionary,
                  let url = d[kColorSyncDeviceProfileURL.takeUnretainedValue() as String] as? URL else { continue }
            return url
        }
        return nil
    }

    private static func xy(_ prof: ColorSyncProfile, _ tag: String) -> (x: Double, y: Double)? {
        guard let d = ColorSyncProfileCopyTag(prof, tag as CFString)?.takeRetainedValue() as Data?, d.count >= 20 else { return nil }
        let v = (0 ..< 3).map { i -> Double in
            let o = 8 + i * 4
            let raw = d.subdata(in: o ..< (o + 4)).withUnsafeBytes { Int32(bigEndian: $0.load(as: Int32.self)) }
            return Double(raw) / 65536.0
        }
        let sum = v[0] + v[1] + v[2]
        guard sum != 0 else { return nil }
        return (v[0] / sum, v[1] / sum)
    }

    private static func trcKind(_ prof: ColorSyncProfile) -> String? {
        guard let d = ColorSyncProfileCopyTag(prof, "rTRC" as CFString)?.takeRetainedValue() as Data?, d.count >= 12 else { return nil }
        let type = String(decoding: d.prefix(4), as: UTF8.self)
        if type == "para" { return "parametric (Apple's shape)" }
        guard type == "curv" else { return type }
        let n = d.subdata(in: 8 ..< 12).withUnsafeBytes { Int(UInt32(bigEndian: $0.load(as: UInt32.self))) }
        if n == 0 { return "curv linear" }
        if n == 1, d.count >= 14 {
            let g = d.subdata(in: 12 ..< 14).withUnsafeBytes { UInt16(bigEndian: $0.load(as: UInt16.self)) }
            return String(format: "curv gamma %.2f", Double(g) / 256.0)
        }
        return "curv table, \(n) points"
    }

    // MARK: write

    /// Build a profile with the panel's own primaries, a D65 white, and one analytic
    /// gamma on all three channels. Returns the file it wrote.
    static func generate(for id: CGDirectDisplayID, gamma: Double) throws -> URL {
        let s = describe(id)
        guard let r = s.red, let g = s.green, let b = s.blue else {
            throw Err.msg("the current profile has no primaries to copy; nothing to base a profile on")
        }
        let w = s.white ?? (0.3127, 0.3290)   // D65
        // xyY to XYZ at Y=1 for the white, then solve the per-primary scale factors so the
        // three primaries sum to exactly that white. This is the standard RGB to XYZ build.
        let white = xyz(w.x, w.y)
        let mr = xyz(r.x, r.y), mg = xyz(g.x, g.y), mb = xyz(b.x, b.y)
        guard let scale = solve3(mr, mg, mb, white) else {
            throw Err.msg("the primaries are degenerate and cannot be inverted")
        }
        let matrix: [CGFloat] = [
            CGFloat(mr.0 * scale.0), CGFloat(mr.1 * scale.0), CGFloat(mr.2 * scale.0),
            CGFloat(mg.0 * scale.1), CGFloat(mg.1 * scale.1), CGFloat(mg.2 * scale.1),
            CGFloat(mb.0 * scale.2), CGFloat(mb.1 * scale.2), CGFloat(mb.2 * scale.2),
        ]
        let wp: [CGFloat] = [CGFloat(white.0), CGFloat(white.1), CGFloat(white.2)]
        let bp: [CGFloat] = [0, 0, 0]
        let gammas: [CGFloat] = [CGFloat(gamma), CGFloat(gamma), CGFloat(gamma)]
        guard let space = CGColorSpace(calibratedRGBWhitePoint: wp, blackPoint: bp, gamma: gammas, matrix: matrix),
              let icc = space.copyICCData() as Data?
        else { throw Err.msg("CoreGraphics refused to build a profile from those primaries") }

        let info = DisplayInfo.gather(id)
        let safe = info.name.replacingOccurrences(of: "/", with: "-")
        let name = String(format: "%@ gamma %.1f (OpenDisplay).icc", safe, gamma)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        let url = installDir.appendingPathComponent(name)
        try icc.write(to: url)
        return url
    }

    /// Install a profile as this display's ColorSync custom profile.
    static func assign(_ url: URL, to id: CGDirectDisplayID) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Err.msg("no profile at \(url.path)") }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { throw Err.msg("no ColorSync UUID for this display") }
        let dict = [kColorSyncDeviceDefaultProfileID.takeUnretainedValue(): url] as CFDictionary
        guard ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid, dict) else {
            throw Err.msg("ColorSync rejected the profile")
        }
    }

    /// Drop back to the profile macOS synthesised from the EDID.
    static func reset(_ id: CGDirectDisplayID) throws {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { throw Err.msg("no ColorSync UUID for this display") }
        guard ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), uuid, nil) else {
            throw Err.msg("ColorSync refused to clear the custom profile")
        }
    }

    // MARK: math

    private static func xyz(_ x: Double, _ y: Double) -> (Double, Double, Double) {
        guard y != 0 else { return (0, 0, 0) }
        return (x / y, 1.0, (1.0 - x - y) / y)
    }

    /// Solve [r g b] * s = white for the three primary scale factors by Cramer's rule.
    private static func solve3(_ r: (Double, Double, Double), _ g: (Double, Double, Double), _ b: (Double, Double, Double),
                               _ w: (Double, Double, Double)) -> (Double, Double, Double)? {
        func det(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ c: (Double, Double, Double)) -> Double {
            a.0 * (b.1 * c.2 - b.2 * c.1) - a.1 * (b.0 * c.2 - b.2 * c.0) + a.2 * (b.0 * c.1 - b.1 * c.0)
        }
        let d = det(r, g, b)
        guard abs(d) > 1e-9 else { return nil }
        return (det(w, g, b) / d, det(r, w, b) / d, det(r, g, w) / d)
    }

    enum Err: Error { case msg(String) }
}
