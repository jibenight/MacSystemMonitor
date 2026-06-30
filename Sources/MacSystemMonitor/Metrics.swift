import Foundation
import Darwin
import IOKit.ps

/// Instantané de toutes les métriques système à un instant T.
struct SystemSnapshot {
    var cpuUsage: Double = 0            // 0...1 (charge globale)
    var cpuPerCore: [Double] = []       // 0...1 par cœur
    var coreCount: Int = 0

    var memUsed: UInt64 = 0             // octets
    var memTotal: UInt64 = 1
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memActive: UInt64 = 0
    var memPressure: Double = 0         // 0...1

    var diskUsed: UInt64 = 0            // octets
    var diskTotal: UInt64 = 1

    var netDown: Double = 0             // octets / seconde
    var netUp: Double = 0              // octets / seconde

    var hasBattery: Bool = false
    var batteryLevel: Double = 0        // 0...1
    var batteryCharging: Bool = false
    var batteryTimeLeft: Int = -1       // minutes, -1 = inconnu

    var topProcesses: [ProcInfo] = []   // top conso CPU (rempli en mode détaillé)

    var memUsedRatio: Double { memTotal == 0 ? 0 : Double(memUsed) / Double(memTotal) }
    var diskUsedRatio: Double { diskTotal == 0 ? 0 : Double(diskUsed) / Double(diskTotal) }
}

/// Collecte bas-niveau des métriques via les API Darwin (Mach), IOKit et le système de fichiers.
final class MetricsCollector {

    // État précédent pour calculer les deltas (CPU = compteurs cumulatifs).
    private var prevCPUTicks: [UInt32] = []
    private var prevCoreTicks: [[UInt32]] = []

    // État réseau précédent pour calculer le débit.
    private var prevNetIn: UInt64 = 0
    private var prevNetOut: UInt64 = 0
    private var prevNetTime: Date?

    // Cache des métriques « lourdes » (disque, batterie) : appels système plus coûteux,
    // sans variation rapide → on ne les relit qu'en mode détaillé et on réutilise sinon.
    private var cachedDiskUsed: UInt64 = 0
    private var cachedDiskTotal: UInt64 = 1
    private var cachedBattery = (has: false, level: 0.0, charging: false, time: -1)

    private let procSampler = ProcessSampler()

    // MARK: - Point d'entrée

    /// `detailed` = false : mode léger (menu fermé) — on saute disque/batterie (servis depuis le cache).
    /// `detailed` = true  : tout est rafraîchi (menu ouvert).
    func collect(detailed: Bool) -> SystemSnapshot {
        var snap = SystemSnapshot()
        // Toujours collecté (peu coûteux, et nécessaire aux deltas continus) :
        readCPU(&snap)
        readMemory(&snap)
        readNetwork(&snap)

        if detailed {
            readDisk(&snap)
            readBattery(&snap)
            snap.topProcesses = procSampler.sample(limit: 5)
            // Mise à jour du cache.
            cachedDiskUsed = snap.diskUsed
            cachedDiskTotal = snap.diskTotal
            cachedBattery = (snap.hasBattery, snap.batteryLevel, snap.batteryCharging, snap.batteryTimeLeft)
        } else {
            // Réutilise les dernières valeurs connues (affichage toujours complet, sans le coût).
            snap.diskUsed = cachedDiskUsed
            snap.diskTotal = cachedDiskTotal
            snap.hasBattery = cachedBattery.has
            snap.batteryLevel = cachedBattery.level
            snap.batteryCharging = cachedBattery.charging
            snap.batteryTimeLeft = cachedBattery.time
        }
        return snap
    }

    // MARK: - CPU

    /// Charge CPU globale + par cœur, via host_processor_info (compteurs de ticks cumulatifs).
    private func readCPU(_ snap: inout SystemSnapshot) {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                         PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount,
                                         &infoArray,
                                         &infoCount)
        guard result == KERN_SUCCESS, let info = infoArray else { return }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        snap.coreCount = Int(cpuCount)
        let statesPerCPU = Int(CPU_STATE_MAX) // user, system, idle, nice

        var coreTicks: [[UInt32]] = []
        var totals = [UInt32](repeating: 0, count: statesPerCPU)

        for i in 0..<Int(cpuCount) {
            let base = i * statesPerCPU
            var states = [UInt32](repeating: 0, count: statesPerCPU)
            for s in 0..<statesPerCPU {
                let v = UInt32(bitPattern: info[base + s])
                states[s] = v
                totals[s] &+= v
            }
            coreTicks.append(states)
        }

