// RetroDesignSystem.swift
// 掌机时光机 · 设计系统
// 视觉母题：掌机博物馆（卡带 / 机身 / 铭牌）＋ 琥珀磷光
// 所有图形均为程序化绘制，不依赖位图素材。

import UIKit

// MARK: - 调色板

struct RTPalette {
    let canvas: UIColor
    let canvasDeep: UIColor
    let surface: UIColor
    let surfaceHigh: UIColor
    let stroke: UIColor
    let text: UIColor
    let textSecondary: UIColor
    let textTertiary: UIColor
    let accent: UIColor
    let accentInk: UIColor
    let accentSoft: UIColor
    let danger: UIColor

    /// 画布是否属于深色主题。控件在主题应用前就被创建时，
    /// 需要靠它决定叠加层的用色（深色加黑、浅色加白）。
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        canvas.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
    }

    static let cathode = RTPalette(
        canvas:       UIColor(hex: 0x0C0E11),
        canvasDeep:   UIColor(hex: 0x07080A),
        surface:      UIColor(hex: 0x16191E),
        surfaceHigh:  UIColor(hex: 0x1F242C),
        stroke:       UIColor(white: 1, alpha: 0.07),
        text:         UIColor(hex: 0xF4F1E8),
        textSecondary: UIColor(hex: 0x9AA4B0),
        textTertiary: UIColor(hex: 0x666F7A),
        accent:       UIColor(hex: 0xF0A63A),
        accentInk:    UIColor(hex: 0x1A1206),
        accentSoft:   UIColor(hex: 0xF0A63A, alpha: 0.16),
        danger:       UIColor(hex: 0xE26A5A)
    )

    static let paper = RTPalette(
        canvas:       UIColor(hex: 0xF5F2EA),
        canvasDeep:   UIColor(hex: 0xEBE7DB),
        surface:      UIColor(hex: 0xFFFFFF),
        surfaceHigh:  UIColor(hex: 0xEFEBE0),
        stroke:       UIColor(white: 0, alpha: 0.07),
        text:         UIColor(hex: 0x17191C),
        textSecondary: UIColor(hex: 0x6A7280),
        textTertiary: UIColor(hex: 0x9AA1AA),
        accent:       UIColor(hex: 0xC0731A),
        accentInk:    UIColor(hex: 0xFFF8EC),
        accentSoft:   UIColor(hex: 0xC0731A, alpha: 0.12),
        danger:       UIColor(hex: 0xC0442F)
    )

    static let phosphor = RTPalette(
        canvas:       UIColor(hex: 0x07100B),
        canvasDeep:   UIColor(hex: 0x040A06),
        surface:      UIColor(hex: 0x0D1A12),
        surfaceHigh:  UIColor(hex: 0x13251A),
        stroke:       UIColor(hex: 0x62E07A, alpha: 0.12),
        text:         UIColor(hex: 0xDDF6E3),
        textSecondary: UIColor(hex: 0x8FB8A0),
        textTertiary: UIColor(hex: 0x5C7A66),
        accent:       UIColor(hex: 0x62E07A),
        accentInk:    UIColor(hex: 0x04160A),
        accentSoft:   UIColor(hex: 0x62E07A, alpha: 0.14),
        danger:       UIColor(hex: 0xE2695B)
    )
}

// MARK: - 设计令牌

enum RT {

    static var palette: RTPalette {
        switch AppThemeManager.shared.current {
        case .light:
            return .paper
        case .retro:
            return .phosphor
        case .dark:
            return .cathode
        case .system:
            return UIScreen.main.traitCollection.userInterfaceStyle == .dark ? .cathode : .paper
        }
    }

    static var canvas: UIColor { palette.canvas }
    static var canvasDeep: UIColor { palette.canvasDeep }
    static var surface: UIColor { palette.surface }
    static var surfaceHigh: UIColor { palette.surfaceHigh }
    static var stroke: UIColor { palette.stroke }
    static var text: UIColor { palette.text }
    static var textSecondary: UIColor { palette.textSecondary }
    static var textTertiary: UIColor { palette.textTertiary }
    static var accent: UIColor { palette.accent }
    static var accentInk: UIColor { palette.accentInk }
    static var accentSoft: UIColor { palette.accentSoft }
    static var danger: UIColor { palette.danger }

