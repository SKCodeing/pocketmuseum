// TimelineViewController.swift
// 「时光」页：自动存档 + 手动存档汇成一条可回溯的时间轴
// 设计意图：把「存档」从技术槽位变成可阅读的旅程记录（时间胶囊）

import UIKit

// MARK: - 模型

enum TimelineSaveKind {
    case auto(AutoSaveEntry)
    case manual(slot: Int)

    var isAuto: Bool {
        if case .auto = self { return true }
        return false
    }

    var badge: String {
        switch self {
        case .auto:          return L10n.str("time.badge.auto")
        case .manual(let s): return L10n.str("time.badge.manual", s)
        }
    }
}

struct TimelineItem {
    let id: String
    let rom: ROMInfo
    let date: Date
    let kind: TimelineSaveKind

    var isAuto: Bool { kind.isAuto }
}

final class TimelineViewController: UIViewController {

    private struct Bucket {
        let title: String
        let items: [TimelineItem]
    }

    private enum Filter: Int, CaseIterable {
        case all, auto, manual

        var title: String {
            switch self {
            case .all:    return L10n.str("time.filter.all")
            case .auto:   return L10n.str("time.filter.auto")
            case .manual: return L10n.str("time.filter.manual")
            }
        }
    }

    // MARK: - 数据

    private var items: [TimelineItem] = []
    private var buckets: [Bucket] = []
    private var filter: Filter = .all
    /// 页面不在前台时收到的库更新只有这一位标记，回到前台再一次性刷
    private var needsReload = false

    // MARK: - 视图

    private let headerView = UIView()
    private let plaqueLabel = UILabel()
    private let titleLabel = UILabel()
    private let statsLabel = UILabel()
    private let segmentBar = RTSegmentBar(titles: Filter.allCases.map { $0.title })
    /// 年度回顾入口：时间轴讲「什么时候存过」，年报讲「这一年攒了什么」
    private let reportButton = UIButton(type: .system)

    private let collectionView: UICollectionView
    private let emptyState = RTEmptyStateView(icon: "hourglass",
                                              title: L10n.str("time.empty.title"),
                                              message: L10n.str("time.empty.message"),
                                              actionTitle: L10n.str("time.empty.action"))

    /// 有存档时 header 由筛选条收底；空时间轴时改用统计行收底
    private var headerBottomWithSegments: NSLayoutConstraint?
    private var headerBottomWithoutSegments: NSLayoutConstraint?

    // 宽屏居中列：窄屏下常量为 0，与改造前的行为完全一致
    private lazy var headerLeadingInset = headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    private lazy var headerTrailingInset = headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    private lazy var listLeadingInset = collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
    private lazy var listTrailingInset = collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
    private var lastLaidOutWidth: CGFloat = 0

    // MARK: - 生命周期