        // Charge par cœur (delta vs échantillon précédent).
        if prevCoreTicks.count == coreTicks.count {
            snap.cpuPerCore = zip(coreTicks, prevCoreTicks).map { usage(cur: $0, prev: $1) }
        } else {
            snap.cpuPerCore = coreTicks.map { _ in 0 }
        }

        // Charge globale.
        if !prevCPUTicks.isEmpty {
            snap.cpuUsage = usage(cur: totals, prev: prevCPUTicks)
        }

        prevCoreTicks = coreTicks
        prevCPUTicks = totals
    }

    /// Calcule (busy / total) à partir des deltas de ticks. Index 2 = CPU_STATE_IDLE.
    private func usage(cur: [UInt32], prev: [UInt32]) -> Double {
        guard cur.count >= 4, prev.count >= 4 else { return 0 }
        var totalDelta: Double = 0
        var idleDelta: Double = 0
        for s in 0..<4 {
            let d = Double(cur[s] &- prev[s])
            totalDelta += d
            if s == Int(CPU_STATE_IDLE) { idleDelta = d }
        }
        guard totalDelta > 0 else { return 0 }
        return max(0, min(1, (totalDelta - idleDelta) / totalDelta))
    }

    // MARK: - Mémoire

    private func readMemory(_ snap: inout SystemSnapshot) {
        // Total physique via sysctl.
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)
        snap.memTotal = total

        // Statistiques VM.
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active     = UInt64(stats.active_count) * pageSize
        let wired      = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize

        snap.memActive = active
        snap.memWired = wired
        snap.memCompressed = compressed
        // Approximation « Mémoire utilisée » d'Activity Monitor : actif + câblé + compressé.
        snap.memUsed = active + wired + compressed
        snap.memPressure = total == 0 ? 0 : Double(wired + compressed) / Double(total)
    }

    // MARK: - Disque (SSD)

    private func readDisk(_ snap: inout SystemSnapshot) {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        if let values = try? url.resourceValues(forKeys: keys),
           let totalCap = values.volumeTotalCapacity {
            let total = UInt64(totalCap)
            let available = UInt64(values.volumeAvailableCapacityForImportantUsage ?? 0)
            snap.diskTotal = total
            snap.diskUsed = total > available ? total - available : 0
        }
    }

    // MARK: - Réseau

    /// Débit montant/descendant via les compteurs d'octets des interfaces (getifaddrs / AF_LINK).
    private func readNetwork(_ snap: inout SystemSnapshot) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        var ptr = ifaddrPtr
        while let cur = ptr {
            let ifa = cur.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK) {
                let name = String(cString: ifa.ifa_name)
                // On ignore le loopback.
                if !name.hasPrefix("lo"), let dataPtr = ifa.ifa_data {
                    let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                    totalIn  &+= UInt64(data.ifi_ibytes)
                    totalOut &+= UInt64(data.ifi_obytes)
                }
            }
            ptr = ifa.ifa_next
        }

        let now = Date()
        if let prevTime = prevNetTime {
            let dt = now.timeIntervalSince(prevTime)
            if dt > 0 {
                // Les compteurs sont 32 bits et peuvent boucler ; on évite les valeurs négatives.
                let inDelta  = totalIn  >= prevNetIn  ? totalIn  - prevNetIn  : 0
                let outDelta = totalOut >= prevNetOut ? totalOut - prevNetOut : 0
                snap.netDown = Double(inDelta) / dt
                snap.netUp   = Double(outDelta) / dt
            }
        }
        prevNetIn = totalIn
        prevNetOut = totalOut
        prevNetTime = now
    }

    // MARK: - Batterie

    private func readBattery(_ snap: inout SystemSnapshot) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return }

        guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
              let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { return }

        snap.hasBattery = true
        snap.batteryLevel = Double(current) / Double(maxCap)

        if let state = desc[kIOPSPowerSourceStateKey] as? String {
            snap.batteryCharging = (state == kIOPSACPowerValue)
        }
        if let charging = desc[kIOPSIsChargingKey] as? Bool {
            snap.batteryCharging = charging
        }
        if let timeToEmpty = desc[kIOPSTimeToEmptyKey] as? Int, timeToEmpty > 0 {
            snap.batteryTimeLeft = timeToEmpty
        } else if let timeToFull = desc[kIOPSTimeToFullChargeKey] as? Int, timeToFull > 0 {
            snap.batteryTimeLeft = timeToFull
        }
    }
}
