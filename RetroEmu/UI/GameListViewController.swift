// GameListViewController.swift
// 首页 = 掌机博物馆：继续上次 → 掌机柜 → 最近游玩 → 全部游戏
// 视觉语言见 RetroDesignSystem（卡带 / 铭牌 / 琥珀磷光）

import UIKit
import UniformTypeIdentifiers

// MARK: - 筛选

enum MuseumFilter: Equatable {
    case all
    case recent
    case favorite
    case system(EmulatorSystem)
    case tag(String)

    var title: String {
        switch self {
        case .all:              return L10n.str("filter.all")
        case .recent:           return L10n.str("filter.recent")
        case .favorite:         return L10n.str("filter.favorite")
        case .system(let s):    return s.displayName
        case .tag(let id):
            return GameTagManager.shared.tags.first(where: { $0.id == id })?.name ?? L10n.str("filter.tag")
        }
    }

    var system: EmulatorSystem? {
        if case .system(let s) = self { return s }
        return nil
    }
}

final class GameListViewController: UIViewController {

    // MARK: - 数据

    private var allRoms: [ROMInfo] = []
    private var filter: MuseumFilter = .all
    private var searchText: String = ""
    private var isEditingLibrary = false
    private var selectedNames: Set<String> = []
    private var totalPlaySeconds: Double = 0
    private var saveCount: Int = 0

    private var filteredRoms: [ROMInfo] {
        var roms: [ROMInfo]
        switch filter {
        case .all:
            roms = allRoms
        case .recent:
            roms = GameStatsManager.shared.recentlyPlayed(limit: 30)
                .compactMap { name in allRoms.first { $0.name == name } }
        case .favorite:
            let favs = GameStatsManager.shared.favorites()
            roms = allRoms.filter { favs.contains($0.name) }
        case .system(let system):
            roms = allRoms.filter { $0.system == system }
        case .tag(let id):
            let names = GameTagManager.shared.romNames(in: id)
            roms = names.compactMap { name in allRoms.first { $0.name == name } }
        }
        if !searchText.isEmpty {
            roms = roms.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
        return roms
    }

    private var isFiltering: Bool { filter != .all || !searchText.isEmpty }

    /// 首页分区。最近游玩为空时整段收起，别在页面上留一条空标题。
    private enum HomeSection { case hero, shelf, recent, library }

    private var sections: [HomeSection] {
        recentRoms.isEmpty ? [.hero, .shelf, .library] : [.hero, .shelf, .recent, .library]
    }

    private var recentRoms: [ROMInfo] {
        GameStatsManager.shared.recentlyPlayed(limit: 8)
            .compactMap { name in allRoms.first { $0.name == name } }
    }

    private var shelfSystems: [EmulatorSystem] {
        let counts = Dictionary(grouping: allRoms, by: { $0.system }).mapValues { $0.count }
        return counts.sorted {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }.map { $0.key }
    }

    // MARK: - 视图

    private let headerView = UIView()
    private let brandLabel = UILabel()
    private let titleLabel = UILabel()
    private let statsLabel = UILabel()
    private let importButton = RTGlassButton(symbol: "plus", pointSize: 15)
    private let searchButton = RTGlassButton(symbol: "magnifyingglass", pointSize: 14)
    private let moreButton = RTGlassButton(symbol: "ellipsis", pointSize: 15)
    private let segmentBar = RTSegmentBar(titles: [L10n.str("filter.all"),
                                                   L10n.str("filter.recent"),
                                                   L10n.str("filter.favorite")])
    private let searchField = UITextField()
    private let searchContainer = UIView()
    private var searchHeightConstraint: NSLayoutConstraint?
    private var searchVisible = false

    /// 筛选条存在时 header 的下边界；空库时改用搜索结果框收底，让页面更紧凑
    private var headerBottomWithSegments: NSLayoutConstraint?
    private var headerBottomWithoutSegments: NSLayoutConstraint?

    private let collectionView: UICollectionView
    private let emptyState = RTEmptyStateView(icon: "tray",
                                              title: L10n.str("empty.title"),
                                              message: L10n.str("empty.message"),
                                              actionTitle: L10n.str("empty.action"))
    private let editBar = UIView()
    private let editCountLabel = UILabel()
    private let deleteButton = UIButton(type: .system)

    // 宽屏居中列：窄屏下常量为 0，与改造前的行为完全一致
    private var headerLeadingInset: NSLayoutConstraint?
    private var headerTrailingInset: NSLayoutConstraint?
    private var listLeadingInset: NSLayoutConstraint?
    private var listTrailingInset: NSLayoutConstraint?
    private var lastLaidOutWidth: CGFloat = 0

    // MARK: - 生命周期

    init() {
        // 真实分区表要等 loadData 之后才知道（「最近上手」可能整段不存在），
        // 先用占位布局，随后由 reloadLayoutIfNeeded 换成按分区映射的布局。
        let layout = UICollectionViewCompositionalLayout { _, environment in
            GameListViewController.makeSection(.library, environment: environment)
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
        setupEditBar()
        loadData()

        NotificationCenter.default.addObserver(self,
                                              selector: #selector(reloadROMs),
                                              name: .romLibraryDidUpdate,
                                              object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        scanLibrary()
        updateStats()
        collectionView.reloadData()
        updateEmptyState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWideLayout()
    }

    /// 宽屏（iPad 横屏、Duo 展开内屏）把头部和列表收成居中阅读栏，
    /// 不然一条列表拉满整块屏、两侧全是空白。窄屏时内边距为 0，布局不变。
    private func updateWideLayout() {
        let width = view.bounds.width
        guard width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        let inset = RT.Metric.readingColumnInset(for: width)
        headerLeadingInset?.constant = inset
        headerTrailingInset?.constant = -inset
        listLeadingInset?.constant = inset
        listTrailingInset?.constant = -inset
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    #if DEBUG
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 取证：-homeRecent 把「最近上手」滚到屏幕中间，检查封面下方的名字与时长是否完整
        guard ProcessInfo.processInfo.arguments.contains("-homeRecent"),
              let index = sections.firstIndex(of: .recent) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.collectionView.scrollToItem(at: IndexPath(item: 0, section: index),
                                             at: .centeredVertically, animated: false)
        }
    }
    #endif

    // MARK: - 头部

    private func setupHeader() {
        headerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerView)

        brandLabel.text = L10n.str("brand.plaque")
        brandLabel.font = RT.Font.mono(10, weight: .semibold)
        brandLabel.textColor = RT.accent
        brandLabel.attributedText = NSAttributedString(string: L10n.str("brand.plaque"),
                                                       attributes: [
                                                        .font: RT.Font.mono(10, weight: .semibold),
                                                        .foregroundColor: RT.accent,
                                                        .kern: 2.6,
                                                       ])

        titleLabel.text = L10n.str("home.title")
        titleLabel.font = RT.Font.display(28)
        titleLabel.textColor = RT.text

        let titleStack = UIStackView(arrangedSubviews: [brandLabel, titleLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 3
        titleStack.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = UIStackView(arrangedSubviews: [importButton, searchButton, moreButton])
        actionStack.axis = .horizontal
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        importButton.addTarget(self, action: #selector(importROM), for: .touchUpInside)
        searchButton.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        moreButton.addTarget(self, action: #selector(showMoreMenu), for: .touchUpInside)

        statsLabel.font = RT.Font.mono(11, weight: .regular)
        statsLabel.textColor = RT.textTertiary
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        setupSearchField()

        headerView.addSubviews(titleStack, actionStack, statsLabel, searchContainer, segmentBar)

        NSLayoutConstraint.activate([
            titleStack.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 10),
            titleStack.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: RT.Metric.screenPadding),

            actionStack.centerYAnchor.constraint(equalTo: titleStack.centerYAnchor),
            actionStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -RT.Metric.screenPadding),

            statsLabel.topAnchor.constraint(equalTo: titleStack.bottomAnchor, constant: 10),
            statsLabel.leadingAnchor.constraint(equalTo: titleStack.leadingAnchor),

            searchContainer.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 12),
            searchContainer.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: RT.Metric.screenPadding),
            searchContainer.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -RT.Metric.screenPadding),

            segmentBar.topAnchor.constraint(equalTo: searchContainer.bottomAnchor, constant: 12),
            segmentBar.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            segmentBar.trailingAnchor.constraint(equalTo: headerView.trailingAnchor),
        ])

