// GamepadView.swift
// 虚拟手柄 UI — 真实手柄外观 + 按键重映射 + 布局编辑 + Turbo + 触觉反馈 + 陀螺仪

import UIKit
import GameController
import CoreMotion
import CoreHaptics

// 方向键样式
enum DPadStyle: String, CaseIterable {
    case dpad     = "十字键"
    case joystick = "浮动摇杆"
}

protocol GamepadViewDelegate: AnyObject {
    func gamepadView(_ view: GamepadView, buttonsChanged buttons: EmulatorButton)
}

final class GamepadView: UIView {

    weak var delegate: GamepadViewDelegate?
    private(set) var currentButtons: EmulatorButton = []

    // 子视图
    private let dpadView     = DPadView()
    private let joystickView = JoystickView()
    private let btnA      = ActionButton(label: "A",     color: .systemRed)
    private let btnB      = ActionButton(label: "B",     color: .systemOrange)
    private let btnX      = ActionButton(label: "X",     color: .systemBlue)
    private let btnY      = ActionButton(label: "Y",     color: .systemGreen)
    private let startBtn  = SmallButton(label: "START")
    private let selectBtn = SmallButton(label: "SEL")

    /// 当前运行的平台，决定露出几个面键（红白机、GB 只需 A/B）
    private var activeSystem: EmulatorSystem?
    private var usesFourFaceButtons: Bool { activeSystem?.usesFourFaceButtons ?? true }

    /// 当前方向键样式，切换时立即生效
    var dpadStyle: DPadStyle = {
        let raw = UserDefaults.standard.string(forKey: "dpad_style") ?? ""
        return DPadStyle(rawValue: raw) ?? .dpad
    }() {
        didSet {
            UserDefaults.standard.set(dpadStyle.rawValue, forKey: "dpad_style")
            applyDPadStyle()
        }
    }

    private var slotButtons: [(ActionButton, GamepadSlot)] = []
    private var pressedSlots: Set<GamepadSlot> = []

    // 编辑模式
    private(set) var isEditing = false
    private var editOverlay: UIView?

    // MARK: - Turbo 连发
    private var turboSlots: Set<GamepadSlot> = []
    private var turboTimer: Timer?
    private var turboState = false

