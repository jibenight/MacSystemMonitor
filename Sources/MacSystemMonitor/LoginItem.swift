import Foundation
import ServiceManagement

/// Gère le lancement automatique au démarrage de session (API moderne SMAppService, macOS 13+).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LoginItem: échec (\(error.localizedDescription)). " +
                  "Active manuellement via Réglages Système → Général → Ouverture.")
        }
    }
}