    init() {
        let layout = UICollectionViewCompositionalLayout { index, environment in
            TimelineViewController.makeSection(index: index, environment: environment)
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        setupHeader()
        setupCollectionView()
        setupEmptyState()

        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                              name: .romLibraryDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                              name: .saveStateDidSyncFromiCloud, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        needsReload = false
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWideLayout()
    }

    /// 宽屏（iPad 横屏、Duo 展开内屏）把头部与时间轴收成居中阅读栏，窄屏不变。
    private func updateWideLayout() {
        let width = view.bounds.width
        guard width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        let inset = RT.Metric.readingColumnInset(for: width)
        headerLeadingInset.constant = inset
        headerTrailingInset.constant = -inset
        listLeadingInset.constant = inset
        listTrailingInset.constant = -inset
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - 头部

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("time.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.6]
        )

        titleLabel.text = L10n.str("time.title")
        titleLabel.font = RT.Font.display(28)
        titleLabel.textColor = RT.text

        let titleStack = UIStackView(arrangedSubviews: [plaqueLabel, titleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 3
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        statsLabel.font = RT.Font.mono(11)
        statsLabel.textColor = RT.textTertiary
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        reportButton.translatesAutoresizingMaskIntoConstraints = false
        applyReportButtonStyle()
        reportButton.addAction(UIAction { [weak self] _ in
            self?.openReport()
        }, for: .touchUpInside)

        headerView.addSubviews(titleStack, statsLabel, segmentBar, reportButton)

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            titleStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: RT.Metric.screenPadding),
            titleStack.trailingAnchor.constraint(lessThanOrEqualTo: reportButton.leadingAnchor, constant: -12),

            reportButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -RT.Metric.screenPadding),
            reportButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),

            statsLabel.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 10),
            statsLabel.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),

            segmentBar.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 12),
            segmentBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            segmentBar.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),

            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            // 横向贴安全区：Duo 展开后的内屏右侧有系统侧置状态栏，「年度回顾」按钮
            // 贴 view 边会被时钟盖住。iPhone / iPad 左右安全区为 0，行为不变。
            // 两段常量留给宽屏居中列（见 updateWideLayout）。
            headerLeadingInset, headerTrailingInset,
        ])

        headerBottomWithSegments = segmentBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10)
        headerBottomWithoutSegments = statsLabel.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10)
        headerBottomWithSegments?.isActive = true

        segmentBar.onSelect = { [weak self] index in
            guard let self = self, let f = Filter(rawValue: index) else { return }
            self.filter = f
            self.rebuild()
            self.collectionView.reloadData()
            self.updateEmptyState()
        }
    }

    // MARK: - 年度回顾

    private func applyReportButtonStyle() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 13)
        config.attributedTitle = AttributedString(
            L10n.str("report.entry"),
            attributes: AttributeContainer([.font: RT.Font.caption(13)])
        )
        config.image = UIImage(systemName: "doc.text.image", withConfiguration:
            UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.imagePadding = 6
        config.baseForegroundColor = RT.textSecondary
        reportButton.configuration = config
        reportButton.backgroundColor = RT.surfaceHigh
        reportButton.layer.cornerRadius = RT.Metric.chipRadius
        reportButton.layer.cornerCurve = .continuous
    }

    private func openReport() {
        RT.haptic()
        present(MuseumReportViewController(), animated: true)
    }

    private func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        collectionView.register(TimelineSaveCell.self, forCellWithReuseIdentifier: TimelineSaveCell.id)
        collectionView.register(TimelineBucketHeader.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: TimelineBucketHeader.id)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            listLeadingInset, listTrailingInset,
            // 底部让出浮岛标签栏
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyState.isHidden = true
        view.addSubview(emptyState)
        emptyState.onAction = { [weak self] in
            guard let self = self else { return }
            (self.parent as? RetroTabBarController)?.select(index: 0, animated: true)
        }
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // 以时间轴可视区为基准居中
            emptyState.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -8),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - 数据

    @objc private func reload() {
        // 导入几百张卡带时会连着收到很多次库更新通知，而一次 reload 要把全库的存档挨个 stat 一遍。
        // 页面不在前台就先记账，等 viewWillAppear 再一次性刷。
        if view.window == nil && !items.isEmpty {
            needsReload = true
            return
        }
        items = TimelineViewController.collectItems()
        rebuild()
        collectionView.reloadData()
        updateEmptyState()
        updateStats()
    }

    private func rebuild() {
        let filtered: [TimelineItem]
        switch filter {
        case .all:    filtered = items
        case .auto:   filtered = items.filter { $0.kind.isAuto }
        case .manual: filtered = items.filter { !$0.kind.isAuto }
        }
        buckets = TimelineViewController.group(filtered)
    }

    private func updateStats() {
        let romCount = Set(items.map { $0.rom.name }).count
        var text = L10n.str("time.stat.total", items.count)
        if let latest = items.first {
            text += "   ·   " + L10n.str("time.stat.latest", MuseumHeroCell.relativeText(latest.date))
        }
        text += "   ·   " + L10n.str("time.stat.games", romCount)
        statsLabel.text = text
    }

    private func updateEmptyState() {
        let empty = buckets.isEmpty
        emptyState.isHidden = !empty
        collectionView.isHidden = empty
        applySegmentVisibility(hidden: items.isEmpty)
    }

    /// 一份存档都没有时筛选条无意义，收起它并让 header 变紧凑
    private func applySegmentVisibility(hidden: Bool) {
        guard segmentBar.isHidden != hidden else { return }
        segmentBar.isHidden = hidden
        headerBottomWithSegments?.isActive = !hidden
        headerBottomWithoutSegments?.isActive = hidden
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private static func collectItems() -> [TimelineItem] {
        var result: [TimelineItem] = []
        for rom in ROMLibrary.shared.roms {
            for entry in SaveStateManager.shared.autoSaveEntries(romName: rom.name) {
                result.append(TimelineItem(id: entry.id,
                                           rom: rom,
                                           date: entry.timestamp,
                                           kind: .auto(entry)))
            }
            for slot in 0..<4 {
                guard let date = SaveStateManager.shared.saveDate(romName: rom.name, slot: slot) else { continue }
                result.append(TimelineItem(id: "\(rom.name)_slot\(slot)",
                                           rom: rom,
                                           date: date,
                                           kind: .manual(slot: slot)))
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private static func group(_ items: [TimelineItem]) -> [Bucket] {
        let calendar = Calendar.current
        var order: [String] = []
        var map: [String: [TimelineItem]] = [:]

        for item in items {
            let title: String
            if calendar.isDateInToday(item.date) {
                title = L10n.str("time.today")
            } else if calendar.isDateInYesterday(item.date) {
                title = L10n.str("time.yesterday")
            } else if let days = calendar.dateComponents([.day], from: item.date, to: Date()).day, days < 7 {
                title = L10n.str("time.thisWeek")
            } else if calendar.isDate(item.date, equalTo: Date(), toGranularity: .year) {
                title = TimelineSaveCell.monthDayFormatter.string(from: item.date)
            } else {
                title = TimelineSaveCell.yearMonthDayFormatter.string(from: item.date)
            }
            if map[title] == nil {
                order.append(title)
                map[title] = []
            }
            map[title]?.append(item)
        }
        return order.compactMap { title in
            guard let list = map[title] else { return nil }
            return Bucket(title: title, items: list)
        }
    }

    // MARK: - 操作

    private func open(_ item: TimelineItem) {
        let data: Data?
        switch item.kind {
        case .auto(let entry):
            data = SaveStateManager.shared.loadAutoSave(entry: entry)
        case .manual(let slot):
            data = try? SaveStateManager.shared.load(romName: item.rom.name, slot: slot)
        }
        guard let state = data else {
            RTToast.show(L10n.str("time.toast.missing"), icon: "exclamationmark.triangle")
            return
        }
        RT.haptic()
        let vc = EmulatorViewController(rom: item.rom, pendingState: state)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func delete(_ item: TimelineItem) {
        let alert = UIAlertController(title: L10n.str("time.delete.title"),
                                      message: L10n.str("time.delete.message", item.rom.name),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("btn.delete"), style: .destructive) { [weak self] _ in
            switch item.kind {
            case .auto(let entry):
                SaveStateManager.shared.deleteAutoSave(entry: entry)
            case .manual(let slot):
                try? SaveStateManager.shared.deleteSave(romName: item.rom.name, slot: slot)
            }
            self?.reload()
            RTToast.show(L10n.str("time.toast.deleted"), icon: "trash")
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func share(_ item: TimelineItem) {
        Task.detached {
            do {
                let url = try SaveStateManager.shared.exportSaves(romName: item.rom.name)
                await MainActor.run { [weak self] in
                    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    vc.popoverPresentationController?.sourceView = self?.view
                    self?.present(vc, animated: true)
                }
            } catch {
                await MainActor.run {
                    RTToast.show(L10n.str("export.fail"), icon: "exclamationmark.triangle")
                }
            }
        }
    }

    // MARK: - 布局

    private static func makeSection(index: Int, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                            heightDimension: .absolute(92)))
        let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                       heightDimension: .absolute(92)),
                                                     subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 18, trailing: 20)
        section.boundarySupplementaryItems = [
            NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(38)),
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top)
        ]
        return section
    }
}

