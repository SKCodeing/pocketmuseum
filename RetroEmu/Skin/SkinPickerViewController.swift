// SkinPickerViewController.swift
// 手柄皮肤选择 — 卡片式陈列，导入 .retroskin 皮肤包

import UIKit
import UniformTypeIdentifiers

final class SkinPickerViewController: UIViewController {

    private let system: EmulatorSystem
    private var skins: [InstalledSkin] = []

    private let collectionView: UICollectionView
    private let headerContainer = UIView()
    private let plaqueLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let importButton = UIButton(type: .system)
    private let emptyState = RTEmptyStateView(icon: "paintpalette",
                                              title: L10n.str("skin.empty.title"),
                                              message: L10n.str("skin.empty.message"),
                                              actionTitle: L10n.str("skin.empty.action"))

    init(system: EmulatorSystem) {
        self.system = system
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 14
        layout.sectionInset = UIEdgeInsets(top: 4, left: 20, bottom: 28, right: 20)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        setupHeader()
        setupCollectionView()
        setupEmptyState()
        reloadSkins()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let inset = layout.sectionInset
        let available = collectionView.bounds.width - inset.left - inset.right
        guard available > 0 else { return }
        let w = (available - layout.minimumInteritemSpacing) / 2
        layout.itemSize = CGSize(width: w, height: w * 1.18)
    }

    // MARK: - Header

