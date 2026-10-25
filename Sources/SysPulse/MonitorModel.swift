import Foundation
import Combine

/// 采样与设置状态中枢。持有历史趋势、菜单栏显示模式、刷新间隔。
/// 所有数据仅保存在内存中，不落盘（设置除外，存入 UserDefaults）。
final class MonitorModel: ObservableObject {

    enum MenuBarMode: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case net = "网速"
        var id: String { rawValue }
    }

    @Published var snapshot: SystemSnapshot
    @Published var cpuHistory: [Double] = []
    @Published var rxHistory: [Double] = []
    @Published var txHistory: [Double] = []

    @Published var menuBarMode: MenuBarMode {
        didSet {
            UserDefaults.standard.set(menuBarMode.rawValue, forKey: "menuBarMode")
        }
    }

    @Published var interval: Double {
        didSet {
            UserDefaults.standard.set(interval, forKey: "interval")
            restartTimer()
        }
    }

    private let monitor = SystemMonitor()
    private var timer: Timer?
    private let historyLength = 60   // 60 个点，2 秒采样 ≈ 2 分钟

    init() {
        snapshot = SystemSnapshot(gpuNames: [])
        let savedMode = UserDefaults.standard.string(forKey: "menuBarMode")
        menuBarMode = MenuBarMode(rawValue: savedMode ?? "") ?? .cpu
        let savedInterval = UserDefaults.standard.double(forKey: "interval")
        interval = savedInterval > 0 ? savedInterval : 2.0
        startTimer()
        tick()   // 立即采样一次，让界面有初始值
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - 采样

    func tick() {
        let s = monitor.snapshot()
        snapshot = s
        cpuHistory.append(s.cpuUsage)
        rxHistory.append(s.rxBytesPerSec)
        txHistory.append(s.txBytesPerSec)
        cpuHistory = trim(cpuHistory)
        rxHistory = trim(rxHistory)
        txHistory = trim(txHistory)
    }

    private func trim(_ arr: [Double]) -> [Double] {
        arr.count > historyLength ? Array(arr.suffix(historyLength)) : arr
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func restartTimer() {
        startTimer()
    }

    // MARK: - 菜单栏文案（数值部分，箭头由视图单独渲染）

    static func cpuText(_ s: SystemSnapshot) -> String {
        String(format: "%.0f%%", s.cpuUsage * 100)
    }

    /// 上行（上传）数值，无箭头
    static func uploadValue(_ s: SystemSnapshot) -> String {
        compactRate(s.txBytesPerSec)
    }

    /// 下行（下载）数值，无箭头
    static func downloadValue(_ s: SystemSnapshot) -> String {
        compactRate(s.rxBytesPerSec)
    }

    static func compactRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_000_000_000 {
            return numberString(bytesPerSec / 1_000_000_000) + "G/s"
        }
        if bytesPerSec >= 1_000_000 {
            return numberString(bytesPerSec / 1_000_000) + "M/s"
        }
        if bytesPerSec >= 1_000 {
            return numberString(bytesPerSec / 1_000) + "K/s"
        }
        return numberString(bytesPerSec) + "B/s"
    }

    /// 个位数补一位小数（1.0）以填满固定宽度，2~3 位数用整数。
    /// 结果字符数最多 3（如 888 / 16 / 1.0），配合单位始终 <= 6 个字符。
    private static func numberString(_ v: Double) -> String {
        if v < 9.95 { return String(format: "%.1f", v) }
        return String(format: "%.0f", v)
    }

    /// 菜单栏悬停提示的完整摘要
    var tooltip: String {
        let s = snapshot
        var lines: [String] = []
        lines.append(String(format: "CPU：%.0f%%", s.cpuUsage * 100))
        lines.append("内存：\(ByteCountFormatter.string(fromByteCount: Int64(s.memoryUsed), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(s.memoryTotal), countStyle: .memory))")
        lines.append("磁盘：已用 \(ByteCountFormatter.string(fromByteCount: Int64(s.diskUsed), countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: Int64(s.diskTotal), countStyle: .file))")
        if let p = s.batteryPercent {
            lines.append("电池：\(p)% \(s.batteryState ?? "")")
        }
        lines.append(String(format: "上传：%@  下载：%@",
                            Self.rateString(s.txBytesPerSec), Self.rateString(s.rxBytesPerSec)))
        return lines.joined(separator: "\n")
    }

    static func rateString(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1024 * 1024 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / 1024 / 1024)
    }
}