// MARK: - DataSource / Delegate

extension TimelineViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int { buckets.count }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        buckets[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                     withReuseIdentifier: TimelineBucketHeader.id,
                                                                     for: indexPath) as! TimelineBucketHeader
        let bucket = buckets[indexPath.section]
        header.configure(title: bucket.title, count: bucket.items.count)
        return header
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: TimelineSaveCell.id,
                                                      for: indexPath) as! TimelineSaveCell
        cell.configure(item: buckets[indexPath.section].items[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        open(buckets[indexPath.section].items[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        let item = buckets[indexPath.section].items[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let resume = UIAction(title: L10n.str("time.menu.resume"),
                                  image: UIImage(systemName: "play.fill")) { _ in
                self?.open(item)
            }
            let share = UIAction(title: L10n.str("time.menu.share"),
                                 image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self?.share(item)
            }
            let delete = UIAction(title: L10n.str("btn.delete"),
                                  image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self?.delete(item)
            }
            return UIMenu(title: item.rom.name, children: [resume, share, delete])
        }
    }
}

// MARK: - 主题

extension TimelineViewController: RTThemeRefreshable {
    func refreshTheme() {
        view.backgroundColor = RT.canvas
        titleLabel.textColor = RT.text
        statsLabel.textColor = RT.textTertiary
        applyReportButtonStyle()
        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("time.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.6]
        )
        collectionView.reloadData()
    }
}

// MARK: - 日期分组标题

final class TimelineBucketHeader: UICollectionReusableView {
    static let id = "TimelineBucketHeader"

    private let titleLabel = UILabel()
    private let countLabel = UILabel()
    private let hairline = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = RT.Font.mono(11, weight: .semibold)
        titleLabel.textColor = RT.textSecondary
        countLabel.font = RT.Font.mono(10)
        countLabel.textColor = RT.textTertiary
        hairline.backgroundColor = RT.stroke

        addSubviews(titleLabel, countLabel, hairline)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            countLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            countLabel.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),

            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            hairline.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 10),
            hairline.heightAnchor.constraint(equalToConstant: 1),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int) {
        titleLabel.attributedText = NSAttributedString(
            string: title.uppercased(),
            attributes: [.font: RT.Font.mono(11, weight: .semibold),
                         .foregroundColor: RT.textSecondary,
                         .kern: 1.6]
        )
        countLabel.text = L10n.str("time.bucket.count", count)
        hairline.backgroundColor = RT.stroke
    }
}

