import Foundation
import Darwin

/// Un processus avec sa conso instantanée.
struct ProcInfo: Identifiable {
    let id: Int32        // PID
    let name: String
    let cpu: Double      // % d'un cœur (peut dépasser 100 % sur du multithread)
    let mem: UInt64      // mémoire résidente (octets)
}

/// Échantillonne les processus via `libproc` et calcule le %CPU instantané (delta de temps CPU).
final class ProcessSampler {
    private var prevCPU: [Int32: UInt64] = [:]   // pid -> temps CPU cumulé (ns)
    private var prevTime: Date?

    /// Retourne les `limit` processus les plus gourmands en CPU.
    /// Remarque : `proc_pid_rusage` n'autorise que les processus de l'utilisateur courant
    /// (les processus root comme kernel_task/WindowServer sont ignorés).
    func sample(limit: Int = 5) -> [ProcInfo] {
        let maxPids = 8192
        var pids = [pid_t](repeating: 0, count: maxPids)
        let bufSize = Int32(maxPids * MemoryLayout<pid_t>.size)
        let returned = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, bufSize)
        guard returned > 0 else { return [] }
        let count = Int(returned) / MemoryLayout<pid_t>.size

        let now = Date()
        let dt = prevTime.map { now.timeIntervalSince($0) } ?? 0
        var newPrev: [Int32: UInt64] = [:]
        var results: [ProcInfo] = []

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var ru = rusage_info_v2()
            let rc = withUnsafeMutablePointer(to: &ru) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard rc == 0 else { continue } // EPERM (autre utilisateur) → on ignore

            let cpuNs = ru.ri_user_time + ru.ri_system_time
            newPrev[pid] = cpuNs

            var cpuPct = 0.0
            if dt > 0, let prev = prevCPU[pid], cpuNs >= prev {
                cpuPct = (Double(cpuNs - prev) / 1_000_000_000.0) / dt * 100.0
            }

            var nameBuf = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuf, UInt32(nameBuf.count))
            let name = String(cString: nameBuf)

            results.append(ProcInfo(id: pid,
                                    name: name.isEmpty ? "pid \(pid)" : name,
                                    cpu: cpuPct,
                                    mem: ru.ri_resident_size))
        }

        prevCPU = newPrev
        prevTime = now

        return Array(results.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }
}
