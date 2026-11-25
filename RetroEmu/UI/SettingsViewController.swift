// SettingsViewController.swift
// 设置：卡片分组 + 主题预览 + 即改即生效
// 产品思路：只保留「外观 / 玩法 / 操控 / 数据 / 关于」五组，
// 每一项都回答「改了什么、现在是什么值、点了会发生什么」。

import UIKit

final class SettingsViewController: UIViewController {

    // MARK: - 容器

    private let headerView = UIView()
    private let plaqueLabel = UILabel()
    private let titleLabel = UILabel()

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    private var themeStrip = SettingsThemeStrip()

    // 需要随数据刷新的行
    private weak var filterRow: SettingsRowView?
    private weak var dpadRow: SettingsRowView?
    private weak var autoSaveRow: SettingsRowView?
    private weak var rewindRow: SettingsRowView?
    private weak var swipeRow: SettingsRowView?
    private weak var watermarkRow: SettingsRowView?
    private weak var skinRow: SettingsRowView?
    private weak var gamepadRow: SettingsRowView?
    private weak var iCloudRow: SettingsRowView?
    private weak var webdavRow: SettingsRowView?
    private weak var tagRow: SettingsRowView?
    private weak var achievementRow: SettingsRowView?
    private weak var logRow: SettingsRowView?

    private var builtTheme: AppTheme?

    // 宽屏居中列：窄屏下常量为 0，与改造前的行为完全一致
    private lazy var headerLeadingInset = headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    private lazy var headerTrailingInset = headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    private lazy var scrollLeadingInset = scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    private lazy var scrollTrailingInset = scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    private var lastLaidOutWidth: CGFloat = 0

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        setupHeader()
        setupScroll()
        rebuild()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if builtTheme != AppThemeManager.shared.current {
            rebuild()
        } else {
            refreshValues()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWideLayout()
    }

