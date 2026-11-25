// AppThemeManager.swift
// 主题/外观管理：跟随系统 / 浅色 / 深色 / 磷光绿
// 视觉令牌统一由 RetroDesignSystem 的 RT 提供，本类型只负责「选择与广播」。

import UIKit

enum AppTheme: String, CaseIterable {
    case system  = "system"
    case light   = "light"
    case dark    = "dark"
    case retro   = "retro"

    var localizedName: String {
        switch self {
        case .system: return L10n.str("theme.system")
        case .light:  return L10n.str("theme.light")
        case .dark:   return L10n.str("theme.dark")
        case .retro:  return L10n.str("theme.retro")
        }
    }

    /// 设置页预览用：把主题映射到调色板
    func previewPalette(dark: Bool) -> RTPalette {
        switch self {
        case .system: return dark ? .cathode : .paper
        case .light:  return .paper
        case .dark:   return .cathode
        case .retro:  return .phosphor
        }
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light:  return .light
        case .dark:   return .dark
        case .retro:  return .dark   // 磷光主题基于深色
        }
    }

    /// 强调色取自当前主题（琥珀 / 磷光绿）
    var tintColor: UIColor { RT.accent }
}

final class AppThemeManager {

    static let shared = AppThemeManager()
    private let key = "app_theme_v1"

    private(set) var current: AppTheme = .system

    private init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let theme = AppTheme(rawValue: raw) {
            current = theme
        }
    }

    func apply(_ theme: AppTheme, to window: UIWindow?) {
        current = theme
        UserDefaults.standard.set(theme.rawValue, forKey: key)

        let windows = Self.allWindows() + (window.map { [$0] } ?? [])
        UIView.animate(withDuration: 0.24) {
            for w in windows {
                w.overrideUserInterfaceStyle = theme.userInterfaceStyle
                w.tintColor = theme.tintColor
                w.rootViewController?.view.backgroundColor = RT.canvas
            }
        }

        NotificationCenter.default.post(name: RT.themeDidChange, object: nil)
    }

    /// 在 App 启动时调用，恢复上次主题
    func applyStored(to window: UIWindow?) {
        current = AppTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .system
        for w in Self.allWindows() + (window.map { [$0] } ?? []) {
            w.overrideUserInterfaceStyle = current.userInterfaceStyle
            w.tintColor = current.tintColor
        }
    }

    private static func allWindows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
    }
}
