// ROMDetailViewController.swift
// 展签：一张卡带的身份档案。
// 博物馆里每件展品都有展签——这一页把「文件属性」翻译成「藏品档案」，
// 加一枚入藏编号和一段藏品笔记。模拟器不会有这一页。

import UIKit

final class ROMDetailViewController: UIViewController {

    private let rom: ROMInfo

    /// 点「开箱游玩」后由首页接手启动，模态收起之后才调用
    var onPlay: ((ROMInfo) -> Void)?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let fieldsStack = UIStackView()
    private let noteView = UITextView()
    private let notePlaceholder = UILabel()
    private let closeButton = UIButton(type: .system)

    private var metadata: ROMMetadata?
    private lazy var record: AccessionRecord = AccessionStore.shared.ensureRecord(for: rom.name)

    // 宽屏居中列：窄屏下常量为 0，与改造前的行为完全一致
    private var closeTrailingInset: NSLayoutConstraint?
    private var scrollLeadingInset: NSLayoutConstraint?
    private var scrollTrailingInset: NSLayoutConstraint?
    private var playLeadingInset: NSLayoutConstraint?
    private var playTrailingInset: NSLayoutConstraint?
    private var lastLaidOutWidth: CGFloat = 0

    init(rom: ROMInfo) {
        self.rom = rom
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        setupSheet()
        setupLayout()
        fillStaticFields()
        loadMetadata()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNote()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWideLayout()
    }

    /// 宽屏（iPad 横屏、Duo 展开内屏）把档案卡收成居中阅读栏，窄屏不变。
    private func updateWideLayout() {
        let width = view.bounds.width
        guard width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        let inset = RT.Metric.readingColumnInset(for: width)
        closeTrailingInset?.constant = -RT.Metric.screenPadding - inset
        scrollLeadingInset?.constant = inset
        scrollTrailingInset?.constant = -inset
        playLeadingInset?.constant = RT.Metric.screenPadding + inset
        playTrailingInset?.constant = -RT.Metric.screenPadding - inset
    }

    // MARK: - 结构

