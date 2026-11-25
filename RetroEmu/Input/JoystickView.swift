// JoystickView.swift
// 固定摇杆 — 底盘常驻显示，旋钮跟随手指，松手弹回中心
// 外观：深色底盘 + 青色发光圆环 + 四方向箭头 + 中心旋钮

import UIKit

protocol JoystickViewDelegate: AnyObject {
    func joystickView(_ view: JoystickView, directionsChanged directions: EmulatorButton)
}

final class JoystickView: UIView {

    weak var delegate: JoystickViewDelegate?

    var deadZoneRatio: CGFloat  = 0.20   // 死区（相对底盘半径）
    var knobRangeRatio: CGFloat = 0.50   // 旋钮最大偏移（相对底盘半径）

    // MARK: - 子视图
    private let baseView   = UIView()        // 底盘
    private let ringView   = UIView()        // 发光圆环
    private let knobView   = UIView()        // 旋钮
    private let arrowLayer = CAShapeLayer()  // 四方向箭头

    // MARK: - 状态
    private var trackingTouch: UITouch?
    private var currentDirections: EmulatorButton = []

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setup() {
        backgroundColor = .clear

        // 底盘
        baseView.backgroundColor = UIColor(white: 0.06, alpha: 0.70)
        baseView.layer.borderColor = UIColor.white.withAlphaComponent(0.15).cgColor
        baseView.layer.borderWidth = 1.5
        addSubview(baseView)

        // 方向箭头加在底盘上
        arrowLayer.fillColor   = UIColor.white.withAlphaComponent(0.22).cgColor
        arrowLayer.strokeColor = UIColor.white.withAlphaComponent(0.30).cgColor
        arrowLayer.lineWidth   = 1
        baseView.layer.addSublayer(arrowLayer)

        // 发光圆环
        ringView.backgroundColor = .clear
        ringView.layer.borderWidth = 2.2
        ringView.layer.borderColor = RT.accent.withAlphaComponent(0.75).cgColor
        addSubview(ringView)

        // 旋钮
        knobView.backgroundColor = UIColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 0.95)
        knobView.layer.borderColor = RT.accent.withAlphaComponent(0.95).cgColor
        knobView.layer.borderWidth = 2.5
        knobView.layer.shadowColor   = RT.accent.withAlphaComponent(0.5).cgColor
        knobView.layer.shadowRadius  = 8
        knobView.layer.shadowOpacity = 0.7
        knobView.layer.shadowOffset  = .zero
        addSubview(knobView)