        headerBottomWithSegments = segmentBar.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10)
        headerBottomWithoutSegments = searchContainer.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -10)
        headerBottomWithSegments?.isActive = true

        segmentBar.onSelect = { [weak self] index in
            guard let self = self else { return }
            let filters: [MuseumFilter] = [.all, .recent, .favorite]
            guard filters.indices.contains(index) else { return }
            self.filter = filters[index]
            self.reloadLayoutIfNeeded()
            self.collectionView.reloadData()
            self.updateEmptyState()
        }

        // Duo 这类折叠态屏幕右侧会留出约 86pt 的系统侧栏，横向贴 view 边时
        // 头部那排圆形按钮会被压在侧栏下面（第三个只剩一半）。这里改贴安全区：
        // iPhone / iPad 上左右安全区为 0，行为与之前一致。
        // 额外两段常量留给宽屏居中列（见 updateWideLayout）。
        headerLeadingInset = headerView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        headerTrailingInset = headerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerLeadingInset!, headerTrailingInset!,
        ])
    }

    private func setupSearchField() {
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.backgroundColor = RT.surface
        searchContainer.layer.cornerRadius = 14
        searchContainer.layer.cornerCurve = .continuous
        searchContainer.layer.borderWidth = 1
        searchContainer.layer.borderColor = RT.stroke.cgColor
        searchHeightConstraint = searchContainer.heightAnchor.constraint(equalToConstant: 0)
        searchHeightConstraint?.isActive = true
        searchContainer.clipsToBounds = true
        searchContainer.alpha = 0

        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .medium)))
        icon.tintColor = RT.textTertiary
        icon.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholder = L10n.str("search.placeholder")
        searchField.font = RT.Font.body(14)
        searchField.textColor = RT.text
        searchField.tintColor = RT.accent
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)

        searchContainer.addSubviews(icon, searchField)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
            searchField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -10),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),
        ])
    }

    private func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        // 底部留出浮岛标签栏的高度：只顶到 safeArea 的话，最后一排的文字会穿在玻璃底下
        collectionView.contentInset = UIEdgeInsets(top: 4, left: 0,
                                                   bottom: RT.Metric.tabBarHeight + 24, right: 0)
        collectionView.register(MuseumHeroCell.self, forCellWithReuseIdentifier: MuseumHeroCell.id)
        collectionView.register(MuseumShelfCell.self, forCellWithReuseIdentifier: MuseumShelfCell.id)
        collectionView.register(MuseumRecentCell.self, forCellWithReuseIdentifier: MuseumRecentCell.id)
        collectionView.register(MuseumGameRowCell.self, forCellWithReuseIdentifier: MuseumGameRowCell.id)
        collectionView.register(MuseumSectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MuseumSectionHeaderView.id)
        view.addSubview(collectionView)
        listLeadingInset = collectionView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        listTrailingInset = collectionView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            listLeadingInset!, listTrailingInset!,
            // 底部让出浮岛标签栏，卡片与列表不再穿在玻璃底下
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyState.isHidden = true
        emptyState.onAction = { [weak self] in
            self?.importROM()
        }
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // 以列表可视区为基准居中，头部再高也不会把空态压到屏幕下半部
            emptyState.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -8),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func setupEditBar() {
        editBar.translatesAutoresizingMaskIntoConstraints = false
        editBar.backgroundColor = RT.surfaceHigh
        editBar.layer.cornerRadius = 22
        editBar.layer.cornerCurve = .continuous
        editBar.layer.borderWidth = 1
        editBar.layer.borderColor = RT.stroke.cgColor
        editBar.alpha = 0
        editBar.isHidden = true
        view.addSubview(editBar)

        editCountLabel.font = RT.Font.mono(12)
        editCountLabel.textColor = RT.textSecondary
        editCountLabel.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.setTitle(L10n.str("btn.delete"), for: .normal)
        deleteButton.titleLabel?.font = RT.Font.headline(14)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = RT.danger
        deleteButton.layer.cornerRadius = 16
        deleteButton.layer.cornerCurve = .continuous
        deleteButton.contentEdgeInsets = UIEdgeInsets(top: 9, left: 20, bottom: 9, right: 20)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteSelected), for: .touchUpInside)

        editBar.addSubviews(editCountLabel, deleteButton)
        NSLayoutConstraint.activate([
            editBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            editBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -RT.Metric.tabBarHeight - 24),
            editBar.heightAnchor.constraint(equalToConstant: 52),

            editCountLabel.leadingAnchor.constraint(equalTo: editBar.leadingAnchor, constant: 18),
            editCountLabel.centerYAnchor.constraint(equalTo: editBar.centerYAnchor),

            deleteButton.trailingAnchor.constraint(equalTo: editBar.trailingAnchor, constant: -8),
            deleteButton.centerYAnchor.constraint(equalTo: editBar.centerYAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: editCountLabel.trailingAnchor, constant: 16),
        ])
    }

    // MARK: - 数据

    /// 布局签名：分区表或筛选态变了才重建布局；单纯滚动/拖拽过程中不换，否则会丢 contentOffset。
    private var layoutSignature = ""

    private func reloadLayoutIfNeeded() {
        let signature = isFiltering
            ? "filtered"
            : sections.map { String(describing: $0) }.joined(separator: "|")
        guard signature != layoutSignature else { return }
        layoutSignature = signature
        let layout = UICollectionViewCompositionalLayout { [weak self] index, environment in
            // 筛选态只有一段，内容是列表行；这里必须用 .library 的行高，
            // 否则会把 78pt 的行套进 176pt 的 hero 布局，撑成一排巨大空卡。
            guard let self = self, !self.isFiltering else {
                return GameListViewController.makeSection(.library, environment: environment)
            }
            let section = self.sections.indices.contains(index) ? self.sections[index] : .library
            return GameListViewController.makeSection(section, environment: environment)
        }
        collectionView.setCollectionViewLayout(layout, animated: false)
    }

    private func loadData() {
        allRoms = ROMLibrary.shared.roms
        if allRoms.isEmpty {
            // 首次进入：立刻扫描一次，避免空白
            ROMLibrary.shared.scan()
            allRoms = ROMLibrary.shared.roms
        }
        updateStats()
        reloadLayoutIfNeeded()
        collectionView.reloadData()
        updateEmptyState()
    }

    private func scanLibrary() {
        Task.detached { [weak self] in
            ROMLibrary.shared.scan()
            let roms = ROMLibrary.shared.roms
            // 几百条索引项的构建也在后台做，别在首页抢主线程的帧
            SpotlightManager.shared.indexAll(roms)
            await MainActor.run {
                self?.reloadROMs()
            }
        }
    }

    @objc private func reloadROMs() {
        allRoms = ROMLibrary.shared.roms
        updateStats()
        reloadLayoutIfNeeded()
        collectionView.reloadData()
        updateEmptyState()
    }

    private func updateStats() {
        totalPlaySeconds = allRoms.reduce(0) { $0 + GameStatsManager.shared.stats(for: $1.name).totalSeconds }
        var saves = 0
        for rom in allRoms {
            for slot in 0..<4 where SaveStateManager.shared.hasSave(romName: rom.name, slot: slot) {
                saves += 1
            }
            saves += SaveStateManager.shared.autoSaveEntries(romName: rom.name).count
        }
        saveCount = saves
        let hours = Int(totalPlaySeconds) / 3600
        let minutes = (Int(totalPlaySeconds) % 3600) / 60
        let timeText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        let attributed = NSMutableAttributedString()
        attributed.append(NSAttributedString(string: L10n.str("home.stat.games", allRoms.count),
                                             attributes: [.font: RT.Font.mono(11, weight: .semibold),
                                                          .foregroundColor: RT.textSecondary]))
        attributed.append(NSAttributedString(string: "   ·   ",
                                             attributes: [.font: RT.Font.mono(11),
                                                          .foregroundColor: RT.textTertiary]))
        attributed.append(NSAttributedString(string: timeText,
                                             attributes: [.font: RT.Font.mono(11, weight: .semibold),
                                                          .foregroundColor: RT.textSecondary]))
        attributed.append(NSAttributedString(string: "   ·   ",
                                             attributes: [.font: RT.Font.mono(11),
                                                          .foregroundColor: RT.textTertiary]))
        attributed.append(NSAttributedString(string: L10n.str("home.stat.saves", saveCount),
                                             attributes: [.font: RT.Font.mono(11, weight: .semibold),
                                                          .foregroundColor: RT.textSecondary]))
        statsLabel.attributedText = attributed
    }

    /// 空库时收起筛选条，并把 header 底边改由搜索框收口
    private func applySegmentVisibility(hidden: Bool) {
        guard segmentBar.isHidden != hidden else { return }
        segmentBar.isHidden = hidden
        headerBottomWithSegments?.isActive = !hidden
        headerBottomWithoutSegments?.isActive = hidden
        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    private func updateEmptyState() {
        let isEmpty = filteredRoms.isEmpty
        emptyState.isHidden = !isEmpty
        collectionView.isHidden = isEmpty

        // 库里一台卡带都没有时，搜索与筛选都无内容可用，收起以腾出视觉空间
        let libraryEmpty = allRoms.isEmpty
        searchButton.isEnabled = !libraryEmpty
        searchButton.alpha = libraryEmpty ? 0.4 : 1
        applySegmentVisibility(hidden: libraryEmpty)

        guard isEmpty else { return }

        let filters: [MuseumFilter] = [.all, .recent, .favorite]
        if !searchText.isEmpty {
            emptyState.configure(icon: "magnifyingglass",
                                 title: L10n.str("empty.search.title"),
                                 message: L10n.str("empty.search.message", searchText))
        } else if !libraryEmpty && filters.contains(filter) && filter != .all {
            // 库里有卡带、只是当前筛选（最近 / 收藏）没命中
            emptyState.configure(icon: "line.3.horizontal.decrease.circle",
                                 title: L10n.str("empty.filter.title"),
                                 message: L10n.str("empty.filter.message"))
        } else if let system = filter.system {
            emptyState.configure(icon: "tray",
                                 title: L10n.str("empty.system.title", system.displayName),
                                 message: L10n.str("empty.system.message"))
        } else {
            emptyState.configure(icon: "tray",
                                 title: L10n.str("empty.title"),
                                 message: L10n.str("empty.message"))
        }
    }

    // MARK: - 交互

    @objc private func toggleSearch() {
        searchVisible.toggle()
        searchHeightConstraint?.constant = searchVisible ? 42 : 0
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseInOut]) {
            self.searchContainer.alpha = self.searchVisible ? 1 : 0
            self.view.layoutIfNeeded()
        }
        if searchVisible {
            searchField.becomeFirstResponder()
        } else {
            searchField.resignFirstResponder()
            searchField.text = ""
            searchText = ""
            reloadLayoutIfNeeded()
            collectionView.reloadData()
        }
    }

    @objc private func searchChanged() {
        searchText = searchField.text ?? ""
        reloadLayoutIfNeeded()
        collectionView.reloadData()
    }

    @objc private func showMoreMenu() {
        var actions: [RTMenuAction] = [
            RTMenuAction(title: L10n.str("menu.wifi"), icon: "wifi", handler: { [weak self] in self?.openWiFiTransfer() }),
            RTMenuAction(title: L10n.str("menu.cloud"), icon: "icloud.and.arrow.down", handler: { [weak self] in self?.openCloudImport() }),
            RTMenuAction(title: L10n.str("menu.skin"), icon: "paintpalette", handler: { [weak self] in self?.openSkinManager() }),
            RTMenuAction(title: L10n.str("menu.manage"), icon: "checkmark.circle", handler: { [weak self] in self?.enterEditMode() }),
        ]
        if let system = filter.system {
            actions.insert(RTMenuAction(title: L10n.str("menu.exitfilter"),
                                        subtitle: system.shortCode,
                                        icon: "line.3.horizontal.decrease.circle",
                                        selected: true,
                                        handler: { [weak self] in
                self?.filter = .all
                self?.segmentBar.select(0)
                self?.reloadLayoutIfNeeded()
                self?.collectionView.reloadData()
            }), at: 0)
        }
        RTMenuSheetViewController.present(from: self, title: L10n.str("menu.title"), actions: actions)
    }

    private func enterEditMode() {
        isEditingLibrary = true
        selectedNames.removeAll()
        collectionView.reloadData()
        view.addSubview(editBar)
        editBar.isHidden = false
        view.bringSubviewToFront(editBar)
        updateEditBar()
        UIView.animate(withDuration: 0.24) { self.editBar.alpha = 1 }
    }

    private func exitEditMode() {
        isEditingLibrary = false
        selectedNames.removeAll()
        collectionView.reloadData()
        UIView.animate(withDuration: 0.2, animations: { self.editBar.alpha = 0 }) { _ in
            self.editBar.isHidden = true
        }
    }

    private func updateEditBar() {
        editCountLabel.text = L10n.str("edit.selected", selectedNames.count)
        deleteButton.isEnabled = !selectedNames.isEmpty
        deleteButton.alpha = selectedNames.isEmpty ? 0.4 : 1
    }

    @objc private func deleteSelected() {
        guard !selectedNames.isEmpty else { return }
        let names = selectedNames
        let alert = UIAlertController(title: L10n.str("delete.title", names.count),
                                      message: L10n.str("delete.message"),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("btn.delete"), style: .destructive) { [weak self] _ in
            for rom in self?.allRoms ?? [] where names.contains(rom.name) {
                try? ROMLibrary.shared.deleteROM(rom)
            }
            self?.exitEditMode()
            self?.scanLibrary()
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    @objc private func importROM() {
        var types: [UTType] = [.data, .zip]
        let exts = EmulatorSystem.allCases.flatMap { $0.fileExtensions }.map { $0.lowercased() }
        for ext in Array(Set(exts)) {
            if let t = UTType(filenameExtension: ext) { types.append(t) }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func openWiFiTransfer() {
        let nav = UINavigationController(rootViewController: WiFiTransferViewController())
        present(nav, animated: true)
    }

    private func openCloudImport() {
        if let config = WebDAVClient.savedConfig() {
            let client = WebDAVClient(config: config)
            let nav = UINavigationController(rootViewController: CloudImportViewController(provider: client))
            present(nav, animated: true)
        } else {
            let setup = WebDAVSetupViewController()
            setup.onConnected = { [weak self] client in
                setup.dismiss(animated: true) {
                    let nav = UINavigationController(rootViewController: CloudImportViewController(provider: client))
                    self?.present(nav, animated: true)
                }
            }
            present(UINavigationController(rootViewController: setup), animated: true)
        }
    }

    private func openSkinManager() {
        let vc = SkinPickerViewController(system: filter.system ?? .gba)
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func launch(_ rom: ROMInfo) {
        let mode: NetworkMode = NetworkManager.shared.isConnected
            ? (NetworkManager.shared.isHost ? .host : .client) : .none
        let vc = EmulatorViewController(rom: rom, networkMode: mode)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    /// 打开展签。开箱由展签底部的按钮触发，收起后再启动，避免两层模态打架。
    private func showExhibit(_ rom: ROMInfo) {
        RT.haptic()
        let vc = ROMDetailViewController(rom: rom)
        vc.onPlay = { [weak self] rom in
            self?.launch(rom)
        }
        present(vc, animated: true)
    }

    private func showTagSheet(for rom: ROMInfo) {
        let current = GameTagManager.shared.tags(for: rom.name)
        var actions: [RTMenuAction] = GameTagManager.shared.tags.map { tag in
            RTMenuAction(title: tag.name,
                         subtitle: "\(tag.romNames.count)",
                         icon: "tag",
                         selected: current.contains(where: { $0.id == tag.id }),
                         handler: { [weak self] in
                GameTagManager.shared.toggleROM(rom.name, in: tag.id)
                self?.collectionView.reloadData()
            })
        }
        actions.append(RTMenuAction(title: L10n.str("tag.create"), icon: "plus", handler: { [weak self] in
            self?.showCreateTag()
        }))
        RTMenuSheetViewController.present(from: self, title: L10n.str("tag.title"), message: rom.name, actions: actions)
    }

    private func showCreateTag() {
        let alert = UIAlertController(title: L10n.str("tag.create"), message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = L10n.str("tag.name.placeholder") }
        alert.addAction(UIAlertAction(title: L10n.str("tag.create"), style: .default) { _ in
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            _ = GameTagManager.shared.createTag(name: name)
            NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func exportSaves(for rom: ROMInfo) {
        Task.detached {
            do {
                let url = try SaveStateManager.shared.exportSaves(romName: rom.name)
                await MainActor.run { [weak self] in
                    let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    vc.popoverPresentationController?.sourceView = self?.view
                    self?.present(vc, animated: true)
                }
            } catch {
                await MainActor.run {
                    RTToast.show(L10n.str("export.fail"), icon: "exclamationmark.triangle", in: nil)
                }
            }
        }
    }

    private func importSaves(for rom: ROMInfo) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.zip])
        picker.delegate = self
        objc_setAssociatedObject(picker, &AssociatedKeys.importROMName, rom.name, .OBJC_ASSOCIATION_RETAIN)
        present(picker, animated: true)
    }

    private func toggleFavorite(_ rom: ROMInfo) {
        GameStatsManager.shared.toggleFavorite(romName: rom.name)
        collectionView.reloadData()
    }

    // MARK: - 布局

    private static func makeSection(_ kind: HomeSection, environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let width = environment.container.effectiveContentSize.width

        switch kind {
        case .hero:
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                             heightDimension: .absolute(176)),
                                                           subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 8, trailing: 20)
            return section

        case .shelf:
            // 掌机柜是货架上的格位：卡带得比图标大一号，不然和下面「最近上手」的封面差得太狠
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(100),
                                                                heightDimension: .absolute(132)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(100),
                                                                             heightDimension: .absolute(132)),
                                                           subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.orthogonalScrollingBehavior = .continuous
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20)
            section.boundarySupplementaryItems = [headerItem()]
            return section

        case .recent:
            // 与「掌机柜」同尺寸：100×132 格子装 58×70 封面，两段横向滚动才对得齐
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(100),
                                                                heightDimension: .absolute(132)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(100),
                                                                             heightDimension: .absolute(132)),
                                                           subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 12
            section.orthogonalScrollingBehavior = .continuous
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20)
            section.boundarySupplementaryItems = [headerItem()]
            return section

        case .library:
            // 宽屏（居中列 860pt）下排两列，否则一条行卡被拉成横贯整屏的长条。
            // 这里用绝对宽度算列宽，避免 fractional + 间距把两列挤到溢出。
            let gap: CGFloat = 16
            let usable = width - RT.Metric.screenPadding * 2
            let columns = usable >= 700 ? 2 : 1
            let itemWidth = (usable - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(itemWidth),
                                                                heightDimension: .absolute(78)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                             heightDimension: .absolute(78)),
                                                           subitem: item,
                                                           count: columns)
            group.interItemSpacing = .fixed(columns > 1 ? gap : 0)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 10
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: RT.Metric.screenPadding,
                                                            bottom: 24, trailing: RT.Metric.screenPadding)
            section.boundarySupplementaryItems = [headerItem()]
            return section
        }
    }

    private static func headerItem() -> NSCollectionLayoutBoundarySupplementaryItem {
        NSCollectionLayoutBoundarySupplementaryItem(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(46)),
            elementKind: UICollectionView.elementKindSectionHeader,
            alignment: .top
        )
    }
}

