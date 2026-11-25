// MuseumReportCanvas.swift
// 年度回顾的版面：同一份画布既放在页面上滚动，也直接渲染成可分享的长图。
// 因此全部用 frame 排版，宽高由 layout(inWidth:) 返回，不依赖 Auto Layout。

import UIKit

final class MuseumReportCanvas: UIView {

    private let report: MuseumReport

    private let eyebrow = UILabel()
    private let yearLabel = UILabel()
    private let summary = UILabel()
    private let divider = UIView()
    private var tiles: [(box: UIView, value: UILabel, caption: UILabel)] = []
    private let topBox = UIView()
    private let topCaption = UILabel()
    private let topValue = UILabel()
    private let monthBox = UIView()
    private let monthCaption = UILabel()
    private let monthValue = UILabel()
    private let footer = UILabel()

    private let padding: CGFloat = 20

    init(report: MuseumReport) {
        self.report = report
        super.init(frame: .zero)
        backgroundColor = RT.canvas
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 内容

    private func build() {
        eyebrow.attributedText = NSAttributedString(
            string: L10n.str("report.eyebrow"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 3.0]
        )

        yearLabel.text = "\(report.year)"
        yearLabel.font = .systemFont(ofSize: 60, weight: .bold)
        yearLabel.textColor = RT.text

        summary.text = report.hasPlayData
            ? L10n.str("report.summary", MuseumReport.durationText(report.secondsThisYear), report.activeDays)
            : L10n.str("report.summary.empty")
        summary.font = RT.Font.body(15)
        summary.textColor = RT.textSecondary
        summary.numberOfLines = 0

        divider.backgroundColor = RT.stroke

        // 没游玩记录时，「0 秒 / 0 天」比留白更刺眼——改成破折号，等有数据再填
        let hasData = report.hasPlayData
        let tileData: [(String, String)] = [
            ("\(report.accessionsThisYear)", L10n.str("report.tile.accessions")),
            (hasData ? MuseumReport.durationText(report.secondsThisYear) : "—",
             L10n.str("report.tile.playtime")),
            (hasData ? "\(report.activeDays)" : "—", L10n.str("report.tile.days")),
            ("\(report.saveCount)", L10n.str("report.tile.saves")),
        ]
        for (value, caption) in tileData {
            let box = UIView()
            box.backgroundColor = RT.surfaceHigh
            box.layer.cornerRadius = 16
            box.layer.cornerCurve = .continuous

            let valueLabel = UILabel()
            valueLabel.text = value
            valueLabel.font = RT.Font.display(26)
            valueLabel.textColor = RT.text
            valueLabel.adjustsFontSizeToFitWidth = true
            valueLabel.minimumScaleFactor = 0.6

            let captionLabel = UILabel()
            captionLabel.text = caption
            captionLabel.font = RT.Font.caption(11)
            captionLabel.textColor = RT.textTertiary

            box.addSubview(valueLabel)
            box.addSubview(captionLabel)
            addSubview(box)
            tiles.append((box, valueLabel, captionLabel))
        }

        style(topBox, caption: topCaption, value: topValue,
              captionText: L10n.str("report.top.caption"),
              valueText: report.topGameName ?? "—",
              accentBackground: true)

        style(monthBox, caption: monthCaption, value: monthValue,
              captionText: L10n.str("report.month.caption"),
              valueText: report.busiestMonth.map {
                  "\(MuseumReport.monthName($0)) · \(MuseumReport.durationText(report.busiestMonthSeconds))"
              } ?? "—",
              accentBackground: false)

        // 没有游玩记录时两张横条卡没有信息量，整块收起
        topBox.isHidden = !hasData
        monthBox.isHidden = !hasData

        // 累计口径单独一行，别和「今年」混在一起
        footer.text = report.sessions > 0
            ? L10n.str("report.footer", report.sessions,
                       MuseumReport.durationText(report.longestSession), report.shelfCount)
            : L10n.str("report.footer.shelf", report.shelfCount)
        footer.font = RT.Font.mono(9.5)
        footer.textColor = RT.textTertiary
        footer.numberOfLines = 0

        [eyebrow, yearLabel, summary, divider, topBox, monthBox, footer].forEach(addSubview)
    }

    private func style(_ box: UIView, caption: UILabel, value: UILabel,
                       captionText: String, valueText: String, accentBackground: Bool) {
        box.backgroundColor = accentBackground ? RT.accentSoft : RT.surfaceHigh
        box.layer.cornerRadius = 18
        box.layer.cornerCurve = .continuous

        caption.text = captionText
        caption.font = RT.Font.mono(9.5)
        caption.textColor = accentBackground ? RT.accent : RT.textTertiary

        value.text = valueText
        value.font = RT.Font.headline(16)
        value.textColor = RT.text
        value.lineBreakMode = .byTruncatingTail

        box.addSubview(caption)
        box.addSubview(value)
    }

    // MARK: - 排版

    /// 返回总高度；调用方据此设置 frame 或滚动内容尺寸
    @discardableResult
    func layout(inWidth width: CGFloat) -> CGFloat {
        let contentW = width - padding * 2
        var y: CGFloat = 28

        eyebrow.frame = CGRect(x: padding, y: y, width: contentW, height: 14)
        y += 14 + 10

        yearLabel.frame = CGRect(x: padding, y: y, width: contentW, height: 72)
        y += 72

        let summaryH = height(summary, width: contentW)
        summary.frame = CGRect(x: padding, y: y, width: contentW, height: summaryH)
        y += summaryH + 20

        divider.frame = CGRect(x: padding, y: y, width: contentW, height: 1)
        y += 1 + 18

        // 2×2 统计格
        let gap: CGFloat = 10
        let tileW = (contentW - gap) / 2
        let tileH: CGFloat = 84
        for (index, tile) in tiles.enumerated() {
            let col = index % 2
            let row = index / 2
            tile.box.frame = CGRect(x: padding + CGFloat(col) * (tileW + gap),
                                    y: y + CGFloat(row) * (tileH + gap),
                                    width: tileW, height: tileH)
            tile.value.frame = CGRect(x: 14, y: 14, width: tileW - 28, height: 34)
            tile.caption.frame = CGRect(x: 14, y: tileH - 26, width: tileW - 28, height: 14)
        }
        y += tileH * 2 + gap + 16

        if !topBox.isHidden {
            y = layoutBar(topBox, caption: topCaption, value: topValue,
                          width: contentW, y: y, height: 66)
            y += 10
        }
        if !monthBox.isHidden {
            y = layoutBar(monthBox, caption: monthCaption, value: monthValue,
                          width: contentW, y: y, height: 66)
            y += 22
        }

        let footerH = height(footer, width: contentW)
        footer.frame = CGRect(x: padding, y: y, width: contentW, height: footerH)
        y += footerH + 28

        return ceil(y)
    }

    private func layoutBar(_ box: UIView, caption: UILabel, value: UILabel,
                           width: CGFloat, y: CGFloat, height boxH: CGFloat) -> CGFloat {
        box.frame = CGRect(x: padding, y: y, width: width, height: boxH)
        caption.frame = CGRect(x: 16, y: 12, width: width - 32, height: 12)
        value.frame = CGRect(x: 16, y: 32, width: width - 32, height: 22)
        return y + boxH
    }

    private func height(_ label: UILabel, width: CGFloat) -> CGFloat {
        label.numberOfLines = 0
        return ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    }

    // MARK: - 导出

    /// 按 3 倍渲染成位图，直接进分享面板
    func renderImage() -> UIImage? {
        let width: CGFloat = 362
        let totalHeight = layout(inWidth: width)
        frame = CGRect(x: 0, y: 0, width: width, height: totalHeight)
        layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: frame.size, format: format)
        return renderer.image { context in
            layer.render(in: context.cgContext)
        }
    }
}
