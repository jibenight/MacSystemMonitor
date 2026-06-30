import Foundation
import Combine

/// Un point d'historique pour les mini-graphiques.
struct HistorySample: Identifiable {
    let id: Int
    let cpu: Double   // 0...1
    let ram: Double   // 0...1
}

/// Modèle observable : rafraîchit l'instantané système à intervalle régulier.
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var history: [HistorySample] = []

    private var sampleIndex = 0
    private let maxHistory = 40

    private let collector = MetricsCollector()
    private var timer: Timer?
    private let idleInterval: TimeInterval    // menu fermé : cadence ralentie
    private let activeInterval: TimeInterval  // menu ouvert : cadence fluide
    private var detailed = false

    init(idleInterval: TimeInterval = 3.0, activeInterval: TimeInterval = 1.5) {
        self.idleInterval = idleInterval
        self.activeInterval = activeInterval
        // Premier échantillon détaillé : amorce les deltas CPU/réseau et le cache disque/batterie.
        _ = collector.collect(detailed: true)
    }

    func start() {
        refresh()
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Bascule entre mode léger (menu fermé) et détaillé (menu ouvert).
    /// Appelé par l'AppDelegate à l'ouverture/fermeture du popover.
    func setDetailed(_ on: Bool) {
        guard on != detailed else { return }
        detailed = on
        refresh()        // échantillon immédiat dans le bon mode
        scheduleTimer()  // ajuste la cadence
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = detailed ? activeInterval : idleInterval
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Remplit le modèle avec des données d'exemple réalistes (pour la capture d'écran).
    func loadSampleData() {
        var s = SystemSnapshot()
        s.cpuUsage = 0.23
        s.coreCount = 10
        s.cpuPerCore = [0.15, 0.42, 0.10, 0.61, 0.20, 0.35, 0.05, 0.52, 0.25, 0.30]
        s.memTotal = 24 * 1024 * 1024 * 1024
        s.memUsed = UInt64(Double(s.memTotal) * 0.63)
        s.diskTotal = 494 * 1_000_000_000
        s.diskUsed = UInt64(Double(s.diskTotal) * 0.21)
        s.netDown = 1_260_000
        s.netUp = 348_000
        s.hasBattery = true
        s.batteryLevel = 0.87
        s.batteryCharging = false
        s.batteryTimeLeft = 352
        s.topProcesses = [
            ProcInfo(id: 401, name: "Google Chrome", cpu: 18, mem: 1_290_000_000),
            ProcInfo(id: 512, name: "Xcode",         cpu: 12, mem: 2_410_000_000),
            ProcInfo(id: 733, name: "Code Helper",   cpu: 9,  mem: 820_000_000),
            ProcInfo(id: 188, name: "Spotify",       cpu: 4,  mem: 410_000_000),
            ProcInfo(id: 99,  name: "Finder",        cpu: 2,  mem: 305_000_000),
        ]
        snapshot = s

        history = (0..<40).map { i in
            let t = Double(i)
            return HistorySample(id: i,
                                 cpu: 0.22 + 0.16 * sin(t / 3.0) + 0.04 * sin(t / 1.3),
                                 ram: 0.60 + 0.05 * sin(t / 5.0))
        }
    }

    private func refresh() {
        // Exécuté sur la run loop principale → assignation directe.
        let snap = collector.collect(detailed: detailed)
        snapshot = snap

        // Historique glissant pour les mini-graphiques.
        sampleIndex += 1
        history.append(HistorySample(id: sampleIndex, cpu: snap.cpuUsage, ram: snap.memUsedRatio))
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }
}

// MARK: - Formatage

enum Fmt {
    /// Octets → chaîne lisible (Ko, Mo, Go…).
    static func bytes(_ value: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useGB, .useMB, .useKB]
        return f.string(fromByteCount: Int64(value))
    }

    /// Débit réseau → « 1.2 Mo/s ».
    static func rate(_ bytesPerSec: Double) -> String {
        let v = UInt64(max(0, bytesPerSec))
        return bytes(v) + "/s"
    }

    /// 0...1 → « 73 % ».
    static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    /// Minutes → « 2 h 15 ».
    static func minutes(_ mins: Int) -> String {
        guard mins > 0 else { return "—" }
        let h = mins / 60
        let m = mins % 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
}