// MARK: - DataSource

extension GameListViewController: UICollectionViewDataSource {

    // MARK: - DataSource

    // 分段见 HomeSection：hero / 掌机柜 / 最近 / 全部，最近为空时那一段不存在
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        isFiltering ? 1 : sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if isFiltering {
            return filteredRoms.isEmpty ? 0 : filteredRoms.count
        }
        switch sections[section] {
        case .hero: return 1
        case .shelf: return shelfSystems.count
        case .recent: return recentRoms.count
        case .library: return filteredRoms.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isFiltering {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MuseumGameRowCell.id, for: indexPath) as! MuseumGameRowCell
            let rom = filteredRoms[indexPath.item]
            cell.configure(rom: rom,
                           selected: selectedNames.contains(rom.name),
                           editing: isEditingLibrary,
                           showSeparator: indexPath.item < filteredRoms.count - 1)
            return cell
        }

        switch sections[indexPath.section] {
        case .hero:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MuseumHeroCell.id, for: indexPath) as! MuseumHeroCell
            // 还没玩过任何一局时，hero 卡展示库里第一张卡带，别让整个首屏停在空态上
            cell.configure(rom: recentRoms.first ?? allRoms.first,
                           totalGames: allRoms.count,
                           onImport: { [weak self] in self?.importROM() },
                           onPlay: { [weak self] rom in self?.launch(rom) })
            return cell
        case .shelf:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MuseumShelfCell.id, for: indexPath) as! MuseumShelfCell
            let system = shelfSystems[indexPath.item]
            let count = allRoms.filter { $0.system == system }.count
            cell.configure(system: system, count: count, selected: filter.system == system)
            return cell
        case .recent:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MuseumRecentCell.id, for: indexPath) as! MuseumRecentCell
            cell.configure(rom: recentRoms[indexPath.item])
            return cell
        case .library:
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MuseumGameRowCell.id, for: indexPath) as! MuseumGameRowCell
            let rom = filteredRoms[indexPath.item]
            cell.configure(rom: rom,
                           selected: selectedNames.contains(rom.name),
                           editing: isEditingLibrary,
                           showSeparator: indexPath.item < filteredRoms.count - 1)
            return cell
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                     withReuseIdentifier: MuseumSectionHeaderView.id,
                                                                     for: indexPath) as! MuseumSectionHeaderView
        if isFiltering {
            header.configure(title: filter.title,
                             subtitle: L10n.str("library.count", filteredRoms.count),
                             action: isEditingLibrary ? L10n.str("btn.done") : L10n.str("btn.manage"))
            header.onAction = { [weak self] in
                guard let self = self else { return }
                self.isEditingLibrary ? self.exitEditMode() : self.enterEditMode()
            }
        } else {
            switch sections[indexPath.section] {
            case .shelf:
                header.configure(title: L10n.str("section.shelf"),
                                 subtitle: L10n.str("section.shelf.subtitle"),
                                 action: nil)
            case .recent:
                header.configure(title: L10n.str("section.recent"),
                                 subtitle: nil,
                                 action: nil)
            case .hero, .library:
                header.configure(title: L10n.str("section.library"),
                                 subtitle: L10n.str("library.count", allRoms.count),
                                 action: isEditingLibrary ? L10n.str("btn.done") : L10n.str("btn.manage"))
                header.onAction = { [weak self] in
                    guard let self = self else { return }
                    self.isEditingLibrary ? self.exitEditMode() : self.enterEditMode()
                }
            }
        }
        return header
    }
}

