// LaunchIntroView.swift
// 冷启动入场动画：卡带滑入机身 → 屏幕亮起 → 品牌落款
// 母题取自产品自身语义（卡带 + 掌机屏幕），全部程序化绘制。
// 支持：系统「减弱动态效果」降级、点击跳过、-skipIntro / -shot 启动参数跳过。

import UIKit

final class LaunchIntroView: UIView {

    static var shouldSkip: Bool {
        if UIAccessibility.isReduceMotionEnabled { return true }
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-skipIntro") || args.contains("-shot")
    }

    var onFinish: (() -> Void)?

    private let deviceLayer = CAShapeLayer()
    private let screenLayer = CAShapeLayer()
    private let glowLayer = CAGradientLayer()
    private let scanlineLayer = CAShapeLayer()
    private let cartridge = RTCartridgeView()
    private let brandStack = UIStackView()
    private var finished = false
    private var timer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = RT.canvas
        clipsToBounds = true
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // 机身
        deviceLayer.fillColor = RT.surface.cgColor
        deviceLayer.strokeColor = RT.accent.withAlphaComponent(0.22).cgColor
        deviceLayer.lineWidth = 1.4
        deviceLayer.opacity = 0
        layer.addSublayer(deviceLayer)

        // 屏幕
        screenLayer.fillColor = RT.canvasDeep.cgColor
        screenLayer.strokeColor = RT.accent.withAlphaComponent(0.35).cgColor
        screenLayer.lineWidth = 1
        screenLayer.opacity = 0
        layer.addSublayer(screenLayer)

        // 磷光
        glowLayer.colors = [RT.accent.withAlphaComponent(0.55).cgColor,
                            RT.accent.withAlphaComponent(0.05).cgColor]
        glowLayer.startPoint = CGPoint(x: 0.5, y: 0)
        glowLayer.endPoint = CGPoint(x: 0.5, y: 1)
        glowLayer.opacity = 0
        layer.addSublayer(glowLayer)

        // 扫描线
        scanlineLayer.strokeColor = UIColor(white: 0, alpha: 0.22).cgColor
        scanlineLayer.lineWidth = 1
        scanlineLayer.opacity = 0
        layer.addSublayer(scanlineLayer)

        // 卡带
        cartridge.system = .gba
        cartridge.translatesAutoresizingMaskIntoConstraints = false
        cartridge.alpha = 0
        addSubview(cartridge)

        // 品牌
        let titleLabel = UILabel()
        titleLabel.text = L10n.str("brand.name")
        titleLabel.font = .systemFont(ofSize: 25, weight: .bold)
        titleLabel.textColor = RT.text
        titleLabel.textAlignment = .center

        let subLabel = UILabel()
        subLabel.attributedText = NSAttributedString(
            string: L10n.str("brand.plaque"),
            attributes: [
                .font: RT.Font.mono(10, weight: .semibold),
                .foregroundColor: RT.textTertiary,
                .kern: 3.2,
            ]
        )
        subLabel.textAlignment = .center

        brandStack.axis = .vertical
        brandStack.spacing = 8
        brandStack.alignment = .center
        brandStack.translatesAutoresizingMaskIntoConstraints = false
        brandStack.addArrangedSubview(titleLabel)
        brandStack.addArrangedSubview(subLabel)
        brandStack.alpha = 0
        addSubview(brandStack)

        NSLayoutConstraint.activate([
            brandStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            brandStack.topAnchor.constraint(equalTo: centerYAnchor, constant: 132),
            brandStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            brandStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(skip))
        addGestureRecognizer(tap)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let deviceW: CGFloat = 188
        let deviceH: CGFloat = 296
        let deviceRect = CGRect(x: bounds.midX - deviceW / 2,
                                y: bounds.midY - deviceH / 2 - 40,
                                width: deviceW, height: deviceH)
        deviceLayer.path = UIBezierPath(roundedRect: deviceRect, cornerRadius: 34).cgPath
        deviceLayer.frame = bounds

        let screenRect = CGRect(x: deviceRect.minX + 18,
                                y: deviceRect.minY + 26,
                                width: deviceW - 36,
                                height: deviceH * 0.46)
        screenLayer.path = UIBezierPath(roundedRect: screenRect, cornerRadius: 10).cgPath
        screenLayer.frame = bounds

        glowLayer.frame = screenRect
        glowLayer.cornerRadius = 10

        let scanPath = UIBezierPath()
        var y = screenRect.minY + 4
        while y < screenRect.maxY - 2 {
            scanPath.move(to: CGPoint(x: screenRect.minX + 2, y: y))
            scanPath.addLine(to: CGPoint(x: screenRect.maxX - 2, y: y))
            y += 4
        }
        scanlineLayer.path = scanPath.cgPath
        scanlineLayer.frame = bounds

        // 卡带尺寸与起点
        let cartSize = CGSize(width: 52, height: 60)
        cartridge.frame = CGRect(x: deviceRect.midX - cartSize.width / 2,
                                 y: deviceRect.minY + 12,
                                 width: cartSize.width, height: cartSize.height)
    }

