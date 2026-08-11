// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Scriptable control surface: `opendisplay <command>`. Stateless commands apply and
// exit; `virtual` holds the process so a headless box (over SSH/Tailscale) can run it
// as a daemon. Shares the GUI's UserDefaults keys so a CLI change and the panel agree.
// This is the dev-audience hook BetterDisplay buries, and it doubles as the Shortcuts
// path (wrap a command in a Run Shell Script action).
// Public surface: CLI.run(_:) -> Bool (true never returns — it exits; false = launch GUI).
// NOT responsible for: daemonizing (launchd/SSH own that); persisting rotation (macOS does).

import AppKit   // NSWorkspace, to hand `scaled` to the running agent over the URL scheme
import CoreGraphics
import Foundation

enum CLI {
    static func run(_ args: [String]) -> Bool {
        guard args.count >= 2 else { return false }
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffer so `virtual` confirms before it blocks
        // Never CGMainDisplayID(): while a scaled mode is on, that is this app's own
        // virtual display and every command would describe or drive the wrong screen.
        let id = PhysicalDisplay.main()
        switch args[1] {
        case "list": listModes(id)
        case "modes": listAllModes(id)
        case "info": print(DisplayInfo.gather(id).report)
        case "res": setRes(id, args)
        case "scaled": setScaled(id, args)
        case "native": setNative(id)
        case "brightness": setBrightness(id, args)
        case "warmth": setWarmth(id, args)
        case "contrast": setContrast(id, args)
        case "refresh": setRefresh(id, args)
        case "rotate": setRotate(id, args)
        case "caps": printCaps()
        case "vcp": rawVCP(args)
        case "smoothing": smoothing(args)
        case "color": color(id, args)
        case "virtual": holdVirtual(args)   // never returns
        case "help", "-h", "--help": printHelp()
        default: return false
        }
        // Every command above that persists a value writes through UserDefaults, and
        // exit(0) tears the process down before CFPreferences flushes to cfprefsd. Without
        // this the write is silently lost: `res` and `native` appear to work on screen and
        // then the old value comes back on the next launch. Measured 2026-08-11.
        UserDefaults.standard.synchronize()
        exit(0)
    }

    private static func die(_ msg: String) -> Never {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        exit(1)
    }

    private static func listModes(_ id: CGDirectDisplayID) {
        // A separate process has no memory of the pre-mirror list, so the honest move is
        // to label what is being printed rather than pass the mirror's framebuffer off as
        // the panel's own modes. The GUI keeps the real list instead (DisplayModel).
        let masked = PhysicalDisplay.isMirrorSlave(id)
        if masked {
            print("note: a scaled mode is active, so these are the mirrored framebuffer's")
            print("      modes, not the panel's. Run `opendisplay scaled off` for its own.")
        }
        let modes = SkyLight.hidpiModes(for: id)
        guard !modes.isEmpty else { print("no hidden HiDPI modes on this display"); return }
        let cur = CGDisplayCopyDisplayMode(id)
        let curW = (cur.map { $0.pixelWidth > $0.width } ?? false) ? cur!.width : 0
        for m in modes {
            let mark = m.looksW == curW ? "*" : " "
            print("\(mark) \(m.looksW)x\(m.looksH)  (renders \(m.pxW)x\(m.pxH) @ \(Int(m.hz))Hz)")
        }
    }

    private static func setRes(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let w = Int(args[2]) else { die("usage: opendisplay res <looks-like-width>") }
        if SkyLight.applyHiDPI(looksW: w, to: id) {
            UserDefaults.standard.set(w, forKey: DisplayModel.key(id))
            print("HiDPI \(w)")
            return
        }
        // Most panels expose exactly one HiDPI mode, or none. Falling back to the 1x mode
        // at the same width means `res 1920` does the obvious thing instead of refusing,
        // at the cost of the panel scaling it: a width that is not the native one is
        // resampled by the display, so text is softer than either native or a HiDPI mode.
        guard let mode = oneToOneMode(id, width: w) else {
            die("no mode at width \(w), HiDPI or 1x; see `opendisplay list` and `opendisplay modes`")
        }
        guard SkyLight.setMode(mode, on: id) else { die("the display refused the \(w) mode") }
        UserDefaults.standard.set(0, forKey: DisplayModel.key(id))
        print("1x \(mode.width)x\(mode.height) (the panel resamples this to its native grid)")
    }

