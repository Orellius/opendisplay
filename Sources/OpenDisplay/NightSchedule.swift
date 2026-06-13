// SPDX-License-Identifier: AGPL-3.0-only
// Copyright © 2026 Orellius — https://github.com/Orellius/opendisplay
// Time-based warmth and dimming - BetterDisplay's most-requested unshipped feature
// (#2678, #758), where the maintainer keeps telling users to script it with the CLI.
// Honest version of Night Shift: a minute timer interpolates brightness and warmth
// between day and night across a 30-minute ramp at each boundary, driving the same
// gamma path as the manual sliders. While enabled it owns brightness/warmth; turning
// it off restores the manual saved values via the restore closure.
// Public surface: enabled + the four settings (persisted), driven by the owner's
// apply/restore closures. NOT responsible for: sun position (time stops avoid a
// location permission), per-display schedules (one external display is the target).

import Foundation

final class NightSchedule: ObservableObject {
    @Published var enabled: Bool { didSet { persist(); reschedule() } }
    @Published var startHour: Int { didSet { persist(); tickIfActive() } }
    @Published var endHour: Int { didSet { persist(); tickIfActive() } }
    @Published var nightWarmth: Double { didSet { persist(); tickIfActive() } }
    @Published var nightBrightness: Double { didSet { persist(); tickIfActive() } }

    private let apply: (_ brightness: Double, _ warmth: Double) -> Void
    private let restore: () -> Void
    private var timer: Timer?
    private var ready = false
    private let rampMinutes = 30.0

    init(apply: @escaping (Double, Double) -> Void, restore: @escaping () -> Void) {
        self.apply = apply
        self.restore = restore
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "schedule.enabled")
        startHour = d.object(forKey: "schedule.startHour") as? Int ?? 20
        endHour = d.object(forKey: "schedule.endHour") as? Int ?? 7
        nightWarmth = d.object(forKey: "schedule.nightWarmth") as? Double ?? 55
        nightBrightness = d.object(forKey: "schedule.nightBrightness") as? Double ?? 85
        ready = true
        reschedule()
    }

    deinit { timer?.invalidate() }

    // Re-read after a settings import; ready=false suppresses the per-field persist.
    func reload() {
        let d = UserDefaults.standard
        ready = false
        enabled = d.bool(forKey: "schedule.enabled")
        startHour = d.object(forKey: "schedule.startHour") as? Int ?? 20
        endHour = d.object(forKey: "schedule.endHour") as? Int ?? 7
        nightWarmth = d.object(forKey: "schedule.nightWarmth") as? Double ?? 55
        nightBrightness = d.object(forKey: "schedule.nightBrightness") as? Double ?? 85
        ready = true
        reschedule()
    }

    private func persist() {
        guard ready else { return }
        let d = UserDefaults.standard
        d.set(enabled, forKey: "schedule.enabled")
        d.set(startHour, forKey: "schedule.startHour")
        d.set(endHour, forKey: "schedule.endHour")
        d.set(nightWarmth, forKey: "schedule.nightWarmth")
        d.set(nightBrightness, forKey: "schedule.nightBrightness")
    }

    private func tickIfActive() { if ready, enabled { tick() } }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard enabled else { restore(); return }
        tick()
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let n = nightness(at: minutes)
        let b = 100 + (nightBrightness - 100) * n
        let w = nightWarmth * n
        apply(b, w)
    }

    /// 0 in full day, 1 in full night, with linear ramps at each boundary. Handles a
    /// window that wraps midnight by measuring minutes since start on a 1440-min circle.
    func nightness(at minutes: Int) -> Double {
        let day = 1440.0
        let start = Double(startHour * 60)
        let end = Double(endHour * 60)
        let sinceStart = (Double(minutes) - start + day).truncatingRemainder(dividingBy: day)
        let windowLen = (end - start + day).truncatingRemainder(dividingBy: day)
        guard windowLen > 0, sinceStart < windowLen else { return 0 }
        let up = min(1, sinceStart / rampMinutes)
        let down = min(1, (windowLen - sinceStart) / rampMinutes)
        return min(up, down)
    }
}