// MARK: - Delegate

extension GameListViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if isFiltering {
            let rom = filteredRoms[indexPath.item]
            if isEditingLibrary {
                selectedNames.insert(rom.name)
                updateEditBar()
                collectionView.reloadItems(at: [indexPath])
            } else {
                // 点卡带先看展签，展签里再开箱——这是博物馆的走法，不是文件管理器
                showExhibit(rom)
            }
            return
        }

        switch sections[indexPath.section] {
        case .hero:
            break
        case .shelf:
            let system = shelfSystems[indexPath.item]
            filter = filter.system == system ? .all : .system(system)
            segmentBar.select(0)
            reloadLayoutIfNeeded()
            collectionView.reloadData()
            updateEmptyState()
        case .recent:
            launch(recentRoms[indexPath.item])
        case .library:
            let rom = filteredRoms[indexPath.item]
            if isEditingLibrary {
                selectedNames.insert(rom.name)
                updateEditBar()
                collectionView.reloadItems(at: [indexPath])
            } else {
                showExhibit(rom)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard isEditingLibrary else { return }
        let roms = isFiltering ? filteredRoms : filteredRoms
        guard roms.indices.contains(indexPath.item) else { return }
        let rom = roms[indexPath.item]
        selectedNames.remove(rom.name)
        updateEditBar()
        collectionView.reloadItems(at: [indexPath])
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isEditingLibrary else { return nil }
        guard let rom = romFor(indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return UIMenu() }
            let exhibit = UIAction(title: L10n.str("menu.exhibit"),
                                   image: UIImage(systemName: "text.alignleft")) { _ in
                self.showExhibit(rom)
            }
            let favorite = UIAction(title: GameStatsManager.shared.isFavorite(rom.name)
                                        ? L10n.str("menu.unfavorite") : L10n.str("menu.favorite"),
                                    image: UIImage(systemName: "star")) { _ in
                self.toggleFavorite(rom)
            }
            let tag = UIAction(title: L10n.str("menu.tag"), image: UIImage(systemName: "tag")) { _ in
                self.showTagSheet(for: rom)
            }
            let pin = UIAction(title: L10n.str("menu.pin"), image: UIImage(systemName: "arrow.up.to.line")) { _ in
                var names = GameTagManager.shared.sortedByCustomOrder(ROMLibrary.shared.roms).map { $0.name }
                names.removeAll { $0 == rom.name }
                names.insert(rom.name, at: 0)
                GameTagManager.shared.setOrder(names)
                self.collectionView.reloadData()
            }
            let export = UIAction(title: L10n.str("menu.export"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.exportSaves(for: rom)
            }
            let importSave = UIAction(title: L10n.str("menu.import"), image: UIImage(systemName: "square.and.arrow.down")) { _ in
                self.importSaves(for: rom)
            }
            let delete = UIAction(title: L10n.str("btn.delete"),
                                  image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                try? ROMLibrary.shared.deleteROM(rom)
                AccessionStore.shared.remove(romName: rom.name)
                self.scanLibrary()
            }
            return UIMenu(title: rom.name, children: [exhibit, favorite, tag, pin, export, importSave, delete])
        }
    }

    private func romFor(_ indexPath: IndexPath) -> ROMInfo? {
        if isFiltering {
            return filteredRoms.indices.contains(indexPath.item) ? filteredRoms[indexPath.item] : nil
        }
        switch sections[indexPath.section] {
        case .recent:
            return recentRoms.indices.contains(indexPath.item) ? recentRoms[indexPath.item] : nil
        case .library:
            return filteredRoms.indices.contains(indexPath.item) ? filteredRoms[indexPath.item] : nil
        case .hero, .shelf:
            return nil
        }
    }
}

