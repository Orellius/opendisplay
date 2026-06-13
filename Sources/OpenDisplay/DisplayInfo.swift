// Reads panel identity and geometry for the Display info pane and its text export.
// The product name comes from the private CoreDisplay info dictionary (the same
// source System Information uses); manufacture/serial details and the EDID UUID come
// from the IORegistry DisplayAttributes node; everything else is public CoreGraphics.
// A single external display is assumed (the product's target hardware), so the first
// DisplayAttributes node is taken without the multi-display matching MonitorControl needs.
// Public surface: DisplayInfo.gather(_:) -> DisplayInfo; .report (formatted text).
// NOT responsible for: multi-display disambiguation, raw EDID byte parsing.

import CoreGraphics
import Foundation
import IOKit

struct DisplayInfo {
    var name = "External Display"
    var vendor: UInt32 = 0
    var model: UInt32 = 0
    var serial: UInt32 = 0
    var nativeW = 0
    var nativeH = 0
    var currentW = 0
    var currentH = 0
    var looksW = 0
    var looksH = 0
    var hz: Double = 0
    var widthMM: Double = 0
    var heightMM: Double = 0
    var rotation: Double = 0
    var isBuiltin = false
    var manufacturerID: String?
    var alphaSerial: String?
    var yearOfManufacture: Int?
    var weekOfManufacture: Int?
    var edidUUID: String?

    var ppi: Int? {
        guard widthMM > 0, nativeW > 0 else { return nil }
        return Int((Double(nativeW) / (widthMM / 25.4)).rounded())
    }

    var diagonalInches: Double? {
        guard widthMM > 0, heightMM > 0 else { return nil }
        return (widthMM * widthMM + heightMM * heightMM).squareRoot() / 25.4
    }
}

extension DisplayInfo {
    static func gather(_ id: CGDirectDisplayID) -> DisplayInfo {
        let cur = CGDisplayCopyDisplayMode(id)
        let size = CGDisplayScreenSize(id)
        let native = nativePixels(id)
        var info = DisplayInfo()
        info.name = productName(id) ?? "External Display"
        info.vendor = CGDisplayVendorNumber(id)
        info.model = CGDisplayModelNumber(id)
        info.serial = CGDisplaySerialNumber(id)
        info.nativeW = native.0
        info.nativeH = native.1
        info.currentW = cur?.pixelWidth ?? 0
        info.currentH = cur?.pixelHeight ?? 0
        info.looksW = cur?.width ?? 0
        info.looksH = cur?.height ?? 0
        info.hz = cur?.refreshRate ?? 0
        info.widthMM = size.width
        info.heightMM = size.height
        info.rotation = CGDisplayRotation(id)
        info.isBuiltin = CGDisplayIsBuiltin(id) != 0
        applyIORegistry(&info)
        return info
    }

    // The panel's physical pixel grid is the largest 1x mode (pixelWidth == width).
    // HiDPI modes report their oversampled RENDER buffer in pixelWidth (e.g. a 2544
    // looks-like mode renders 5088 px and downscales to the panel), so picking the
    // overall max pixelWidth would overstate the native resolution and the PPI.
    private static func nativePixels(_ id: CGDirectDisplayID) -> (Int, Int) {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else {
            let m = CGDisplayCopyDisplayMode(id)
            return (m?.pixelWidth ?? 0, m?.pixelHeight ?? 0)
        }
        var bw = 0, bh = 0
        for m in modes where m.pixelWidth == m.width && m.pixelWidth > bw { bw = m.pixelWidth; bh = m.pixelHeight }
        return (bw, bh)
    }

    private typealias InfoDictFn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
    private static let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW)
    private static let createInfo: InfoDictFn? = coreDisplay
        .flatMap { dlsym($0, "CoreDisplay_DisplayCreateInfoDictionary") }
        .map { unsafeBitCast($0, to: InfoDictFn.self) }

    private static func productName(_ id: CGDirectDisplayID) -> String? {
        guard let dict = createInfo?(id)?.takeRetainedValue() as NSDictionary?,
              let names = dict["DisplayProductName"] as? [String: String] else { return nil }
        return names[Locale.current.identifier] ?? names["en_US"] ?? names.first?.value
    }

    private static func applyIORegistry(_ info: inout DisplayInfo) {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        var iter = io_iterator_t()
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != IO_OBJECT_NULL {
            if let attrsRef = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)),
               let attrs = attrsRef.takeRetainedValue() as? NSDictionary,
               let product = attrs["ProductAttributes"] as? NSDictionary {
                info.manufacturerID = product["ManufacturerID"] as? String
                info.alphaSerial = product["AlphanumericSerialNumber"] as? String
                info.yearOfManufacture = product["YearOfManufacture"] as? Int
                info.weekOfManufacture = product["WeekOfManufacture"] as? Int
                if info.name == "External Display", let pn = product["ProductName"] as? String { info.name = pn }
                if let uuidRef = IORegistryEntryCreateCFProperty(entry, "EDID UUID" as CFString, kCFAllocatorDefault, 0),
                   let uuid = uuidRef.takeRetainedValue() as? String { info.edidUUID = uuid }
                IOObjectRelease(entry)
                break
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
    }

    var report: String {
        var lines = ["OpenDisplay — display info", ""]
        lines.append("Name:           \(name)")
        if let m = manufacturerID { lines.append("Manufacturer:   \(m)") }
        lines.append(String(format: "Vendor / Model: 0x%04X / 0x%04X", vendor, model))
        if let s = alphaSerial { lines.append("Serial:         \(s)") }
        else if serial != 0 { lines.append("Serial:         \(serial)") }
        if let w = weekOfManufacture, let y = yearOfManufacture { lines.append("Manufactured:   week \(w), \(y)") }
        lines.append("")
        lines.append("Native:         \(nativeW) × \(nativeH) px")
        lines.append("Current:        \(looksW) × \(looksH) (renders \(currentW) × \(currentH)) @ \(Int(hz.rounded())) Hz")
        if let d = diagonalInches { lines.append(String(format: "Panel:          %.1f″ · %.0f × %.0f mm", d, widthMM, heightMM)) }
        if let p = ppi { lines.append("Density:        \(p) PPI") }
        if rotation != 0 { lines.append("Rotation:       \(Int(rotation))°") }
        if let u = edidUUID { lines.append("EDID UUID:      \(u)") }
        return lines.joined(separator: "\n")
    }
}
