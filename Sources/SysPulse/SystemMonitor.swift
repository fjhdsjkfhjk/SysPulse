import Foundation
import Darwin
import IOKit
import IOKit.ps
import CoreWLAN

/// 一次采样得到的系统状态快照。全部为本地读取，无任何网络上传。
struct SystemSnapshot {
    var cpuUsage: Double = 0        // 0...1
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var memoryUsed: UInt64 = 0      // bytes
    var memoryTotal: UInt64 = 0
    var diskUsed: UInt64 = 0
    var diskTotal: UInt64 = 0
    var batteryPercent: Int?
    var batteryState: String?       // "充电中" / "已充满" / "电源供电" / "电池供电"
    var batteryHealth: String?
    var batteryCycles: Int?
    var batteryMinutesRemaining: Int?
    var primaryIP: String?
    var ssid: String?
    var gpuNames: [String]
    var rxBytesPerSec: Double = 0
    var txBytesPerSec: Double = 0
}

/// 纯本地系统信息采集器。
/// 只调用系统公开 API，不做任何网络请求、不采集任何可标识个人的数据。
final class SystemMonitor {
    private var lastCPUTicks: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var lastNet: (rx: UInt64, tx: UInt64, date: Date)?

    func snapshot() -> SystemSnapshot {
        var snap = SystemSnapshot(gpuNames: [])

        // --- CPU ---
        if let ticks = readCPUTicks() {
            if let last = lastCPUTicks {
                let userD = diff(ticks.user, last.user)
                let sysD = diff(ticks.system, last.system)
                let idleD = diff(ticks.idle, last.idle)
                let niceD = diff(ticks.nice, last.nice)
                let total = userD + sysD + idleD + niceD
                if total > 0 {
                    snap.cpuUser = userD / total
                    snap.cpuSystem = sysD / total
                    snap.cpuUsage = 1.0 - (idleD / total)
                }
            }
            lastCPUTicks = ticks
        }

        // --- 内存 ---
        if let mem = readMemory() {
            snap.memoryUsed = mem.used
            snap.memoryTotal = mem.total
        }

        // --- 磁盘 ---
        if let disk = readDisk() {
            snap.diskUsed = disk.used
            snap.diskTotal = disk.total
        }

        // --- 电池 ---
        if let battery = readBattery() {
            snap.batteryPercent = battery.percent
            snap.batteryState = battery.state
            snap.batteryHealth = battery.health
            snap.batteryCycles = battery.cycles
            snap.batteryMinutesRemaining = battery.minutesRemaining
        }

        // --- 网络 ---
        snap.primaryIP = readPrimaryIP()
        snap.ssid = readSSID()

        if let counters = readNetworkCounters() {
            let now = Date()
            if let last = lastNet {
                let dt = now.timeIntervalSince(last.date)
                if dt > 0 {
                    snap.rxBytesPerSec = Double(diff(counters.rx, last.rx)) / dt
                    snap.txBytesPerSec = Double(diff(counters.tx, last.tx)) / dt
                }
            }
            lastNet = (counters.rx, counters.tx, now)
        }

        // --- GPU ---
        snap.gpuNames = readGPUNames()

        return snap
    }

    // MARK: - CPU

