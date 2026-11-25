// CheatViewController.swift
// 作弊码管理界面

import UIKit

final class CheatViewController: UIViewController {

    private let romName: String
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cheats: [CheatCode] = []

    init(romName: String) {
        self.romName = romName
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.str("cheat.title")
        view.backgroundColor = .systemBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L10n.str("btn.close"), style: .plain, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addCheat)
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
        reload()
    }

    private func reload() {
        cheats = CheatManager.shared.cheats(for: romName)
        tableView.reloadData()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func addCheat() {
        showEditor(cheat: nil)
    }

    private func showEditor(cheat: CheatCode?) {
        let alert = UIAlertController(
            title: cheat == nil ? L10n.str("cheat.add.title") : L10n.str("cheat.edit.title"),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = L10n.str("cheat.field.name")
            tf.text = cheat?.name
        }
        alert.addTextField { tf in
            tf.placeholder = L10n.str("cheat.field.code")
            tf.text = cheat?.code
            tf.autocapitalizationType = .allCharacters
        }

        // 类型选择
        let typeLabel = UILabel()
        typeLabel.text = "类型：\(cheat?.type.rawValue ?? CheatType.rawAddress.rawValue)"
        typeLabel.font = .systemFont(ofSize: 13)
        typeLabel.textColor = .secondaryLabel

        alert.addAction(UIAlertAction(title: "Raw (ADDR:VAL)", style: .default) { [weak self, weak alert] _ in
            self?.saveCheat(from: alert, existing: cheat, type: .rawAddress)
        })
        alert.addAction(UIAlertAction(title: "GameShark", style: .default) { [weak self, weak alert] _ in
            self?.saveCheat(from: alert, existing: cheat, type: .gameShark)
        })
        alert.addAction(UIAlertAction(title: "Game Genie", style: .default) { [weak self, weak alert] _ in
            self?.saveCheat(from: alert, existing: cheat, type: .gameGenie)
        })
        alert.addAction(UIAlertAction(title: L10n.str("btn.cancel"), style: .cancel))
        present(alert, animated: true)
    }

    private func saveCheat(from alert: UIAlertController?, existing: CheatCode?, type: CheatType) {
        guard let name = alert?.textFields?[0].text, !name.isEmpty,
              let code = alert?.textFields?[1].text, !code.isEmpty else { return }
        if var existing = existing {
            existing.name = name
            existing.code = code
            existing.type = type
            CheatManager.shared.update(existing, for: romName)
        } else {
            let cheat = CheatCode(name: name, code: code, type: type)
            CheatManager.shared.add(cheat, for: romName)
        }
        reload()
    }
}

// MARK: - UITableViewDataSource / Delegate
extension CheatViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cheats.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        cheats.isEmpty ? nil : L10n.str("cheat.section.header", romName)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let cheat = cheats[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = cheat.name
        config.secondaryText = "\(cheat.type.rawValue)  \(cheat.code)"
        config.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = config
        cell.accessoryType = cheat.enabled ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let cheat = cheats[indexPath.row]
        CheatManager.shared.toggleEnabled(id: cheat.id, for: romName)
        reload()
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let cheat = cheats[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: L10n.str("cheat.swipe.delete")) { [weak self] _, _, done in
            guard let self = self else { return }
            CheatManager.shared.delete(id: cheat.id, for: self.romName)
            self.reload()
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: L10n.str("cheat.swipe.edit")) { [weak self] _, _, done in
            self?.showEditor(cheat: cheat)
            done(true)
        }
        edit.backgroundColor = .systemBlue
        return UISwipeActionsConfiguration(actions: [delete, edit])
    }
}
