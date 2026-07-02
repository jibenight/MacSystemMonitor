import Foundation
import UserNotifications

/// Surveille les seuils critiques et envoie des notifications natives.
///
/// Seuils :
/// - CPU  : > 90 % soutenu pendant 60 s (évite les pics normaux de compilation, etc.)
/// - RAM  : > 92 % utilisée
/// - SSD  : > 90 % plein
///
/// Un délai de silence (cooldown) évite le spam : une même alerte ne se répète
/// pas avant 15 minutes.
final class AlertEngine {
    private let cpuThreshold = 0.90
    private let cpuSustain: TimeInterval = 60
    private let ramThreshold = 0.92
    private let diskThreshold = 0.90
    private let cooldown: TimeInterval = 15 * 60

    private var cpuHighSince: Date?
    private var lastNotified: [String: Date] = [:]

    /// UNUserNotificationCenter exige un vrai bundle .app : sur un binaire nu
    /// (`swift run`), l'API n'est pas disponible et ferait planter le process.
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    /// À appeler à chaque échantillon.
    func check(_ snap: SystemSnapshot, now: Date = Date()) {
        guard available, Preferences.shared.alertsEnabled else { return }

        // CPU : seuil + durée soutenue.
        if snap.cpuUsage > cpuThreshold {
            if let since = cpuHighSince {
                if now.timeIntervalSince(since) >= cpuSustain {
                    notify(key: "cpu",
                           title: "CPU élevé",
                           body: "Le CPU est à \(Fmt.percent(snap.cpuUsage)) depuis plus d'une minute.",
                           now: now)
                }
            } else {
                cpuHighSince = now
            }
        } else {
            cpuHighSince = nil
        }

        // Mémoire.
        if snap.memUsedRatio > ramThreshold {
            notify(key: "ram",
                   title: "Mémoire presque saturée",
                   body: "\(Fmt.percent(snap.memUsedRatio)) de la mémoire est utilisée (\(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal))).",
                   now: now)
        }

        // Disque.
        if snap.diskUsedRatio > diskThreshold {
            let free = snap.diskTotal > snap.diskUsed ? snap.diskTotal - snap.diskUsed : 0
            notify(key: "disk",
                   title: "SSD presque plein",
                   body: "Il ne reste que \(Fmt.bytes(free)) d'espace libre (\(Fmt.percent(snap.diskUsedRatio)) utilisé).",
                   now: now)
        }
    }

    private func notify(key: String, title: String, body: String, now: Date) {
        // Cooldown par type d'alerte.
        if let last = lastNotified[key], now.timeIntervalSince(last) < cooldown { return }
        lastNotified[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "msm.\(key).\(now.timeIntervalSince1970)",
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