    enum Font {
        static func display(_ size: CGFloat = 30) -> UIFont {
            .systemFont(ofSize: size, weight: .bold)
        }
        static func title(_ size: CGFloat = 20) -> UIFont {
            .systemFont(ofSize: size, weight: .semibold)
        }
        static func headline(_ size: CGFloat = 16) -> UIFont {
            .systemFont(ofSize: size, weight: .semibold)
        }
        static func body(_ size: CGFloat = 15) -> UIFont {
            .systemFont(ofSize: size, weight: .regular)
        }
        static func caption(_ size: CGFloat = 12) -> UIFont {
            .systemFont(ofSize: size, weight: .regular)
        }
        static func mono(_ size: CGFloat = 12, weight: UIFont.Weight = .medium) -> UIFont {
            .monospacedSystemFont(ofSize: size, weight: weight)
        }
        /// 铭牌式字距（用于 MUSEUM / SYSTEM CODE）
        static func plaque(_ size: CGFloat = 11) -> UIFont {
            .systemFont(ofSize: size, weight: .semibold)
        }
    }

    enum Metric {
        static let screenPadding: CGFloat = 20
        static let cardRadius: CGFloat = 24
        static let innerRadius: CGFloat = 16
        static let chipRadius: CGFloat = 13
        static let rowGap: CGFloat = 14
        static let sectionGap: CGFloat = 28
        static let tabBarHeight: CGFloat = 62

        /// 内容列宽度上限。窄屏（iPhone）时列宽就等于屏宽，宽屏（iPad 横屏、
        /// 折叠机展开内屏）时把内容收成居中阅读栏，避免一条一列拉满整块屏、
        /// 两侧空出大片空白。
        static let readingColumnMaxWidth: CGFloat = 860

        /// 宽度达到这个值才启用居中列（iPhone 不触发，iPad 竖屏也不触发）
        static let wideScreenThreshold: CGFloat = 900

        /// 居中列在屏幕两侧应留的边距
        static func readingColumnInset(for screenWidth: CGFloat) -> CGFloat {
            guard screenWidth >= wideScreenThreshold else { return 0 }
            return max(0, (screenWidth - readingColumnMaxWidth) / 2)
        }

        /// 当前宽度下内容列的实际宽度
        static func readingColumnWidth(for screenWidth: CGFloat) -> CGFloat {
            min(screenWidth, readingColumnMaxWidth)
        }
    }

    static let themeDidChange = Notification.Name("rt.themeDidChange")

    static func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - 颜色工具

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }

    func lighter(_ amount: CGFloat) -> UIColor { mixed(with: .white, amount: amount) }
    func darker(_ amount: CGFloat) -> UIColor { mixed(with: .black, amount: amount) }
}

// MARK: - 布局工具

extension UIView {
    func addSubviews(_ views: UIView...) {
        views.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
    }

    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func applyCardShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 10)
    }

    func roundCorners(_ radius: CGFloat, continuous: Bool = true) {
        layer.cornerRadius = radius
        layer.cornerCurve = continuous ? .continuous : .circular
        clipsToBounds = true
    }
}

// MARK: - 卡片

final class RTCardView: UIView {

    enum Style { case plain, raised, accent }

    private let cardStyle: Style