    func start() {
        guard !finished else { return }
        layoutIfNeeded()

        brandStack.transform = CGAffineTransform(translationX: 0, y: 10)
        cartridge.alpha = 0
        cartridge.transform = CGAffineTransform(translationX: 0, y: -34)

        UIView.animateKeyframes(withDuration: 1.35, delay: 0, options: [.calculationModeCubic]) { [weak self] in
            guard let self = self else { return }

            // 机身描边
            UIView.addKeyframe(withRelativeStartTime: 0.00, relativeDuration: 0.30) {
                self.deviceLayer.opacity = 1
                self.screenLayer.opacity = 1
            }

            // 卡带入槽
            UIView.addKeyframe(withRelativeStartTime: 0.12, relativeDuration: 0.34) {
                self.cartridge.alpha = 1
                self.cartridge.transform = .identity
            }

            // 屏幕亮起
            UIView.addKeyframe(withRelativeStartTime: 0.38, relativeDuration: 0.26) {
                self.glowLayer.opacity = 1
                self.scanlineLayer.opacity = 1
            }

            // 品牌落款
            UIView.addKeyframe(withRelativeStartTime: 0.50, relativeDuration: 0.34) {
                self.brandStack.alpha = 1
                self.brandStack.transform = .identity
            }
        } completion: { [weak self] _ in
            guard let self = self else { return }
            // 停稳后停留 0.45s 供阅读，再交给外层交叉淡入
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.finish()
            }
        }
    }

    @objc private func skip() {
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        timer?.invalidate()
        timer = nil
        onFinish?()
    }
}

// MARK: - 根容器：主界面 + 入场动画交叉淡入

final class RetroRootViewController: UIViewController {

    lazy var tabs = RetroTabBarController()
    private var intro: LaunchIntroView?
    private var tabsInstalled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas

        // 首帧只挂入场动画。库页面要扫 ROM、算存档，全部塞进 viewDidLoad 的话
        // 白屏会把动画本身吞掉，用户先看到的是一段空白。
        if LaunchIntroView.shouldSkip {
            installTabsIfNeeded()
            presentCuratorIfNeeded()
            return
        }
        installIntro()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 首帧已经上屏，这时候再建库页面，耗时都藏在入场动画里
        installTabsIfNeeded()
    }

    // MARK: - 主界面

    private func installTabsIfNeeded() {
        guard !tabsInstalled else { return }
        tabsInstalled = true
        addChild(tabs)
        if let intro = intro {
            view.insertSubview(tabs.view, belowSubview: intro)
        } else {
            view.addSubview(tabs.view)
        }
        tabs.view.pinEdges(to: view)
        tabs.didMove(toParent: self)
    }

    // MARK: - 入场动画

    private func installIntro() {
        let introView = LaunchIntroView()
        view.addSubview(introView)
        introView.pinEdges(to: view)
        intro = introView

        introView.onFinish = { [weak self, weak introView] in
            guard let self = self, let introView = introView else { return }
            // 动画结束时主界面必须已经在底下，否则会淡成一张空底
            self.installTabsIfNeeded()
            UIView.animate(withDuration: 0.34, delay: 0, options: [.curveEaseInOut]) {
                introView.alpha = 0
            } completion: { _ in
                introView.removeFromSuperview()
                self.intro = nil
                // 入仓动画退场之后再讲三屏导览，别抢同一段时间
                self.presentCuratorIfNeeded(delay: 0.12)
            }
        }
        introView.start()
    }

    /// 首启导览只出现一次；自动化启动参数下 shouldSkip 会拦掉
    private func presentCuratorIfNeeded(delay: TimeInterval = 0.35) {
        guard !CuratorOnboardingView.shouldSkip else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            CuratorOnboardingView.present(in: self)
        }
    }

    private func dismissCurator() {
        CuratorOnboardingView.hasBeenSeen = true
        for subview in view.subviews where subview is CuratorOnboardingView {
            subview.removeFromSuperview()
        }
    }

    /// 供 SceneDelegate / Widget 深链使用
    func presentGame(_ rom: ROMInfo) {
        dismissCurator()
        // 直接进游戏时入场动画让路，别让玩家先看两秒动画
        intro?.removeFromSuperview()
        intro = nil
        installTabsIfNeeded()
        tabs.select(index: 0, animated: false)
        if let presented = presentedViewController, !(presented is EmulatorViewController) {
            presented.dismiss(animated: false)
        }
        let vc = EmulatorViewController(rom: rom)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}
