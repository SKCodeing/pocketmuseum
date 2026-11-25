// CuratorOnboardingView.swift
// 首启策展导览：接在入仓动画之后，三屏讲清「这是一座博物馆」——
// 展签（每张卡的身份）、时光轴（存档可回溯）、年报（这一年攒下了什么）。
// 只在第一次启动出现；自动化启动参数下自动跳过，别挡住截图。

import UIKit

final class CuratorOnboardingView: UIView {

    /// 看过一次就不再打扰
    static let storageKey = "museum_onboarding_v1"

    static var hasBeenSeen: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey) }
    }

    static var shouldSkip: Bool {
        let args = ProcessInfo.processInfo.arguments
        // 取证时用 -showCurator 强制出现
        if args.contains("-showCurator") { return false }
        let automation = ["-skipIntro", "-shot", "-captureShots", "-openROM", "-makeHistory",
                          "-openExhibit", "-openReport", "-seedStats"]
        if automation.contains(where: { args.contains($0) }) { return true }
        return hasBeenSeen
    }

    /// 挂在根容器上，铺满全屏淡入
    static func present(in host: UIViewController) {
        let view = CuratorOnboardingView()
        host.view.addSubview(view)
        view.pinEdges(to: host.view)
        view.alpha = 0
        UIView.animate(withDuration: 0.36, delay: 0, options: [.curveEaseOut]) {
            view.alpha = 1
        }
    }

    // MARK: - 子视图

    private let scrollView = UIScrollView()
    private var pages: [PageView] = []
    private let dotsStack = UIStackView()
    private let primaryButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)

    private var pageIndex = 0

    // MARK: - 初始化

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RT.canvas
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        scrollView.translatesAutoresizingMaskIntoConstraints = true
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        addSubview(scrollView)

        let content: [(eyebrow: String, title: String, body: String, artwork: UIView)] = [
            (L10n.str("onboarding.1.eyebrow"), L10n.str("onboarding.1.title"),
             L10n.str("onboarding.1.body"), Self.labelArtwork()),
            (L10n.str("onboarding.2.eyebrow"), L10n.str("onboarding.2.title"),
             L10n.str("onboarding.2.body"), Self.timelineArtwork()),
            (L10n.str("onboarding.3.eyebrow"), L10n.str("onboarding.3.title"),
             L10n.str("onboarding.3.body"), Self.reportArtwork()),
        ]
        for item in content {
            let page = PageView(artwork: item.artwork, eyebrow: item.eyebrow,
                                title: item.title, body: item.body)
            scrollView.addSubview(page)
            pages.append(page)
        }

        dotsStack.axis = .horizontal
        dotsStack.spacing = 7
        dotsStack.alignment = .center
        for _ in pages {
            let dot = UIView()
            dot.layer.cornerRadius = 3
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
            dotsStack.addArrangedSubview(dot)
        }
        addSubview(dotsStack)

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RT.accent
        config.baseForegroundColor = RT.accentInk
        config.cornerStyle = .capsule
        primaryButton.configuration = config
        primaryButton.addAction(UIAction { [weak self] _ in
            self?.advance()
        }, for: .touchUpInside)
        addSubview(primaryButton)

        skipButton.setTitle(L10n.str("onboarding.skip"), for: .normal)
        skipButton.setTitleColor(RT.textTertiary, for: .normal)
        skipButton.titleLabel?.font = RT.Font.caption(13)
        skipButton.addAction(UIAction { [weak self] _ in
            self?.finish()
        }, for: .touchUpInside)
        addSubview(skipButton)

        // 取证用：-curatorPage 2 直接落在第 N 屏
        if let start = Self.debugStartPage, pages.indices.contains(start) {
            pageIndex = start
        }
        refreshControls()
    }

    private static var debugStartPage: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "-curatorPage"), args.indices.contains(flag + 1) else { return nil }
        return Int(args[flag + 1]).map { $0 - 1 }
    }

    // MARK: - 排版

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0 else { return }

        skipButton.sizeToFit()
        skipButton.frame = CGRect(x: width - 20 - skipButton.bounds.width,
                                  y: safeAreaInsets.top + 6,
                                  width: skipButton.bounds.width,
                                  height: 32)

        let buttonH: CGFloat = 52
        let bottomInset = safeAreaInsets.bottom
        primaryButton.frame = CGRect(x: 24,
                                     y: bounds.height - bottomInset - 24 - buttonH,
                                     width: width - 48, height: buttonH)

        dotsStack.sizeToFit()
        // UIStackView 的 sizeToFit 在纯 frame 布局里量不准，按间距自己算宽度
        let dotsW = CGFloat(pages.count) * 6 + CGFloat(max(0, pages.count - 1)) * 7
        dotsStack.frame = CGRect(x: (width - dotsW) / 2,
                                 y: primaryButton.frame.minY - 30,
                                 width: dotsW, height: 8)

        let top = safeAreaInsets.top + 52
        let bottom = dotsStack.frame.minY - 20
        scrollView.frame = CGRect(x: 0, y: top, width: width, height: max(0, bottom - top))
        scrollView.contentSize = CGSize(width: width * CGFloat(pages.count),
                                        height: scrollView.bounds.height)

        for (index, page) in pages.enumerated() {
            page.frame = CGRect(x: CGFloat(index) * width, y: 0,
                                width: width, height: scrollView.bounds.height)
            page.layout(inWidth: width)
        }
        scrollView.contentOffset = CGPoint(x: CGFloat(pageIndex) * width, y: 0)
    }

    // MARK: - 翻页

    private func advance() {
        RT.haptic()
        guard pageIndex < pages.count - 1 else {
            finish()
            return
        }
        pageIndex += 1
        scrollView.setContentOffset(CGPoint(x: CGFloat(pageIndex) * bounds.width, y: 0), animated: true)
        refreshControls()
    }

    private func refreshControls() {
        let isLast = pageIndex >= pages.count - 1
        var config = primaryButton.configuration
        config?.attributedTitle = AttributedString(
            L10n.str(isLast ? "onboarding.start" : "onboarding.next"),
            attributes: AttributeContainer([.font: RT.Font.headline(16)])
        )
        config?.image = isLast ? UIImage(systemName: "shippingbox") : nil
        config?.imagePadding = 8
        primaryButton.configuration = config

        for (index, dot) in dotsStack.arrangedSubviews.enumerated() {
            dot.backgroundColor = index == pageIndex ? RT.accent : RT.stroke
            dot.transform = index == pageIndex
                ? CGAffineTransform(scaleX: 1.0, y: 1.0)
                : CGAffineTransform(scaleX: 0.75, y: 0.75)
        }
    }

    private func finish() {
        Self.hasBeenSeen = true
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseInOut]) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
}