    private func setupHeader() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerContainer)

        plaqueLabel.attributedText = NSAttributedString(
            string: L10n.str("skin.plaque"),
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.4]
        )
        plaqueLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.text = system.displayName
        titleLabel.font = RT.Font.display(26)
        titleLabel.textColor = RT.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.text = L10n.str("skin.subtitle")
        subtitleLabel.font = RT.Font.caption(13)
        subtitleLabel.textColor = RT.textSecondary
        subtitleLabel.numberOfLines = 2
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

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

        var config = UIButton.Configuration.plain()
        config.title = L10n.str("skin.import")
        config.image = UIImage(systemName: "square.and.arrow.down",
                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        config.imagePadding = 6
        config.baseForegroundColor = RT.accent
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        importButton.configuration = config
        importButton.titleLabel?.font = RT.Font.headline(12)
        importButton.backgroundColor = RT.accentSoft
        importButton.layer.cornerRadius = 15
        importButton.layer.cornerCurve = .continuous
        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.addTarget(self, action: #selector(importSkin), for: .touchUpInside)

        [plaqueLabel, titleLabel, subtitleLabel, closeButton, importButton].forEach { headerContainer.addSubview($0) }

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

            importButton.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 12),
            importButton.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            importButton.heightAnchor.constraint(equalToConstant: 34),
            importButton.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor),
        ])
    }

    // MARK: - Collection

    private func setupCollectionView() {
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.register(SkinCell.self, forCellWithReuseIdentifier: SkinCell.reuseID)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 14),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.onAction = { [weak self] in self?.importSkin() }
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 40),
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - Data

    private func reloadSkins() {
        skins = SkinManager.shared.installedSkins.filter {
            $0.system == system.rawValue || $0.system == "unknown"
        }
        collectionView.reloadData()
        emptyState.isHidden = !skins.isEmpty
        collectionView.isHidden = skins.isEmpty
    }

    // MARK: - Actions

    @objc private func cancel() { dismiss(animated: true) }

    @objc private func importSkin() {
        var types: [UTType] = []
        if let skinType = UTType(filenameExtension: SkinManager.skinExtension) {
            types.append(skinType)
        }
        // 兼容历史皮肤包：允许选择任意数据文件，解析失败会给出提示
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func activateSkin(_ skin: InstalledSkin) {
        SkinManager.shared.setActiveSkin(skin, for: system)
        RT.haptic()
        collectionView.reloadData()
        RTToast.show(L10n.str("skin.toast.applied", skin.name), icon: "checkmark", in: view)
    }

    private func deleteSkin(_ skin: InstalledSkin) {
        let alert = UIAlertController(title: L10n.str("skin.delete.title"),
                                      message: L10n.str("skin.delete.message", skin.name),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("btn.delete"), style: .destructive) { [weak self] _ in
            SkinManager.shared.deleteSkin(skin)
            self?.reloadSkins()
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - UICollectionViewDataSource / Delegate

extension SkinPickerViewController: UICollectionViewDataSource, UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        skins.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SkinCell.reuseID, for: indexPath) as! SkinCell
        let skin = skins[indexPath.item]
        let isActive = SkinManager.shared.activeSkin(for: system)?.id == skin.id
        cell.configure(skin: skin,
                       preview: SkinManager.shared.loadPreviewImage(skin: skin),
                       isActive: isActive)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        activateSkin(skins[indexPath.item])
    }

    func collectionView(_ collectionView: UICollectionView,
                        contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        let skin = skins[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let delete = UIAction(title: L10n.str("btn.delete"),
                                  image: UIImage(systemName: "trash"),
                                  attributes: .destructive) { _ in
                self?.deleteSkin(skin)
            }
            return UIMenu(title: skin.name, children: [delete])
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension SkinPickerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        _ = url.startAccessingSecurityScopedResource()
        SkinManager.shared.installSkin(from: url) { [weak self] result in
            url.stopAccessingSecurityScopedResource()
            guard let self = self else { return }
            switch result {
            case .success(let skin):
                self.reloadSkins()
                RTToast.show(L10n.str("skin.toast.installed", skin.name), icon: "checkmark", in: self.view)
            case .failure(let error):
                let alert = UIAlertController(title: L10n.str("skin.import.fail"),
                                              message: error.localizedDescription,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L10n.str("btn.ok"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }
}

// MARK: - SkinCell

private final class SkinCell: UICollectionViewCell {

    static let reuseID = "SkinCell"

    private let card = UIView()
    private let previewView = UIImageView()
    private let nameLabel = UILabel()
    private let badge = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = RT.surface
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = RT.stroke.cgColor
        card.clipsToBounds = true
        contentView.addSubview(card)

        previewView.contentMode = .scaleAspectFit
        previewView.backgroundColor = RT.surfaceHigh
        previewView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(previewView)

        nameLabel.font = RT.Font.headline(12)
        nameLabel.textColor = RT.text
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(nameLabel)

        badge.font = RT.Font.mono(9, weight: .semibold)
        badge.textColor = RT.accentInk
        badge.backgroundColor = RT.accent
        badge.textAlignment = .center
        badge.layer.cornerRadius = 8
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.text = L10n.str("skin.current")
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(badge)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            previewView.topAnchor.constraint(equalTo: card.topAnchor),
            previewView.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            previewView.heightAnchor.constraint(equalTo: card.heightAnchor, multiplier: 0.76),

            nameLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 6),
            nameLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),

            badge.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            badge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            badge.widthAnchor.constraint(equalToConstant: 46),
            badge.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.card.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    func configure(skin: InstalledSkin, preview: UIImage?, isActive: Bool) {
        card.backgroundColor = RT.surface
        card.layer.borderColor = isActive ? RT.accent.cgColor : RT.stroke.cgColor
        card.layer.borderWidth = isActive ? 1.6 : 1
        previewView.backgroundColor = RT.surfaceHigh
        nameLabel.text = skin.name
        nameLabel.textColor = RT.text
        badge.isHidden = !isActive
        badge.backgroundColor = RT.accent
        badge.textColor = RT.accentInk

        if let preview = preview {
            previewView.image = preview
            previewView.contentMode = .scaleAspectFit
            previewView.tintColor = nil
        } else {
            previewView.image = UIImage(systemName: "gamecontroller",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .light))
            previewView.contentMode = .center
            previewView.tintColor = RT.textTertiary
        }
    }
}