    init(style: Style = .plain, radius: CGFloat = RT.Metric.cardRadius) {
        self.cardStyle = style
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = radius
        layer.cornerCurve = .continuous
        clipsToBounds = style != .raised

        switch style {
        case .plain:
            backgroundColor = RT.surface
            layer.borderWidth = 1
            layer.borderColor = RT.stroke.cgColor
        case .raised:
            backgroundColor = RT.surface
            layer.borderWidth = 1
            layer.borderColor = RT.stroke.cgColor
            applyCardShadow()
        case .accent:
            backgroundColor = RT.accentSoft
            layer.borderWidth = 1
            layer.borderColor = RT.accent.withAlphaComponent(0.28).cgColor
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        layer.borderColor = (cardStyle == .accent ? RT.accent.withAlphaComponent(0.28) : RT.stroke).cgColor
    }
}

// MARK: - 胶囊按钮

final class RTPillButton: UIButton {

    private var normalBackground: UIColor = RT.surfaceHigh
    private var selectedBackground: UIColor = RT.accent

    init(title: String = "", icon: String? = nil, selected: Bool = false) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = RT.Metric.chipRadius
        layer.cornerCurve = .continuous

        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14)
        config.attributedTitle = Self.makeTitle(title)
        if let icon = icon {
            config.image = UIImage(systemName: icon, withConfiguration:
                UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            config.imagePadding = 6
        }
        configuration = config
        apply(selected: selected)
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func makeTitle(_ text: String) -> AttributedString {
        AttributedString(text, attributes: AttributeContainer([.font: RT.Font.caption(13)]))
    }

    func apply(selected: Bool) {
        backgroundColor = selected ? selectedBackground : normalBackground
        let foreground = selected ? RT.accentInk : RT.textSecondary
        configuration?.baseForegroundColor = foreground
        titleLabel?.textColor = foreground
    }

    /// 用于「危险」类胶囊（如退出编辑）
    func makeDanger() {
        normalBackground = RT.danger.withAlphaComponent(0.16)
        selectedBackground = RT.danger
    }
}

// MARK: - 玻璃圆钮（游戏内浮层用）

final class RTGlassButton: UIButton {

    init(symbol: String, pointSize: CGFloat = 15) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        widthAnchor.constraint(equalToConstant: 40).isActive = true
        heightAnchor.constraint(equalToConstant: 40).isActive = true
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // overrideUserInterfaceStyle 在窗口挂载后才生效，
        // 而这颗按钮往往在 view controller 属性初始化阶段就建好了，
        // 所以颜色要在这里再套一次，否则会停在建时的旧主题上。
        applyTheme()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            applyTheme()
        }
    }

    private func applyTheme() {
        let palette = RT.palette
        tintColor = palette.text
        if palette.isDark {
            backgroundColor = UIColor(white: 0, alpha: 0.42)
            layer.borderColor = UIColor(white: 1, alpha: 0.14).cgColor
        } else {
            // 浅色画布上黑底会变成一块脏灰，改用白色卡片 + 细描边
            backgroundColor = palette.surface
            layer.borderColor = palette.stroke.cgColor
        }
    }
}

// MARK: - 区块标题

final class RTSectionHeaderView: UIView {

    let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    let actionButton = UIButton(type: .system)