        // 四角星图标
        let star = UILabel()
        star.text = "✦"
        star.textColor = RT.accent.withAlphaComponent(1.0)
        star.font = .systemFont(ofSize: 16, weight: .bold)
        star.textAlignment = .center
        star.translatesAutoresizingMaskIntoConstraints = false
        knobView.addSubview(star)
        NSLayoutConstraint.activate([
            star.centerXAnchor.constraint(equalTo: knobView.centerXAnchor),
            star.centerYAnchor.constraint(equalTo: knobView.centerYAnchor),
        ])
    }

    // MARK: - Layout（由外部设置 frame 后自动布局）

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let r = min(w, h) / 2

        // 底盘铺满
        baseView.frame = bounds
        baseView.layer.cornerRadius = r

        // 圆环略小
        let rr = r * 0.86
        ringView.bounds = CGRect(origin: .zero, size: CGSize(width: rr * 2, height: rr * 2))
        ringView.center = CGPoint(x: w / 2, y: h / 2)
        ringView.layer.cornerRadius = rr

        // 旋钮
        let kr = r * 0.40
        knobView.bounds = CGRect(origin: .zero, size: CGSize(width: kr * 2, height: kr * 2))
        knobView.center = CGPoint(x: w / 2, y: h / 2)
        knobView.layer.cornerRadius = kr

        // 箭头
        arrowLayer.frame = bounds
        drawArrows()
    }

    // MARK: - 触摸处理

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackingTouch == nil, let touch = touches.first else { return }
        trackingTouch = touch
        updateKnob(to: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackingTouch, touches.contains(touch) else { return }
        updateKnob(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackingTouch, touches.contains(touch) else { return }
        endTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTracking()
    }

    // MARK: - 旋钮逻辑

    private func updateKnob(to pt: CGPoint) {
        let cx = bounds.midX, cy = bounds.midY
        let r  = min(bounds.width, bounds.height) / 2
        let maxOffset = r * knobRangeRatio
        let dead      = r * deadZoneRatio

        let dx   = pt.x - cx
        let dy   = pt.y - cy
        let dist = sqrt(dx * dx + dy * dy)

        let clamped = min(dist, maxOffset)
        let angle   = atan2(dy, dx)
        let knobX   = cx + cos(angle) * clamped
        let knobY   = cy + sin(angle) * clamped

        knobView.center = CGPoint(x: knobX, y: knobY)

        // 圆环发光强度随偏移变化
        let intensity = maxOffset > 0 ? min(clamped / maxOffset, 1.0) : 0
        let alpha = 0.55 + 0.45 * intensity
        ringView.layer.borderColor = RT.accent.withAlphaComponent(alpha).cgColor

        // 方向计算
        var dirs: EmulatorButton = []
        if dist > dead {
            let deg = angle * 180 / .pi
            if deg > -135 && deg < -45  { dirs.insert(.up) }
            if deg >   45 && deg <  135 { dirs.insert(.down) }
            if deg < -135 || deg > 135  { dirs.insert(.left) }
            if deg >  -45 && deg <   45 { dirs.insert(.right) }
        }

        updateArrowHighlight(dirs: dirs)

        if dirs != currentDirections {
            currentDirections = dirs
            delegate?.joystickView(self, directionsChanged: dirs)
            if !dirs.isEmpty {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func endTracking() {
        trackingTouch = nil

        // 旋钮弹回中心
        UIView.animate(withDuration: 0.15,
                       delay: 0,
                       usingSpringWithDamping: 0.6,
                       initialSpringVelocity: 0.3,
                       options: [.curveEaseOut, .allowUserInteraction]) {
            self.knobView.center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        }

        // 圆环恢复默认亮度
        ringView.layer.borderColor = RT.accent.withAlphaComponent(0.75).cgColor

        if !currentDirections.isEmpty {
            currentDirections = []
            delegate?.joystickView(self, directionsChanged: [])
        }

        updateArrowHighlight(dirs: [])
    }

    // MARK: - 箭头绘制

    private func drawArrows() {
        let w = bounds.width, h = bounds.height
        let cx = w / 2, cy = h / 2
        let r  = min(w, h) / 2
        let inner: CGFloat = r * 0.54
        let aw:    CGFloat = r * 0.20
        let ah:    CGFloat = r * 0.17

        let path = CGMutablePath()
        // 上
        path.addLines(between: [
            CGPoint(x: cx,      y: cy - inner - ah),
            CGPoint(x: cx - aw, y: cy - inner),
            CGPoint(x: cx + aw, y: cy - inner),
        ]); path.closeSubpath()
        // 下
        path.addLines(between: [
            CGPoint(x: cx,      y: cy + inner + ah),
            CGPoint(x: cx - aw, y: cy + inner),
            CGPoint(x: cx + aw, y: cy + inner),
        ]); path.closeSubpath()
        // 左
        path.addLines(between: [
            CGPoint(x: cx - inner - ah, y: cy),
            CGPoint(x: cx - inner,      y: cy - aw),
            CGPoint(x: cx - inner,      y: cy + aw),
        ]); path.closeSubpath()
        // 右
        path.addLines(between: [
            CGPoint(x: cx + inner + ah, y: cy),
            CGPoint(x: cx + inner,      y: cy - aw),
            CGPoint(x: cx + inner,      y: cy + aw),
        ]); path.closeSubpath()

        arrowLayer.path = path
    }

    private func updateArrowHighlight(dirs: EmulatorButton) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arrowLayer.fillColor = dirs.isEmpty
            ? UIColor.white.withAlphaComponent(0.22).cgColor
            : RT.accent.withAlphaComponent(0.65).cgColor
        CATransaction.commit()
    }
}
