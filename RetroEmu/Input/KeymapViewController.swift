// KeymapViewController.swift
// 按键重映射界面 + 快捷键绑定（F8）

import UIKit

final class KeymapViewController: UIViewController {

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    // MARK: - 数据源

    // Section 0/1：按键重映射（GamepadSlot → EmulatorButton）
    private let remapSections: [(title: String, slots: [GamepadSlot])] = [
        ("方向键",   [.dpadUp, .dpadDown, .dpadLeft, .dpadRight]),
        ("功能键",   [.btnA, .btnB, .btnX, .btnY, .btnStart, .btnSelect]),
    ]

    // Section 2：快捷键绑定（ShortcutAction → GamepadSlot?）
    private let shortcutActions = ShortcutAction.allCases

    private enum SectionKind { case remap(Int), shortcuts }
    private func sectionKind(_ section: Int) -> SectionKind {
        section < remapSections.count ? .remap(section) : .shortcuts
    }
    private var totalSections: Int { remapSections.count + 1 }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.str("keymap.title")
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.str("btn.close"), style: .plain, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L10n.str("keymap.reset.confirm"), style: .plain, target: self, action: #selector(resetAll)
        )

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - 操作

    @objc private func close() { dismiss(animated: true) }

    @objc private func resetAll() {
        let alert = UIAlertController(title: L10n.str("keymap.reset.title"), message: L10n.str("keymap.reset.message"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("keymap.reset.confirm"), style: .destructive) { [weak self] _ in
            KeymapSettings.shared.reset()
            ShortcutKeymap.shared.reset()
            self?.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    // MARK: - 按键重映射选择器

    private func showRemapPicker(for slot: GamepadSlot, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "映射「\(slot.displayName)」到",
            message: "选择此按键触发的模拟器按键",
            preferredStyle: .actionSheet
        )
        for item in KeymapSettings.mappableButtons {
            let current = KeymapSettings.shared.button(for: slot)
            let check = current == item.button ? "✓ " : ""
            alert.addAction(UIAlertAction(title: "\(check)\(item.label)", style: .default) { [weak self] _ in
                KeymapSettings.shared.setButton(item.button, for: slot)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        popoverSource(alert, at: indexPath)
        present(alert, animated: true)
    }

    // MARK: - 快捷键绑定选择器（F8）

    private func showShortcutPicker(for action: ShortcutAction, at indexPath: IndexPath) {
        let alert = UIAlertController(
            title: "绑定「\(action.displayName)」",
            message: "选择触发此操作的手柄按键（按下时触发）",
            preferredStyle: .actionSheet
        )
        // 「无」选项
        let noneCheck = ShortcutKeymap.shared.slot(for: action) == nil ? "✓ " : ""
        alert.addAction(UIAlertAction(title: "\(noneCheck)无（禁用）", style: .default) { [weak self] _ in
            ShortcutKeymap.shared.setSlot(nil, for: action)
            self?.tableView.reloadRows(at: [indexPath], with: .none)
        })
        // 所有可绑定的槽位
        for slot in GamepadSlot.allCases {
            let current = ShortcutKeymap.shared.slot(for: action)
            let check = current == slot ? "✓ " : ""
            alert.addAction(UIAlertAction(title: "\(check)\(slot.displayName)", style: .default) { [weak self] _ in
                ShortcutKeymap.shared.setSlot(slot, for: action)
                self?.tableView.reloadRows(at: [indexPath], with: .none)
            })
        }
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        popoverSource(alert, at: indexPath)
        present(alert, animated: true)
    }

    private func popoverSource(_ alert: UIAlertController, at indexPath: IndexPath) {
        if let pop = alert.popoverPresentationController,
           let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
    }
}

// MARK: - UITableViewDataSource / Delegate

extension KeymapViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { totalSections }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sectionKind(section) {
        case .remap(let i): return remapSections[i].slots.count
        case .shortcuts:    return shortcutActions.count
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch sectionKind(section) {
        case .remap(let i): return remapSections[i].title
        case .shortcuts:    return "快捷键绑定"
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch sectionKind(section) {
        case .shortcuts: return "将常用操作绑定到手柄按键，游戏中按下即可触发。"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.accessoryType = .disclosureIndicator

        switch sectionKind(indexPath.section) {
        case .remap(let si):
            let slot = remapSections[si].slots[indexPath.row]
            let mapped = KeymapSettings.shared.button(for: slot)
            let label = KeymapSettings.mappableButtons.first { $0.button == mapped }?.label ?? "?"
            var config = cell.defaultContentConfiguration()
            config.text = slot.displayName
            config.secondaryText = label
            config.secondaryTextProperties.color = .systemBlue
            cell.contentConfiguration = config

        case .shortcuts:
            let action = shortcutActions[indexPath.row]
            let boundSlot = ShortcutKeymap.shared.slot(for: action)
            var config = cell.defaultContentConfiguration()
            config.text = action.displayName
            config.secondaryText = boundSlot?.displayName ?? "未绑定"
            config.secondaryTextProperties.color = boundSlot != nil ? .systemBlue : .tertiaryLabel
            cell.contentConfiguration = config
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sectionKind(indexPath.section) {
        case .remap(let si):
            showRemapPicker(for: remapSections[si].slots[indexPath.row], at: indexPath)
        case .shortcuts:
            showShortcutPicker(for: shortcutActions[indexPath.row], at: indexPath)
        }
    }
}