    /// 触觉反馈（虚拟手柄按键）
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - 陀螺仪
    private let motionManager = CMMotionManager()
    var onGyroInput: ((Float, Float) -> Void)?
    private(set) var isGyroEnabled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
        haptic.prepare()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup(); haptic.prepare() }

    deinit {
        turboTimer?.invalidate()
        motionManager.stopDeviceMotionUpdates()
    }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        slotButtons = [
            (btnA, .btnA), (btnB, .btnB),
            (btnX, .btnX), (btnY, .btnY),
        ]

        [dpadView, btnA, btnB, btnX, btnY, startBtn, selectBtn, joystickView].forEach { addSubview($0) }
        dpadView.delegate = self
        joystickView.delegate = self

        for (btn, slot) in slotButtons {
            btn.tag = GamepadSlot.allCases.firstIndex(of: slot) ?? 0
            btn.addTarget(self, action: #selector(btnDown(_:)), for: [.touchDown, .touchDragEnter])
            btn.addTarget(self, action: #selector(btnUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
        }
        for (btn, slot) in [(startBtn, GamepadSlot.btnStart), (selectBtn, .btnSelect)] as [(SmallButton, GamepadSlot)] {
            btn.tag = GamepadSlot.allCases.firstIndex(of: slot) ?? 0
            btn.addTarget(self, action: #selector(smallBtnDown(_:)), for: [.touchDown, .touchDragEnter])
            btn.addTarget(self, action: #selector(smallBtnUp(_:)),   for: [.touchUpInside, .touchUpOutside, .touchDragExit, .touchCancel])
        }
        refreshLabels()
        applyDPadStyle()
    }

    private func applyDPadStyle() {
        switch dpadStyle {
        case .dpad:
            dpadView.isHidden = false
            joystickView.isHidden = true
        case .joystick:
            dpadView.isHidden = true
            joystickView.isHidden = false
        }
        setNeedsLayout()
    }

    func refreshLabels() {
        for (btn, slot) in slotButtons {
            let mapped = KeymapSettings.shared.button(for: slot)
            let label = KeymapSettings.mappableButtons.first { $0.button == mapped }?.label ?? slot.displayName
            btn.setLabel(label)
        }
    }

    /// 按平台适配键位：两键平台收起 X/Y，A/B 排成斜向，避免画面被多余按键占满
    func configure(for system: EmulatorSystem) {
        activeSystem = system
        let four = system.usesFourFaceButtons
        btnX.isHidden = !four
        btnY.isHidden = !four
        setNeedsLayout()
    }

    // MARK: - HitTest（编辑模式下整个区域响应触摸）
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isEditing {
            if let bar = editOverlay {
                let ptInBar = convert(point, to: bar)
                if let hit = bar.hitTest(ptInBar, with: event), hit !== bar {
                    return hit
                }
            }
            return self
        }
        return super.hitTest(point, with: event)
    }

    // MARK: - Layout（从 GamepadLayoutSettings 读取 / 竖屏自动布局）

    private var portraitMode = false

    /// 由 EmulatorViewController 在方向变化时调用
    func updateOrientation(portrait: Bool) {
        portraitMode = portrait
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isEditing, bounds.width > 0, bounds.height > 0 else { return }
        if portraitMode {
            applyPortraitLayout()
        } else {
            applyStoredLayouts()
        }
    }

    /// 竖屏固定布局：左下 DPad，右下 ABXY，中间 START/SEL
    private func applyPortraitLayout() {
        let w = bounds.width, h = bounds.height
        // 手柄区域在下方 55% 高度
        let padTop = h * 0.45
        let padH   = h - padTop
        let btnSize: CGFloat = min(w * 0.14, 52)
        let dpadSize: CGFloat = min(w * 0.36, 130)

        // DPad / Joystick：左下角（共用同一位置和尺寸）
        let dpadCenter = CGPoint(x: w * 0.22, y: padTop + padH * 0.52)
        dpadView.bounds = CGRect(origin: .zero, size: CGSize(width: dpadSize, height: dpadSize))
        dpadView.center = dpadCenter
        joystickView.bounds = CGRect(origin: .zero, size: CGSize(width: dpadSize, height: dpadSize))
        joystickView.center = dpadCenter

        // 面键：右下角。四键平台排菱形，两键平台斜向排列并放大
        let rCX = w * 0.78
        let rCY = padTop + padH * 0.48
        let gap: CGFloat = btnSize * 1.15
        btnA.bounds = CGRect(origin: .zero, size: CGSize(width: btnSize, height: btnSize))
        btnB.bounds = btnA.bounds
        btnX.bounds = btnA.bounds
        btnY.bounds = btnA.bounds
        if usesFourFaceButtons {
            btnA.center = CGPoint(x: rCX + gap, y: rCY)          // 右
            btnB.center = CGPoint(x: rCX,       y: rCY + gap)     // 下
            btnX.center = CGPoint(x: rCX,       y: rCY - gap)     // 上
            btnY.center = CGPoint(x: rCX - gap, y: rCY)           // 左
        } else {
            let twoSize: CGFloat = min(w * 0.17, 60)
            btnA.bounds = CGRect(origin: .zero, size: CGSize(width: twoSize, height: twoSize))
            btnB.bounds = btnA.bounds
            let twoGap = twoSize * 0.72
            btnA.center = CGPoint(x: rCX + twoGap * 0.55, y: rCY - twoGap)
            btnB.center = CGPoint(x: rCX - twoGap * 0.55, y: rCY + twoGap)
        }

        // START / SEL：中间偏下
        let smallW: CGFloat = 56, smallH: CGFloat = 22
        selectBtn.bounds = CGRect(origin: .zero, size: CGSize(width: smallW, height: smallH))
        startBtn.bounds  = selectBtn.bounds
        selectBtn.center = CGPoint(x: w * 0.42, y: padTop + padH * 0.82)
        startBtn.center  = CGPoint(x: w * 0.58, y: padTop + padH * 0.82)

        [dpadView, btnA, btnB, btnX, btnY, startBtn, selectBtn].forEach { $0.alpha = 0.85 }
    }

    private func applyStoredLayouts() {
        let w = bounds.width, h = bounds.height
        func apply(_ v: UIView, key: String) {
            let l = GamepadLayoutSettings.shared.layout(for: key)
            v.bounds = CGRect(origin: .zero, size: CGSize(width: l.size, height: l.size))
            v.center = CGPoint(x: l.centerX * w, y: l.centerY * h)
            v.alpha  = l.opacity
        }
        apply(dpadView,  key: "dpad")
        // 摇杆和十字键共用同一位置
        joystickView.bounds = dpadView.bounds
        joystickView.center = dpadView.center
        joystickView.alpha  = dpadView.alpha
        apply(btnA,      key: "btnA")
        apply(btnB,      key: "btnB")
        apply(btnX,      key: "btnX")
        apply(btnY,      key: "btnY")
        apply(startBtn,  key: "start")
        apply(selectBtn, key: "select")
    }

    // MARK: - 按键事件

    @objc private func btnDown(_ sender: ActionButton) {
        guard let slot = GamepadSlot.allCases[safe: sender.tag] else { return }
        pressedSlots.insert(slot)
        recalculate()
        sender.setPressed(true)
        triggerHaptic()
    }

    @objc private func btnUp(_ sender: ActionButton) {
        guard let slot = GamepadSlot.allCases[safe: sender.tag] else { return }
        pressedSlots.remove(slot)
        recalculate()
        sender.setPressed(false)
    }

    @objc private func smallBtnDown(_ sender: SmallButton) {
        guard let slot = GamepadSlot.allCases[safe: sender.tag] else { return }
        pressedSlots.insert(slot)
        recalculate()
        sender.setPressed(true)
        triggerHaptic()
    }

    @objc private func smallBtnUp(_ sender: SmallButton) {
        guard let slot = GamepadSlot.allCases[safe: sender.tag] else { return }
        pressedSlots.remove(slot)
        recalculate()
        sender.setPressed(false)
    }

    private func recalculate() {
        // F8: 检测快捷键（只在新按下的槽位中检测，避免持续触发）
        let newlyPressed  = pressedSlots.subtracting(lastPressedSlots)
        let newlyReleased = lastPressedSlots.subtracting(pressedSlots)

        if !newlyPressed.isEmpty {
            checkShortcuts(newlyPressed: newlyPressed)
        }
        if !newlyReleased.isEmpty {
            checkShortcutsReleased(releasedSlots: newlyReleased)
        }
        lastPressedSlots = pressedSlots

        currentButtons = KeymapSettings.shared.translate(pressedSlots: pressedSlots)
        delegate?.gamepadView(self, buttonsChanged: currentButtons)
    }

    private var lastPressedSlots: Set<GamepadSlot> = []

    // MARK: - Turbo 连发

    /// 某个槽位是否已开启连发
    func isTurboEnabled(for slot: GamepadSlot) -> Bool {
        turboSlots.contains(slot)
    }

    /// 切换某个槽位的 Turbo 状态
    func toggleTurbo(for slot: GamepadSlot) {
        if turboSlots.contains(slot) {
            turboSlots.remove(slot)
        } else {
            turboSlots.insert(slot)
        }
        // 如果有 Turbo 槽位，启动定时器（每 1/15 秒切换一次）
        if turboSlots.isEmpty {
            turboTimer?.invalidate()
            turboTimer = nil
        } else if turboTimer == nil {
            turboTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                self?.tickTurbo()
            }
        }
    }

    private func tickTurbo() {
        turboState.toggle()
        // 对所有按下的 Turbo 槽位，根据 turboState 决定是否注入按键
        var buttons = KeymapSettings.shared.translate(pressedSlots: pressedSlots)
        if turboState {
            for slot in turboSlots where pressedSlots.contains(slot) {
                buttons.insert(KeymapSettings.shared.button(for: slot))
            }
        } else {
            for slot in turboSlots where pressedSlots.contains(slot) {
                buttons.remove(KeymapSettings.shared.button(for: slot))
            }
        }
        currentButtons = buttons
        delegate?.gamepadView(self, buttonsChanged: currentButtons)
    }

    // MARK: - 触觉反馈

    private func triggerHaptic() {
        haptic.impactOccurred()
    }

    // MARK: - 陀螺仪

    func enableGyro(_ enabled: Bool) {
        isGyroEnabled = enabled
        if enabled {
            guard motionManager.isDeviceMotionAvailable else { return }
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
                guard let motion = motion else { return }
                // 将重力向量映射为倾斜输入
                let tiltX = Float(max(-1.0, min(1.0, motion.gravity.x * 2.0)))
                let tiltY = Float(max(-1.0, min(1.0, motion.gravity.y * 2.0)))
                self?.onGyroInput?(tiltX, tiltY)
            }
        } else {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    // MARK: - 编辑模式

    private var draggingView: UIView?
    private var selectedView: UIView?   // 当前选中的按钮（显示属性面板）

    // 属性面板控件
    private weak var sizeSlider: UISlider?
    private weak var opacitySlider: UISlider?
    private weak var selectedLabel: UILabel?

    func enterEditMode() {
        guard !isEditing else { return }
        isEditing = true

        // 顶部面板：只拦截自身区域的触摸
        let bar = PassthroughView()
        bar.backgroundColor = RT.surfaceHigh.withAlphaComponent(0.94)
        bar.layer.cornerRadius = 18
        bar.layer.cornerCurve = .continuous
        bar.layer.borderWidth = 1
        bar.layer.borderColor = RT.stroke.cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        editOverlay = bar

        // 铭牌
        let plaqueLabel = UILabel()
        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("gamepad.edit.hint"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.textSecondary,
                         .kern: 0.4]
        )
        plaqueLabel.translatesAutoresizingMaskIntoConstraints = false

        // 保存：琥珀胶囊
        let saveBtn = UIButton(type: .system)
        var config = UIButton.Configuration.filled()
        config.title = L10n.str("btn.done")
        config.baseBackgroundColor = RT.accent
        config.baseForegroundColor = RT.accentInk
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 15, bottom: 6, trailing: 15)
        config.background.cornerRadius = 14
        config.attributedTitle = AttributedString(
            L10n.str("btn.done"),
            attributes: AttributeContainer([.font: RT.Font.headline(12)])
        )
        saveBtn.configuration = config
        saveBtn.translatesAutoresizingMaskIntoConstraints = false
        saveBtn.addTarget(self, action: #selector(exitEditMode), for: .touchUpInside)

        // 当前选中
        let selLabel = UILabel()
        selLabel.text = L10n.str("gamepad.edit.none")
        selLabel.font = RT.Font.mono(10, weight: .semibold)
        selLabel.textColor = RT.accent
        selLabel.translatesAutoresizingMaskIntoConstraints = false
        selectedLabel = selLabel

        // 大小滑块
        let sizeRow = makeSliderRow(icon: "arrow.up.left.and.arrow.down.right",
                                    label: L10n.str("gamepad.edit.size"))
        let sizeSlider = sizeRow.slider
        sizeSlider.minimumValue = 32
        sizeSlider.maximumValue = 180
        sizeSlider.value = 48
        sizeSlider.addTarget(self, action: #selector(sizeChanged(_:)), for: .valueChanged)
        self.sizeSlider = sizeSlider

        // 透明度滑块
        let opacityRow = makeSliderRow(icon: "circle.lefthalf.filled",
                                       label: L10n.str("gamepad.edit.opacity"))
        let opacitySlider = opacityRow.slider
        opacitySlider.minimumValue = 0.1
        opacitySlider.maximumValue = 1.0
        opacitySlider.value = 0.85
        opacitySlider.addTarget(self, action: #selector(opacityChanged(_:)), for: .valueChanged)
        self.opacitySlider = opacitySlider

        // 布局
        let stack = UIStackView(arrangedSubviews: [sizeRow.row, opacityRow.row])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        [plaqueLabel, saveBtn, selLabel, stack].forEach { bar.addSubview($0) }

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            plaqueLabel.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            plaqueLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),

            saveBtn.centerYAnchor.constraint(equalTo: plaqueLabel.centerYAnchor),
            saveBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -10),

            selLabel.topAnchor.constraint(equalTo: plaqueLabel.bottomAnchor, constant: 6),
            selLabel.leadingAnchor.constraint(equalTo: plaqueLabel.leadingAnchor),
            selLabel.trailingAnchor.constraint(lessThanOrEqualTo: saveBtn.leadingAnchor, constant: -8),

            stack.topAnchor.constraint(equalTo: selLabel.bottomAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: plaqueLabel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10),
        ])

        // 高亮所有可编辑按钮
        editableViews.forEach { (v, _) in
            v.layer.borderColor = RT.accent.withAlphaComponent(0.35).cgColor
            v.layer.borderWidth = 1.5
        }

        // 手势加在 GamepadView 自身
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleEditTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleEditPan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
    }

    @objc func exitEditMode() {
        guard isEditing else { return }
        isEditing = false
        draggingView = nil
        selectedView = nil
        editOverlay?.removeFromSuperview()
        editOverlay = nil
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }

        editableViews.forEach { (v, key) in
            v.layer.borderWidth = 0
            let cx = v.center.x / bounds.width
            let cy = v.center.y / bounds.height
            // joystick 和 dpad 共用 "dpad" key 存储位置
            let saveKey = key == "joystick" ? "dpad" : key
            GamepadLayoutSettings.shared.setLayout(
                ButtonLayout(centerX: cx, centerY: cy, size: v.bounds.width, opacity: v.alpha),
                for: saveKey
            )
        }
        // 同步另一个方向控件的位置
        joystickView.bounds = dpadView.bounds
        joystickView.center = dpadView.center
        joystickView.alpha  = dpadView.alpha
    }

    private var editableViews: [(UIView, String)] {
        // 根据当前样式，dpad 和 joystick 二选一
        let dirView: (UIView, String) = dpadStyle == .joystick
            ? (joystickView, "joystick")
            : (dpadView, "dpad")
        return [dirView, (btnA, "btnA"), (btnB, "btnB"),
                (btnX, "btnX"), (btnY, "btnY"), (startBtn, "start"), (selectBtn, "select")]
    }

    private var editableNames: [String: String] {
        [
            "dpad": L10n.str("gamepad.edit.dpad"),
            "joystick": L10n.str("gamepad.edit.joystick"),
            "btnA": "A", "btnB": "B", "btnX": "X", "btnY": "Y",
            "start": L10n.str("gamepad.edit.start"),
            "select": L10n.str("gamepad.edit.select"),
        ]
    }

    // 选中某个按钮，更新面板
    private func selectView(_ v: UIView, name: String) {
        // 取消上一个高亮
        selectedView?.layer.borderColor = RT.accent.withAlphaComponent(0.35).cgColor
        selectedView?.layer.borderWidth = 1.5

        selectedView = v
        v.layer.borderColor = RT.accent.cgColor
        v.layer.borderWidth = 2

        selectedLabel?.text = L10n.str("gamepad.edit.selected", name)
        sizeSlider?.value = Float(v.bounds.width)
        opacitySlider?.value = Float(v.alpha)
    }

    @objc private func handleEditTap(_ gr: UITapGestureRecognizer) {
        let pt = gr.location(in: self)
        if let bar = editOverlay, bar.frame.contains(pt) { return }
        guard let (v, key) = editableViews.reversed().first(where: { $0.0.frame.contains(pt) }) else { return }
        selectView(v, name: editableNames[key] ?? key)
    }

    @objc private func handleEditPan(_ gr: UIPanGestureRecognizer) {
        let pt = gr.location(in: self)
        if gr.state == .began, let bar = editOverlay, bar.frame.contains(pt) { return }
        switch gr.state {
        case .began:
            draggingView = editableViews.reversed().first(where: { $0.0.frame.contains(pt) })?.0
            if let v = draggingView {
                let key = editableViews.first(where: { $0.0 === v })?.1 ?? ""
                selectView(v, name: editableNames[key] ?? key)
            }
        case .changed:
            guard let v = draggingView else { return }
            let delta = gr.translation(in: self)
            let half = v.bounds.width / 2
            v.center = CGPoint(
                x: max(half, min(bounds.width  - half, v.center.x + delta.x)),
                y: max(half, min(bounds.height - half, v.center.y + delta.y))
            )
            gr.setTranslation(.zero, in: self)
        case .ended, .cancelled:
            draggingView = nil
        default: break
        }
    }

    // 滑块回调
    @objc private func sizeChanged(_ slider: UISlider) {
        guard let v = selectedView else { return }
        let s = CGFloat(slider.value)
        let center = v.center
        v.bounds = CGRect(origin: .zero, size: CGSize(width: s, height: s))
        v.center = center
        // DPadView 需要重绘圆角
        if let d = v as? DPadView { d.setNeedsDisplay() }
        if let b = v as? ActionButton { b.layer.cornerRadius = s / 2 }
    }

    @objc private func opacityChanged(_ slider: UISlider) {
        selectedView?.alpha = CGFloat(slider.value)
    }

    // MARK: - 滑块行工厂
    private func makeSliderRow(icon: String, label: String) -> (row: UIView, slider: UISlider) {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView(image: UIImage(systemName: icon, withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 10, weight: .semibold)))
        iconView.tintColor = RT.accent
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = RT.Font.mono(9, weight: .medium)
        nameLabel.textColor = RT.textSecondary
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)

        let slider = UISlider()
        slider.minimumTrackTintColor = RT.accent
        slider.maximumTrackTintColor = RT.stroke
        slider.translatesAutoresizingMaskIntoConstraints = false

        [iconView, nameLabel, slider].forEach { row.addSubview($0) }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 26),
            iconView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.widthAnchor.constraint(equalToConstant: 46),
            slider.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            slider.trailingAnchor.constraint(equalTo: row.trailingAnchor),
        ])
        return (row, slider)
    }

    // MARK: - F5: 虚拟手柄显示/隐藏

    /// 外接手柄连接/断开时由 EmulatorViewController 调用
    func setVirtualPadHidden(_ hidden: Bool) {
        UIView.animate(withDuration: 0.3) {
            self.alpha = hidden ? 0 : 1
        }
        isUserInteractionEnabled = !hidden
    }

    // MARK: - F8: 快捷键检测

    /// 在 recalculate() 中调用，检测是否有快捷键触发
    private func checkShortcuts(newlyPressed: Set<GamepadSlot>) {
        guard !newlyPressed.isEmpty else { return }
        let actions = ShortcutKeymap.shared.triggeredActions(for: newlyPressed)
        guard !actions.isEmpty else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let evc = r as? EmulatorViewController {
                evc.handleShortcutActions(actions)
                return
            }
            responder = r.next
        }
    }

    /// 检测快捷键松开（用于倒带结束等"按住"操作）
    private func checkShortcutsReleased(releasedSlots: Set<GamepadSlot>) {
        let actions = ShortcutKeymap.shared.triggeredActions(for: releasedSlots)
        guard !actions.isEmpty else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let evc = r as? EmulatorViewController {
                evc.handleShortcutReleased(actions)
                return
            }
            responder = r.next
        }
    }
}

