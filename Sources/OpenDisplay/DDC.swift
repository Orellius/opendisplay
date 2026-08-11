// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// DDC/CI brightness over the Apple Silicon I2C path. The IOAVService private
// IOKit symbols have no public headers, so they are resolved with dlsym (same
// pattern as SkyLight). Targets the single external display: find the
// DCPAVServiceProxy whose Location is "External", create its IOAVService, and
// write VCP 0x10 (luminance). Packet framing and checksum ported from
// MonitorControl (MIT, waydabber et al.).

import Foundation
import IOKit

enum DDC {
    private typealias CreateFn = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteFn  = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias ReadFn   = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32

    private static let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        iokit.flatMap { dlsym($0, name) }.map { unsafeBitCast($0, to: T.self) }
    }
    private static let createService = sym("IOAVServiceCreateWithService", CreateFn.self)
    private static let writeI2C = sym("IOAVServiceWriteI2C", WriteFn.self)
    private static let readI2C = sym("IOAVServiceReadI2C", ReadFn.self)

    static var available: Bool { createService != nil && writeI2C != nil && externalService() != nil }

    private static let chip: UInt8 = 0x37
    private static let dataAddr: UInt8 = 0x51
    private static let brightnessVCP: UInt8 = 0x10

    /// MCCS feature codes this tool names. Not every panel implements every one;
    /// `capabilities()` is the only honest answer for a given monitor.
    enum VCP: UInt8 {
        case luminance      = 0x10
        case contrast       = 0x12
        case redGain        = 0x16
        case greenGain      = 0x18
        case blueGain       = 0x1A
        case colorPreset    = 0x14   // 05=6500K, 08=9300K, 0B=user; panel-specific
        case sharpness      = 0x87
        case gammaSelect    = 0x72
        case inputSource    = 0x60
        case blackLevelRed  = 0x6C
        case blackLevelGrn  = 0x6E
        case blackLevelBlu  = 0x70
    }

    private static var cached: CFTypeRef?
    private static func externalService() -> CFTypeRef? {
        if let cached { return cached }
        cached = findExternalService()
        return cached
    }

    private static func findExternalService() -> CFTypeRef? {
        guard let createService else { return nil }
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iter = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var result: CFTypeRef?
        var entry = IOIteratorNext(iter)
        while entry != IO_OBJECT_NULL {
            var nameBuf = [CChar](repeating: 0, count: 128)
            if IORegistryEntryGetName(entry, &nameBuf) == KERN_SUCCESS, String(cString: nameBuf) == "DCPAVServiceProxy",
               let locRef = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)),
               let loc = locRef.takeRetainedValue() as? String, loc == "External",
               let svc = createService(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                result = svc
                IOObjectRelease(entry)
                break
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return result
    }

    /// Set luminance 0...100.
    @discardableResult
    static func setBrightness(_ percent: Int) -> Bool {
        writeVCP(brightnessVCP, value: UInt16(max(0, min(100, percent))))
    }

    /// Read current luminance as a percentage (0...100), or nil if unsupported.
    static func brightness() -> Int? {
        guard let (current, max) = readVCP(brightnessVCP), max > 0 else { return nil }
        return Int((Double(current) / Double(max)) * 100.0 + 0.5)
    }

    /// Read any MCCS feature. Returns (current, max) in the panel's own units.
    static func read(_ code: UInt8) -> (current: UInt16, max: UInt16)? { readVCP(code) }

    /// Write any MCCS feature in the panel's own units.
    @discardableResult
    static func write(_ code: UInt8, _ value: UInt16) -> Bool { writeVCP(code, value: value) }

    /// The MCCS capability string (VCP 0xF3), assembled from its 32-byte fragments.
    /// This is the ground truth for which controls a panel actually exposes; everything
    /// else in this file is a guess until this string is read.
    static func capabilities() -> String? {
        guard let writeI2C, let readI2C, let service = externalService() else { return nil }
        var out = [UInt8]()
        var offset = 0
        while offset < 0x2000 {
            guard let frag = capsFragment(writeI2C, readI2C, service, offset: UInt16(offset)) else {
                return out.isEmpty ? nil : String(decoding: out, as: UTF8.self)
            }
            if frag.isEmpty { break }   // zero-length fragment terminates the string
            out += frag
            offset += frag.count
        }
        return out.isEmpty ? nil : String(decoding: out, as: UTF8.self)
    }

    // Reply frame: 0x6E, 0x80|len, 0xE3, offsetHi, offsetLo, data..., checksum.
    // Three data bytes of the length are the opcode and offset, so payload = len - 3.
    private static func capsFragment(_ writeI2C: WriteFn, _ readI2C: ReadFn, _ service: CFTypeRef, offset: UInt16) -> [UInt8]? {
        var send: [UInt8] = [UInt8(0x80 | 3), 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)]
        send.append(checksum(chk: chip << 1, data: send, end: send.count - 1))
        var reply = [UInt8](repeating: 0, count: 39)
        for _ in 0 ..< 4 {
            usleep(10000)
            _ = send.withUnsafeMutableBytes { writeI2C(service, UInt32(chip), UInt32(dataAddr), $0.baseAddress!, UInt32($0.count)) }
            usleep(50000)
            let r = reply.withUnsafeMutableBytes { readI2C(service, UInt32(chip), 0, $0.baseAddress!, UInt32($0.count)) }
            guard r == 0, reply[2] == 0xE3 else { usleep(20000); continue }
            let len = Int(reply[1] & 0x7F)
            guard len >= 3, 5 + (len - 3) <= reply.count else { usleep(20000); continue }
            return Array(reply[5 ..< (5 + len - 3)])
        }
        return nil
    }

    private static func writeVCP(_ command: UInt8, value: UInt16) -> Bool {
        guard let writeI2C, let service = externalService() else { return false }
        let send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 0xFF)]
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        packet[packet.count - 1] = checksum(chk: (chip << 1) ^ dataAddr, data: packet, end: packet.count - 2)
        var ok = false
        for _ in 0 ..< 3 {
            usleep(10000)
            ok = packet.withUnsafeMutableBytes {
                writeI2C(service, UInt32(chip), UInt32(dataAddr), $0.baseAddress!, UInt32($0.count)) == 0
            }
            if ok { break }
            usleep(20000)
        }
        return ok
    }

    private static func readVCP(_ command: UInt8) -> (current: UInt16, max: UInt16)? {
        guard let writeI2C, let readI2C, let service = externalService() else { return nil }
        var send: [UInt8] = [UInt8(0x80 | 2), 1, command]
        send.append(checksum(chk: chip << 1, data: send, end: send.count - 1))
        var reply = [UInt8](repeating: 0, count: 11)
        for _ in 0 ..< 4 {
            usleep(10000)
            _ = send.withUnsafeMutableBytes { writeI2C(service, UInt32(chip), UInt32(dataAddr), $0.baseAddress!, UInt32($0.count)) }
            usleep(50000)
            let r = reply.withUnsafeMutableBytes { readI2C(service, UInt32(chip), 0, $0.baseAddress!, UInt32($0.count)) }
            if r == 0, checksum(chk: 0x50, data: reply, end: reply.count - 2) == reply[reply.count - 1] {
                let maxV = UInt16(reply[6]) * 256 + UInt16(reply[7])
                let curV = UInt16(reply[8]) * 256 + UInt16(reply[9])
                return (curV, maxV)
            }
            usleep(20000)
        }
        return nil
    }

    private static func checksum(chk: UInt8, data: [UInt8], end: Int) -> UInt8 {
        var c = chk
        for i in 0 ... end { c ^= data[i] }
        return c
    }
}
