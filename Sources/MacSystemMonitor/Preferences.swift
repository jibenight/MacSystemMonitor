import Foundation
import Combine

/// Préférences utilisateur, persistées dans UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var showCPUInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showCPUInMenuBar, forKey: "showCPUInMenuBar") }
    }
    @Published var showRAMInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showRAMInMenuBar, forKey: "showRAMInMenuBar") }
    }
    @Published var alertsEnabled: Bool {
        didSet { UserDefaults.standard.set(alertsEnabled, forKey: "alertsEnabled") }
    }

    private init() {
        let d = UserDefaults.standard
        // Valeur par défaut : true si la clé n'a jamais été écrite.
        func flag(_ key: String, default def: Bool) -> Bool {
            d.object(forKey: key) == nil ? def : d.bool(forKey: key)
        }
        showCPUInMenuBar = flag("showCPUInMenuBar", default: true)
        showRAMInMenuBar = flag("showRAMInMenuBar", default: true)
        alertsEnabled = flag("alertsEnabled", default: true)
    }
}