// MARK: - 存档行

final class TimelineSaveCell: UICollectionViewCell {
    static let id = "TimelineSaveCell"

    static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    static let yearMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("jm")
        return f
    }()

    private let card = RTCardView(style: .plain, radius: 20)
    private let rail = UIView()
    private let dot = UIView()
    private let thumbView = UIImageView()
    private let cover = RTCoverView()
    private let nameLabel = UILabel()
    private let badgeLabel = UILabel()
    private let metaLabel = UILabel()
    private let openIcon = UIImageView()

    private var currentToken = UUID()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.addSubview(card)
        card.pinEdges(to: contentView, insets: UIEdgeInsets(top: 0, left: 30, bottom: 0, right: 0))

        rail.backgroundColor = RT.stroke
        rail.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rail)

        dot.backgroundColor = RT.accent
        dot.layer.cornerRadius = 3.5
        dot.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dot)

        thumbView.contentMode = .scaleAspectFill
        thumbView.clipsToBounds = true
        thumbView.layer.cornerRadius = 11
        thumbView.layer.cornerCurve = .continuous
        thumbView.backgroundColor = RT.surfaceHigh
        thumbView.isHidden = true

        cover.layer.cornerRadius = 11

        nameLabel.font = RT.Font.headline(15)
        nameLabel.textColor = RT.text
        nameLabel.numberOfLines = 1

        badgeLabel.font = RT.Font.mono(9, weight: .semibold)
        badgeLabel.textColor = RT.accent
        badgeLabel.backgroundColor = RT.accent.withAlphaComponent(0.14)
        badgeLabel.textAlignment = .center
        badgeLabel.layer.cornerRadius = 6
        badgeLabel.layer.cornerCurve = .continuous
        badgeLabel.clipsToBounds = true

        metaLabel.font = RT.Font.mono(10)
        metaLabel.textColor = RT.textTertiary
        metaLabel.numberOfLines = 1

        openIcon.image = UIImage(systemName: "play.circle",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        openIcon.tintColor = RT.textTertiary
        openIcon.contentMode = .scaleAspectFit

        card.addSubviews(cover, thumbView, nameLabel, badgeLabel, metaLabel, openIcon)

        NSLayoutConstraint.activate([
            rail.centerXAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 11),
            rail.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -6),
            rail.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 6),
            rail.widthAnchor.constraint(equalToConstant: 1),

            dot.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),

            cover.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            cover.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: 52),
            cover.heightAnchor.constraint(equalToConstant: 64),

            thumbView.leadingAnchor.constraint(equalTo: cover.leadingAnchor),
            thumbView.topAnchor.constraint(equalTo: cover.topAnchor),
            thumbView.trailingAnchor.constraint(equalTo: cover.trailingAnchor),
            thumbView.bottomAnchor.constraint(equalTo: cover.bottomAnchor),

            nameLabel.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: openIcon.leadingAnchor, constant: -8),

            badgeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            badgeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46),
            badgeLabel.heightAnchor.constraint(equalToConstant: 17),

            metaLabel.leadingAnchor.constraint(equalTo: badgeLabel.trailingAnchor, constant: 8),
            metaLabel.centerYAnchor.constraint(equalTo: badgeLabel.centerYAnchor),
            metaLabel.trailingAnchor.constraint(lessThanOrEqualTo: openIcon.leadingAnchor, constant: -8),

            openIcon.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            openIcon.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            openIcon.widthAnchor.constraint(equalToConstant: 24),
            openIcon.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentToken = UUID()
        thumbView.image = nil
        thumbView.isHidden = true
        cover.isHidden = false
    }

    func configure(item: TimelineItem) {
        nameLabel.text = item.rom.name
        badgeLabel.text = item.kind.badge
        let time = TimelineSaveCell.timeFormatter.string(from: item.date)
        metaLabel.text = "\(item.rom.system.shortCode) · \(time) · \(MuseumHeroCell.relativeText(item.date))"

        cover.isHidden = false
        thumbView.isHidden = true
        cover.loadCover(for: item.rom)
        dot.backgroundColor = item.kind.isAuto ? RT.accent : RT.textSecondary

        let token = UUID()
        currentToken = token
        let romName = item.rom.name
        let kind = item.kind
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data: Data?
            switch kind {
            case .auto(let entry):
                data = SaveStateManager.shared.loadAutoSaveThumb(entry: entry)
            case .manual(let slot):
                data = SaveStateManager.shared.loadScreenshotData(romName: romName, slot: slot)
            }
            guard let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self = self, self.currentToken == token else { return }
                self.thumbView.image = image
                self.thumbView.isHidden = false
                self.cover.isHidden = true
            }
        }
    }
}
