// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// The Resolution detail pane: a scrub slider over the hidden HiDPI modes, a list of
// those modes (each star-pinnable to the menu bar), a native fallback, and refresh /
// rotation pickers when the panel supports them. Reads everything from DisplayModel
// and calls back into it to apply. ResRow/ResRowPlain are co-located here because this
// is their only consumer. NOT responsible for: mode enumeration (SkyLight/DisplayModel).

import SwiftUI

struct ResolutionDetail: View {
    @ObservedObject var model: DisplayModel
    @State private var sliderIdx: Double = 0

    private var ascModes: [DisplayMode] { model.modes.sorted { $0.looksW < $1.looksW } }

    private func syncSlider() {
        if let i = ascModes.firstIndex(where: { $0.looksW == model.currentLooksW }) {
            sliderIdx = Double(i)
        } else if !ascModes.isEmpty {
            sliderIdx = Double(ascModes.count - 1)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                PaneTitle("Resolution", sub: "Sharp HiDPI modes macOS hides")
                if !SkyLight.available {
                    Text("SkyLight private API unavailable on this macOS version.")
                        .foregroundStyle(.secondary).padding(.top, 8)
                } else {
                    if model.modes.isEmpty {
                        Text("This display doesn't support HiDPI (\u{201C}Retina\u{201D}) scaling.\nmacOS only exposes HiDPI modes on higher-density panels, around 4K and up.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8).padding(.horizontal, 12)
                    } else {
                        if ascModes.count > 1 {
                            let i = min(max(0, Int(sliderIdx.rounded())), ascModes.count - 1)
                            let m = ascModes[i]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Scrub resolution").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(m.looksW) × \(m.looksH)").font(.caption)
                                        .monospacedDigit().foregroundStyle(.secondary)
                                }
                                Slider(value: $sliderIdx, in: 0 ... Double(ascModes.count - 1), step: 1,
                                       onEditingChanged: { editing in
                                           if !editing {
                                               let j = min(max(0, Int(sliderIdx.rounded())), ascModes.count - 1)
                                               model.apply(looksW: ascModes[j].looksW)
                                           }
                                       })
                                .tint(.orange)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        ForEach(model.modes) { mode in
                            ResRow(mode: mode,
                                   active: model.currentLooksW == mode.looksW,
                                   favorite: model.isFavorite(mode.looksW),
                                   apply: { model.apply(looksW: mode.looksW) },
                                   toggleFav: { model.toggleFavorite(mode.looksW) })
                        }
                    }
                    ResRowPlain(title: model.modes.isEmpty ? "Standard" : "Native (no HiDPI)",
                                sub: "\(model.nativeW) × \(model.nativeH)",
                                active: model.currentLooksW == 0) {
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
        .onAppear { syncSlider() }
        .onChange(of: model.currentLooksW) { _, _ in syncSlider() }
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
