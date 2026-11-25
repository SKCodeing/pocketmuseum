// WiFiTransferViewController.swift
// WiFi 传输界面，显示上传/解压进度

import UIKit

final class WiFiTransferViewController: UIViewController {

    private let server = WiFiTransferServer.shared

    private let toggleBtn      = UIButton(type: .system)
    private let urlLabel       = UILabel()
    private let copyBtn        = UIButton(type: .system)
    private let statusCard     = UIView()

    // 进度区域
    private let progressCard   = UIView()
    private let uploadLabel    = UILabel()
    private let uploadBar      = UIProgressView(progressViewStyle: .default)
    private let extractLabel   = UILabel()
    private let extractBar     = UIProgressView(progressViewStyle: .default)
    private let logView        = UITextView()

    // 统计
    private var totalReceived  = 0
    private var logLines: [String] = []

    // 节流：上传进度按 64KB 一次回调，扫码刷新也只能合并成一次
    private var latestProgress: (name: String, fileReceived: Int, fileTotal: Int,
                                 received: Int, grandTotal: Int, totalFiles: Int)?
    private var lastProgressRender = Date.distantPast
    private var progressFlushScheduled = false
    private var refreshWork: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.str("wifi.title")
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(closeSelf)
        )
        setupUI()
        setupServerCallbacks()
        updateState()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        flushLibraryRefresh()
        if server.isRunning { server.stop() }
    }

    // MARK: - 服务器回调

    private func setupServerCallbacks() {
        server.onUploadProgress = { [weak self] filename, fileReceived, fileTotal, totalReceived, grandTotal, totalFiles in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.latestProgress = (filename, fileReceived, fileTotal, totalReceived, grandTotal, totalFiles)
                self.flushProgressIfNeeded()
            }
        }

        server.onExtractProgress = { [weak self] zipName, current, total in
            DispatchQueue.main.async {
                let progress = total > 0 ? Float(current) / Float(total) : 0
                self?.extractBar.isHidden = false
                self?.extractLabel.isHidden = false
                self?.extractBar.setProgress(progress, animated: true)
                self?.extractLabel.text = L10n.str("wifi.extract.label", zipName, current, total)
                self?.progressCard.isHidden = false
            }
        }

        server.onFileReceived = { [weak self] url in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.totalReceived += 1
                let name = url.lastPathComponent
                self.appendLog("✅ \(name)")
                self.progressCard.isHidden = false
                // 进度行统一交给 renderProgress 画：这里如果自己改一次文案、再把进度条拉满，
                // 下一次字节回调又改回去，就成了屏幕上那个来回跳的进度
                self.flushProgressIfNeeded()
                // 别每个文件都扫全库：扫一次会连带刷新首页与时光轴（每份存档都要 stat 文件），
                // 252 个文件就是 252 次全库刷新，主线程会被堵住几十秒
                self.scheduleLibraryRefresh()
            }
        }
    }

    // MARK: - 进度节流与扫库合并

    private func flushProgressIfNeeded() {
        let elapsed = Date().timeIntervalSince(lastProgressRender)
        if elapsed >= 0.1 {
            renderProgress()
        } else if !progressFlushScheduled {
            progressFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.progressFlushScheduled = false
                self?.renderProgress()
            }
        }
    }

    private func renderProgress() {
        guard let p = latestProgress else { return }
        lastProgressRender = Date()

        let overallProgress: Float
        if p.grandTotal > 0 {
            overallProgress = Float(p.received) / Float(p.grandTotal)
        } else if p.fileTotal > 0 {
            overallProgress = Float(p.fileReceived) / Float(p.fileTotal)
        } else {
            overallProgress = 1.0
        }
        uploadBar.setProgress(overallProgress, animated: true)

        // 只报个数：日志区已经逐条打文件名了，名字跟着 64KB 一次的回调变就是「来回闪」的元凶
        let done = totalReceived
        let count = p.totalFiles > 0
            ? L10n.str("wifi.upload.received.of", done, p.totalFiles)
            : L10n.str("wifi.upload.received", done)
        uploadLabel.text = "\(count)  ·  \(Int((overallProgress * 100).rounded()))%"
        progressCard.isHidden = false
    }

    /// 上传安静 0.5 秒后再扫一次库，中间的刷新请求全部丢掉
    private func scheduleLibraryRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.refreshWork = nil
            ROMLibrary.shared.scan()
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// 关页面前把还没执行的刷新补上，否则刚传完的卡带要等下次进首页才出现
    private func flushLibraryRefresh() {
        guard let work = refreshWork else { return }
        refreshWork = nil
        work.cancel()
        ROMLibrary.shared.scan()
    }

    // MARK: - UI

    private func setupUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40),
        ])

        // 开关按钮
        toggleBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        toggleBtn.layer.cornerRadius = 10
        toggleBtn.translatesAutoresizingMaskIntoConstraints = false
        toggleBtn.addTarget(self, action: #selector(toggleServer), for: .touchUpInside)
        toggleBtn.heightAnchor.constraint(equalToConstant: 50).isActive = true

        // 状态卡片
        statusCard.backgroundColor = .secondarySystemBackground
        statusCard.layer.cornerRadius = 12
        urlLabel.font = .monospacedSystemFont(ofSize: 17, weight: .bold)
        urlLabel.textAlignment = .center
        urlLabel.adjustsFontSizeToFitWidth = true
        copyBtn.setTitle(L10n.str("wifi.copy"), for: .normal)
        copyBtn.addTarget(self, action: #selector(copyURL), for: .touchUpInside)
        let hintLabel = UILabel()
        hintLabel.text = L10n.str("wifi.hint")
        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        let statusStack = UIStackView(arrangedSubviews: [urlLabel, copyBtn, hintLabel])
        statusStack.axis = .vertical
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusStack)
        NSLayoutConstraint.activate([
            statusStack.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: 16),
            statusStack.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: 16),
            statusStack.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -16),
            statusStack.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -16),
        ])

        // 进度卡片
        progressCard.backgroundColor = .secondarySystemBackground
        progressCard.layer.cornerRadius = 12
        progressCard.isHidden = true

        uploadLabel.font = .systemFont(ofSize: 13)
        uploadLabel.textColor = .secondaryLabel
        uploadLabel.text = L10n.str("wifi.upload.waiting")
        uploadBar.tintColor = .systemBlue
        uploadBar.trackTintColor = .systemFill

        extractLabel.font = .systemFont(ofSize: 13)
        extractLabel.textColor = .secondaryLabel
        extractLabel.text = L10n.str("wifi.extract.title")
        extractBar.tintColor = .systemOrange
        extractBar.trackTintColor = .systemFill
        // 没有 zip 时这两行没意义，等真正解压再露出来
        extractLabel.isHidden = true
        extractBar.isHidden = true

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.backgroundColor = UIColor.black.withAlphaComponent(0.05)
        logView.layer.cornerRadius = 6
        logView.translatesAutoresizingMaskIntoConstraints = false
        logView.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let clearBtn = UIButton(type: .system)
        clearBtn.setTitle(L10n.str("wifi.log.clear"), for: .normal)
        clearBtn.titleLabel?.font = .systemFont(ofSize: 12)
        clearBtn.addTarget(self, action: #selector(clearLog), for: .touchUpInside)

        let progressStack = UIStackView(arrangedSubviews: [
            uploadLabel, uploadBar,
            extractLabel, extractBar,
            logView, clearBtn
        ])
        progressStack.axis = .vertical
        progressStack.spacing = 6
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressCard.addSubview(progressStack)
        NSLayoutConstraint.activate([
            progressStack.topAnchor.constraint(equalTo: progressCard.topAnchor, constant: 16),
            progressStack.leadingAnchor.constraint(equalTo: progressCard.leadingAnchor, constant: 16),
            progressStack.trailingAnchor.constraint(equalTo: progressCard.trailingAnchor, constant: -16),
            progressStack.bottomAnchor.constraint(equalTo: progressCard.bottomAnchor, constant: -16),
        ])

        // 说明卡片
        let guideCard = makeGuideCard()
        // 格式说明卡片
        let formatsCard = makeFormatsCard()

        stack.addArrangedSubview(toggleBtn)
        stack.addArrangedSubview(statusCard)
        stack.addArrangedSubview(progressCard)
        stack.addArrangedSubview(guideCard)
        stack.addArrangedSubview(formatsCard)
    }

    private func makeGuideCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12
        let title = UILabel()
        title.text = L10n.str("wifi.guide.title")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let steps = UILabel()
        steps.text = L10n.str("wifi.guide.steps")
        steps.font = .systemFont(ofSize: 13)
        steps.textColor = .secondaryLabel
        steps.numberOfLines = 0
        let s = UIStackView(arrangedSubviews: [title, steps])
        s.axis = .vertical; s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            s.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            s.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            s.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    private func makeFormatsCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 12

        let title = UILabel()
        title.text = "支持的 ROM 格式"
        title.font = .systemFont(ofSize: 15, weight: .semibold)

        let formats: [(platform: String, icon: String, exts: String)] = [
            ("NES（红白机）",              "🎮", ".nes"),
            ("Game Boy / GBC",            "🟩", ".gb  .gbc"),
            ("Game Boy Advance",          "🟦", ".gba"),
            ("Super Nintendo（超任）",     "🟣", ".sfc  .smc"),
            ("Nintendo DS",               "📱", ".nds"),
            ("Nintendo 64",               "🔵", ".z64  .n64  .v64"),
            ("Game Gear",                 "📺", ".gg"),
            ("Sega Master System",        "📺", ".sms"),
            ("Mega Drive / Genesis",      "⚫", ".md  .bin  .gen"),
            ("Sega 32X",                  "⚫", ".32x"),
            ("Sega CD / Mega-CD",         "💿", ".cue  .iso"),
            ("PlayStation（PS1）",         "🔲", ".bin  .cue  .iso  .pbp"),
            ("PSP",                       "🎯", ".iso  .cso  .pbp"),
            ("ZIP 压缩包",                "📦", ".zip（自动解压）"),
        ]

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(title)

        let divider = UIView()
        divider.backgroundColor = .separator
        divider.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        stack.addArrangedSubview(divider)
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(8, after: divider)

        for (platform, icon, exts) in formats {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = 8
            row.alignment = .firstBaseline

            let iconLabel = UILabel()
            iconLabel.text = icon
            iconLabel.font = .systemFont(ofSize: 14)
            iconLabel.setContentHuggingPriority(.required, for: .horizontal)
            iconLabel.widthAnchor.constraint(equalToConstant: 22).isActive = true

            let platformLabel = UILabel()
            platformLabel.text = platform
            platformLabel.font = .systemFont(ofSize: 13)
            platformLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let extLabel = UILabel()
            extLabel.text = exts
            extLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            extLabel.textColor = .systemBlue
            extLabel.textAlignment = .right
            extLabel.setContentHuggingPriority(.required, for: .horizontal)
            extLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

            row.addArrangedSubview(iconLabel)
            row.addArrangedSubview(platformLabel)
            row.addArrangedSubview(extLabel)
            stack.addArrangedSubview(row)
            stack.setCustomSpacing(6, after: row)
        }

        let note = UILabel()
        note.text = "💡 也可通过「文件 App」或「从其他 App 打开」导入"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .tertiaryLabel
        note.numberOfLines = 0
        stack.addArrangedSubview(note)

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
        return card
    }

    // MARK: - 状态更新

    private func updateState() {
        if server.isRunning {
            toggleBtn.setTitle(L10n.str("wifi.btn.stop"), for: .normal)
            toggleBtn.backgroundColor = .systemRed
            toggleBtn.setTitleColor(.white, for: .normal)
            urlLabel.text = server.localURL
            urlLabel.textColor = .systemBlue
            copyBtn.isHidden = false
        } else {
            toggleBtn.setTitle(L10n.str("wifi.btn.start"), for: .normal)
            toggleBtn.backgroundColor = .systemGreen
            toggleBtn.setTitleColor(.white, for: .normal)
            urlLabel.text = L10n.str("wifi.server.stopped")
            urlLabel.textColor = .secondaryLabel
            copyBtn.isHidden = true
        }
    }

    // MARK: - Actions

    @objc private func toggleServer() {
        if server.isRunning {
            server.stop()
            updateState()
        } else {
            totalReceived = 0
            server.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.updateState()
            }
        }
    }

    @objc private func copyURL() {
        UIPasteboard.general.string = server.localURL
        showToast(L10n.str("wifi.toast.copied"))
    }

    @objc private func clearLog() {
        logLines = []
        logView.text = ""
        uploadBar.setProgress(0, animated: false)
        extractBar.setProgress(0, animated: false)
        uploadLabel.text = L10n.str("wifi.upload.waiting")
        extractLabel.text = L10n.str("wifi.extract.title")
        totalReceived = 0
    }

    @objc private func closeSelf() {
        dismiss(animated: true)
    }

    private func appendLog(_ msg: String) {
        logLines.append(msg)
        if logLines.count > 200 { logLines.removeFirst(50) }
        logView.text = logLines.joined(separator: "\n")
        let range = NSRange(location: logView.text.count - 1, length: 1)
        logView.scrollRangeToVisible(range)
        progressCard.isHidden = false
    }

    private func showToast(_ msg: String) {
        let label = UILabel()
        label.text = msg
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14)
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            label.heightAnchor.constraint(equalToConstant: 36),
        ])
        UIView.animate(withDuration: 0.3, delay: 1.5) { label.alpha = 0 } completion: { _ in
            label.removeFromSuperview()
        }
    }
}
