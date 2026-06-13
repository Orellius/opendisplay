// Launch-at-login via SMAppService (macOS 13+). Registers the bundled .app as a
// login item; the system relaunches it at boot.

import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("OpenDisplay: login-item toggle failed: \(error.localizedDescription)")
        }
    }
}