// MARK: - 单屏

private final class PageView: UIView {

    private let artwork: UIView
    private let eyebrow = UILabel()
    private let titleLabel = UILabel()
    private let bodyLabel = UILabel()

    private static let artworkSize = CGSize(width: 260, height: 200)

    init(artwork: UIView, eyebrow: String, title: String, body: String) {
        self.artwork = artwork
        super.init(frame: .zero)

        self.eyebrow.attributedText = NSAttributedString(
            string: eyebrow,
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.4]
        )

        titleLabel.text = title
        titleLabel.font = RT.Font.display(26)
        titleLabel.textColor = RT.text
        titleLabel.numberOfLines = 0

        bodyLabel.text = body
        bodyLabel.font = RT.Font.body(15)
        bodyLabel.textColor = RT.textSecondary
        bodyLabel.numberOfLines = 0

        addSubview(artwork)
        addSubview(self.eyebrow)
        addSubview(titleLabel)
        addSubview(bodyLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func layout(inWidth width: CGFloat) {
        let padding: CGFloat = 32
        let contentW = width - padding * 2

        let artW = Self.artworkSize.width
        let artH = Self.artworkSize.height

        let titleH = ceil(titleLabel.sizeThatFits(CGSize(width: contentW, height: .greatestFiniteMagnitude)).height)
        let bodyH = ceil(bodyLabel.sizeThatFits(CGSize(width: contentW, height: .greatestFiniteMagnitude)).height)
        let blockH = artH + 24 + 14 + 10 + titleH + 12 + bodyH

        // 整块在可视区里垂直居中，别让文字顶在上面、下面空一大片
        var y = max(0, (bounds.height - blockH) / 2)
        let artTop = y

        artwork.frame = CGRect(x: (width - artW) / 2, y: artTop, width: artW, height: artH)
        y += artH + 24

        eyebrow.frame = CGRect(x: padding, y: y, width: contentW, height: 14)
        y += 14 + 10

        titleLabel.frame = CGRect(x: padding, y: y, width: contentW, height: titleH)
        y += titleH + 12

        bodyLabel.frame = CGRect(x: padding, y: y, width: contentW, height: bodyH)
    }
}

// MARK: - 三张小插画（同一套设计令牌，尺寸固定 260×200）

private extension CuratorOnboardingView {

    static func panel(_ rect: CGRect, radius: CGFloat, fill: UIColor) -> UIView {
        let view = UIView(frame: rect)
        view.backgroundColor = fill
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = RT.stroke.cgColor
        return view
    }

    static func bar(_ rect: CGRect, color: UIColor) -> UIView {
        let view = UIView(frame: rect)
        view.backgroundColor = color
        view.layer.cornerRadius = rect.height / 2
        return view
    }

    /// 一屏：展签 + 卡带
    static func labelArtwork() -> UIView {
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 260, height: 200))

        let cartridge = RTCartridgeView()
        cartridge.system = .nes
        cartridge.frame = CGRect(x: 168, y: 6, width: 78, height: 92)
        cartridge.transform = CGAffineTransform(rotationAngle: 0.10)
        box.addSubview(cartridge)

        let card = panel(CGRect(x: 4, y: 42, width: 178, height: 122), radius: 18, fill: RT.surface)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        box.addSubview(card)

