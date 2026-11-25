// GamepadLayoutSettings.swift
// 持久化虚拟手柄每个按钮的位置和大小

import UIKit

struct ButtonLayout: Codable {
    var centerX: CGFloat
    var centerY: CGFloat
    var size: CGFloat
    var opacity: CGFloat  // 0.0 ~ 1.0

    init(centerX: CGFloat, centerY: CGFloat, size: CGFloat, opacity: CGFloat = 0.85) {
        self.centerX = centerX
        self.centerY = centerY
        self.size = size
        self.opacity = opacity
    }
}

final class GamepadLayoutSettings {

    static let shared = GamepadLayoutSettings()
    private let key = "gamepad_layout_v1"

    // 默认布局（比例坐标）
    private static let defaults: [String: ButtonLayout] = [
        "dpad":   ButtonLayout(centerX: 0.15, centerY: 0.78, size: 120, opacity: 0.85),
        "btnA":   ButtonLayout(centerX: 0.88, centerY: 0.72, size: 48,  opacity: 0.85),
        "btnB":   ButtonLayout(centerX: 0.78, centerY: 0.82, size: 48,  opacity: 0.85),
        "btnX":   ButtonLayout(centerX: 0.78, centerY: 0.62, size: 48,  opacity: 0.85),
        "btnY":   ButtonLayout(centerX: 0.68, centerY: 0.72, size: 48,  opacity: 0.85),
        "start":  ButtonLayout(centerX: 0.60, centerY: 0.92, size: 52,  opacity: 0.85),
        "select": ButtonLayout(centerX: 0.40, centerY: 0.92, size: 52,  opacity: 0.85),
    ]

    private var layouts: [String: ButtonLayout] = [:]

    private init() { load() }

    func layout(for key: String) -> ButtonLayout {
        layouts[key] ?? Self.defaults[key] ?? ButtonLayout(centerX: 0.5, centerY: 0.5, size: 48)
    }

    func setLayout(_ layout: ButtonLayout, for key: String) {
        layouts[key] = layout
        save()
    }

    func reset() {
        layouts = [:]
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ButtonLayout].self, from: data)
        else { return }
        layouts = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
