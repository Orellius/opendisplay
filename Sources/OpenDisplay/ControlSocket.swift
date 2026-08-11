// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius, https://github.com/Orellius/opendisplay
// A local control socket, so another process can read this app's state and drive it
// without shelling out. The CLI and the opendisplay:// scheme are both fire-and-forget:
// they apply a change and exit, and neither can answer "what is the display doing right
// now" or tell a caller when something changed underneath it. A long-lived UNIX socket
// can do both, which is what a live dashboard needs.
//
// Transport: a UNIX domain socket at
//   ~/Library/Application Support/com.orellius.opendisplay/control.sock
// created on launch and unlinked on exit. UNIX domain, not TCP, on purpose: it is
// filesystem-scoped and never reachable off the machine. The directory is 0700 and the
// socket 0600, so it is the user's own processes or nothing.
//
// Protocol: line-delimited JSON. One request object per line, one reply object per line.
//   -> {"cmd":"state"}                      <- {"ok":true,"displays":[...]}
//   -> {"cmd":"brightness","pct":60}        <- {"ok":true,...}
//   -> {"cmd":"res","looksW":1920}          <- {"ok":false,"error":"..."} when unlisted
//   -> {"cmd":"subscribe"}                  <- {"ok":true}, then {"event":"state",...}
// Unknown commands are refused rather than ignored, so a caller learns immediately.
//
// `scaled` is deliberately absent. It rewrites display topology and its confirm countdown
// has a known defect, so it stays off a machine-driven interface until that is fixed.
//
// Public surface: start(model:), stop(), path.
// NOT responsible for: applying anything itself. Every command routes through
// DisplayModel on the main queue, so socket callers and the UI cannot diverge.

import Combine
import Darwin
import Foundation

