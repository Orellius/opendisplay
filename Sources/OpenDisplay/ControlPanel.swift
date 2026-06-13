// The control panel: a sidebar of categories with a glass detail pane.
// Resolution picks a hidden HiDPI mode; Brightness drives software dimming
// (and optional DDC); Settings holds launch-at-login and display info.

import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case resolution = "Resolution"
    case brightness = "Brightness"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .resolution: return "rectangle.on.rectangle.angled"
        case .brightness: return "sun.max"
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
                        ResRow(mode: mode, active: model.currentLooksW == mode.looksW) {
                            model.apply(looksW: mode.looksW)
                        }
                    }
                    ResRowPlain(title: "Native (no HiDPI)", sub: "2560 × 1440", active: model.currentLooksW == 0) {
                        model.applyNative()
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
                PaneTitle("Brightness", sub: "Software dimming, applied live")
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

private struct SettingsDetail: View {
    @ObservedObject var model: DisplayModel
    @State private var launch = LoginItem.isEnabled
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
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow("Display", "LG UltraGear · 27″")
                        InfoRow("Density", "≈ 109 PPI")
                        InfoRow("OpenDisplay", "v0.1")
                    }
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
    let mode: DisplayMode; let active: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
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
            .padding(.vertical, 8).padding(.horizontal, 12).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
