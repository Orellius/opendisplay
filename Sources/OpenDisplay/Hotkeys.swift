// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Global hotkeys via Carbon RegisterEventHotKey. Carbon hot keys fire system-wide
// without the Accessibility permission a CGEventTap would need, which is why a
// menubar agent uses them for brightness/warmth nudges that work with the panel
// closed. Bindings are fixed for v1 (a recorder UI is a later slice).
// Public surface: Hotkeys(model:) registers on init, unregisters on deinit.
// NOT responsible for: configurable bindings, resolution cycling (menu/CLI cover that).

import Carbon.HIToolbox
import Foundation

final class Hotkeys {
    private let model: DisplayModel
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private static let signature: OSType = 0x4F50_4459   // 'OPDY'
    private static let step = 6.0

    init(model: DisplayModel) {
        self.model = model
        installHandler()
        register()
    }

    deinit {
        for ref in refs { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            guard let ctx, let event else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            Unmanaged<Hotkeys>.fromOpaque(ctx).takeUnretainedValue().actions[id.id]?()
            return noErr
        }, 1, &spec, context, &handler)
    }

    private func register() {
        let mod = UInt32(controlKey | optionKey | cmdKey)
        bind(1, key: UInt32(kVK_ANSI_RightBracket), mod: mod) { [weak self] in self?.model.nudgeBrightness(Self.step) }
        bind(2, key: UInt32(kVK_ANSI_LeftBracket),  mod: mod) { [weak self] in self?.model.nudgeBrightness(-Self.step) }
        bind(3, key: UInt32(kVK_ANSI_Quote),        mod: mod) { [weak self] in self?.model.nudgeWarmth(Self.step) }
        bind(4, key: UInt32(kVK_ANSI_Semicolon),    mod: mod) { [weak self] in self?.model.nudgeWarmth(-Self.step) }
        bind(5, key: UInt32(kVK_ANSI_B),            mod: mod) { [weak self] in self?.model.toggleBlackout() }
        bind(6, key: UInt32(kVK_ANSI_R),            mod: mod) { [weak self] in self?.model.quickReset() }
    }

    private func bind(_ id: UInt32, key: UInt32, mod: UInt32, action: @escaping () -> Void) {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: Self.signature, id: id)
        guard RegisterEventHotKey(key, mod, hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return }
        actions[id] = action
        refs.append(ref)
    }
}
