// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Scriptable control surface: `opendisplay <command>`. Stateless commands apply and
// exit; `virtual` holds the process so a headless box (over SSH/Tailscale) can run it
// as a daemon. Shares the GUI's UserDefaults keys so a CLI change and the panel agree.
// This is the dev-audience hook BetterDisplay buries, and it doubles as the Shortcuts
// path (wrap a command in a Run Shell Script action).
// Public surface: CLI.run(_:) -> Bool (true never returns — it exits; false = launch GUI).
// NOT responsible for: daemonizing (launchd/SSH own that); persisting rotation (macOS does).

import CoreGraphics
import Foundation

enum CLI {
    static func run(_ args: [String]) -> Bool {
        guard args.count >= 2 else { return false }
        setvbuf(stdout, nil, _IOLBF, 0)   // line-buffer so `virtual` confirms before it blocks
        let id = CGMainDisplayID()
        switch args[1] {
        case "list": listModes(id)
        case "info": print(DisplayInfo.gather(id).report)
        case "res": setRes(id, args)
        case "native": setNative(id)
        case "brightness": setBrightness(id, args)
        case "warmth": setWarmth(id, args)
        case "contrast": setContrast(id, args)
        case "refresh": setRefresh(id, args)
        case "rotate": setRotate(id, args)
        case "virtual": holdVirtual(args)   // never returns
        case "help", "-h", "--help": printHelp()
        default: return false
        }
        exit(0)
    }

    private static func die(_ msg: String) -> Never {
        FileHandle.standardError.write(Data((msg + "\n").utf8))
        exit(1)
    }

    private static func listModes(_ id: CGDirectDisplayID) {
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
        guard SkyLight.applyHiDPI(looksW: w, to: id) else { die("no HiDPI mode at width \(w); see `opendisplay list`") }
        UserDefaults.standard.set(w, forKey: DisplayModel.key(id))
        print("HiDPI \(w)")
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
          info                 panel identity and geometry
          res <width>          set a HiDPI mode by looks-like width
          native               return to the native (non-HiDPI) mode
          brightness <0-100>   software brightness
          warmth <0-100>       color warmth
          contrast <0-100>     contrast (50 = neutral)
          refresh <hz>         refresh rate at the current resolution
          rotate <0|90|180|270>  rotate the display
          virtual [w] [h]      create a headless HiDPI display and hold it
          help                 this text
        """)
    }
}