    init(title: String, subtitle: String? = nil, actionTitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = title
        titleLabel.font = RT.Font.title(19)
        titleLabel.textColor = RT.text

        subtitleLabel.text = subtitle
        subtitleLabel.font = RT.Font.caption(12)
        subtitleLabel.textColor = RT.textTertiary
        subtitleLabel.isHidden = subtitle == nil

        actionButton.setTitle(actionTitle, for: .normal)
        actionButton.titleLabel?.font = RT.Font.caption(13)
        actionButton.setTitleColor(RT.accent, for: .normal)
        actionButton.isHidden = actionTitle == nil

        addSubviews(titleLabel, subtitleLabel, actionButton)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: topAnchor),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            bottomAnchor.constraint(equalTo: subtitleLabel.isHidden ? titleLabel.bottomAnchor : subtitleLabel.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - 空状态

final class RTEmptyStateView: UIView {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    /// 行动按钮回调（可在初始化后替换）
    var onAction: (() -> Void)?

    init(icon: String, title: String, message: String, actionTitle: String? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconView.image = UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .light))
        iconView.tintColor = RT.accent.withAlphaComponent(0.8)
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = title
        titleLabel.font = RT.Font.headline(17)
        titleLabel.textColor = RT.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        messageLabel.text = message
        messageLabel.font = RT.Font.body(13)
        messageLabel.textColor = RT.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        addSubviews(iconView, titleLabel, messageLabel)

        var lastAnchor = messageLabel.bottomAnchor
        if let actionTitle = actionTitle {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = RT.accent
            config.baseForegroundColor = RT.accentInk
            config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 26, bottom: 11, trailing: 26)
            config.background.cornerRadius = 22
            config.attributedTitle = AttributedString(
                actionTitle,
                attributes: AttributeContainer([.font: RT.Font.headline(14)])
            )
            actionButton.configuration = config
            actionButton.addTarget(self, action: #selector(tapAction), for: .touchUpInside)
            addSubview(actionButton)
            actionButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                actionButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
                actionButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            ])
            lastAnchor = actionButton.bottomAnchor
        }

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            bottomAnchor.constraint(equalTo: lastAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        titleLabel.textColor = RT.text
        messageLabel.textColor = RT.textSecondary
        actionButton.backgroundColor = RT.accent
        actionButton.setTitleColor(RT.accentInk, for: .normal)
        iconView.tintColor = RT.accent.withAlphaComponent(0.8)
    }

    func configure(icon: String? = nil, title: String, message: String) {
        if let icon = icon {
            iconView.image = UIImage(systemName: icon,
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .light))
        }
        titleLabel.text = title
        messageLabel.text = message
    }

    @objc private func tapAction() {
        RT.haptic()
        onAction?()
    }
}

// MARK: - Toast

enum RTToast {

    /// 出现位置：底部用于列表页，顶部用于游戏内（避免与手柄重叠）
    enum Position { case bottom, top }

    static func show(_ message: String,
                     icon: String = "checkmark",
                     in view: UIView? = nil,
                     position: Position = .bottom) {
        guard let host = view ?? UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
            .first else { return }

        let container = UIView()
        container.backgroundColor = RT.surfaceHigh
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous
        container.layer.borderWidth = 1
        container.layer.borderColor = RT.stroke.cgColor
        container.alpha = 0
        container.transform = CGAffineTransform(translationX: 0, y: position == .top ? -10 : 12)
        container.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)))
        iconView.tintColor = RT.accent
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = RT.Font.caption(13)
        label.textColor = RT.text
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(iconView)
        container.addSubview(label)
        host.addSubview(container)

        let anchor: NSLayoutConstraint
        switch position {
        case .bottom:
            anchor = container.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -96)
        case .top:
            anchor = container.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor, constant: 68)
        }

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            anchor,
            container.heightAnchor.constraint(equalToConstant: 40),

            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            container.alpha = 1
            container.transform = .identity
        }
        UIView.animate(withDuration: 0.3, delay: 1.6, options: [.curveEaseIn]) {
            container.alpha = 0
            container.transform = CGAffineTransform(translationX: 0, y: position == .top ? -8 : 8)
        } completion: { _ in
            container.removeFromSuperview()
        }
    }
}

// MARK: - 卡带视图（程序化绘制）

final class RTCartridgeView: UIView {

    var system: EmulatorSystem = .gba { didSet { setNeedsDisplay() } }
    /// 是否显示底部卡槽脊线
    var showsRidge = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { super.init(coder: coder); backgroundColor = .clear; isOpaque = false }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let accent = system.tintColor
        let bodyRect = rect.insetBy(dx: 1, dy: 1)
        let radius = max(8, rect.width * 0.13)