// MARK: - UIGestureRecognizerDelegate
extension GamepadView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // tap 和 pan 不同时识别，pan 优先
        if gr is UITapGestureRecognizer && other is UIPanGestureRecognizer { return false }
        if gr is UIPanGestureRecognizer && other is UITapGestureRecognizer { return false }
        return true
    }
}

// MARK: - DPad 回调
extension GamepadView: DPadViewDelegate {
    func dpadView(_ view: DPadView, directionsChanged directions: EmulatorButton) {
        pressedSlots.remove(.dpadUp)
        pressedSlots.remove(.dpadDown)
        pressedSlots.remove(.dpadLeft)
        pressedSlots.remove(.dpadRight)
        if directions.contains(.up)    { pressedSlots.insert(.dpadUp) }
        if directions.contains(.down)  { pressedSlots.insert(.dpadDown) }
        if directions.contains(.left)  { pressedSlots.insert(.dpadLeft) }
        if directions.contains(.right) { pressedSlots.insert(.dpadRight) }
        recalculate()
    }
}

// MARK: - Joystick 回调
extension GamepadView: JoystickViewDelegate {
    func joystickView(_ view: JoystickView, directionsChanged directions: EmulatorButton) {
        pressedSlots.remove(.dpadUp)
        pressedSlots.remove(.dpadDown)
        pressedSlots.remove(.dpadLeft)
        pressedSlots.remove(.dpadRight)
        if directions.contains(.up)    { pressedSlots.insert(.dpadUp) }
        if directions.contains(.down)  { pressedSlots.insert(.dpadDown) }
        if directions.contains(.left)  { pressedSlots.insert(.dpadLeft) }
        if directions.contains(.right) { pressedSlots.insert(.dpadRight) }
        recalculate()
    }
}