// MARK: - 文档选择

extension GameListViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let romName = objc_getAssociatedObject(controller, &AssociatedKeys.importROMName) as? String {
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let count = try SaveStateManager.shared.importSaves(from: url, romName: romName)
                RTToast.show(L10n.str("import.saves.ok", count))
            } catch {
                RTToast.show(error.localizedDescription, icon: "exclamationmark.triangle")
            }
            return
        }

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            try? ROMLibrary.shared.importROM(from: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        scanLibrary()
    }
}

private enum AssociatedKeys {
    static var importROMName = "importROMName"
}

// MARK: - 主题刷新

extension GameListViewController: RTThemeRefreshable {
    func refreshTheme() {
        view.backgroundColor = RT.canvas
        headerView.backgroundColor = RT.canvas
        searchContainer.backgroundColor = RT.surface
        searchContainer.layer.borderColor = RT.stroke.cgColor
        editBar.backgroundColor = RT.surfaceHigh
        editBar.layer.borderColor = RT.stroke.cgColor
        titleLabel.textColor = RT.text
        statsLabel.textColor = RT.textTertiary
        collectionView.reloadData()
        updateStats()
    }
}

// MARK: - Hero 卡片

/// hero 卡片上的渐变泛光。用 layerClass 直接把 CAGradientLayer 当自己的 backing layer，
/// 尺寸完全交给 Auto Layout，不再需要在 layoutSubviews 里手动同步 frame。
private final class RTHeroGlowView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerRadius = RT.Metric.cardRadius
        layer.cornerCurve = .continuous

        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [RT.accent.withAlphaComponent(0.22).cgColor,
                           RT.accent.withAlphaComponent(0.06).cgColor,
                           RT.accent.withAlphaComponent(0.0).cgColor]
        gradient.locations = [0, 0.55, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 0.9, y: 1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.colors = [RT.accent.withAlphaComponent(0.22).cgColor,
                           RT.accent.withAlphaComponent(0.06).cgColor,
                           RT.accent.withAlphaComponent(0.0).cgColor]
    }
}