        // 机身
        ctx.saveGState()
        let bodyPath = UIBezierPath(roundedRect: bodyRect, cornerRadius: radius)
        bodyPath.addClip()
        let colors = [accent.lighter(0.10).cgColor, accent.darker(0.30).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: bodyRect.minX, y: bodyRect.minY),
                                   end: CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
                                   options: [])
        }

        // 顶部斜切高光
        let gloss = UIBezierPath()
        gloss.move(to: CGPoint(x: bodyRect.minX, y: bodyRect.minY))
        gloss.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.minY))
        gloss.addLine(to: CGPoint(x: bodyRect.maxX, y: bodyRect.midY * 0.6))
        gloss.addLine(to: CGPoint(x: bodyRect.minX, y: bodyRect.midY * 0.9))
        gloss.close()
        UIColor(white: 1, alpha: 0.14).setFill()
        gloss.fill()

        // 标签区
        let labelRect = bodyRect.insetBy(dx: rect.width * 0.16, dy: rect.height * 0.20)
        let labelPath = UIBezierPath(roundedRect: labelRect, cornerRadius: max(4, radius * 0.45))
        RT.canvasDeep.withAlphaComponent(0.82).setFill()
        labelPath.fill()
        accent.withAlphaComponent(0.55).setStroke()
        labelPath.lineWidth = 1
        labelPath.stroke()

        // 卡槽脊线
        if showsRidge {
            UIColor(white: 0, alpha: 0.20).setFill()
            let ridgeH = max(2, rect.height * 0.05)
            let ridgeY = bodyRect.maxY - rect.height * 0.14
            let ridge = UIBezierPath(roundedRect: CGRect(x: bodyRect.minX + rect.width * 0.22,
                                                         y: ridgeY,
                                                         width: bodyRect.width * 0.56,
                                                         height: ridgeH),
                                     cornerRadius: ridgeH / 2)
            ridge.fill()
        }

        // 系统铭牌
        let code = system.shortCode
        let font = RT.Font.mono(max(8, rect.width * 0.20), weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: accent.lighter(0.35),
            .kern: rect.width * 0.02,
        ]
        let size = (code as NSString).size(withAttributes: attrs)
        (code as NSString).draw(at: CGPoint(x: labelRect.midX - size.width / 2,
                                            y: labelRect.midY - size.height / 2),
                                withAttributes: attrs)
        ctx.restoreGState()
    }
}

// MARK: - 封面视图（渐变占位 + 异步封面）

final class RTCoverView: UIView {

    private let imageView = UIImageView()
    private let gradientLayer = CAGradientLayer()
    private let codeLabel = UILabel()
    private let shineLayer = CAGradientLayer()
    private var system: EmulatorSystem = .gba

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerCurve = .continuous

        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)

        shineLayer.startPoint = CGPoint(x: 0.1, y: 0)
        shineLayer.endPoint = CGPoint(x: 0.9, y: 1)
        shineLayer.colors = [UIColor(white: 1, alpha: 0.16).cgColor,
                             UIColor(white: 1, alpha: 0.0).cgColor,
                             UIColor(white: 0, alpha: 0.16).cgColor]
        shineLayer.locations = [0, 0.55, 1]
        layer.addSublayer(shineLayer)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isHidden = true
        addSubview(imageView)

        codeLabel.font = RT.Font.mono(16, weight: .bold)
        codeLabel.textColor = UIColor(white: 1, alpha: 0.9)
        codeLabel.textAlignment = .center
        codeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codeLabel)
        NSLayoutConstraint.activate([
            codeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            codeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = bounds
        shineLayer.frame = bounds
        imageView.frame = bounds
        CATransaction.commit()
    }

    func setSystem(_ system: EmulatorSystem, cornerRadius: CGFloat) {
        self.system = system
        layer.cornerRadius = cornerRadius
        gradientLayer.colors = [system.tintColor.darker(0.10).cgColor,
                                system.tintColor.darker(0.55).cgColor]
        codeLabel.text = system.shortCode
    }

    func setImage(_ image: UIImage?) {
        imageView.image = image
        imageView.isHidden = image == nil
        codeLabel.isHidden = image != nil
    }

    func loadCover(for rom: ROMInfo) {
        setSystem(rom.system, cornerRadius: layer.cornerRadius)
        CoverArtManager.shared.coverArt(for: rom) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.setImage(image)
        }
    }
}