    private func setupSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 28
    }

    private func setupLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.spacing = 22
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
                             for: .normal)
        closeButton.tintColor = RT.textSecondary
        closeButton.backgroundColor = RT.surfaceHigh
        closeButton.layer.cornerRadius = 17
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeButton)

        // 底部固定：开箱游玩
        let playButton = makePlayButton()
        view.addSubview(playButton)

        closeTrailingInset = closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                                  constant: -RT.Metric.screenPadding)
        scrollLeadingInset = scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
        scrollTrailingInset = scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor)
        playLeadingInset = playButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                               constant: RT.Metric.screenPadding)
        playTrailingInset = playButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                                 constant: -RT.Metric.screenPadding)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeTrailingInset!,
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollLeadingInset!, scrollTrailingInset!,
            scrollView.bottomAnchor.constraint(equalTo: playButton.topAnchor, constant: -12),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                                                  constant: RT.Metric.screenPadding),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                                   constant: -RT.Metric.screenPadding),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor,
                                                constant: -RT.Metric.screenPadding * 2),

            playLeadingInset!, playTrailingInset!,
            playButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makeIdentity())
        contentStack.addArrangedSubview(makeArchiveCard())
        contentStack.addArrangedSubview(makeNoteSection())
    }

    // MARK: - 顶部：眉标 + 入藏编号

    private func makeHeader() -> UIView {
        let eyebrow = UILabel()
        eyebrow.attributedText = NSAttributedString(
            string: "\(L10n.str("exhibit.eyebrow"))  ·  \(record.number)",
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: RT.accent,
                         .kern: 2.2]
        )

        let row = UIStackView(arrangedSubviews: [eyebrow, UIView()])
        row.axis = .horizontal
        row.alignment = .center
        return row
    }

    // MARK: - 卡带 + 名称

    private func makeIdentity() -> UIView {
        let cartridge = RTCartridgeView()
        cartridge.system = rom.system
        cartridge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cartridge.widthAnchor.constraint(equalToConstant: 84),
            cartridge.heightAnchor.constraint(equalToConstant: 98),
        ])

        let name = UILabel()
        name.text = rom.name
        name.font = RT.Font.title(24)
        name.textColor = RT.text
        name.numberOfLines = 2

        let meta = UILabel()
        meta.text = "\(rom.system.displayName) · \(rom.system.launchYear) · \(sizeText)"
        meta.font = RT.Font.caption(12)
        meta.textColor = RT.textSecondary

        let textStack = UIStackView(arrangedSubviews: [name, meta])
        textStack.axis = .vertical
        textStack.spacing = 6
        textStack.alignment = .leading

        let row = UIStackView(arrangedSubviews: [cartridge, textStack])
        row.axis = .horizontal
        row.spacing = 16
        row.alignment = .center
        return row
    }

    // MARK: - 档案卡

    private func makeArchiveCard() -> UIView {
        fieldsStack.axis = .vertical
        fieldsStack.spacing = 12
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = L10n.str("exhibit.section.archive")
        title.font = RT.Font.headline(14)
        title.textColor = RT.text

        let stack = UIStackView(arrangedSubviews: [title, fieldsStack])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let card = RTCardView(style: .plain)
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
        ])

        // 展签左侧那根竖色条：博物馆标签的固定记号
        let spine = UIView()
        spine.backgroundColor = RT.accent.withAlphaComponent(0.65)
        spine.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(spine)
        NSLayoutConstraint.activate([
            spine.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            spine.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            spine.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            spine.widthAnchor.constraint(equalToConstant: 3),
        ])
        return card
    }

    private func addField(_ title: String, _ value: String, mono: Bool = false) {
        let key = UILabel()
        key.text = title
        key.font = RT.Font.caption(11)
        key.textColor = RT.textTertiary
        key.setContentHuggingPriority(.required, for: .horizontal)
        key.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let val = UILabel()
        val.text = value
        val.font = mono ? RT.Font.mono(12) : RT.Font.caption(13)
        val.textColor = RT.text
        val.numberOfLines = 0

        let row = UIStackView(arrangedSubviews: [key, val])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .firstBaseline
        fieldsStack.addArrangedSubview(row)
    }

    /// 先把不需要读文件就能算出来的字段填上，文件头解析完再补技术字段
    private func fillStaticFields() {
        let autoCount = SaveStateManager.shared.autoSaveEntries(romName: rom.name).count
        let manualCount = (0..<SaveStateManager.manualSlotCount)
            .filter { SaveStateManager.shared.hasSave(romName: rom.name, slot: $0) }
            .count
        let stats = GameStatsManager.shared.stats(for: rom.name)

        addField(L10n.str("exhibit.field.platform"), rom.system.displayName)
        addField(L10n.str("exhibit.field.size"), sizeText)

        if stats.totalSeconds >= 1 {
            addField(L10n.str("exhibit.field.playtime"),
                     GameStatsManager.shared.formattedPlayTime(romName: rom.name))
        } else {
            addField(L10n.str("exhibit.field.playtime"), L10n.str("exhibit.playtime.none"))
        }

        if let last = stats.lastPlayedDate {
            addField(L10n.str("exhibit.field.lastplayed"), MuseumHeroCell.relativeText(last))
        }

        addField(L10n.str("exhibit.field.saves"),
                 L10n.str("exhibit.saves.value", autoCount, manualCount))

        addField(L10n.str("exhibit.field.accessioned"), dateText(record.date))
    }

    private func loadMetadata() {
        let url = rom.url
        let system = rom.system
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let meta = ROMMetadata.read(url: url, system: system)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.metadata = meta
                self.appendTechnicalFields(meta)
            }
        }
    }

    /// 技术字段另起一段，读不出来的就整行不加，不留「—」占位
    private func appendTechnicalFields(_ meta: ROMMetadata) {
        if let format = meta.format, let board = meta.board {
            addField(L10n.str("exhibit.field.board"), "\(format) · \(board)", mono: true)
        } else if let format = meta.format {
            addField(L10n.str("exhibit.field.board"), format, mono: true)
        }

        if let prg = meta.prgSize, let chr = meta.chrSize, chr != prg {
            addField(L10n.str("exhibit.field.memory"),
                     L10n.str("exhibit.memory.value", prg / 1024, chr / 1024), mono: true)
        }

        let fingerprint = meta.fingerprintNote.map { "\(meta.fingerprint) · \($0)" } ?? meta.fingerprint
        addField(L10n.str("exhibit.field.fingerprint"), fingerprint, mono: true)
    }

    // MARK: - 藏品笔记

    private func makeNoteSection() -> UIView {
        let title = UILabel()
        title.text = L10n.str("exhibit.note.title")
        title.font = RT.Font.headline(14)
        title.textColor = RT.text

        let hint = UILabel()
        hint.text = L10n.str("exhibit.note.hint")
        hint.font = RT.Font.caption(11)
        hint.textColor = RT.textTertiary

        noteView.text = record.note
        noteView.font = RT.Font.body(14)
        noteView.textColor = RT.text
        noteView.backgroundColor = .clear
        noteView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        noteView.isScrollEnabled = false
        noteView.delegate = self
        noteView.translatesAutoresizingMaskIntoConstraints = false

        notePlaceholder.text = L10n.str("exhibit.note.placeholder")
        notePlaceholder.font = RT.Font.body(14)
        notePlaceholder.textColor = RT.textTertiary
        notePlaceholder.numberOfLines = 0
        notePlaceholder.translatesAutoresizingMaskIntoConstraints = false
        notePlaceholder.isHidden = !record.note.isEmpty

        let box = RTCardView(style: .plain, radius: RT.Metric.innerRadius)
        box.backgroundColor = RT.surfaceHigh
        box.addSubview(noteView)
        box.addSubview(notePlaceholder)
        NSLayoutConstraint.activate([
            noteView.topAnchor.constraint(equalTo: box.topAnchor),
            noteView.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            noteView.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            noteView.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            noteView.heightAnchor.constraint(greaterThanOrEqualToConstant: 132),

            notePlaceholder.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            notePlaceholder.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 15),
            notePlaceholder.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -15),
        ])

        let stack = UIStackView(arrangedSubviews: [title, hint, box])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(6, after: title)
        return stack
    }

    private func saveNote() {
        AccessionStore.shared.updateNote(noteView.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                        for: rom.name)
    }

    // MARK: - 底部按钮

    private func makePlayButton() -> UIButton {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RT.accent
        config.baseForegroundColor = RT.accentInk
        config.cornerStyle = .capsule
        config.attributedTitle = AttributedString(
            L10n.str("exhibit.play"),
            attributes: AttributeContainer([.font: RT.Font.headline(16)])
        )
        config.image = UIImage(systemName: "shippingbox")
        config.imagePadding = 8
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            RT.haptic(.medium)
            self.saveNote()
            let rom = self.rom
            self.dismiss(animated: true) { self.onPlay?(rom) }
        }, for: .touchUpInside)
        return button
    }

    @objc private func dismissSelf() {
        saveNote()
        dismiss(animated: true)
    }

    // MARK: - 工具

    private var sizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: rom.fileSize)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.str("meta.dateLocale"))
        formatter.dateFormat = L10n.str("meta.dateFormat")
        return formatter.string(from: date)
    }
}

extension ROMDetailViewController: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        notePlaceholder.isHidden = !textView.text.isEmpty
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        saveNote()
    }
}