final class MuseumHeroCell: UICollectionViewCell {
    static let id = "MuseumHeroCell"

    private let card = RTCardView(style: .raised)
    private let cartridge = RTCartridgeView()
    /// 卡片左上角的绿色泛光。用约束贴边的子视图，尺寸永远跟卡片一致；
    /// 之前是裸 CAGradientLayer，在 layoutSubviews 里手动同步 frame，旋转后总慢一拍，
    /// 泛光会残留横屏的宽度，溢出到卡片右上方。
    private let glow = RTHeroGlowView()
    private let eyebrow = UILabel()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let importButton = UIButton(type: .system)
    private var rom: ROMInfo?
    private var onPlay: ((ROMInfo) -> Void)?
    private var onImport: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(card)
        card.pinEdges(to: contentView)

        // 放在最底层：覆盖卡片的surface色，又不会遮住文字和按钮
        card.insertSubview(glow, at: 0)
        glow.pinEdges(to: card)

        cartridge.translatesAutoresizingMaskIntoConstraints = false

        eyebrow.font = RT.Font.mono(10, weight: .semibold)
        eyebrow.textColor = RT.accent

        nameLabel.font = RT.Font.display(23)
        nameLabel.textColor = RT.text
        nameLabel.numberOfLines = 1

        metaLabel.font = RT.Font.caption(12)
        metaLabel.textColor = RT.textSecondary
        metaLabel.numberOfLines = 1