// MARK: - 系统视觉映射

extension EmulatorSystem {

    /// 每个平台的博物馆铭牌色
    var tintColor: UIColor {
        switch self {
        case .nes:     return UIColor(hex: 0xE4573D)
        case .gbc:     return UIColor(hex: 0x9B7BF0)
        case .gg:      return UIColor(hex: 0x35C2B8)
        case .sms:     return UIColor(hex: 0x4C8DFF)
        case .md:      return UIColor(hex: 0xE8B04B)
        case .gba:     return UIColor(hex: 0x7C6CF0)
        case .snes:    return UIColor(hex: 0xC96BD8)
        case .nds:     return UIColor(hex: 0x8FA3B8)
        case .sega32x: return UIColor(hex: 0xD9764A)
        case .segaCD:  return UIColor(hex: 0xB07AD6)
        case .n64:     return UIColor(hex: 0x53A8E0)
        case .ps1:     return UIColor(hex: 0x9BA6B4)
        case .psp:     return UIColor(hex: 0x5FD2C0)
        }
    }

    /// 卡带铭牌上的短码
    var shortCode: String {
        switch self {
        case .nes:     return "NES"
        case .gbc:     return "GBC"
        case .gg:      return "GG"
        case .sms:     return "SMS"
        case .md:      return "MD"
        case .gba:     return "GBA"
        case .snes:    return "SFC"
        case .nds:     return "NDS"
        case .sega32x: return "32X"
        case .segaCD:  return "MCD"
        case .n64:     return "N64"
        case .ps1:     return "PS1"
        case .psp:     return "PSP"
        }
    }

    /// 平台陈列名（博物馆式命名）
    var displayName: String {
        switch self {
        case .nes:     return L10n.str("platform.nes.name")
        case .gbc:     return "Game Boy"
        case .gg:      return "Game Gear"
        case .sms:     return "Master System"
        case .md:      return "Mega Drive"
        case .gba:     return "Game Boy Advance"
        case .snes:    return L10n.str("platform.snes.name")
        case .nds:     return "Nintendo DS"
        case .sega32x: return "Sega 32X"
        case .segaCD:  return "Mega-CD"
        case .n64:     return "Nintendo 64"
        case .ps1:     return "PlayStation"
        case .psp:     return "PlayStation Portable"
        }
    }

    /// 平台首发年份，展签上的「年代」一栏用
    var launchYear: Int {
        switch self {
        case .nes:     return 1983
        case .gbc:     return 1989
        case .gg:      return 1990
        case .sms:     return 1985
        case .md:      return 1988
        case .gba:     return 2001
        case .snes:    return 1990
        case .nds:     return 2004
        case .sega32x: return 1994
        case .segaCD:  return 1991
        case .n64:     return 1996
        case .ps1:     return 1994
        case .psp:     return 2004
        }
    }

    /// 是否显示 X/Y 四键（只有 SNES / NDS 真正使用）
    var usesFourFaceButtons: Bool {
        self == .snes || self == .nds || self == .n64 || self == .ps1 || self == .psp
    }
}

// MARK: - 浮岛标签栏

final class RTFloatingTabBar: UIView {

    struct Item {
        let icon: String
        let title: String
    }

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex: Int = 0

    private var itemViews: [(container: UIView, icon: UIImageView, label: UILabel, button: UIButton)] = []
    private let stack = UIStackView()