    /// 宽屏（iPad 横屏、Duo 展开内屏）把设置卡片收成居中阅读栏，窄屏不变。
    private func updateWideLayout() {
        let width = view.bounds.width
        guard width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        let inset = RT.Metric.readingColumnInset(for: width)
        headerLeadingInset.constant = inset
        headerTrailingInset.constant = -inset
        scrollLeadingInset.constant = inset
        scrollTrailingInset.constant = -inset
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - 头部

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("settings.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.6]
        )

        titleLabel.text = L10n.str("settings.title")
        titleLabel.font = RT.Font.display(28)
        titleLabel.textColor = RT.text

        let titleStack = UIStackView(arrangedSubviews: [plaqueLabel, titleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 3
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleStack)

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            titleStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: RT.Metric.screenPadding),
            titleStack.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -12),

            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // 横向贴安全区：Duo 展开后的内屏右侧有系统侧置状态栏，贴 view 边会压到卡片。
            // iPhone / iPad 左右安全区为 0，行为不变。两段常量留给宽屏居中列。
            headerLeadingInset, headerTrailingInset,
        ])
    }

    private func setupScroll() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = RT.Metric.sectionGap
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            scrollLeadingInset, scrollTrailingInset,
            // 底部让出浮岛标签栏，避免最后几行穿在玻璃底下
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: RT.Metric.screenPadding),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -RT.Metric.screenPadding),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor,
                                         constant: -2 * RT.Metric.screenPadding),
        ])
    }

    // MARK: - 构建

    private func rebuild() {
        builtTheme = AppThemeManager.shared.current
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        themeStrip.select(AppThemeManager.shared.current, notify: false)

        stack.addArrangedSubview(makeThemeGroup())
        stack.addArrangedSubview(makePlayGroup())
        stack.addArrangedSubview(makeControlsGroup())
        stack.addArrangedSubview(makeDataGroup())
        stack.addArrangedSubview(makeAboutGroup())
        stack.addArrangedSubview(makeFooter())

        refreshValues()
    }

    private func makeThemeGroup() -> UIView {
        let caption = UILabel()
        caption.text = L10n.str("settings.row.theme")
        caption.font = RT.Font.headline(14)
        caption.textColor = RT.text

        let hint = UILabel()
        hint.text = L10n.str("settings.theme.hint")
        hint.font = RT.Font.caption(11)
        hint.textColor = RT.textTertiary

        let headStack = UIStackView(arrangedSubviews: [caption, hint])
        headStack.axis = .vertical
        headStack.spacing = 2

        let card = RTCardView(style: .plain, radius: 22)

        // 每次重建都生成新的预览条，避免旧约束残留
        let strip = SettingsThemeStrip()
        strip.select(AppThemeManager.shared.current, notify: false)
        strip.onSelect = { theme in
            AppThemeManager.shared.apply(theme, to: UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first)
        }
        themeStrip = strip

        let inner = UIStackView(arrangedSubviews: [headStack, strip])
        inner.axis = .vertical
        inner.spacing = 14
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        let filterRow = SettingsRowView(icon: "wand.and.stars",
                                        title: L10n.str("settings.row.filter"),
                                        subtitle: L10n.str("settings.row.filter.hint"),
                                        value: currentFilterName(),
                                        kind: .disclosure)
        filterRow.onTap = { [weak self] in self?.showFilterPicker() }
        self.filterRow = filterRow

        let watermarkRow = SettingsRowView(icon: "camera.badge.ellipsis",
                                           title: L10n.str("settings.row.watermark"),
                                           subtitle: L10n.str("settings.row.watermark.hint"),
                                           value: nil,
                                           kind: .toggle(UserDefaults.standard.bool(forKey: "screenshot_watermark")))
        watermarkRow.onToggle = { on in
            UserDefaults.standard.set(on, forKey: "screenshot_watermark")
        }
        self.watermarkRow = watermarkRow

        return makeGroup(title: L10n.str("settings.section.appearance"),
                         cards: [card, makeCard(rows: [filterRow, watermarkRow])])
    }

    private func makePlayGroup() -> UIView {
        let autoSaveRow = SettingsRowView(icon: "clock.arrow.2.circlepath",
                                          title: L10n.str("settings.row.autosave"),
                                          subtitle: L10n.str("settings.row.autosave.hint"),
                                          value: autoSaveText(),
                                          kind: .disclosure)
        autoSaveRow.onTap = { [weak self] in self?.showAutoSaveIntervalPicker() }
        self.autoSaveRow = autoSaveRow

        let rewindRow = SettingsRowView(icon: "arrow.uturn.backward.circle",
                                        title: L10n.str("settings.row.rewind"),
                                        subtitle: L10n.str("settings.row.rewind.hint"),
                                        value: rewindText(),
                                        kind: .disclosure)
        rewindRow.onTap = { [weak self] in self?.showRewindBufferPicker() }
        self.rewindRow = rewindRow

        let swipeRow = SettingsRowView(icon: "hand.draw",
                                       title: L10n.str("settings.row.swipe"),
                                       subtitle: L10n.str("settings.row.swipe.hint"),
                                       value: nil,
                                       kind: .toggle(UserDefaults.standard.object(forKey: "swipe_gestures_enabled") as? Bool ?? true))
        swipeRow.onToggle = { on in
            UserDefaults.standard.set(on, forKey: "swipe_gestures_enabled")
        }
        self.swipeRow = swipeRow

        return makeGroup(title: L10n.str("settings.section.play"),
                         cards: [makeCard(rows: [autoSaveRow, rewindRow, swipeRow])])
    }

    private func makeControlsGroup() -> UIView {
        let dpadRow = SettingsRowView(icon: "circle.grid.cross",
                                      title: L10n.str("settings.row.dpad"),
                                      subtitle: nil,
                                      value: currentDPadName(),
                                      kind: .disclosure)
        dpadRow.onTap = { [weak self] in self?.showDPadStylePicker() }
        self.dpadRow = dpadRow

        let keymapRow = SettingsRowView(icon: "keyboard",
                                        title: L10n.str("settings.row.keymap"),
                                        subtitle: nil,
                                        value: nil,
                                        kind: .disclosure)
        keymapRow.onTap = { [weak self] in
            guard let self = self else { return }
            self.navigationController?.pushViewController(KeymapViewController(), animated: true)
        }

        let skinRow = SettingsRowView(icon: "paintpalette",
                                      title: L10n.str("settings.row.skin"),
                                      subtitle: L10n.str("settings.row.skin.hint"),
                                      value: nil,
                                      kind: .disclosure)
        skinRow.onTap = { [weak self] in self?.showSkinPicker() }
        self.skinRow = skinRow

        let gamepadRow = SettingsRowView(icon: "gamecontroller",
                                         title: L10n.str("settings.row.gamepad"),
                                         subtitle: nil,
                                         value: gamepadText(),
                                         kind: .readonly)
        self.gamepadRow = gamepadRow

        return makeGroup(title: L10n.str("settings.section.controls"),
                         cards: [makeCard(rows: [dpadRow, keymapRow, skinRow, gamepadRow])])
    }

    private func makeDataGroup() -> UIView {
        let iCloudRow = SettingsRowView(icon: "icloud",
                                        title: L10n.str("settings.row.icloud"),
                                        subtitle: L10n.str("settings.row.icloud.hint"),
                                        value: SaveStateManager.shared.iCloudAvailable
                                            ? L10n.str("settings.row.icloud.on")
                                            : L10n.str("settings.row.icloud.off"),
                                        kind: .readonly)
        self.iCloudRow = iCloudRow

        let webdavRow = SettingsRowView(icon: "externaldrive.connected.to.line.below",
                                        title: L10n.str("settings.row.webdav"),
                                        subtitle: nil,
                                        value: WebDAVClient.savedConfig()?.serverURL ?? L10n.str("settings.row.webdav.off"),
                                        kind: .disclosure)
        webdavRow.onTap = { [weak self] in self?.showWebDAVSettings() }
        self.webdavRow = webdavRow

        let tagRow = SettingsRowView(icon: "tag",
                                     title: L10n.str("settings.row.tags"),
                                     subtitle: nil,
                                     value: L10n.str("settings.row.tags.count", GameTagManager.shared.tags.count),
                                     kind: .disclosure)
        tagRow.onTap = { [weak self] in self?.showTagManager() }
        self.tagRow = tagRow

        let achievementRow = SettingsRowView(icon: "trophy",
                                             title: L10n.str("settings.row.achievements"),
                                             subtitle: nil,
                                             value: AchievementManager.shared.currentUser?.username ?? L10n.str("settings.row.achievements.off"),
                                             kind: .disclosure)
        achievementRow.onTap = { [weak self] in self?.showRAAccountSettings() }
        self.achievementRow = achievementRow

        let clearRow = SettingsRowView(icon: "trash",
                                       title: L10n.str("settings.row.clearcache"),
                                       subtitle: L10n.str("settings.row.clearcache.hint"),
                                       value: nil,
                                       kind: .danger)
        clearRow.onTap = { [weak self] in self?.confirmClearCache() }

        return makeGroup(title: L10n.str("settings.section.data"),
                         cards: [makeCard(rows: [iCloudRow, webdavRow, tagRow]),
                                 makeCard(rows: [achievementRow, clearRow])])
    }

    private func makeAboutGroup() -> UIView {
        let versionRow = SettingsRowView(icon: "info.circle",
                                         title: L10n.str("settings.row.version"),
                                         subtitle: nil,
                                         value: Self.versionText,
                                         kind: .readonly)

        let licenseRow = SettingsRowView(icon: "doc.text",
                                         title: L10n.str("settings.row.opensource"),
                                         subtitle: nil,
                                         value: "GPL / MIT",
                                         kind: .disclosure)
        licenseRow.onTap = { [weak self] in self?.showLicenses() }

        let logRow = SettingsRowView(icon: "ladybug",
                                     title: L10n.str("settings.row.log"),
                                     subtitle: nil,
                                     value: L10n.str("settings.row.log.count", EmuLog.recentLogs.count),
                                     kind: .disclosure)
        logRow.onTap = { [weak self] in self?.showDebugLog() }
        self.logRow = logRow

        return makeGroup(title: L10n.str("settings.section.about"),
                         cards: [makeCard(rows: [versionRow, licenseRow, logRow])])
    }

    private func makeFooter() -> UIView {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = NSAttributedString(
            string: L10n.str("settings.footer", Self.versionText),
            attributes: [.font: RT.Font.mono(10),
                         .foregroundColor: RT.textTertiary]
        )
        let box = UIView()
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }

    // MARK: - 卡片工具

    private func makeGroup(title: String, cards: [UIView]) -> UIView {
        let group = UIStackView()
        group.axis = .vertical
        group.spacing = 10

        let header = UILabel()
        header.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.textTertiary,
                         .kern: 1.8]
        )
        group.addArrangedSubview(header)
        cards.forEach { group.addArrangedSubview($0) }
        return group
    }

    private func makeCard(rows: [UIView]) -> UIView {
        let card = RTCardView(style: .plain, radius: 22)
        let rowStack = UIStackView()
        rowStack.axis = .vertical
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        for (index, row) in rows.enumerated() {
            if index > 0 {
                let holder = UIView()
                let line = UIView()
                line.backgroundColor = RT.stroke
                holder.addSubview(line)
                NSLayoutConstraint.activate([
                    line.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 56),
                    line.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -14),
                    line.topAnchor.constraint(equalTo: holder.topAnchor),
                    line.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
                    line.heightAnchor.constraint(equalToConstant: 1),
                    holder.heightAnchor.constraint(equalToConstant: 1),
                ])
                rowStack.addArrangedSubview(holder)
            }
            rowStack.addArrangedSubview(row)
        }

        card.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 6),
            rowStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            rowStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            rowStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
        ])
        return card
    }

    // MARK: - 值文案

    private static var versionText: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func currentFilterName() -> String {
        (RenderFilter(rawValue: UserDefaults.standard.integer(forKey: "render_filter")) ?? .nearest).displayName
    }

    private func currentDPadName() -> String {
        (DPadStyle(rawValue: UserDefaults.standard.string(forKey: "dpad_style") ?? "") ?? .dpad).rawValue
    }

    private func autoSaveText() -> String {
        let interval = UserDefaults.standard.integer(forKey: "auto_save_interval")
        return interval == 0 ? L10n.str("settings.value.off") : L10n.str("settings.value.seconds", interval)
    }

    private func rewindText() -> String {
        let dur = UserDefaults.standard.integer(forKey: "rewind_buffer_duration")
        return dur == 0 ? L10n.str("settings.value.off") : L10n.str("settings.value.seconds", dur > 0 ? dur : 10)
    }

    private func gamepadText() -> String {
        GamepadManager.shared.hasConnectedController
            ? L10n.str("settings.row.gamepad.on")
            : L10n.str("settings.row.gamepad.off")
    }

    private func refreshValues() {
        filterRow?.valueText = currentFilterName()
        dpadRow?.valueText = currentDPadName()
        autoSaveRow?.valueText = autoSaveText()
        rewindRow?.valueText = rewindText()
        gamepadRow?.valueText = gamepadText()
        iCloudRow?.valueText = SaveStateManager.shared.iCloudAvailable
            ? L10n.str("settings.row.icloud.on")
            : L10n.str("settings.row.icloud.off")
        webdavRow?.valueText = WebDAVClient.savedConfig()?.serverURL ?? L10n.str("settings.row.webdav.off")
        tagRow?.valueText = L10n.str("settings.row.tags.count", GameTagManager.shared.tags.count)
        achievementRow?.valueText = AchievementManager.shared.currentUser?.username
            ?? L10n.str("settings.row.achievements.off")
        logRow?.valueText = L10n.str("settings.row.log.count", EmuLog.recentLogs.count)
        swipeRow?.setOn(UserDefaults.standard.object(forKey: "swipe_gestures_enabled") as? Bool ?? true)
        watermarkRow?.setOn(UserDefaults.standard.bool(forKey: "screenshot_watermark"))
        themeStrip.select(AppThemeManager.shared.current, notify: false)
    }

    // MARK: - 选择器

    private func sheet(title: String, message: String? = nil, actions: [RTMenuAction]) {
        RTMenuSheetViewController.present(from: self, title: title, message: message, actions: actions)
    }

    private func showFilterPicker() {
        let current = RenderFilter(rawValue: UserDefaults.standard.integer(forKey: "render_filter")) ?? .nearest
        let actions = RenderFilter.allCases.map { filter in
            RTMenuAction(title: filter.displayName,
                         subtitle: Self.filterSubtitle(filter),
                         icon: Self.filterIcon(filter),
                         selected: filter == current) { [weak self] in
                UserDefaults.standard.set(filter.rawValue, forKey: "render_filter")
                self?.refreshValues()
            }
        }
        sheet(title: L10n.str("settings.filter.title"), actions: actions)
    }

    private func showDPadStylePicker() {
        let current = DPadStyle(rawValue: UserDefaults.standard.string(forKey: "dpad_style") ?? "") ?? .dpad
        let actions = DPadStyle.allCases.map { style in
            RTMenuAction(title: style.rawValue,
                         subtitle: style == .dpad ? L10n.str("settings.dpad.dpad.hint") : L10n.str("settings.dpad.joystick.hint"),
                         icon: style == .dpad ? "plus" : "circle.dotted",
                         selected: style == current) { [weak self] in
                UserDefaults.standard.set(style.rawValue, forKey: "dpad_style")
                self?.refreshValues()
            }
        }
        sheet(title: L10n.str("settings.dpad.title"), actions: actions)
    }

    private func showAutoSaveIntervalPicker() {
        let current = UserDefaults.standard.integer(forKey: "auto_save_interval")
        let options: [(String, Int)] = [
            (L10n.str("settings.value.off"), 0),
            (L10n.str("settings.value.seconds", 30), 30),
            (L10n.str("settings.value.seconds.recommended", 60), 60),
            (L10n.str("settings.value.seconds", 120), 120),
            (L10n.str("settings.value.seconds", 300), 300),
        ]
        let actions = options.map { label, value in
            RTMenuAction(title: label,
                         icon: value == 0 ? "xmark.circle" : "timer",
                         selected: current == value) { [weak self] in
                UserDefaults.standard.set(value, forKey: "auto_save_interval")
                EmulatorCore.shared.autoSaveInterval = value == 0 ? 0 : TimeInterval(value)
                self?.refreshValues()
            }
        }
        sheet(title: L10n.str("settings.autosave.title"),
              message: L10n.str("settings.autosave.message"),
              actions: actions)
    }

    private func showRewindBufferPicker() {
        let current = UserDefaults.standard.integer(forKey: "rewind_buffer_duration")
        let options: [(String, Int)] = [
            (L10n.str("settings.value.off"), 0),
            (L10n.str("settings.value.seconds", 5), 5),
            (L10n.str("settings.value.seconds.recommended", 10), 10),
            (L10n.str("settings.value.seconds", 30), 30),
        ]
        let actions = options.map { label, value in
            RTMenuAction(title: label,
                         icon: value == 0 ? "xmark.circle" : "arrow.uturn.backward",
                         selected: current == value) { [weak self] in
                UserDefaults.standard.set(value, forKey: "rewind_buffer_duration")
                RewindManager.shared.bufferDuration = value
                self?.refreshValues()
            }
        }
        sheet(title: L10n.str("settings.rewind.title"),
              message: L10n.str("settings.rewind.message"),
              actions: actions)
    }

    private func showSkinPicker() {
        let actions = EmulatorSystem.allCases.map { system in
            RTMenuAction(title: system.displayName,
                         subtitle: system.shortCode,
                         icon: "paintpalette") { [weak self] in
                guard let self = self else { return }
                let vc = SkinPickerViewController(system: system)
                self.present(UINavigationController(rootViewController: vc), animated: true)
            }
        }
        sheet(title: L10n.str("settings.skin.title"),
              message: L10n.str("settings.skin.message"),
              actions: actions)
    }

    private func showLicenses() {
        let text = L10n.str("settings.opensource.message")
        let actions = [RTMenuAction(title: L10n.str("btn.ok"), icon: "checkmark") {}]
        sheet(title: L10n.str("settings.opensource.title"), message: text, actions: actions)
    }

    private func confirmClearCache() {
        let alert = UIAlertController(title: L10n.str("settings.clearcache.title"),
                                      message: L10n.str("settings.clearcache.message"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("settings.clearcache.confirm"), style: .destructive) { _ in
            CoverArtManager.shared.clearCache()
            RTToast.show(L10n.str("settings.clearcache.done"), icon: "checkmark")
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func showDebugLog() {
        let nav = UINavigationController(rootViewController: DebugLogViewController())
        present(nav, animated: true)
    }

    // MARK: - 标签

    private func showTagManager() {
        var actions: [RTMenuAction] = GameTagManager.shared.tags.map { tag in
            let isBuiltin = GameTag.builtinIDs.contains(tag.id)
            return RTMenuAction(title: tag.name,
                                subtitle: L10n.str("settings.tags.count", tag.romNames.count, isBuiltin ? L10n.str("settings.tags.builtin") : L10n.str("settings.tags.custom")),
                                icon: "tag",
                                handler: { [weak self] in
                if !isBuiltin { self?.confirmDeleteTag(tag) }
                else { RTToast.show(L10n.str("settings.tags.builtin.locked"), icon: "lock") }
            })
        }
        actions.append(RTMenuAction(title: L10n.str("settings.tags.create"),
                                    icon: "plus.circle") { [weak self] in
            self?.showCreateTagDialog()
        })
        sheet(title: L10n.str("settings.tags.title"),
              message: L10n.str("settings.tags.message"),
              actions: actions)
    }

    private func showCreateTagDialog() {
        let alert = UIAlertController(title: L10n.str("settings.tags.create"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = L10n.str("settings.tags.name.placeholder") }
        alert.addAction(UIAlertAction(title: L10n.str("settings.tags.create"), style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !name.isEmpty else { return }
            _ = GameTagManager.shared.createTag(name: name)
            self?.refreshValues()
            RTToast.show(L10n.str("settings.tags.created", name), icon: "tag")
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func confirmDeleteTag(_ tag: GameTag) {
        let alert = UIAlertController(title: L10n.str("settings.tags.delete.title"),
                                      message: L10n.str("settings.tags.delete.message", tag.name),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("btn.delete"), style: .destructive) { [weak self] _ in
            GameTagManager.shared.deleteTag(id: tag.id)
            self?.refreshValues()
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - WebDAV

    private func showWebDAVSettings() {
        if let config = WebDAVClient.savedConfig() {
            let actions = [
                RTMenuAction(title: L10n.str("settings.webdav.browse"), icon: "folder") { [weak self] in
                    guard let self = self else { return }
                    let client = WebDAVClient(config: config)
                    let vc = CloudImportViewController(provider: client)
                    self.present(UINavigationController(rootViewController: vc), animated: true)
                },
                RTMenuAction(title: L10n.str("settings.webdav.delete"),
                             icon: "trash",
                             destructive: true) { [weak self] in
                    WebDAVClient.deleteConfig()
                    self?.refreshValues()
                },
            ]
            sheet(title: L10n.str("settings.row.webdav"), actions: actions)
        } else {
            let setup = WebDAVSetupViewController()
            setup.onConnected = { [weak self] _ in
                setup.dismiss(animated: true) { self?.refreshValues() }
            }
            present(UINavigationController(rootViewController: setup), animated: true)
        }
    }

    // MARK: - RetroAchievements

    private func showRAAccountSettings() {
        if let user = AchievementManager.shared.currentUser {
            let actions = [
                RTMenuAction(title: L10n.str("settings.achv.logout"),
                             subtitle: user.username,
                             icon: "person.crop.circle.badge.xmark",
                             destructive: true) { [weak self] in
                    AchievementManager.shared.logout()
                    self?.refreshValues()
                },
            ]
            sheet(title: "RetroAchievements", actions: actions)
            return
        }

        let alert = UIAlertController(title: L10n.str("settings.achv.login"),
                                      message: L10n.str("settings.achv.message"),
                                      preferredStyle: .alert)
        alert.addTextField { $0.placeholder = L10n.str("settings.achv.username") }
        alert.addTextField { tf in
            tf.placeholder = L10n.str("settings.achv.apikey")
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: L10n.str("settings.achv.login"), style: .default) { [weak self] _ in
            guard let username = alert.textFields?[0].text, !username.isEmpty,
                  let apiKey = alert.textFields?[1].text, !apiKey.isEmpty else { return }
            AchievementManager.shared.login(username: username, apiKey: apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.refreshValues()
                        RTToast.show(L10n.str("settings.achv.ok"), icon: "trophy")
                    case .failure(let error):
                        RTToast.show(error.localizedDescription, icon: "exclamationmark.triangle")
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 选项文案

    private static func filterSubtitle(_ filter: RenderFilter) -> String {
        switch filter {
        case .nearest:       return L10n.str("settings.filter.nearest.hint")
        case .sharpBilinear: return L10n.str("settings.filter.sharp.hint")
        case .lcdGrid:       return L10n.str("settings.filter.lcd.hint")
        case .crt:           return L10n.str("settings.filter.crt.hint")
        case .scanline:      return L10n.str("settings.filter.scanline.hint")
        case .ntsc:          return L10n.str("settings.filter.ntsc.hint")
        case .hd:            return L10n.str("settings.filter.hd.hint")
        }
    }

    private static func filterIcon(_ filter: RenderFilter) -> String {
        switch filter {
        case .nearest:       return "square.grid.3x3"
        case .sharpBilinear: return "sparkles"
        case .lcdGrid:       return "square.grid.4x3.fill"
        case .crt:           return "tv"
        case .scanline:      return "line.3.horizontal"
        case .ntsc:          return "rainbow"
        case .hd:            return "wand.and.stars"
        }
    }
}

// MARK: - 主题刷新

extension SettingsViewController: RTThemeRefreshable {
    func refreshTheme() {
        view.backgroundColor = RT.canvas
        titleLabel.textColor = RT.text
        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("settings.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.6]
        )
        rebuild()
    }
}

// MARK: - 设置行

final class SettingsRowView: UIView {

    enum Kind {
        case disclosure
        case readonly
        case danger
        case toggle(Bool)
    }

    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let valueLabel = UILabel()
    private let chevron = UIImageView()
    private let toggle = UISwitch()

    private var tapGesture: UITapGestureRecognizer?

    var onTap: (() -> Void)?
    var onToggle: ((Bool) -> Void)?

    init(icon: String,
         title: String,
         subtitle: String? = nil,
         value: String? = nil,
         kind: Kind = .disclosure) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        iconContainer.backgroundColor = RT.accent.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 9
        iconContainer.layer.cornerCurve = .continuous

        iconView.image = UIImage(systemName: icon,
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold))
        iconView.tintColor = RT.accent
        iconView.contentMode = .scaleAspectFit

        titleLabel.text = title
        titleLabel.font = RT.Font.headline(15)
        titleLabel.textColor = RT.text

        subtitleLabel.text = subtitle
        subtitleLabel.font = RT.Font.caption(11)
        subtitleLabel.textColor = RT.textTertiary
        subtitleLabel.numberOfLines = 2
        subtitleLabel.isHidden = subtitle == nil

        valueLabel.text = value
        valueLabel.font = RT.Font.mono(11)
        valueLabel.textColor = RT.textSecondary
        valueLabel.textAlignment = .right
        valueLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        // 值过长（如 WebDAV 地址）时优先截断自己，不挤压标题
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        chevron.image = UIImage(systemName: "chevron.right",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        chevron.tintColor = RT.textTertiary

        toggle.onTintColor = RT.accent
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 2

        iconContainer.addSubview(iconView)
        addSubviews(iconContainer, textStack, valueLabel, chevron, toggle)

        iconView.translatesAutoresizingMaskIntoConstraints = false

        // 按行类型决定右侧控件的可见性与配色
        switch kind {
        case .disclosure:
            valueLabel.isHidden = value == nil
            toggle.isHidden = true
            chevron.isHidden = false
        case .readonly:
            valueLabel.isHidden = false
            toggle.isHidden = true
            chevron.isHidden = true
        case .danger:
            titleLabel.textColor = RT.danger
            iconContainer.backgroundColor = RT.danger.withAlphaComponent(0.12)
            iconView.tintColor = RT.danger
            valueLabel.isHidden = true
            toggle.isHidden = true
            chevron.isHidden = false
        case .toggle(let on):
            toggle.isOn = on
            valueLabel.isHidden = true
            toggle.isHidden = false
            chevron.isHidden = true
        }

        var constraints: [NSLayoutConstraint] = [
            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 30),
            iconContainer.heightAnchor.constraint(equalToConstant: 30),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            textStack.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ]

        // 右侧附属控件按行类型定位，textStack 只让位给本行真正存在的控件
        switch kind {
        case .disclosure:
            constraints += [
                chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueLabel.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -10),
            ]
        case .readonly:
            constraints += [
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: valueLabel.leadingAnchor, constant: -10),
            ]
        case .danger:
            constraints += [
                chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -10),
            ]
        case .toggle:
            constraints += [
                toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
                textStack.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -10),
            ]
        }
        NSLayoutConstraint.activate(constraints)

        if case .toggle = kind {
            // 开关行由 UISwitch 自己接管点击
        } else if case .readonly = kind {
            // 只读行不可点
        } else {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            addGestureRecognizer(gesture)
            tapGesture = gesture
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    var valueText: String? {
        get { valueLabel.text }
        set { valueLabel.text = newValue }
    }

    func setOn(_ on: Bool) {
        toggle.setOn(on, animated: false)
    }

    @objc private func handleTap() {
        RT.haptic()
        onTap?()
    }

    @objc private func toggleChanged() {
        RT.haptic()
        onToggle?(toggle.isOn)
    }
}

// MARK: - 主题预览条

final class SettingsThemeStrip: UIView {

    var onSelect: ((AppTheme) -> Void)?

    private var tiles: [SettingsThemeTile] = []
    private var current: AppTheme = .system

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 10
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        for theme in AppTheme.allCases {
            let tile = SettingsThemeTile(theme: theme)
            tile.onTap = { [weak self] in
                self?.select(theme, notify: true)
            }
            tiles.append(tile)
            stack.addArrangedSubview(tile)
        }

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        select(.system, notify: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func select(_ theme: AppTheme, notify: Bool) {
        current = theme
        tiles.forEach { $0.setSelected($0.theme == theme) }
        if notify { onSelect?(theme) }
    }
}

final class SettingsThemeTile: UIControl {

    let theme: AppTheme
    var onTap: (() -> Void)?

    private let preview = UIView()
    private let screen = UIView()
    private let dot = UIView()
    private let label = UILabel()
    private let check = UIImageView()

    private var isPicked = false

    init(theme: AppTheme) {
        self.theme = theme
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let palette = theme.previewPalette(dark: UITraitCollection.current.userInterfaceStyle == .dark)

        preview.backgroundColor = palette.canvas
        preview.layer.cornerRadius = 11
        preview.layer.cornerCurve = .continuous
        preview.layer.borderWidth = 1
        preview.layer.borderColor = palette.stroke.cgColor
        preview.clipsToBounds = true

        screen.backgroundColor = palette.surface
        screen.layer.cornerRadius = 4
        dot.backgroundColor = palette.accent
        dot.layer.cornerRadius = 3

        check.image = UIImage(systemName: "checkmark.circle.fill",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .bold))
        check.tintColor = RT.accent
        check.isHidden = true

        label.text = theme.localizedName
        label.font = RT.Font.caption(11)
        label.textColor = RT.textSecondary
        label.textAlignment = .center

        addSubviews(preview, label, screen, dot, check)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: 52),

            screen.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 8),
            screen.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -8),
            screen.topAnchor.constraint(equalTo: preview.topAnchor, constant: 9),
            screen.heightAnchor.constraint(equalToConstant: 24),

            dot.leadingAnchor.constraint(equalTo: screen.leadingAnchor, constant: 5),
            dot.bottomAnchor.constraint(equalTo: screen.bottomAnchor, constant: -4),
            dot.widthAnchor.constraint(equalToConstant: 6),
            dot.heightAnchor.constraint(equalToConstant: 6),

            check.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -5),
            check.topAnchor.constraint(equalTo: preview.topAnchor, constant: 5),
            check.widthAnchor.constraint(equalToConstant: 14),
            check.heightAnchor.constraint(equalToConstant: 14),

            label.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 7),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addTarget(self, action: #selector(tap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        isPicked = selected
        check.isHidden = !selected
        preview.layer.borderWidth = selected ? 1.6 : 1
        preview.layer.borderColor = selected ? RT.accent.cgColor : RT.stroke.cgColor
        label.textColor = selected ? RT.accent : RT.textSecondary
        label.font = selected ? RT.Font.caption(11).withWeight(.semibold) : RT.Font.caption(11)
    }

    @objc private func tap() {
        RT.haptic()
        onTap?()
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        UIFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