        playButton.titleLabel?.font = RT.Font.headline(14)
        playButton.setTitleColor(RT.accentInk, for: .normal)
        playButton.backgroundColor = RT.accent
        playButton.layer.cornerRadius = 17
        playButton.layer.cornerCurve = .continuous
        playButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)

        importButton.titleLabel?.font = RT.Font.headline(14)
        importButton.setTitle(L10n.str("empty.action"), for: .normal)
        importButton.setTitleColor(RT.accentInk, for: .normal)
        importButton.backgroundColor = RT.accent
        importButton.layer.cornerRadius = 17
        importButton.layer.cornerCurve = .continuous
        importButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 18, bottom: 8, right: 18)
        importButton.addTarget(self, action: #selector(importTapped), for: .touchUpInside)

        card.addSubviews(cartridge, eyebrow, nameLabel, metaLabel, playButton, importButton)
        NSLayoutConstraint.activate([
            cartridge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            cartridge.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            cartridge.widthAnchor.constraint(equalToConstant: 62),
            cartridge.heightAnchor.constraint(equalToConstant: 74),

            eyebrow.leadingAnchor.constraint(equalTo: cartridge.trailingAnchor, constant: 16),
            eyebrow.topAnchor.constraint(equalTo: card.topAnchor, constant: 26),
            eyebrow.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -20),

            nameLabel.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 5),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            metaLabel.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            metaLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            playButton.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            playButton.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            playButton.heightAnchor.constraint(equalToConstant: 34),

            importButton.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            importButton.topAnchor.constraint(equalTo: metaLabel.bottomAnchor, constant: 12),
            importButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(rom: ROMInfo?, totalGames: Int, onImport: @escaping () -> Void, onPlay: @escaping (ROMInfo) -> Void) {
        self.rom = rom
        self.onImport = onImport
        self.onPlay = onPlay

        let hasGame = rom != nil
        playButton.isHidden = !hasGame
        importButton.isHidden = hasGame
        cartridge.isHidden = !hasGame

        guard let rom = rom else {
            eyebrow.text = L10n.str("hero.empty.eyebrow").uppercased()
            nameLabel.text = L10n.str("hero.empty.title")
            metaLabel.text = L10n.str("hero.empty.subtitle", totalGames)
            return
        }

        nameLabel.text = rom.name
        cartridge.system = rom.system
        playButton.setTitle(L10n.str("hero.play"), for: .normal)

        let stats = GameStatsManager.shared.stats(for: rom.name)
        if let last = stats.lastPlayedDate {
            eyebrow.text = L10n.str("hero.continue").uppercased()
            let playtime = GameStatsManager.shared.formattedPlayTime(romName: rom.name)
            metaLabel.text = "\(rom.system.displayName) · \(playtime) · \(MuseumHeroCell.relativeText(last))"
        } else {
            // 卡带在柜子里但一局没打过，别说成「继续上次」
            eyebrow.text = L10n.str("hero.newcomer").uppercased()
            metaLabel.text = "\(rom.system.displayName) · \(MuseumHeroCell.sizeText(rom.fileSize))"
        }
    }

    private static func sizeText(_ bytes: Int64) -> String {
        let kb = bytes / 1024
        return kb > 1024 ? "\(kb / 1024) MB" : "\(kb) KB"
    }

    @objc private func playTapped() {
        if let rom = rom { onPlay?(rom) }
    }

    @objc private func importTapped() {
        onImport?()
    }

    static func relativeText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L10n.str("time.justnow") }
        if interval < 3600 { return L10n.str("time.minutes", Int(interval / 60)) }
        if interval < 86400 { return L10n.str("time.hours", Int(interval / 3600)) }
        return L10n.str("time.days", Int(interval / 86400))
    }
}

