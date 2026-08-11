// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius, https://github.com/Orellius/opendisplay
// The dropdown. Replaces the stock NSMenu of text rows with the same popover shape
// Trumpet uses, because the two apps sit next to each other in the menu bar and a
// plain AppKit menu beside a designed panel reads as the unfinished one.
// Layout follows Trumpet's: 320 wide, small-caps section headers, rows as filled
// rounded rectangles, footer with quit plus the license credit.
//
// The two resolution families are separate sections on purpose. The enumerated modes
// are what the panel declares and are free; the scaled ones are synthesized on a
// mirrored virtual display, cost GPU, and revert themselves unless accepted. Folding
// them into one list would hide that difference behind identical-looking rows.
//
// Both lists are Menus rather than stacked rows: this panel would be 400pt taller with
// twelve scaled sizes spelled out, and the menu bar is not where anyone scrolls.
// NOT responsible for: applying anything. Everything routes through DisplayModel.

import AppKit
import SwiftUI

struct MenuPanel: View {
    @ObservedObject var model: DisplayModel
    var onOpenPanel: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            displaySection
            Divider().padding(.vertical, 10)
            resolutionSection
            Divider().padding(.vertical, 10)
            brightnessSection
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    // MARK: display

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("DISPLAY")
            HStack(spacing: 8) {
                Image(systemName: "display").frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.effectiveName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(currentSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var currentSummary: String {
        let hz = model.currentHz > 0 ? " · \(Int(model.currentHz.rounded())) Hz" : ""
        if let s = model.scaledActive {
            return "\(s.looksW) × \(s.looksH) scaled\(hz)"
        }
        if model.currentLooksW > 0,
           let m = model.modes.first(where: { $0.looksW == model.currentLooksW }) {
            return "\(m.looksW) × \(m.looksH) HiDPI\(hz)"
        }
        return "\(model.nativeW) × \(model.nativeH)\(hz)"
    }

    // MARK: resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("RESOLUTION")
            Menu {
                Button {
                    model.applyNative()
                } label: {
                    Text("Native  \(model.nativeW) × \(model.nativeH)")
                }
                if !model.modes.isEmpty { Divider() }
                ForEach(model.modes) { mode in
                    Button {
                        model.apply(looksW: mode.looksW)
                    } label: {
                        Text("\(mode.looksW) × \(mode.looksH)  HiDPI")
                    }
                }
            } label: {
                MenuRowLabel(icon: "rectangle.on.rectangle.angled", text: enumeratedLabel)
            }
            .menuStyle(.borderlessButton)
            .modifier(RowChrome())

            scaledPicker
        }
    }

    private var enumeratedLabel: String {
        guard model.scaledActive == nil else { return "Overridden by scaling" }
        if model.currentLooksW > 0,
           let m = model.modes.first(where: { $0.looksW == model.currentLooksW }) {
            return "\(m.looksW) × \(m.looksH)  HiDPI"
        }
        return "Native  \(model.nativeW) × \(model.nativeH)"
    }

    @ViewBuilder
    private var scaledPicker: some View {
        if !model.scaledOptions.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("SCALED (VIRTUAL)")
                Menu {
                    Button("Off") { model.clearScaled() }
                    Divider()
                    ForEach(model.scaledOptions) { opt in
                        Button {
                            model.applyScaled(opt)
                        } label: {
                            Text("\(opt.looksW) × \(opt.looksH)   \(opt.percent)%")
                        }
                    }
                } label: {
                    MenuRowLabel(icon: "square.resize", text: scaledLabel)
                }
                .menuStyle(.borderlessButton)
                .modifier(RowChrome(tinted: model.scaledActive != nil))

                Text("Sizes the panel does not have. Reverts in "
                     + "\(ScaledResolution.confirmWindow)s unless you keep it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var scaledLabel: String {
        guard let s = model.scaledActive else { return "Off" }
        return "\(s.looksW) × \(s.looksH)   \(s.percent)%"
    }

    // MARK: brightness

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("BRIGHTNESS")
            HStack(spacing: 9) {
                Image(systemName: "sun.max").frame(width: 15)
                Slider(value: Binding(get: { model.brightness },
                                      set: { model.setBrightness($0) }), in: 0 ... 100)
                    .controlSize(.small)
                Text("\(Int(model.brightness.rounded()))%")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 9) {
            Button(action: onOpenPanel) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                    Text("Open Control Panel").font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08)))
            .padding(.top, 10)

            Divider()
            HStack(spacing: 6) {
                Button(action: onQuit) {
                    HStack(spacing: 4) {
                        Image(systemName: "power").font(.system(size: 10))
                        Text("Quit OpenDisplay").font(.system(size: 11))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button(LoginItem.isEnabled ? "Stop Opening at Login" : "Open at Login") {
                        LoginItem.toggle()
                    }
                    Divider()
                    Button("Reset Display") { model.quickReset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            }
            credit
        }
        .padding(.top, 8)
    }

    /// Rendered from the same constant the launch guard checks, so the visible credit
    /// and the enforced one cannot drift apart.
    private var credit: some View {
        Link(destination: URL(string: Attribution.url)!) {
            VStack(spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                    Text("View on GitHub")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Text("Made for the community by \(Attribution.author)")  // allow-personal: rendered from the single Attribution source
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .kerning(0.6)
    }
}

private struct MenuRowLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 16)
            Text(text).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
        }
    }
}

/// The filled-rounded-rect chrome Trumpet puts on its output picker, so a control that
/// opens a menu looks like a control and not like a label.
private struct RowChrome: ViewModifier {
    var tinted = false
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(tinted ? AnyShapeStyle(Color.orange.opacity(0.20))
                               : AnyShapeStyle(Color.primary.opacity(0.06)),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08)))
    }
}
