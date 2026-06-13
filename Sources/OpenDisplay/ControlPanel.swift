// The control-panel window: pick a HiDPI resolution for the display. The active
// choice is highlighted; tapping a row applies it live.

import SwiftUI

struct ControlPanel: View {
    @ObservedObject var model: DisplayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack").foregroundStyle(.orange)
                Text("OpenDisplay").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()

            if !SkyLight.available {
                Spacer()
                Text("SkyLight private API unavailable on this macOS version.")
                    .foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        sectionLabel("HiDPI resolutions")
                        ForEach(model.modes) { row($0) }
                        sectionLabel("Standard")
                        nativeRow
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 380, height: 480)
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack { Text(text).font(.caption).foregroundStyle(.secondary); Spacer() }
            .padding(.top, 10).padding(.horizontal, 8)
    }

    private func row(_ mode: DisplayMode) -> some View {
        let active = model.currentLooksW == mode.looksW
        return Button { model.apply(looksW: mode.looksW) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(mode.looksW) × \(mode.looksH)").font(.body)
                    Text("\(mode.pxW)×\(mode.pxH) rendered • \(Int(mode.hz)) Hz")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if active { Image(systemName: "checkmark").foregroundStyle(.orange) }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(active ? Color.orange.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var nativeRow: some View {
        let active = model.currentLooksW == 0
        return Button { model.applyNative() } label: {
            HStack {
                Text("Native (no HiDPI)").font(.body)
                Spacer()
                if active { Image(systemName: "checkmark").foregroundStyle(.orange) }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(active ? Color.orange.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