    private func readCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &load) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks = (user, system, idle, nice)
        return (UInt64(load.cpu_ticks.0), UInt64(load.cpu_ticks.1),
                UInt64(load.cpu_ticks.2), UInt64(load.cpu_ticks.3))
    }

    // MARK: - 内存

    private func readMemory() -> (used: UInt64, total: UInt64)? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return (used, total)
    }

    // MARK: - 磁盘

    private func readDisk() -> (used: UInt64, total: UInt64)? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return nil }
        let total64 = UInt64(total)
        let available64 = UInt64(available)
        return (total64 - available64, total64)
    }

    // MARK: - 电池

    private func readBattery() -> (percent: Int, state: String, health: String?, cycles: Int?, minutesRemaining: Int?)? {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source).takeUnretainedValue() as? [String: Any],
                  let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 0
            let percent = max > 0 ? Int(Double(current) / Double(max) * 100) : 0
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let charged = desc["Is Charged"] as? Bool ?? false
            let external = desc["External Connected"] as? Bool ?? false

            let state: String
            if charging { state = "充电中" }
            else if charged { state = "已充满" }
            else if external { state = "电源供电" }
            else { state = "电池供电" }

            let minutesRemaining: Int?
            if charging {
                minutesRemaining = desc["Time to Full Charge"] as? Int
            } else {
                minutesRemaining = desc["Time to Empty"] as? Int
            }

            // 循环次数与最大容量在 AppleSmartBattery 节点（独立于电源源）
            let smart = readSmartBattery()
            let health: String? = smart.maxCapacityPercent.map { "最大容量 \($0)%" }
            let cycles = smart.cycles
            return (percent, state, health, cycles, minutesRemaining)
        }
        return nil
    }

    /// 读取 AppleSmartBattery：循环次数、归一化最大容量（100 = 满设计容量）。
    private func readSmartBattery() -> (cycles: Int?, maxCapacityPercent: Int?) {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("AppleSmartBattery"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return (nil, nil)
        }
        defer { IOObjectRelease(iterator) }

        var obj = IOIteratorNext(iterator)
        while obj != 0 {
            defer { obj = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            let kr = IORegistryEntryCreateCFProperties(obj, &props, kCFAllocatorDefault, 0)
            guard kr == KERN_SUCCESS, let dict = props?.takeRetainedValue() as? [String: Any] else {
                IOObjectRelease(obj)
                continue
            }
            let cycles = dict["CycleCount"] as? Int
            let max = dict["MaxCapacity"] as? Int
            IOObjectRelease(obj)
            return (cycles, max)
        }
        return (nil, nil)
    }

    // MARK: - 网络 IP

    private func readPrimaryIP() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var preferred: (name: String, ip: String)?
        var fallback: String?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            defer { cursor = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr else { continue }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard Int32(addr.pointee.sa_family) == AF_INET else { continue }

            let ifname = String(cString: cur.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let ip = String(cString: host)

            // 优先真实物理网卡 (en0 / en1)，其次其它
            if ifname == "en0" { preferred = (ifname, ip) }
            else if preferred == nil && ifname.hasPrefix("en") { preferred = (ifname, ip) }
            else if fallback == nil { fallback = ip }
        }
        return preferred?.ip ?? fallback
    }

    // MARK: - WiFi SSID

    private func readSSID() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    // MARK: - 网速

    private func readNetworkCounters() -> (rx: UInt64, tx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = cursor {
            defer { cursor = cur.pointee.ifa_next }
            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let dataPtr = cur.pointee.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            rx += UInt64(data.ifi_ibytes)
            tx += UInt64(data.ifi_obytes)
        }
        return (rx, tx)
    }

    // MARK: - GPU

    private func readGPUNames() -> [String] {
        var names: [String] = []
        for serviceName in ["IOGPU", "AGXAccelerator", "IOAccelerator"] {
            if let models = gpuModels(matching: serviceName) {
                for m in models where !names.contains(m) {
                    names.append(m)
                }
            }
        }
        if names.isEmpty {
            names = pciDisplayModels()
        }
        return names
    }

    private func gpuModels(matching serviceName: String) -> [String]? {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(serviceName),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var models: [String] = []
        var obj = IOIteratorNext(iterator)
        while obj != 0 {
            defer { obj = IOIteratorNext(iterator) }
            if let model = IORegistryEntryCreateCFProperty(obj, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                models.append(model)
            }
            IOObjectRelease(obj)
        }
        return models.isEmpty ? nil : models
    }

    private func pciDisplayModels() -> [String] {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOPCIDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var models: [String] = []
        var obj = IOIteratorNext(iterator)
        while obj != 0 {
            defer { obj = IOIteratorNext(iterator) }
            // classCode 0x03 = 显示控制器 (0x030000 = VGA, 0x030200 = 3D 等)
            if let classCode = IORegistryEntryCreateCFProperty(obj, "class-code" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
               classCode.count >= 2 {
                let high = classCode[classCode.count - 1]  // 高位字节 = 大类
                if high == 0x03 {
                    if let model = IORegistryEntryCreateCFProperty(obj, "model" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
                        models.append(model)
                    }
                }
            }
            IOObjectRelease(obj)
        }
        return models
    }

    // MARK: - 工具

    /// 无符号差值（防计数回绕，负数按 0 处理）
    private func diff(_ a: UInt64, _ b: UInt64) -> Double {
        if a >= b { return Double(a - b) }
        return 0
    }
}