// MARK: - 方向键（十字形，圆形背景）
protocol DPadViewDelegate: AnyObject {
    func dpadView(_ view: DPadView, directionsChanged directions: EmulatorButton)
}

final class DPadView: UIView {

    weak var delegate: DPadViewDelegate?
    private var currentDirections: EmulatorButton = []

    // 四个方向箭头（SF Symbols 细箭头，比文字三角更精致）
    private let upArrow    = DPadView.makeArrow("chevron.up")
    private let downArrow  = DPadView.makeArrow("chevron.down")
    private let leftArrow  = DPadView.makeArrow("chevron.left")
    private let rightArrow = DPadView.makeArrow("chevron.right")

    private static func makeArrow(_ symbol: String) -> UIImageView {
        let config = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let view = UIImageView(image: UIImage(systemName: symbol, withConfiguration: config))
        view.tintColor = UIColor.white.withAlphaComponent(0.55)
        view.contentMode = .center
        return view
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupAppearance() {
        backgroundColor = .clear
        isMultipleTouchEnabled = false

        // 圆形底盘
        layer.cornerRadius = bounds.width / 2
        layer.masksToBounds = true

        for arrow in [upArrow, downArrow, leftArrow, rightArrow] {
            addSubview(arrow)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        layer.cornerRadius = w / 2

        let s: CGFloat = 20
        let cx = w / 2, cy = h / 2
        upArrow.frame    = CGRect(x: cx - s/2, y: 5,          width: s, height: s)
        downArrow.frame  = CGRect(x: cx - s/2, y: h - s - 5,  width: s, height: s)
        leftArrow.frame  = CGRect(x: 5,        y: cy - s/2,   width: s, height: s)
        rightArrow.frame = CGRect(x: w - s - 5, y: cy - s/2,  width: s, height: s)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height

        // 圆形底盘
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.07).cgColor)
        ctx.fillEllipse(in: rect)
        // 外圈描边，让方向区有"实体"边界
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.10).cgColor)
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))

        // 十字形轨道
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.11).cgColor)
        let arm: CGFloat = w / 3
        ctx.fill(CGRect(x: (w - arm) / 2, y: 0, width: arm, height: h))
        ctx.fill(CGRect(x: 0, y: (h - arm) / 2, width: w, height: arm))

        // 中心圆
        let cr: CGFloat = arm * 0.36
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.16).cgColor)
        ctx.fillEllipse(in: CGRect(x: (w - cr*2)/2, y: (h - cr*2)/2, width: cr*2, height: cr*2))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?)    { clear() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { clear() }

    private func update(_ touches: Set<UITouch>) {
        guard let pt = touches.first?.location(in: self) else { return }
        let cx = bounds.midX, cy = bounds.midY
        let dx = pt.x - cx, dy = pt.y - cy
        let dead: CGFloat = bounds.width * 0.15

        var dirs: EmulatorButton = []
        if dy < -dead { dirs.insert(.up) }
        if dy >  dead { dirs.insert(.down) }
        if dx < -dead { dirs.insert(.left) }
        if dx >  dead { dirs.insert(.right) }

        // 高亮按下的方向
        let idleColor    = UIColor.white.withAlphaComponent(0.45)
        let activeColor  = RT.accent
        upArrow.tintColor    = dirs.contains(.up)    ? activeColor : idleColor
        downArrow.tintColor  = dirs.contains(.down)  ? activeColor : idleColor
        leftArrow.tintColor  = dirs.contains(.left)  ? activeColor : idleColor
        rightArrow.tintColor = dirs.contains(.right) ? activeColor : idleColor

        if dirs != currentDirections {
            currentDirections = dirs
            delegate?.dpadView(self, directionsChanged: dirs)
            // 方向变化时触觉反馈
            if !dirs.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func clear() {
        [upArrow, downArrow, leftArrow, rightArrow].forEach {
            $0.tintColor = UIColor.white.withAlphaComponent(0.45)
        }
        guard !currentDirections.isEmpty else { return }
        currentDirections = []
        delegate?.dpadView(self, directionsChanged: [])
    }
}

// MARK: - 圆形动作按钮（A/B/X/Y）
final class ActionButton: UIButton {

    private let labelText: String
    private let baseColor: UIColor

    init(label: String, color: UIColor) {
        self.labelText = label
        self.baseColor = color
        super.init(frame: .zero)
        setupAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupAppearance() {
        setTitle(labelText, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        setTitleColor(UIColor.white.withAlphaComponent(0.95), for: .normal)
        // 深色玻璃底 + 平台色描边／辉光，比实心糖豆按钮更贴近掌机机身
        backgroundColor = UIColor(white: 0.05, alpha: 0.62)
        layer.borderColor = baseColor.withAlphaComponent(0.62).cgColor
        layer.borderWidth = 1.5
        layer.cornerCurve = .continuous
        layer.shadowColor = baseColor.cgColor
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0.30
        layer.shadowRadius = 10
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.width / 2
        // 阴影沿按钮轮廓走，避免方形投影
        layer.shadowPath = UIBezierPath(ovalIn: bounds).cgPath
    }

    func setLabel(_ text: String) {
        setTitle(text, for: .normal)
    }

    func setPressed(_ pressed: Bool) {
        layer.borderColor = baseColor.withAlphaComponent(pressed ? 1.0 : 0.62).cgColor
        layer.shadowOpacity = pressed ? 0.7 : 0.30
        UIView.animate(withDuration: 0.06,
                       delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.transform = pressed ? CGAffineTransform(scaleX: 0.92, y: 0.92) : .identity
            self.backgroundColor = pressed
                ? self.baseColor.withAlphaComponent(0.55)
                : UIColor(white: 0.05, alpha: 0.62)
        }
    }
}

// MARK: - 小型功能按钮（START/SEL）
final class SmallButton: UIButton {

    init(label: String) {
        super.init(frame: .zero)
        applyLabel(label)
        backgroundColor = UIColor(white: 1, alpha: 0.10)
        layer.borderColor = UIColor(white: 1, alpha: 0.18).cgColor
        layer.borderWidth = 1
        layer.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }

    private func applyLabel(_ text: String) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.82),
            .kern: 0.8,
        ])
        setAttributedTitle(attr, for: .normal)
    }

    func setPressed(_ pressed: Bool) {
        UIView.animate(withDuration: 0.05,
                       delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.backgroundColor = UIColor(white: 1, alpha: pressed ? 0.26 : 0.10)
            self.transform = pressed ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        }
    }
}

// MARK: - 安全下标
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - 只拦截自身子控件触摸的容器视图
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        // 如果命中的是自身（背景），返回 nil 让触摸穿透到下层
        return hit === self ? nil : hit
    }
}
