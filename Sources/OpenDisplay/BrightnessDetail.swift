// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// The Brightness & Color detail pane: software brightness and warmth sliders, the
// three tone presets, and the optional DDC hardware toggle. All values drive the
// gamma path through DisplayModel. NOT responsible for: the gamma math (Brightness).

import SwiftUI

struct BrightnessDetail: View {
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
                Card {
                    HStack(spacing: 14) {
                        Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { model.contrast },
                                              set: { model.setContrast($0) }),
                               in: 0 ... 100)
                        .tint(.orange)
                        Image(systemName: "circle.righthalf.filled").foregroundStyle(.orange)
                        Text("\(Int(model.contrast))%").font(.system(.body, design: .rounded))
                            .monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(0 ..< 3, id: \.self) { i in
                            Button { model.applyPreset(i) } label: {
                                VStack(spacing: 2) {
                                    Text("Preset \(i + 1)").font(.caption2)
                                    if let p = model.presets[i] {
                                        Text("\(Int(p.brightness)) / \(Int(p.warmth))")
                                            .font(.caption).monospacedDigit()
                                    } else {
                                        Text("empty").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .contextMenu { Button("Save current here") { model.savePreset(i) } }
                        }
                    }
                    Text("Click to apply · right-click to save the current brightness and warmth")
                        .font(.caption2).foregroundStyle(.secondary)
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
