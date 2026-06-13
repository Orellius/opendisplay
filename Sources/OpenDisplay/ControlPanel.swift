// The control panel shell: a fixed two-pane layout - a category sidebar beside a glass
// detail pane. Each category routes to its own detail view (ResolutionDetail/
// BrightnessDetail/DisplayDetail/SettingsDetail), all in sibling files; the shared pane
// primitives live in PaneComponents. A plain HStack rather than NavigationSplitView on
// purpose: hosted in a manually-built NSWindow, the split view's collapse animation
// crashes in NSView layout, and its sidebar gets no titlebar inset. NOT responsible
// for: any pane's contents.

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
    @State private var tab: PanelTab = .resolution

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 660, height: 470)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoMark().frame(width: 20, height: 20)
                Text("OpenDisplay").font(.headline).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.top, 32)   // clear the window's traffic-light controls
            .padding(.horizontal, 14).padding(.bottom, 10)
            VStack(spacing: 2) {
                ForEach(PanelTab.allCases) { sidebarRow($0) }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
            SidebarFooter()
        }
        .frame(width: 188)
        .background(SidebarBackground().ignoresSafeArea())
    }

    private func sidebarRow(_ t: PanelTab) -> some View {
        Button { tab = t } label: {
            Label(t.rawValue, systemImage: t.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tab == t ? Color.primary : Color.secondary)
        .background(tab == t ? Color.primary.opacity(0.12) : .clear,
                    in: RoundedRectangle(cornerRadius: 7))
    }

    private var detail: some View {
        Group {
            switch tab {
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
}

// Native sidebar vibrancy, matching what listStyle(.sidebar) gave before.
private struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
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
