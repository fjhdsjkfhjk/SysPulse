import AppKit

/// 菜单栏自定义视图：固定宽度 + 全等宽字体 + 手绘文本，数字变化时图标不跳动、箭头不被裁切。
/// - CPU 模式：单行 "17%"
/// - 网速模式：两行，上行 "↑1.2MB/s"（上传），下行 "↓0.3KB/s"（下载）
final class StatusItemView: NSView {
    var onClick: (() -> Void)?

    private var mode: MonitorModel.MenuBarMode = .cpu
    private var cpuText = "—"
    private var uploadText = ""
    private var downloadText = ""

    private let font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    /// 箭头与数值之间的小间距
    private let arrowGap: CGFloat = 3.5
    private var attrs: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    func render(mode: MonitorModel.MenuBarMode, cpu: String, upload: String, download: String) {
        self.mode = mode
        self.cpuText = cpu
        self.uploadText = upload
        self.downloadText = download

        let width: CGFloat
        switch mode {
        case .cpu:
            width = measure("100%") + 8
        case .net:
            width = 2 + measure("↓") + arrowGap + measure("888M/s") + 2   // 固定宽度：最多 3 位数字 + 单位
        }
        frame = NSRect(x: 0, y: 0, width: width, height: 22)
        needsDisplay = true
    }

    private func measure(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: attrs).width
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let a = attrs

        switch mode {
        case .cpu:
            let s = NSAttributedString(string: cpuText, attributes: a)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                               y: (bounds.height - sz.height) / 2))

        case .net:
            // 箭头和数值分开画，保留一小段间距
            let upArrow = NSAttributedString(string: "↑", attributes: a)
            let upValue = NSAttributedString(string: uploadText, attributes: a)
            let downArrow = NSAttributedString(string: "↓", attributes: a)
            let downValue = NSAttributedString(string: downloadText, attributes: a)

            let lineH = upValue.size().height
            let arrowW = upArrow.size().width
            let valueX = 2 + arrowW + arrowGap

            let blockH = lineH * 2
            let bottomY = (bounds.height - blockH) / 2
            let topY = bottomY + lineH

            upArrow.draw(at: NSPoint(x: 2, y: topY))
            upValue.draw(at: NSPoint(x: valueX, y: topY))
            downArrow.draw(at: NSPoint(x: 2, y: bottomY))
            downValue.draw(at: NSPoint(x: valueX, y: bottomY))
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
