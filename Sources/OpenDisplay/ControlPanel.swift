// The control panel shell: a sidebar of categories with a glass detail pane. Each
// category routes to its own detail view (ResolutionDetail/BrightnessDetail/
// DisplayDetail/SettingsDetail), all in sibling files; the shared pane primitives live
// in PaneComponents. This file owns only the split-view chrome, the sidebar footer,
// and the logo mark. NOT responsible for: any pane's contents.

import AppKit
import SwiftUI

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
            VStack(spacing: 0) {
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
                .frame(maxHeight: .infinity)
                SidebarFooter()
            }
            .navigationSplitViewColumnWidth(min: 172, ideal: 172, max: 210)
        } detail: {
            Group {
                switch tab ?? .resolution {
                case .resolution: ResolutionDetail(model: model)
                case .brightness: BrightnessDetail(model: model)
                case .display: DisplayDetail(model: model)
                case .settings: SettingsDetail(model: model, schedule: model.schedule,
                                               idle: model.idle, sleep: model.sleepGuard)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
        }
        .frame(width: 660, height: 470)
    }
}

private struct SidebarFooter: View {
    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    var body: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 6) {
                LogoMark().frame(width: 13, height: 13)
                Text("OpenDisplay").font(.caption2).fontWeight(.semibold)
                Text(version).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(.primary.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
            Link(destination: URL(string: "https://github.com/Orellius/opendisplay")!) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("View on GitHub")
                }
                .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Text("Made for the community by\nOrellius (Orel Ohayon)")  // allow-personal: founder attribution footer stamp, requested by Orel
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 12)
        .frame(maxWidth: .infinity)
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
