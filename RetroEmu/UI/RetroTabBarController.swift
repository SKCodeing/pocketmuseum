// RetroTabBarController.swift
// 主容器：游戏库 / 时光 / 设置 三个自持导航栈的页面 + 浮岛式标签栏

import UIKit

final class RetroTabBarController: UIViewController {

    // 页面视图惰性创建：时光页/设置页一建 view 就要把几百个存档目录全 stat 一遍，
    // 不该压在启动路径上。这边只存控制器对象（很轻），视图等切到那一页再建。
    private lazy var childrenViews: [UIViewController] = [
        GameListViewController(),
        TimelineViewController(),
        SettingsViewController(),
    ]

    /// 已经挂进容器的页
    private var installedIndexes: Set<Int> = []

    private let tabBar = RTFloatingTabBar(items: [
        .init(icon: "square.grid.2x2.fill", title: L10n.str("tab.library")),
        .init(icon: "clock.arrow.circlepath", title: L10n.str("tab.timeline")),
        .init(icon: "slider.horizontal.3", title: L10n.str("tab.settings")),
    ])

    private let contentContainer = UIView()
    private var currentIndex = -1

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentContainer)
        contentContainer.pinEdges(to: view)

        view.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
        ])

        tabBar.onSelect = { [weak self] index in
            self?.select(index: index, animated: true)
        }

        // 只建首屏那一页，其余等切页时再建
        installChild(at: 0)

        select(index: 0, animated: false)

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(themeDidChange),
                                              name: RT.themeDidChange,
                                              object: nil)
    }

    /// 把某一页的视图挂进容器（只在第一次切到它时执行）
    @discardableResult
    private func installChild(at index: Int) -> UIViewController {
        let child = childrenViews[index]
        guard !installedIndexes.contains(index) else { return child }
        installedIndexes.insert(index)
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        child.additionalSafeAreaInsets.bottom = RT.Metric.tabBarHeight + 18
        contentContainer.addSubview(child.view)
        child.view.pinEdges(to: contentContainer)
        child.view.isHidden = true
        child.didMove(toParent: self)
        return child
    }

    func select(index: Int, animated: Bool) {
        guard childrenViews.indices.contains(index) else { return }
        let previous = currentIndex
        currentIndex = index

        let target = installChild(at: index)
        target.view.isHidden = false
        tabBar.select(index, animated: animated)

        if previous >= 0, previous != index, installedIndexes.contains(previous),
           let previousView = childrenViews[previous].viewIfLoaded {
            if animated {
                target.view.alpha = 0
                UIView.animate(withDuration: 0.22) {
                    target.view.alpha = 1
                    previousView.alpha = 0
                } completion: { _ in
                    previousView.isHidden = true
                    previousView.alpha = 1
                }
            } else {
                previousView.isHidden = true
            }
        } else {
            target.view.alpha = 1
        }
    }

    @objc private func themeDidChange() {
        view.backgroundColor = RT.canvas
        tabBar.backgroundColor = RT.surface.withAlphaComponent(0.92)
        tabBar.layer.borderColor = RT.stroke.cgColor
        // 没建过的页不用刷，它建的时候会直接读到新调色板
        for index in installedIndexes {
            (childrenViews[index] as? RTThemeRefreshable)?.refreshTheme()
        }
    }
}

/// 页面实现该协议后，主题切换时会被通知刷新
protocol RTThemeRefreshable: AnyObject {
    func refreshTheme()
}
