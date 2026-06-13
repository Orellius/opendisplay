// The control panel: a sidebar of categories with a glass detail pane.
// Resolution picks a hidden HiDPI mode; Brightness drives software dimming
// (and optional DDC); Settings holds launch-at-login and display info.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PanelTab: String, CaseIterable, Identifiable {
    case resolution = "Resolution"
    case brightness = "Brightness"
    case display = "Display"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .resolution: return "rectangle.on.rectangle.angled"
        case .brightness: return "sun.max"
        case .display: return "display"
        case .settings: return "gearshape"
        }
    }
}

struct ControlPanel: View {
    @ObservedObject var model: DisplayModel
    @State private var tab: PanelTab? = .resolution

    var body: some View {
        NavigationSplitView {
            List(selection: $tab) {
                Section {
                    ForEach(PanelTab.allCases) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                } header: {
                    HStack(spacing: 8) {
                        LogoMark().frame(width: 20, height: 20)
                        Text("OpenDisplay").font(.headline).foregroundStyle(.primary)
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 172, ideal: 172, max: 210)
        } detail: {
            Group {
                switch tab ?? .resolution {
                case .resolution: ResolutionDetail(model: model)
                case .brightness: BrightnessDetail(model: model)
                case .display: DisplayDetail(model: model)
                case .settings: SettingsDetail(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
        }
        .frame(width: 660, height: 470)
    }
}

// MARK: detail panes

private struct ResolutionDetail: View {
    @ObservedObject var model: DisplayModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                PaneTitle("Resolution", sub: "Sharp HiDPI modes macOS hides")
                if !SkyLight.available {
                    Text("SkyLight private API unavailable on this macOS version.")
                        .foregroundStyle(.secondary).padding(.top, 8)
                } else {
                    ForEach(model.modes) { mode in
                        ResRow(mode: mode,
                               active: model.currentLooksW == mode.looksW,
                               favorite: model.isFavorite(mode.looksW),
                               apply: { model.apply(looksW: mode.looksW) },
                               toggleFav: { model.toggleFavorite(mode.looksW) })
                    }
                    ResRowPlain(title: "Native (no HiDPI)", sub: "2560 × 1440", active: model.currentLooksW == 0) {
                        model.applyNative()
                    }
                    if !model.refreshRates.isEmpty {
                        HStack { Text("Refresh rate").font(.caption).foregroundStyle(.secondary); Spacer() }
                            .padding(.top, 12).padding(.horizontal, 12)
                        Picker("", selection: Binding(get: { Int(model.currentHz.rounded()) },
                                                      set: { model.setRefresh(Double($0)) })) {
                            ForEach(model.refreshRates, id: \.self) { hz in
                                Text("\(Int(hz)) Hz").tag(Int(hz))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.horizontal, 12)
                    }
                    if model.canRotate {
                        HStack { Text("Rotation").font(.caption).foregroundStyle(.secondary); Spacer() }
                            .padding(.top, 12).padding(.horizontal, 12)
                        Picker("", selection: Binding(get: { model.rotation },
                                                      set: { model.rotate(to: $0) })) {
                            ForEach(Rotation.degrees, id: \.self) { d in
                                Text(d == 0 ? "Standard" : "\(d)°").tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .padding(.horizontal, 12)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct BrightnessDetail: View {
    @ObservedObject var model: DisplayModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneTitle("Brightness & Color", sub: "Software dimming and warmth, applied live")
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { model.brightness },
                                              set: { model.setBrightness($0) }),
                               in: 0 ... 100)
                        .tint(.orange)
                        Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                        Text("\(Int(model.brightness))%").font(.system(.body, design: .rounded))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "thermometer.snowflake").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { model.warmth },
                                              set: { model.setWarmth($0) }),
                               in: 0 ... 100)
                        .tint(.orange)
                        Image(systemName: "thermometer.sun.fill").foregroundStyle(.orange)
                        Text("\(Int(model.warmth))%").font(.system(.body, design: .rounded))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                if model.hardwareAvailable {
                    Card {
                        Toggle(isOn: $model.hardwareDDC) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Also set hardware brightness (DDC)")
                                Text("Your panel may ignore DDC writes")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch).tint(.orange)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct DisplayDetail: View {
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

private struct VirtualRes: Identifiable, Hashable {
    let w: Int; let h: Int
    var id: Int { w }
    var label: String { "\(w) × \(h)" }
}

private struct SettingsDetail: View {
    @ObservedObject var model: DisplayModel
    @State private var launch = LoginItem.isEnabled
    @State private var virtualW = 2560
    private let virtualPresets = [VirtualRes(w: 1920, h: 1080), VirtualRes(w: 2560, h: 1440),
                                  VirtualRes(w: 3008, h: 1692), VirtualRes(w: 3360, h: 1890)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PaneTitle("Settings", sub: nil)
                Card {
                    Toggle(isOn: Binding(get: { launch },
                                         set: { _ in LoginItem.toggle(); launch = LoginItem.isEnabled })) {
                        Text("Start at login")
                    }
                    .toggleStyle(.switch).tint(.orange)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: Binding(get: { model.virtualActive }, set: { on in
                            if on {
                                let r = virtualPresets.first { $0.w == virtualW } ?? virtualPresets[1]
                                model.startVirtual(looksW: r.w, looksH: r.h)
                            } else { model.stopVirtual() }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Headless virtual display")
                                Text("A HiDPI surface for remote access when no panel is attached")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch).tint(.orange)
                        Picker("Resolution", selection: $virtualW) {
                            ForEach(virtualPresets) { Text($0.label).tag($0.w) }
                        }
                        .disabled(model.virtualActive)
                    }
                }
                Card {
                    InfoRow("OpenDisplay", "v1.0")
                }
                Text("HiDPI renders at 2× and downsamples to the panel. Sharper, not denser.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}

// MARK: building blocks

private struct PaneTitle: View {
    let title: String; let sub: String?
    init(_ t: String, sub: String?) { title = t; self.sub = sub }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2).fontWeight(.semibold)
            if let sub { Text(sub).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.bottom, 4)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
    }
}

private struct ResRow: View {
    let mode: DisplayMode; let active: Bool; let favorite: Bool
    let apply: () -> Void; let toggleFav: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button(action: apply) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(mode.looksW) × \(mode.looksH)").font(.body)
                        Text("\(mode.pxW)×\(mode.pxH) rendered · \(Int(mode.hz)) Hz")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("HiDPI").font(.caption2).fontWeight(.bold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                    if active { Image(systemName: "checkmark").foregroundStyle(.orange) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: toggleFav) {
                Image(systemName: favorite ? "star.fill" : "star")
                    .foregroundStyle(favorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(favorite ? "Remove from menu bar" : "Pin to menu bar")
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(active ? Color.orange.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ResRowPlain: View {
    let title: String; let sub: String; let active: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active { Image(systemName: "checkmark").foregroundStyle(.orange) }
            }
            .padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(active ? Color.orange.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct InfoRow: View {
    let k: String; let v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v) }
    }
}

struct LogoMark: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { cell(.white); cell(.white) }
            HStack(spacing: 2) { cell(.white); cell(.orange) }
        }
        .padding(2.5)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(white: 0.12)))
    }
    private func cell(_ c: Color) -> some View { RoundedRectangle(cornerRadius: 2.5).fill(c) }
}