final class ControlSocket {
    private(set) var path = ""
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: DispatchSourceRead] = [:]
    private var pending: [Int32: Data] = [:]
    private var subscribers: Set<Int32> = []
    private weak var model: DisplayModel?
    private var watch: AnyCancellable?
    private var pushQueued = false

    /// Serialises every socket touch. Model reads hop to main and back.
    private let queue = DispatchQueue(label: "com.orellius.opendisplay.control")

    static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("com.orellius.opendisplay/control.sock").path
    }

    @discardableResult
    func start(model: DisplayModel, at path: String = ControlSocket.defaultPath()) -> Bool {
        stop()
        self.model = model
        self.path = path

        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])

        // sun_path is 104 bytes. A long enough home directory would silently truncate into
        // a path nobody can connect to, so refuse instead of binding somewhere wrong.
        let bytes = Array(path.utf8)
        guard bytes.count < 104 else { return false }

        unlink(path)   // a stale socket from a crash would make bind fail with EADDRINUSE
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return false }
        chmod(path, 0o600)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptOne() }
        source.resume()
        acceptSource = source

        // Any published change on the model is a state change worth pushing. Coalesced,
        // because a slider drag emits a burst and subscribers want the settled value.
        watch = model.objectWillChange.sink { [weak self] _ in self?.queuePush() }
        return true
    }

    func stop() {
        watch = nil
        acceptSource?.cancel(); acceptSource = nil
        for (fd, source) in clients { source.cancel(); close(fd) }
        clients.removeAll(); pending.removeAll(); subscribers.removeAll()
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        if !path.isEmpty { unlink(path) }
    }

    // MARK: connections

    private func acceptOne() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.readFrom(fd) }
        source.setCancelHandler { close(fd) }
        clients[fd] = source
        pending[fd] = Data()
        source.resume()
    }

    private func drop(_ fd: Int32) {
        clients[fd]?.cancel()
        clients[fd] = nil
        pending[fd] = nil
        subscribers.remove(fd)
    }

    private func readFrom(_ fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { drop(fd); return }
        pending[fd, default: Data()].append(contentsOf: buf[0 ..< n])
        // Line-delimited: hold a partial tail until its newline arrives.
        while let idx = pending[fd]?.firstIndex(of: 0x0A) {
            let line = pending[fd]!.subdata(in: pending[fd]!.startIndex ..< idx)
            pending[fd]!.removeSubrange(pending[fd]!.startIndex ... idx)
            handle(line, from: fd)
        }
    }

    private func send(_ object: [String: Any], to fd: Int32) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var off = 0
            while off < raw.count {
                let w = write(fd, base.advanced(by: off), raw.count - off)
                if w <= 0 { break }
                off += w
            }
        }
    }

    // MARK: commands

    private func handle(_ line: Data, from fd: Int32) {
        guard !line.isEmpty else { return }
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let cmd = obj["cmd"] as? String else {
            send(["ok": false, "error": "expected a JSON object with a cmd field"], to: fd)
            return
        }
        if cmd == "subscribe" {
            subscribers.insert(fd)
            send(["ok": true, "subscribed": true], to: fd)
            queuePush()
            return
        }
        // Everything else touches the model, which is main-queue only.
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.model else { return }
            let reply = self.apply(cmd: cmd, args: obj, model: model)
            self.queue.async { self.send(reply, to: fd) }
        }
    }

    private func pct(_ args: [String: Any]) -> Double? {
        guard let raw = args["pct"] as? NSNumber else { return nil }
        return min(100, max(0, raw.doubleValue))
    }

    private func apply(cmd: String, args: [String: Any], model: DisplayModel) -> [String: Any] {
        switch cmd {
        case "state":
            return ["ok": true, "displays": [Self.state(of: model)]]
        case "brightness":
            guard let v = pct(args) else { return ["ok": false, "error": "brightness needs pct 0-100"] }
            model.setBrightness(v)
            return ["ok": true, "brightness": v]
        case "warmth":
            guard let v = pct(args) else { return ["ok": false, "error": "warmth needs pct 0-100"] }
            model.setWarmth(v)
            return ["ok": true, "warmth": v]
        case "contrast":
            guard let v = pct(args) else { return ["ok": false, "error": "contrast needs pct 0-100"] }
            model.setContrast(v)
            return ["ok": true, "contrast": v]
        case "res":
            guard let w = (args["looksW"] as? NSNumber)?.intValue else {
                return ["ok": false, "error": "res needs looksW"]
            }
            // Refuse rather than guess, matching the CLI: a width that is not enumerated
            // would otherwise be silently rounded to something the caller never asked for.
            guard model.modes.contains(where: { $0.looksW == w }) else {
                return ["ok": false, "error": "no HiDPI mode at looks-width \(w)",
                        "available": model.modes.map(\.looksW)]
            }
            model.apply(looksW: w)
            return ["ok": true, "looksW": w]
        case "native":
            model.applyNative()
            return ["ok": true]
        case "reset":
            model.quickReset()
            return ["ok": true]
        default:
            return ["ok": false, "error": "unknown cmd \(cmd)"]
        }
    }

    /// Main queue only.
    private static func state(of model: DisplayModel) -> [String: Any] {
        var current: [String: Any] = ["hz": Int(model.currentHz.rounded())]
        if let s = model.scaledActive {
            current["looksW"] = s.looksW
            current["looksH"] = s.looksH
            current["kind"] = "scaled"
        } else if model.currentLooksW > 0,
                  let m = model.modes.first(where: { $0.looksW == model.currentLooksW }) {
            current["looksW"] = m.looksW
            current["looksH"] = m.looksH
            current["kind"] = "hidpi"
        } else {
            current["looksW"] = model.nativeW
            current["looksH"] = model.nativeH
            current["kind"] = "native"
        }
        // Every tone value is this app's own gamma state. DDC on some panels answers no
        // reads at all, so a hardware number would be last-written-by-us at best; saying
        // "app-local" is the only honest label for what these are.
        return [
            "id": Int(model.displayID),
            "name": model.effectiveName,
            "native": ["w": model.nativeW, "h": model.nativeH],
            "current": current,
            "modes": model.modes.map(\.looksW),
            "refreshRates": model.refreshRates.map { Int($0.rounded()) },
            "rotation": model.rotation,
            "brightness": ["value": model.brightness, "source": "app-local"],
            "warmth": ["value": model.warmth, "source": "app-local"],
            "contrast": ["value": model.contrast, "source": "app-local"],
            "hardwareDDC": ["enabled": model.hardwareDDC, "readable": false],
        ]
    }

    // MARK: events

    private func queuePush() {
        queue.async { [weak self] in
            guard let self, !self.subscribers.isEmpty, !self.pushQueued else { return }
            self.pushQueued = true
            self.queue.asyncAfter(deadline: .now() + 0.15) { self.pushNow() }
        }
    }

    private func pushNow() {
        pushQueued = false
        let targets = subscribers
        guard !targets.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let model = self.model else { return }
            let payload: [String: Any] = ["event": "state", "displays": [Self.state(of: model)]]
            self.queue.async { for fd in targets { self.send(payload, to: fd) } }
        }
    }
}