// MARK: - 掌机柜

final class MuseumShelfCell: UICollectionViewCell {
    static let id = "MuseumShelfCell"

    private let cartridge = RTCartridgeView()
    private let nameLabel = UILabel()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        cartridge.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = RT.Font.caption(12)
        nameLabel.textColor = RT.textSecondary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2

        countLabel.font = RT.Font.mono(10)
        countLabel.textColor = RT.textTertiary
        countLabel.textAlignment = .center

        contentView.addSubviews(cartridge, nameLabel, countLabel)
        NSLayoutConstraint.activate([
            cartridge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            cartridge.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cartridge.widthAnchor.constraint(equalToConstant: 58),
            cartridge.heightAnchor.constraint(equalToConstant: 70),

            nameLabel.topAnchor.constraint(equalTo: cartridge.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            countLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            countLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(system: EmulatorSystem, count: Int, selected: Bool) {
        cartridge.system = system
        nameLabel.text = system.displayName
        nameLabel.textColor = selected ? RT.accent : RT.textSecondary
        countLabel.text = L10n.str("shelf.count", count)
        contentView.alpha = selected ? 1 : 0.92
        transform = selected ? CGAffineTransform(scaleX: 1.02, y: 1.02) : .identity
    }
}

// MARK: - 最近游玩卡

final class MuseumRecentCell: UICollectionViewCell {
    static let id = "MuseumRecentCell"

    private let cover = RTCoverView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        // 与「掌机柜」的卡带格子对齐：58×70 封面、居中、下面两行小字
        cover.layer.cornerRadius = 12
        cover.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = RT.Font.caption(12)
        nameLabel.textColor = RT.textSecondary
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2

        metaLabel.font = RT.Font.mono(10)
        metaLabel.textColor = RT.textTertiary
        metaLabel.textAlignment = .center

        contentView.addSubviews(cover, nameLabel, metaLabel)
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            cover.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            cover.widthAnchor.constraint(equalToConstant: 58),
            cover.heightAnchor.constraint(equalToConstant: 70),

            nameLabel.topAnchor.constraint(equalTo: cover.bottomAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(rom: ROMInfo) {
        nameLabel.text = rom.name
        let playtime = GameStatsManager.shared.formattedPlayTime(romName: rom.name)
        metaLabel.text = "\(rom.system.shortCode) · \(playtime)"
        cover.loadCover(for: rom)
    }
}

// MARK: - 游戏列表行

final class MuseumGameRowCell: UICollectionViewCell {
    static let id = "MuseumGameRowCell"

    private let card = RTCardView(style: .plain, radius: 20)
    private let cover = RTCoverView()
    private let nameLabel = UILabel()
    private let metaLabel = UILabel()
    private let favoriteDot = UIView()
    private let checkView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(card)
        card.pinEdges(to: contentView)

        cover.layer.cornerRadius = 12
        cover.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = RT.Font.headline(15)
        nameLabel.textColor = RT.text
        nameLabel.numberOfLines = 1

        metaLabel.font = RT.Font.mono(10)
        metaLabel.textColor = RT.textTertiary

        favoriteDot.backgroundColor = RT.accent
        favoriteDot.layer.cornerRadius = 3
        favoriteDot.translatesAutoresizingMaskIntoConstraints = false

        checkView.image = UIImage(systemName: "checkmark.circle.fill",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        checkView.tintColor = RT.accent
        checkView.isHidden = true
        checkView.translatesAutoresizingMaskIntoConstraints = false

        card.addSubviews(cover, nameLabel, metaLabel, favoriteDot, checkView)
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            cover.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: 42),
            cover.heightAnchor.constraint(equalToConstant: 54),

            nameLabel.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: checkView.leadingAnchor, constant: -8),

            metaLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            metaLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),

            favoriteDot.leadingAnchor.constraint(equalTo: metaLabel.trailingAnchor, constant: 6),
            favoriteDot.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
            favoriteDot.widthAnchor.constraint(equalToConstant: 6),
            favoriteDot.heightAnchor.constraint(equalToConstant: 6),

            checkView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            checkView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: 22),
            checkView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(rom: ROMInfo, selected: Bool, editing: Bool, showSeparator: Bool) {
        nameLabel.text = rom.name
        let playtime = GameStatsManager.shared.formattedPlayTime(romName: rom.name)
        let size = rom.fileSize / 1024
        let sizeText = size > 1024 ? "\(size / 1024) MB" : "\(size) KB"
        metaLabel.text = "\(rom.system.shortCode) · \(sizeText) · \(playtime)"
        favoriteDot.isHidden = !GameStatsManager.shared.isFavorite(rom.name)
        checkView.isHidden = !editing
        checkView.image = UIImage(systemName: selected ? "checkmark.circle.fill" : "circle",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        checkView.tintColor = selected ? RT.accent : RT.textTertiary
        card.layer.borderColor = selected ? RT.accent.withAlphaComponent(0.6).cgColor : RT.stroke.cgColor
        cover.loadCover(for: rom)
        _ = showSeparator
    }
}

// MARK: - 区块标题

final class MuseumSectionHeaderView: UICollectionReusableView {
    static let id = "MuseumSectionHeaderView"

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    var onAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = RT.Font.title(18)
        titleLabel.textColor = RT.text

        subtitleLabel.font = RT.Font.caption(11)
        subtitleLabel.textColor = RT.textTertiary

        actionButton.titleLabel?.font = RT.Font.caption(13)
        actionButton.setTitleColor(RT.accent, for: .normal)
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        addSubviews(titleLabel, subtitleLabel, actionButton)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: RT.Metric.screenPadding),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            subtitleLabel.lastBaselineAnchor.constraint(equalTo: titleLabel.lastBaselineAnchor),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -RT.Metric.screenPadding),
            actionButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, subtitle: String?, action: String?) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil
        actionButton.setTitle(action, for: .normal)
        actionButton.isHidden = action == nil
    }

    @objc private func actionTapped() {
        RT.haptic()
        onAction?()
    }
}
