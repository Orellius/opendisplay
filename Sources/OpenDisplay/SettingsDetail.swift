// The Settings detail pane: launch-at-login, the headless virtual display, the night
// schedule, and idle dimming, plus a version row. Most controls bind straight to the
// relevant observable (NightSchedule/IdleDimmer) or DisplayModel. VirtualRes is the
// small resolution-preset model for the virtual-display picker, co-located here as its
// only consumer. NOT responsible for: the schedule/idle timers themselves.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct VirtualRes: Identifiable, Hashable {
    let w: Int; let h: Int
    var id: Int { w }
    var label: String { "\(w) × \(h)" }
}

struct SettingsDetail: View {
    @ObservedObject var model: DisplayModel
    @ObservedObject var schedule: NightSchedule
    @ObservedObject var idle: IdleDimmer
    @ObservedObject var sleep: DisplaySleepGuard
    @State private var launch = LoginItem.isEnabled
    @AppStorage("osd.classic") private var classicOSD = false
    @State private var virtualW = (UserDefaults.standard.object(forKey: "virtual.w") as? Int) ?? 2560
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
                    Toggle(isOn: $model.protectConfig) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protect resolution")
                            Text("Put the chosen resolution back if an app or macOS changes it")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch).tint(.orange)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $schedule.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Night schedule")
                                Text("Warm and dim on a daily timer")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch).tint(.orange)
                        if schedule.enabled {
                            HStack(spacing: 10) {
                                Stepper("From \(schedule.startHour):00", value: $schedule.startHour, in: 0 ... 23)
                                Stepper("to \(schedule.endHour):00", value: $schedule.endHour, in: 0 ... 23)
                            }
                            .font(.callout)
                            HStack(spacing: 12) {
                                Image(systemName: "thermometer.sun").foregroundStyle(.secondary)
                                Slider(value: $schedule.nightWarmth, in: 0 ... 100).tint(.orange)
                                Text("\(Int(schedule.nightWarmth))%").font(.callout).monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                            HStack(spacing: 12) {
                                Image(systemName: "sun.min").foregroundStyle(.secondary)
                                Slider(value: $schedule.nightBrightness, in: 25 ... 100).tint(.orange)
                                Text("\(Int(schedule.nightBrightness))%").font(.callout).monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                Card {
                    Toggle(isOn: $sleep.enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prevent display sleep")
                            Text("Keep the screen awake while OpenDisplay runs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch).tint(.orange)
                }
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $idle.enabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dim when idle")
                                Text("Fade the screen after no input, restore on activity")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch).tint(.orange)
                        if idle.enabled {
                            Stepper("After \(idle.minutes) min", value: $idle.minutes, in: 1 ... 30)
                                .font(.callout)
                            HStack(spacing: 12) {
                                Image(systemName: "moon").foregroundStyle(.secondary)
                                Slider(value: $idle.level, in: 0.3 ... 0.95).tint(.orange)
                                Text("\(Int(idle.level * 100))%").font(.callout).monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
                Card {
                    Toggle(isOn: $classicOSD) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Classic OSD style")
                            Text("Square macOS-classic on-screen display instead of glass")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch).tint(.orange)
                    .onChange(of: classicOSD) { _, _ in OSD.brightness(model.brightness) }
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Settings file").font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button { exportSettings() } label: { Label("Export…", systemImage: "square.and.arrow.up") }
                            Button { importSettings() } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                        }
                        .buttonStyle(.bordered)
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

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "OpenDisplay-settings.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? SettingsPortability.exportData() else { return }
        try? data.write(to: url)
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return }
        SettingsPortability.importData(data)
        model.reloadFromDefaults()
    }
}
