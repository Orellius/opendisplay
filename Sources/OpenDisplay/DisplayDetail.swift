// The Display detail pane: panel identity (name, manufacturer, serial, manufacture
// date) and geometry (native/current resolution, panel size, PPI, EDID UUID), with
// copy-to-clipboard and text export. Reads a DisplayInfo snapshot on appear.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DisplayDetail: View {
    @ObservedObject var model: DisplayModel
    @State private var info = DisplayInfo()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneTitle("Display", sub: info.name)
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        if let m = info.manufacturerID { InfoRow("Manufacturer", m) }
                        InfoRow("Vendor / Model", String(format: "0x%04X / 0x%04X", info.vendor, info.model))
                        if let s = info.alphaSerial { InfoRow("Serial", s) }
                        if let w = info.weekOfManufacture, let y = info.yearOfManufacture {
                            InfoRow("Manufactured", "week \(w), \(y)")
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow("Native", "\(info.nativeW) × \(info.nativeH)")
                        InfoRow("Current", "\(info.looksW) × \(info.looksH) · \(Int(info.hz.rounded())) Hz")
                        if let d = info.diagonalInches { InfoRow("Panel", String(format: "%.1f″", d)) }
                        if let p = info.ppi { InfoRow("Density", "\(p) PPI") }
                        if let u = info.edidUUID { InfoRow("EDID UUID", u) }
                    }
                }
                HStack(spacing: 10) {
                    Button { copyReport() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    Button { exportReport() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(.bordered)
            }
            .padding(20)
        }
        .onAppear { info = DisplayInfo.gather(model.displayID) }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(info.report, forType: .string)
    }

    private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenDisplay-\(info.name).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? info.report.write(to: url, atomically: true, encoding: .utf8)
    }
}
