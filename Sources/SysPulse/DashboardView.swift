import SwiftUI

// MARK: - 折线图

struct Sparkline: View {
    let values: [Double]
    var color: Color = .blue
    /// 固定上限（如 CPU=1.0）；nil 则自动用序列最大值
    var fixedMax: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let maxV = max(fixedMax ?? values.max() ?? 1.0, 0.0001)
            ZStack {
                Rectangle()
                    .fill(color.opacity(0.12))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Path { p in
                    guard values.count >= 2, geo.size.width > 0, geo.size.height > 0 else { return }
                    for (i, v) in values.enumerated() {
                        let clamped = min(max(v, 0), maxV)
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * CGFloat(1 - clamped / maxV)
                        let pt = CGPoint(x: x, y: y)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - 条形图

struct GaugeBar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 7)
    }
}

// MARK: - 仪表盘

struct DashboardView: View {
    @ObservedObject var model: MonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            cpuSection
            memorySection
            diskSection
            batterySection
            networkSection
            gpuSection

            Divider()

            settingsSection
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Text("SysPulse").font(.headline)
            Spacer()
            Text("本地 · 零遥测")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("CPU").foregroundStyle(.secondary)
                Spacer()
                Text(pct(model.snapshot.cpuUsage)).font(.system(.title3, design: .rounded)).bold().monospacedDigit()
            }
            Sparkline(values: model.cpuHistory, color: .blue, fixedMax: 1.0).frame(height: 30)
            Text("用户 \(pct(model.snapshot.cpuUser)) · 系统 \(pct(model.snapshot.cpuSystem))")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("内存").foregroundStyle(.secondary)
                Spacer()
                Text("\(mem(model.snapshot.memoryUsed)) / \(mem(model.snapshot.memoryTotal))")
                    .monospacedDigit()
            }
            GaugeBar(fraction: model.snapshot.memoryTotal > 0
                     ? Double(model.snapshot.memoryUsed) / Double(model.snapshot.memoryTotal) : 0,
                     color: .purple)
            Text(pct(model.snapshot.memoryTotal > 0
                     ? Double(model.snapshot.memoryUsed) / Double(model.snapshot.memoryTotal) : 0))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("磁盘").foregroundStyle(.secondary)
                Spacer()
                Text("\(disk(model.snapshot.diskUsed)) / \(disk(model.snapshot.diskTotal))").monospacedDigit()
            }
            GaugeBar(fraction: model.snapshot.diskTotal > 0
                     ? Double(model.snapshot.diskUsed) / Double(model.snapshot.diskTotal) : 0,
                     color: .indigo)
            Text(pct(model.snapshot.diskTotal > 0
                     ? Double(model.snapshot.diskUsed) / Double(model.snapshot.diskTotal) : 0))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var batterySection: some View {
        let p = model.snapshot.batteryPercent
        let detail = batteryDetail()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("电池").foregroundStyle(.secondary)
                Spacer()
                Text(p.map { "\($0)%" } ?? "无").monospacedDigit()
            }
            if let p {
                GaugeBar(fraction: Double(p) / 100.0, color: .green)
                if !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func batteryDetail() -> String {
        var parts: [String] = []
        if let st = model.snapshot.batteryState, !st.isEmpty { parts.append(st) }
        if let h = model.snapshot.batteryHealth { parts.append(h) }
        if let c = model.snapshot.batteryCycles { parts.append("循环 \(c)") }
        if let m = model.snapshot.batteryMinutesRemaining, m > 0 {
            parts.append(timeString(minutes: m))
        }
        return parts.joined(separator: " · ")
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("网络").foregroundStyle(.secondary)
                Spacer()
                Text(model.snapshot.ssid ?? "未连接 WiFi").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                netColumn(label: "下载", rate: model.snapshot.rxBytesPerSec,
                          history: model.rxHistory, color: .green)
                netColumn(label: "上传", rate: model.snapshot.txBytesPerSec,
                          history: model.txHistory, color: .orange)
            }
        }
    }

    private func netColumn(label: String, rate: Double, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(MonitorModel.rateString(rate)).font(.caption).monospacedDigit()
            }
            Sparkline(values: history, color: color).frame(height: 18)
        }
    }

    private var gpuSection: some View {
        HStack {
            Text("GPU").foregroundStyle(.secondary)
            Spacer()
            Text(model.snapshot.gpuNames.isEmpty ? "未知" : model.snapshot.gpuNames.joined(separator: " · "))
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("菜单栏显示").font(.caption).foregroundStyle(.secondary)
                Picker("菜单栏显示", selection: $model.menuBarMode) {
                    ForEach(MonitorModel.MenuBarMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Text("刷新间隔").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("刷新间隔", selection: $model.interval) {
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                    Text("30 秒").tag(30.0)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            HStack {
                Spacer()
                Button("退出 SysPulse") { NSApp.terminate(nil) }
            }
        }
    }

    // MARK: - 格式化

    private func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
    private func mem(_ v: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .memory)
    }
    private func disk(_ v: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
    }
    private func timeString(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h) 小时 \(m) 分" : "\(m) 分钟"
    }
}
