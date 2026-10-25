import AppKit
import SwiftUI
import Combine

// 诊断模式：SYSPULSE_DIAG=1 时打印一次采样并退出。
if ProcessInfo.processInfo.environment["SYSPULSE_DIAG"] == "1" {
    let m = SystemMonitor()
    _ = m.snapshot()
    usleep(1_200_000)
    let s = m.snapshot()
    func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
    func bytes(_ v: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory)
    }
    print("CPU      : \(pct(s.cpuUsage))  (用户 \(pct(s.cpuUser)) · 系统 \(pct(s.cpuSystem)))")
    print("内存     : \(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))")
    print("磁盘     : 已用 \(bytes(s.diskUsed)) / \(bytes(s.diskTotal))")
    print("电池     : \(s.batteryPercent.map(String.init) ?? "无")%  \(s.batteryState ?? "")  \(s.batteryHealth ?? "健康未知")  循环 \(s.batteryCycles.map(String.init) ?? "?")")
    print("本机 IP  : \(s.primaryIP ?? "—")")
    print("WiFi SSID: \(s.ssid ?? "未连接")")
    print(String(format: "网速     : ↓ %.1f KB/s  ↑ %.1f KB/s", s.rxBytesPerSec / 1024, s.txBytesPerSec / 1024))
    print("GPU      : \(s.gpuNames.isEmpty ? "未知" : s.gpuNames.joined(separator: " · "))")
    exit(0)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusView = StatusItemView()
    private let model = MonitorModel()
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏用自定义视图（固定宽度，避免抖动）
        statusItem.view = statusView

        // 弹出窗内容 = SwiftUI 仪表盘
        popover.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        popover.behavior = .transient
        popover.animates = true

        statusView.onClick = { [weak self] in
            self?.togglePopover(nil)
        }

        // 订阅：菜单栏文案 + 悬停提示实时更新
        cancellable = Publishers.CombineLatest(model.$snapshot, model.$menuBarMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] snap, mode in
                guard let self else { return }
                self.statusView.render(
                    mode: mode,
                    cpu: MonitorModel.cpuText(snap),
                    upload: MonitorModel.uploadValue(snap),
                    download: MonitorModel.downloadValue(snap)
                )
                self.statusView.toolTip = self.model.tooltip
            }
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