    init(items: [Item]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = RT.surface.withAlphaComponent(0.92)
        layer.cornerRadius = RT.Metric.tabBarHeight / 2
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = RT.stroke.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 22
        layer.shadowOffset = CGSize(width: 0, height: 12)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: RT.Metric.tabBarHeight),
        ])

        for (index, item) in items.enumerated() {
            let container = UIView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.layer.cornerRadius = 22
            container.layer.cornerCurve = .continuous

            let icon = UIImageView(image: UIImage(systemName: item.icon,
                                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.isAccessibilityElement = false

            let label = UILabel()
            label.text = item.title
            label.font = RT.Font.headline(13)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.alpha = 0
            // 读屏由外层按钮统一发声，避免重复朗读
            label.isAccessibilityElement = false

            let button = UIButton(type: .custom)
            button.tag = index
            button.accessibilityIdentifier = "tab.\(index)"
            button.accessibilityLabel = item.title
            button.accessibilityTraits = .button
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            button.translatesAutoresizingMaskIntoConstraints = false

            container.addSubview(icon)
            container.addSubview(label)
            container.addSubview(button)
            stack.addArrangedSubview(container)

            NSLayoutConstraint.activate([
                container.heightAnchor.constraint(equalToConstant: 44),
                icon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
                icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

                button.topAnchor.constraint(equalTo: container.topAnchor),
                button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            itemViews.append((container, icon, label, button))
        }

        updateSelection(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func select(_ index: Int, animated: Bool = true) {
        guard itemViews.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        updateSelection(animated: animated)
    }

    private func updateSelection(animated: Bool) {
        for (i, item) in itemViews.enumerated() {
            let selected = i == selectedIndex
            item.button.accessibilityTraits = selected ? [.button, .selected] : .button
            let changes = {
                item.container.backgroundColor = selected ? RT.accentSoft : .clear
                item.icon.tintColor = selected ? RT.accent : RT.textTertiary
                item.label.alpha = selected ? 1 : 0
                item.label.textColor = RT.accent
            }
            if animated {
                UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.4, options: [.curveEaseOut], animations: changes)
            } else {
                changes()
            }
        }
    }

    @objc private func tap(_ sender: UIButton) {
        RT.haptic()
        onSelect?(sender.tag)
    }
}

// MARK: - 菜单弹层

struct RTMenuAction {
    let title: String
    var subtitle: String? = nil
    var icon: String = "circle"
    var destructive: Bool = false
    var selected: Bool = false
    var enabled: Bool = true
    let handler: () -> Void

    init(title: String,
         subtitle: String? = nil,
         icon: String = "circle",
         destructive: Bool = false,
         selected: Bool = false,
         enabled: Bool = true,
         handler: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.destructive = destructive
        self.selected = selected
        self.enabled = enabled
        self.handler = handler
    }
}

final class RTMenuSheetViewController: UIViewController {

    private let sheetTitle: String
    private let sheetMessage: String?
    private let actions: [RTMenuAction]
    private let onDismiss: (() -> Void)?

    init(title: String, message: String? = nil, actions: [RTMenuAction], onDismiss: (() -> Void)? = nil) {
        self.sheetTitle = title
        self.sheetMessage = message
        self.actions = actions
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = actions.count > 6 ? [.large()] : [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas

        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let content = UIStackView()
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            content.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -28),
            content.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -40),
        ])

        let titleLabel = UILabel()
        titleLabel.text = sheetTitle
        titleLabel.font = RT.Font.title(20)
        titleLabel.textColor = RT.text
        titleLabel.numberOfLines = 2
        content.addArrangedSubview(titleLabel)

        if let message = sheetMessage {
            let messageLabel = UILabel()
            messageLabel.text = message
            messageLabel.font = RT.Font.caption(12)
            messageLabel.textColor = RT.textTertiary
            messageLabel.numberOfLines = 0
            content.addArrangedSubview(messageLabel)
        }

        content.setCustomSpacing(16, after: content.arrangedSubviews.last!)

        for action in actions {
            content.addArrangedSubview(makeRow(action))
        }

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle(L10n.str("btn.cancel"), for: .normal)
        cancelButton.titleLabel?.font = RT.Font.headline(14)
        cancelButton.setTitleColor(RT.textSecondary, for: .normal)
        cancelButton.backgroundColor = RT.surface
        cancelButton.layer.cornerRadius = 16
        cancelButton.layer.cornerCurve = .continuous
        cancelButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        cancelButton.addTarget(self, action: #selector(dismissSheet), for: .touchUpInside)
        content.setCustomSpacing(16, after: content.arrangedSubviews.last!)
        content.addArrangedSubview(cancelButton)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed { onDismiss?() }
    }

    private func makeRow(_ action: RTMenuAction) -> UIView {
        let row = UIControl()
        row.backgroundColor = action.selected ? RT.accentSoft : RT.surface
        row.layer.cornerRadius = 16
        row.layer.cornerCurve = .continuous
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        row.isEnabled = action.enabled

        let iconContainer = UIView()
        iconContainer.backgroundColor = action.destructive ? RT.danger.withAlphaComponent(0.16) : RT.surfaceHigh
        iconContainer.layer.cornerRadius = 11
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.isUserInteractionEnabled = false

        let iconView = UIImageView(image: UIImage(systemName: action.icon,
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)))
        iconView.tintColor = action.destructive ? RT.danger : (action.selected ? RT.accent : RT.textSecondary)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        let titleLabel = UILabel()
        titleLabel.text = action.title
        titleLabel.font = RT.Font.body(15)
        titleLabel.textColor = action.destructive ? RT.danger : (action.enabled ? RT.text : RT.textTertiary)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isUserInteractionEnabled = false

        row.addSubview(iconContainer)
        row.addSubview(titleLabel)

        var trailingView: UIView?
        if action.selected {
            let check = UIImageView(image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)))
            check.tintColor = RT.accent
            check.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(check)
            NSLayoutConstraint.activate([
                check.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -18),
                check.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ])
            trailingView = check
        } else if action.subtitle != nil {
            let subtitleLabel = UILabel()
            subtitleLabel.text = action.subtitle
            subtitleLabel.font = RT.Font.mono(11)
            subtitleLabel.textColor = RT.textTertiary
            subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(subtitleLabel)
            NSLayoutConstraint.activate([
                subtitleLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                subtitleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            ])
            trailingView = subtitleLabel
        }

        NSLayoutConstraint.activate([
            iconContainer.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconContainer.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 32),
            iconContainer.heightAnchor.constraint(equalToConstant: 32),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingView?.leadingAnchor ?? row.trailingAnchor,
                                                 constant: trailingView == nil ? -16 : -8),
        ])

        row.addAction(UIAction { [weak self] _ in
            RT.haptic()
            self?.dismissSheet(after: action.handler)
        }, for: .touchUpInside)

        return row
    }

    private func dismissSheet(after handler: (() -> Void)? = nil) {
        dismiss(animated: true) {
            handler?()
        }
    }

    @objc private func dismissSheet() {
        dismiss(animated: true)
    }

    /// 通用入口
    static func present(from presenter: UIViewController,
                        title: String,
                        message: String? = nil,
                        actions: [RTMenuAction],
                        onDismiss: (() -> Void)? = nil) {
        let vc = RTMenuSheetViewController(title: title, message: message, actions: actions, onDismiss: onDismiss)
        presenter.present(vc, animated: true)
    }
}

// MARK: - 胶囊筛选条

final class RTSegmentBar: UIView {

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [RTPillButton] = []
    private(set) var selectedIndex: Int = 0
    var onSelect: ((Int) -> Void)?

    init(titles: [String]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        scrollView.pinEdges(to: self)

        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: RT.Metric.screenPadding),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -RT.Metric.screenPadding),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            heightAnchor.constraint(equalToConstant: 34),
        ])

        for (index, title) in titles.enumerated() {
            let button = RTPillButton(title: title, selected: index == 0)
            button.tag = index
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(titles: [String]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll()
        for (index, title) in titles.enumerated() {
            let button = RTPillButton(title: title, selected: index == selectedIndex)
            button.tag = index
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
    }

    func select(_ index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        for (i, button) in buttons.enumerated() {
            button.apply(selected: i == index)
        }
    }

    @objc private func tap(_ sender: UIButton) {
        RT.haptic()
        select(sender.tag)
        onSelect?(sender.tag)
    }
}
