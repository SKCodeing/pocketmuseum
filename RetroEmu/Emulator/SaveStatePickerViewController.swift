// SaveStatePickerViewController.swift
// 存档槽选择 — 「时间胶囊」视觉
// - save / load：4 个手动槽位，双列卡片，缩略图 + 时间
// - autoLoad：自动存档按时间倒序的列表

import UIKit

enum SaveStatePickerMode {
    case save
    case load
    case autoLoad   // F1: 自动存档历史
}

final class SaveStatePickerViewController: UIViewController {

    private let romName: String
    private let mode: SaveStatePickerMode
    var onComplete: (() -> Void)?

    private static let slotCount = SaveStateManager.manualSlotCount
    private var autoSaveEntries: [AutoSaveEntry] = []

    private let collectionView: UICollectionView
    private let headerContainer = UIView()
    private let plaqueLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let romLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    // MARK: - 时间格式

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    static let preciseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f
    }()

    /// 相对时间，与「时光」页保持同一套说法
    static func relativeText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return L10n.str("time.justnow") }
        if interval < 3600 { return L10n.str("time.minutes", Int(interval / 60)) }
        if interval < 86400 { return L10n.str("time.hours", Int(interval / 3600)) }
        return L10n.str("time.days", Int(interval / 86400))
    }

    // MARK: - Init

    init(romName: String, mode: SaveStatePickerMode) {
        self.romName = romName
        self.mode = mode

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 24, right: 20)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        title = nil

        if mode == .autoLoad {
            autoSaveEntries = SaveStateManager.shared.autoSaveEntries(romName: romName)
        }

        setupHeader()
        setupCollectionView()
        observeTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if mode == .autoLoad {
            autoSaveEntries = SaveStateManager.shared.autoSaveEntries(romName: romName)
            collectionView.reloadData()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let inset = layout.sectionInset
        let available = collectionView.bounds.width - inset.left - inset.right
        guard available > 0 else { return }

        if mode == .autoLoad {
            layout.itemSize = CGSize(width: available, height: 88)
        } else {
            let w = (available - layout.minimumInteritemSpacing) / 2
            layout.itemSize = CGSize(width: w, height: w * 0.92)
        }
    }

    // MARK: - Header

    private func setupHeader() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("savestate.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.4]
        )
        plaqueLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = headerTitle
        titleLabel.font = RT.Font.display(26)
        titleLabel.textColor = RT.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = headerSubtitle
        subtitleLabel.font = RT.Font.caption(13)
        subtitleLabel.textColor = RT.textSecondary
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        romLabel.text = romName
        romLabel.font = RT.Font.mono(11)
        romLabel.textColor = RT.textTertiary
        romLabel.lineBreakMode = .byTruncatingMiddle
        romLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)),
                             for: .normal)
        closeButton.tintColor = RT.text
        closeButton.backgroundColor = RT.surfaceHigh
        closeButton.layer.cornerRadius = 16
        closeButton.layer.cornerCurve = .continuous
        closeButton.layer.borderWidth = 1
        closeButton.layer.borderColor = RT.stroke.cgColor
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        [plaqueLabel, titleLabel, subtitleLabel, romLabel, closeButton].forEach { headerContainer.addSubview($0) }

        NSLayoutConstraint.activate([
            headerContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            headerContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            plaqueLabel.topAnchor.constraint(equalTo: headerContainer.topAnchor),
            plaqueLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),

            closeButton.centerYAnchor.constraint(equalTo: plaqueLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: plaqueLabel.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerContainer.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),

            romLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 8),
            romLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            romLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            romLabel.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
        ])
    }

    private var headerTitle: String {
        switch mode {
        case .save:     return L10n.str("savestate.title.save")
        case .load:     return L10n.str("savestate.title.load")
        case .autoLoad: return L10n.str("savestate.auto.title")
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .save:     return L10n.str("savestate.subtitle.save")
        case .load:     return L10n.str("savestate.subtitle.load")
        case .autoLoad: return L10n.str("savestate.subtitle.auto")
        }
    }

    // MARK: - Collection

    private func setupCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(SaveSlotCell.self, forCellWithReuseIdentifier: SaveSlotCell.reuseID)
        collectionView.register(AutoSaveRowCell.self, forCellWithReuseIdentifier: AutoSaveRowCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 14),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func observeTheme() {
        NotificationCenter.default.addObserver(self,
                                              selector: #selector(themeDidChange),
                                              name: RT.themeDidChange,
                                              object: nil)
    }

    @objc private func themeDidChange() {
        view.backgroundColor = RT.canvas
        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("savestate.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.4]
        )
        titleLabel.textColor = RT.text
        subtitleLabel.textColor = RT.textSecondary
        romLabel.textColor = RT.textTertiary
        closeButton.tintColor = RT.text
        closeButton.backgroundColor = RT.surfaceHigh
        closeButton.layer.borderColor = RT.stroke.cgColor
        collectionView.reloadData()
    }

    @objc private func cancel() {
        dismiss(animated: true) {
            EmulatorCore.shared.start()
        }
    }
}

