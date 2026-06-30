import SwiftUI
import Charts

/// Couleur d'une jauge selon le niveau (vert → orange → rouge).
func levelColor(_ ratio: Double) -> Color {
    switch ratio {
    case ..<0.6:  return .green
    case ..<0.85: return .orange
    default:      return .red
    }
}

/// Une ligne de métrique avec libellé, barre de progression et valeur.
private struct MetricBar: View {
    let icon: String
    let title: String
    let ratio: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(levelColor(ratio))
                        .frame(width: max(2, geo.size.width * min(1, ratio)))
                        .animation(.easeOut(duration: 0.4), value: ratio)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Mini-graphique d'historique CPU (orange) + RAM (bleu).
private struct HistoryChart: View {
    let samples: [HistorySample]

    var body: some View {
        Chart {
            ForEach(samples) { s in
                LineMark(x: .value("t", s.id), y: .value("%", s.cpu * 100),
                         series: .value("série", "CPU"))
                    .foregroundStyle(.orange)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", s.id), y: .value("%", s.ram * 100),
                         series: .value("série", "RAM"))
                    .foregroundStyle(.blue)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) {
                AxisGridLine().foregroundStyle(.primary.opacity(0.08))
                AxisValueLabel().font(.system(size: 8))
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 60)
    }
}

/// Grille de mini-barres : une par cœur CPU.
private struct CoreGrid: View {
    let cores: [Double]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(levelColor(v))
                        .frame(height: max(2, 18 * min(1, v)))
                        .animation(.easeOut(duration: 0.3), value: v)
                }
                .frame(height: 18)
            }
        }
    }
}

/// Section repliable avec un titre.
private struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }
}

/// Contenu du menu déroulant.
struct ContentView: View {
    @ObservedObject var monitor: SystemMonitor
    /// En mode capture, les contrôles interactifs sont remplacés par un visuel statique
    /// (ImageRenderer ne rend pas correctement Toggle/Button hors écran).
    var screenshotMode = false

    private var snap: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // En-tête
            HStack {
                Image(systemName: "cpu")
                Text("Moniteur Système")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            // Historique
            HistoryChart(samples: monitor.history)

            MetricBar(
                icon: "cpu",
                title: "CPU",
                ratio: snap.cpuUsage,
                detail: "\(Fmt.percent(snap.cpuUsage)) · \(snap.coreCount) cœurs"
            )

            // Détail par cœur
            if !snap.cpuPerCore.isEmpty {
                CoreGrid(cores: snap.cpuPerCore)
            }

            MetricBar(
                icon: "memorychip",
                title: "Mémoire",
                ratio: snap.memUsedRatio,
                detail: "\(Fmt.bytes(snap.memUsed)) / \(Fmt.bytes(snap.memTotal))"
            )

            MetricBar(
                icon: "internaldrive",
                title: "SSD",
                ratio: snap.diskUsedRatio,
                detail: "\(Fmt.bytes(snap.diskUsed)) / \(Fmt.bytes(snap.diskTotal))"
            )

            // Réseau
            HStack(spacing: 16) {
                Label(Fmt.rate(snap.netDown), systemImage: "arrow.down")
                    .foregroundStyle(.blue)
                Label(Fmt.rate(snap.netUp), systemImage: "arrow.up")
                    .foregroundStyle(.green)
                Spacer()
            }
            .font(.system(size: 12))
            .monospacedDigit()

            // Top processus
            if !snap.topProcesses.isEmpty {
                Divider()
                SectionLabel(text: "Processus les plus gourmands")
                VStack(spacing: 5) {
                    ForEach(snap.topProcesses) { p in
                        HStack(spacing: 8) {
                            Text(p.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("\(Int(p.cpu.rounded()))%")
                                .foregroundStyle(.orange)
                                .frame(width: 38, alignment: .trailing)
                            Text(Fmt.bytes(p.mem))
                                .foregroundStyle(.secondary)
                                .frame(width: 62, alignment: .trailing)
                        }
                        .font(.system(size: 11))
                        .monospacedDigit()
                    }
                }
            }

            // Batterie (si présente)
            if snap.hasBattery {
                Divider()
                HStack {
                    Image(systemName: batteryIcon)
                        .foregroundStyle(snap.batteryCharging ? .green : .primary)
                    Text("Batterie")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Fmt.percent(snap.batteryLevel))\(snap.batteryCharging ? " ⚡︎" : "")")
                        .font(.system(size: 12))
                        .monospacedDigit()
                    if snap.batteryTimeLeft > 0 {
                        Text("· \(Fmt.minutes(snap.batteryTimeLeft))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // Pied : démarrage auto + quitter
            HStack {
                if screenshotMode {
                    Text("Lancer au démarrage")
                        .font(.system(size: 11))
                    // Faux interrupteur statique (off)
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 26, height: 15)
                        .overlay(Circle().fill(.white).padding(1.5), alignment: .leading)
                    Spacer()
                    Text("Quitter")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    Toggle(isOn: Binding(
                        get: { LoginItem.isEnabled },
                        set: { LoginItem.set($0) }
                    )) {
                        Text("Lancer au démarrage")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    Spacer()

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quitter")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var batteryIcon: String {
        if snap.batteryCharging { return "battery.100.bolt" }
        switch snap.batteryLevel {
        case ..<0.15: return "battery.0"
        case ..<0.4:  return "battery.25"
        case ..<0.65: return "battery.50"
        case ..<0.9:  return "battery.75"
        default:      return "battery.100"
        }
    }
}