    // Unlike every other command here, this one cannot do the work itself. A
    // CGVirtualDisplay is destroyed the moment the process holding it exits, so a
    // short-lived CLI that built one would leave the panel mirroring a display that no
    // longer exists. Hand it to the running menubar agent over the URL scheme instead;
    // LaunchServices starts the agent if it is not up yet.
    private static func setScaled(_ id: CGDirectDisplayID, _ args: [String]) {
        let arg = args.count >= 3 ? args[2].lowercased() : "list"
        if arg == "list" { listScaled(id); return }
        guard arg == "off" || Int(arg) != nil else {
            die("usage: opendisplay scaled <looks-like-width> | off | list")
        }
        if arg != "off", let w = Int(arg), !scaledOptions(id).contains(where: { $0.looksW == w }) {
            die("no scaled size at width \(w); see `opendisplay scaled list`")
        }
        guard let url = URL(string: "opendisplay://scaled/\(arg)") else { die("bad url") }
        guard NSWorkspace.shared.open(url) else {
            die("could not reach the OpenDisplay agent; is the .app installed?")
        }
        print(arg == "off" ? "scaling off" : "scaled \(arg) (confirm in the panel within \(ScaledResolution.confirmWindow)s)")
    }

    private static func scaledOptions(_ id: CGDirectDisplayID) -> [ScaledOption] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        let native = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode])?
            .filter { $0.pixelWidth == $0.width }.max { $0.pixelWidth < $1.pixelWidth }
        return ScaledResolution.options(nativeW: native?.width ?? 0, nativeH: native?.height ?? 0)
    }

    private static func listScaled(_ id: CGDirectDisplayID) {
        let options = scaledOptions(id)
        guard !options.isEmpty else { print("no scaled sizes available on this display"); return }
        for o in options {
            print("  \(o.looksW)x\(o.looksH)  (\(o.percent)% of native, renders \(o.pxW)x\(o.pxH))")
        }
    }

    private static func oneToOneMode(_ id: CGDirectDisplayID, width: Int) -> CGDisplayMode? {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { return nil }
        return modes.filter { $0.width == width && $0.pixelWidth == $0.width }
            .max { $0.refreshRate < $1.refreshRate }
    }

    private static func listAllModes(_ id: CGDirectDisplayID) {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { print("no modes"); return }
        let cur = CGDisplayCopyDisplayMode(id)
        var seen = Set<String>()
        var rows: [(Int, Int, Int, Int, Double, Bool, Bool)] = []
        for m in modes {
            let key = "\(m.width)x\(m.height)@\(m.pixelWidth)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let hz = modes.filter { $0.width == m.width && $0.pixelWidth == m.pixelWidth }.map(\.refreshRate).max() ?? 0
            let isCur = cur.map { $0.width == m.width && $0.pixelWidth == m.pixelWidth } ?? false
            rows.append((m.width, m.height, m.pixelWidth, m.pixelHeight, hz, m.pixelWidth > m.width, isCur))
        }
        rows.sort { $0.0 == $1.0 ? $0.2 > $1.2 : $0.0 > $1.0 }
        print("  looks-like     renders         scale  maxHz")
        for r in rows {
            print(String(format: "%@ %5d x %-5d  %5d x %-5d  %@   %.0f",
                         r.6 ? "*" : " ", r.0, r.1, r.2, r.3, r.5 ? "2x" : "1x", r.4))
        }
    }

    private static func setNative(_ id: CGDirectDisplayID) {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode],
              let native = modes.filter({ $0.pixelWidth == $0.width }).max(by: { $0.pixelWidth < $1.pixelWidth })
        else { die("no native mode found") }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { die("display config failed") }
        CGConfigureDisplayWithDisplayMode(cfg, id, native, nil)
        CGCompleteDisplayConfiguration(cfg, .forSession)
        UserDefaults.standard.set(0, forKey: DisplayModel.key(id))
        print("native \(native.width)x\(native.height)")
    }

    private static func setBrightness(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let v = Double(args[2]), (0...100).contains(v) else { die("usage: opendisplay brightness <0-100>") }
        let warmth = UserDefaults.standard.object(forKey: DisplayModel.warmthKey(id)) as? Double ?? 0
        let contrast = UserDefaults.standard.object(forKey: DisplayModel.contrastKey(id)) as? Double ?? 50
        Brightness.apply(brightness: v / 100, warmth: warmth / 100, contrast: contrast / 100, on: id)
        UserDefaults.standard.set(v, forKey: DisplayModel.brightKey(id))
        print("brightness \(Int(v))%")
    }

    private static func setWarmth(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let v = Double(args[2]), (0...100).contains(v) else { die("usage: opendisplay warmth <0-100>") }
        let bright = UserDefaults.standard.object(forKey: DisplayModel.brightKey(id)) as? Double ?? 100
        let contrast = UserDefaults.standard.object(forKey: DisplayModel.contrastKey(id)) as? Double ?? 50
        Brightness.apply(brightness: bright / 100, warmth: v / 100, contrast: contrast / 100, on: id)
        UserDefaults.standard.set(v, forKey: DisplayModel.warmthKey(id))
        print("warmth \(Int(v))%")
    }

    private static func setContrast(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let v = Double(args[2]), (0...100).contains(v) else { die("usage: opendisplay contrast <0-100>") }
        let bright = UserDefaults.standard.object(forKey: DisplayModel.brightKey(id)) as? Double ?? 100
        let warmth = UserDefaults.standard.object(forKey: DisplayModel.warmthKey(id)) as? Double ?? 0
        Brightness.apply(brightness: bright / 100, warmth: warmth / 100, contrast: v / 100, on: id)
        UserDefaults.standard.set(v, forKey: DisplayModel.contrastKey(id))
        print("contrast \(Int(v))% (50 = neutral)")
    }

    private static func setRefresh(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let hz = Double(args[2]) else { die("usage: opendisplay refresh <hz>") }
        guard let cur = CGDisplayCopyDisplayMode(id), cur.pixelWidth > cur.width else { die("set a HiDPI resolution first") }
        guard SkyLight.applyHiDPI(looksW: cur.width, hz: hz, to: id) else { die("no \(Int(hz))Hz at the current resolution") }
        print("refresh \(Int(hz))Hz")
    }

    private static func setRotate(_ id: CGDirectDisplayID, _ args: [String]) {
        guard args.count >= 3, let deg = Int(args[2]), Rotation.degrees.contains(deg) else { die("usage: opendisplay rotate <0|90|180|270>") }
        guard Rotation.rotate(id, to: deg) else { die("this display cannot rotate") }
        print("rotated \(deg)\u{00B0}")
    }

    private static func printCaps() {
        guard DDC.available else { die("no DDC/CI path to an external display") }
        guard let caps = DDC.capabilities() else { die("the panel did not answer the capability request (VCP 0xF3)") }
        print(caps)
    }

    private static func rawVCP(_ args: [String]) {
        guard args.count >= 3, let code = UInt8(args[2].replacingOccurrences(of: "0x", with: ""), radix: 16)
        else { die("usage: opendisplay vcp <hex-code> [value]   e.g. `vcp 87` reads sharpness") }
        guard DDC.available else { die("no DDC/CI path to an external display") }
        if args.count >= 4 {
            guard let v = UInt16(args[3]) else { die("value must be a decimal integer") }
            guard DDC.write(code, v) else { die(String(format: "write to VCP 0x%02X failed", code)) }
            print(String(format: "VCP 0x%02X = %d", code, v))
        } else {
            guard let r = DDC.read(code) else { die(String(format: "VCP 0x%02X is not readable on this panel", code)) }
            print(String(format: "VCP 0x%02X = %d (max %d)", code, r.current, r.max))
        }
    }

    private static func smoothing(_ args: [String]) {
        guard args.count >= 3 else {
            print("font smoothing: \(FontSmoothing.label(FontSmoothing.current))")
            print("apps pick this up on next launch; the WindowServer needs a logout")
            return
        }
        if args[2] == "auto" {
            guard FontSmoothing.clear() else { die("could not clear the preference") }
            print("font smoothing: unset (macOS default)")
            return
        }
        guard let level = Int(args[2]), (0 ... 3).contains(level) else { die("usage: opendisplay smoothing <0-3|auto>   0 is sharpest on a 1x panel") }
        guard FontSmoothing.set(level) else { die("could not write the preference") }
        print("font smoothing: \(FontSmoothing.label(level))")
        print("apps pick this up on next launch; the WindowServer needs a logout")
    }

    private static func color(_ id: CGDirectDisplayID, _ args: [String]) {
        let sub = args.count >= 3 ? args[2] : "show"
        do {
            switch sub {
            case "show":
                let s = ColorProfile.describe(id)
                print("Profile:        \(s.name ?? "unknown")\(s.isCustom ? " (custom)" : " (macOS EDID default)")")
                if let u = s.url { print("File:           \(u.path)") }
                func xy(_ label: String, _ p: (x: Double, y: Double)?) {
                    guard let p else { return }
                    print(String(format: "%@x %.4f  y %.4f", label.padding(toLength: 16, withPad: " ", startingAt: 0), p.x, p.y))
                }
                xy("White:", s.white)
                xy("Red:", s.red)
                xy("Green:", s.green)
                xy("Blue:", s.blue)
                if let t = s.trc { print("Tone curve:     \(t)") }
            case "gamma":
                guard args.count >= 4, let g = Double(args[3]), (1.0 ... 3.0).contains(g)
                else { die("usage: opendisplay color gamma <1.0-3.0>   2.2 is the Apple-style response") }
                let url = try ColorProfile.generate(for: id, gamma: g)
                try ColorProfile.assign(url, to: id)
                print("assigned \(url.lastPathComponent)")
            case "set":
                guard args.count >= 4 else { die("usage: opendisplay color set <path-to.icc>") }
                try ColorProfile.assign(URL(fileURLWithPath: args[3]), to: id)
                print("assigned \(args[3])")
            case "reset":
                try ColorProfile.reset(id)
                print("back to the macOS EDID profile")
            default:
                die("usage: opendisplay color [show|gamma <n>|set <path>|reset]")
            }
        } catch let ColorProfile.Err.msg(m) {
            die(m)
        } catch {
            die(error.localizedDescription)
        }
    }

    private static func holdVirtual(_ args: [String]) {
        let w = args.count >= 3 ? (Int(args[2]) ?? 2560) : 2560
        let h = args.count >= 4 ? (Int(args[3]) ?? (w * 9 / 16)) : (w * 9 / 16)
        let vd = VirtualDisplay()
        guard vd.start(looksW: w, looksH: h) else { die("failed to create virtual display") }
        print("virtual display \(w)x\(h) HiDPI created (id \(vd.displayID)); Ctrl-C to remove")
        withExtendedLifetime(vd) { RunLoop.main.run() }
    }

    private static func printHelp() {
        print("""
        opendisplay - control the display from the command line

          list                 hidden HiDPI modes (* = current)
          modes                every mode, 1x and 2x, with its render size
          info                 panel identity and geometry
          res <width>          set a HiDPI mode by looks-like width
          scaled <w>|off|list  size the panel does not have, via a mirrored virtual display
          native               return to the native (non-HiDPI) mode
          brightness <0-100>   software brightness
          warmth <0-100>       color warmth
          contrast <0-100>     contrast (50 = neutral)
          refresh <hz>         refresh rate at the current resolution
          rotate <0|90|180|270>  rotate the display
          caps                 the panel's DDC/CI capability string
          vcp <hex> [value]    read or write a raw MCCS feature
          smoothing <0-3|auto> text dilation; 0 is sharpest on a 1x panel
          color [show|gamma <n>|set <path>|reset]   display ICC profile
          virtual [w] [h]      create a headless HiDPI display and hold it
          help                 this text
        """)
    }
}