// MARK: - UICollectionViewDataSource / Delegate
extension SaveStatePickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        mode == .autoLoad ? autoSaveEntries.count : Self.slotCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if mode == .autoLoad {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AutoSaveRowCell.reuseID, for: indexPath) as! AutoSaveRowCell
            let entry = autoSaveEntries[indexPath.item]
            cell.configure(entry: entry,
                           thumbData: SaveStateManager.shared.loadAutoSaveThumb(entry: entry),
                           index: indexPath.item)
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SaveSlotCell.reuseID, for: indexPath) as! SaveSlotCell
        let slot = indexPath.item
        let thumb = SaveStateManager.shared.loadScreenshotData(romName: romName, slot: slot).flatMap(UIImage.init(data:))
        let date = SaveStateManager.shared.saveDate(romName: romName, slot: slot)
        cell.configure(slot: slot, thumbnail: thumb, date: date, mode: mode)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        RT.haptic()

        if mode == .autoLoad {
            let entry = autoSaveEntries[indexPath.item]
            guard let data = SaveStateManager.shared.loadAutoSave(entry: entry) else {
                RTToast.show(L10n.str("time.toast.missing"), icon: "exclamationmark.triangle", in: view)
                return
            }
            _ = EmulatorCore.shared.bridge?.loadState(data)
            EmulatorCore.shared.start()
            onComplete?()
            dismiss(animated: true)
            return
        }

        let slot = indexPath.item
        if mode == .save {
            if SaveStateManager.shared.hasSave(romName: romName, slot: slot) {
                let alert = UIAlertController(title: L10n.str("savestate.overwrite.title"),
                                              message: L10n.str("savestate.overwrite.message", slot + 1),
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.str("savestate.overwrite.confirm"), style: .destructive) { [weak self] _ in
                    self?.performSave(slot: slot)
                })
                alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
                present(alert, animated: true)
            } else {
                performSave(slot: slot)
            }
        } else {
            guard SaveStateManager.shared.hasSave(romName: romName, slot: slot) else { return }
            EmulatorCore.shared.loadState(slot: slot)
            EmulatorCore.shared.start()
            onComplete?()
            dismiss(animated: true)
        }
    }

    private func performSave(slot: Int) {
        EmulatorCore.shared.saveState(slot: slot)
        EmulatorCore.shared.start()
        onComplete?()
        dismiss(animated: true)
    }
}

// MARK: - 手动槽位卡片

private final class SaveSlotCell: UICollectionViewCell {

    static let reuseID = "SaveSlotCell"

    private let card = UIView()
    private let thumbView = UIImageView()
    private let footer = UIView()
    private let slotLabel = UILabel()
    private let dateLabel = UILabel()
    private let emptyIcon = UIImageView()
    private let emptyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        contentView.addSubview(card)

        thumbView.contentMode = .scaleAspectFill
        thumbView.clipsToBounds = true
        thumbView.backgroundColor = RT.surfaceHigh
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(thumbView)

