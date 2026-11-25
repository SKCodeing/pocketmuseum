// ScreenLayoutSettings.swift
// 持久化保存每个系统的画面缩放和位移

import UIKit

final class ScreenLayoutSettings {
    static let shared = ScreenLayoutSettings()
    private init() {}

    struct Layout {
        var scale: CGFloat   // 1.0 = 默认适配宽高比
        var offsetX: CGFloat // 相对屏幕宽的比例偏移
        var offsetY: CGFloat // 相对屏幕高的比例偏移
    }

    private func key(_ system: EmulatorSystem, portrait: Bool) -> String {
        "screen_layout_\(system.rawValue)_\(portrait ? "p" : "l")"
    }

    func load(for system: EmulatorSystem, portrait: Bool) -> Layout {
        let k = key(system, portrait: portrait)
        let scale   = CGFloat(UserDefaults.standard.float(forKey: k + "_scale"))
        let offsetX = CGFloat(UserDefaults.standard.float(forKey: k + "_ox"))
        let offsetY = CGFloat(UserDefaults.standard.float(forKey: k + "_oy"))
        return Layout(
            scale:   scale   > 0 ? scale : 1.0,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }

    func save(_ layout: Layout, for system: EmulatorSystem, portrait: Bool) {
        let k = key(system, portrait: portrait)
        UserDefaults.standard.set(Float(layout.scale),   forKey: k + "_scale")
        UserDefaults.standard.set(Float(layout.offsetX), forKey: k + "_ox")
        UserDefaults.standard.set(Float(layout.offsetY), forKey: k + "_oy")
    }

    func reset(for system: EmulatorSystem, portrait: Bool) {
        save(Layout(scale: 1.0, offsetX: 0, offsetY: 0), for: system, portrait: portrait)
    }
}
