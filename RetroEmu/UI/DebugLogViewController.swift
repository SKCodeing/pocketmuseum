// DebugLogViewController.swift
// 调试日志查看器 — 实时显示 EmuLog 输出，支持导出

import UIKit

final class DebugLogViewController: UIViewController {

    private let textView = UITextView()
    private let clearButton = UIBarButtonItem(title: "清空", style: .plain, target: nil, action: nil)
    private let exportButton = UIBarButtonItem(title: "导出", style: .plain, target: nil, action: nil)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "🪲 调试日志"
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismiss_)
        )
        clearButton.target = self
        clearButton.action = #selector(clearLogs)
        exportButton.target = self
        exportButton.action = #selector(exportLogs)
        navigationItem.rightBarButtonItems = [exportButton, clearButton]

        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isEditable = false
        textView.backgroundColor = UIColor.systemBackground
        textView.textColor = .label
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 实时接收新日志
        EmuLog.onLog = { [weak self] _, entry in
            self?.appendLine(entry)
        }

        reloadAll()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        EmuLog.onLog = nil
    }

    private func reloadAll() {
        let text = EmuLog.recentLogs.joined(separator: "\n")
        textView.text = text.isEmpty ? "（暂无日志）" : text
        scrollToBottom()
    }

    private func appendLine(_ line: String) {
        let current = textView.text ?? ""
        textView.text = current == "（暂无日志）" ? line : current + "\n" + line
        scrollToBottom()
    }

    private func scrollToBottom() {
        guard !textView.text.isEmpty else { return }
        let range = NSRange(location: textView.text.count - 1, length: 1)
        textView.scrollRangeToVisible(range)
    }

    @objc private func dismiss_() {
        dismiss(animated: true)
    }

    @objc private func clearLogs() {
        EmuLog.clear()
        textView.text = "（已清空）"
    }

    @objc private func exportLogs() {
        guard let url = EmuLog.exportToFile() else {
            let alert = UIAlertController(title: "导出失败", message: "无法写入文件", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.barButtonItem = exportButton
        }
        present(vc, animated: true)
    }
}