        emptyIcon.image = UIImage(systemName: "plus.circle",
                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .light))
        emptyIcon.tintColor = RT.textTertiary
        emptyIcon.contentMode = .center
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(emptyIcon)

        emptyLabel.text = L10n.str("savestate.empty")
        emptyLabel.font = RT.Font.caption(11)
        emptyLabel.textColor = RT.textTertiary
        emptyLabel.textAlignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(emptyLabel)

        footer.backgroundColor = RT.surface
        footer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(footer)

        slotLabel.font = RT.Font.mono(10, weight: .semibold)
        slotLabel.textColor = RT.accent
        slotLabel.translatesAutoresizingMaskIntoConstraints = false

        dateLabel.font = RT.Font.mono(10)
        dateLabel.textColor = RT.textSecondary
        dateLabel.textAlignment = .right
        dateLabel.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(slotLabel)
        footer.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbView.topAnchor.constraint(equalTo: card.topAnchor),
            thumbView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            thumbView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            thumbView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            emptyIcon.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            emptyIcon.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor, constant: -10),

            emptyLabel.topAnchor.constraint(equalTo: emptyIcon.bottomAnchor, constant: 4),
            emptyLabel.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),

            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 40),

            slotLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 12),
            slotLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),

            dateLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -12),
            dateLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: slotLabel.trailingAnchor, constant: 6),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.card.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
                self.card.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    func configure(slot: Int, thumbnail: UIImage?, date: Date?, mode: SaveStatePickerMode) {
        card.backgroundColor = RT.surface
        card.layer.borderWidth = 1
        card.layer.borderColor = (thumbnail == nil ? RT.stroke : RT.accent.withAlphaComponent(0.25)).cgColor
        footer.backgroundColor = RT.surface
        slotLabel.text = L10n.str("savestate.slot", slot + 1)
        slotLabel.textColor = thumbnail == nil ? RT.textSecondary : RT.accent
        emptyIcon.tintColor = RT.textTertiary
        emptyLabel.textColor = RT.textTertiary

        if let thumb = thumbnail {
            thumbView.image = thumb
            emptyIcon.isHidden = true
            emptyLabel.isHidden = true
            dateLabel.text = date.map { Self.dateFormatter.string(from: $0) } ?? ""
            dateLabel.textColor = RT.textSecondary
        } else {
            thumbView.image = nil
            emptyIcon.isHidden = false
            emptyLabel.isHidden = false
            emptyIcon.image = UIImage(systemName: mode == .load ? "lock" : "plus.circle",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .light))
            dateLabel.text = mode == .load ? "" : L10n.str("savestate.empty.hint")
            dateLabel.textColor = RT.textTertiary
        }
        contentView.alpha = (mode == .load && thumbnail == nil) ? 0.55 : 1
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}

// MARK: - 自动存档行

private final class AutoSaveRowCell: UICollectionViewCell {

    static let reuseID = "AutoSaveRowCell"

    private let card = UIView()
    private let thumbView = UIImageView()
    private let badgeLabel = UILabel()
    private let relativeLabel = UILabel()
    private let preciseLabel = UILabel()
    private let chevron = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = RT.surface
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = RT.stroke.cgColor
        contentView.addSubview(card)

        thumbView.contentMode = .scaleAspectFill
        thumbView.clipsToBounds = true
        thumbView.layer.cornerRadius = 12
        thumbView.layer.cornerCurve = .continuous
        thumbView.backgroundColor = RT.surfaceHigh
        thumbView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(thumbView)

        badgeLabel.font = RT.Font.mono(9, weight: .semibold)
        badgeLabel.textColor = RT.accent
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        relativeLabel.font = RT.Font.headline(14)
        relativeLabel.textColor = RT.text
        relativeLabel.translatesAutoresizingMaskIntoConstraints = false

        preciseLabel.font = RT.Font.mono(10)
        preciseLabel.textColor = RT.textTertiary
        preciseLabel.translatesAutoresizingMaskIntoConstraints = false

        chevron.image = UIImage(systemName: "chevron.right",
                                withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        chevron.tintColor = RT.textTertiary
        chevron.contentMode = .center
        chevron.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(chevron)

        [badgeLabel, relativeLabel, preciseLabel].forEach { card.addSubview($0) }

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            thumbView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 72),
            thumbView.heightAnchor.constraint(equalToConstant: 56),

            badgeLabel.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 12),
            badgeLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            relativeLabel.leadingAnchor.constraint(equalTo: badgeLabel.leadingAnchor),
            relativeLabel.topAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 3),

            preciseLabel.leadingAnchor.constraint(equalTo: badgeLabel.leadingAnchor),
            preciseLabel.topAnchor.constraint(equalTo: relativeLabel.bottomAnchor, constant: 3),

            chevron.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: preciseLabel.trailingAnchor, constant: 8),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.card.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
                self.card.alpha = self.isHighlighted ? 0.85 : 1
            }
        }
    }

    func configure(entry: AutoSaveEntry, thumbData: Data?, index: Int) {
        card.backgroundColor = RT.surface
        card.layer.borderColor = RT.stroke.cgColor
        badgeLabel.text = L10n.str("savestate.auto.index", index + 1)
        relativeLabel.text = SaveStatePickerViewController.relativeText(entry.timestamp)
        relativeLabel.textColor = RT.text
        preciseLabel.text = SaveStatePickerViewController.preciseFormatter.string(from: entry.timestamp)
        preciseLabel.textColor = RT.textTertiary
        chevron.tintColor = RT.textTertiary

        if let data = thumbData, let image = UIImage(data: data) {
            thumbView.image = image
            thumbView.contentMode = .scaleAspectFill
            thumbView.tintColor = nil
        } else {
            thumbView.image = UIImage(systemName: "clock.arrow.circlepath",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .light))
            thumbView.contentMode = .center
            thumbView.tintColor = RT.textTertiary
        }
    }
}