        let plaque = UILabel(frame: CGRect(x: 16, y: 16, width: 146, height: 12))
        plaque.attributedText = NSAttributedString(
            string: L10n.str("exhibit.eyebrow"),
            attributes: [.font: RT.Font.mono(8, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 1.8]
        )
        card.addSubview(plaque)

        let demoName = ROMLibrary.shared.roms.first?.name ?? "PocketMuseumDemo"
        let name = UILabel(frame: CGRect(x: 16, y: 34, width: 148, height: 20))
        name.text = demoName
        name.font = RT.Font.headline(14)
        name.textColor = RT.text
        card.addSubview(name)

        let hairline = UIView(frame: CGRect(x: 16, y: 62, width: 146, height: 1))
        hairline.backgroundColor = RT.stroke
        card.addSubview(hairline)

        let systemLine = UILabel(frame: CGRect(x: 16, y: 72, width: 146, height: 14))
        systemLine.text = "\(EmulatorSystem.nes.shortCode) · \(EmulatorSystem.nes.launchYear)"
        systemLine.font = RT.Font.mono(9.5)
        systemLine.textColor = RT.textTertiary
        card.addSubview(systemLine)

        let year = Calendar.current.component(.year, from: Date()) % 100
        let number = UILabel(frame: CGRect(x: 16, y: 92, width: 146, height: 14))
        number.text = String(format: "PM-%02d-%04d", year, 1)
        number.font = RT.Font.mono(9.5, weight: .semibold)
        number.textColor = RT.textSecondary
        card.addSubview(number)

        return box
    }

    /// 二屏：存档铺成时间轴
    static func timelineArtwork() -> UIView {
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 260, height: 200))

        let rail = UIView(frame: CGRect(x: 34, y: 18, width: 1, height: 164))
        rail.backgroundColor = RT.stroke
        box.addSubview(rail)

        let rows: [(y: CGFloat, filled: Bool)] = [(30, true), (86, true), (142, false)]
        for row in rows {
            let dot = UIView(frame: CGRect(x: 31, y: row.y + 14, width: 7, height: 7))
            dot.backgroundColor = row.filled ? RT.accent : RT.surfaceHigh
            dot.layer.cornerRadius = 3.5
            dot.layer.borderWidth = row.filled ? 0 : 1
            dot.layer.borderColor = RT.stroke.cgColor
            box.addSubview(dot)

            let card = panel(CGRect(x: 54, y: row.y, width: 190, height: 44), radius: 14, fill: RT.surface)
            box.addSubview(card)

            card.addSubview(bar(CGRect(x: 14, y: 12, width: 76, height: 6),
                                color: row.filled ? RT.textSecondary : RT.stroke))
            // RT.stroke 是「半透明黑」，withAlphaComponent 会把它改成实色，空位另取浅色
            card.addSubview(bar(CGRect(x: 14, y: 26, width: 46, height: 5),
                                color: row.filled ? RT.stroke : RT.textTertiary.withAlphaComponent(0.28)))
            let badge = bar(CGRect(x: 148, y: 14, width: 28, height: 14),
                            color: row.filled ? RT.accent.withAlphaComponent(0.16)
                                              : RT.textTertiary.withAlphaComponent(0.14))
            card.addSubview(badge)
        }

        return box
    }

    /// 三屏：一页年报
    static func reportArtwork() -> UIView {
        let box = UIView(frame: CGRect(x: 0, y: 0, width: 260, height: 200))

        let card = panel(CGRect(x: 24, y: 6, width: 212, height: 188), radius: 20, fill: RT.surface)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowRadius = 12
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        box.addSubview(card)

        let eyebrow = UILabel(frame: CGRect(x: 22, y: 22, width: 168, height: 10))
        eyebrow.attributedText = NSAttributedString(
            string: L10n.str("report.eyebrow"),
            attributes: [.font: RT.Font.mono(8, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 1.8]
        )
        card.addSubview(eyebrow)

        let year = UILabel(frame: CGRect(x: 20, y: 36, width: 168, height: 44))
        year.text = "\(Calendar.current.component(.year, from: Date()))"
        year.font = .systemFont(ofSize: 38, weight: .bold)
        year.textColor = RT.text
        card.addSubview(year)

        card.addSubview(bar(CGRect(x: 22, y: 94, width: 142, height: 7), color: RT.accent))
        card.addSubview(bar(CGRect(x: 22, y: 110, width: 112, height: 7), color: RT.surfaceHigh))
        card.addSubview(bar(CGRect(x: 22, y: 126, width: 84, height: 7), color: RT.surfaceHigh))

        for index in 0..<2 {
            let tile = UIView(frame: CGRect(x: 22 + CGFloat(index) * 88, y: 146, width: 80, height: 28))
            tile.backgroundColor = RT.surfaceHigh
            tile.layer.cornerRadius = 10
            tile.layer.cornerCurve = .continuous
            card.addSubview(tile)
        }

        return box
    }
}

// MARK: - 翻页回调

extension CuratorOnboardingView: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard bounds.width > 0 else { return }
        let index = Int(round(scrollView.contentOffset.x / bounds.width))
        guard index != pageIndex, pages.indices.contains(index) else { return }
        pageIndex = index
        refreshControls()
    }
}
