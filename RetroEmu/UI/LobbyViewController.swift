// LobbyViewController.swift
// 局域网多人大厅：创建房间 / 加入房间

import UIKit
import Network

enum NetworkMode {
    case none
    case host
    case client
}

final class LobbyViewController: UIViewController {

    private let stackView = UIStackView()
    private let statusLabel = UILabel()
    private let hostButton = UIButton(type: .system)
    private let joinButton = UIButton(type: .system)
    private let playerNameField = UITextField()
    private let tableView = UITableView()
    private var discoveredHosts: [NWBrowser.Result] = []
    private var isHosting = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L10n.str("lobby.title")
        view.backgroundColor = .systemBackground
        setupUI()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NetworkManager.shared.stopBrowsing()
        if isHosting { NetworkManager.shared.stopHosting() }
    }

    // MARK: - UI
    private func setupUI() {
        // 玩家名称输入
        playerNameField.placeholder = L10n.str("lobby.name.placeholder")
        playerNameField.borderStyle = .roundedRect
        playerNameField.text = UIDevice.current.name
        playerNameField.translatesAutoresizingMaskIntoConstraints = false

        // 按钮
        hostButton.setTitle(L10n.str("lobby.btn.host"), for: .normal)
        hostButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        hostButton.backgroundColor = .systemBlue
        hostButton.setTitleColor(.white, for: .normal)
        hostButton.layer.cornerRadius = 10
        hostButton.addTarget(self, action: #selector(startHosting), for: .touchUpInside)

        joinButton.setTitle(L10n.str("lobby.btn.join"), for: .normal)
        joinButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        joinButton.backgroundColor = .systemGreen
        joinButton.setTitleColor(.white, for: .normal)
        joinButton.layer.cornerRadius = 10
        joinButton.addTarget(self, action: #selector(startBrowsing), for: .touchUpInside)

        statusLabel.textAlignment = .center
        statusLabel.textColor = .secondaryLabel
        statusLabel.font = .systemFont(ofSize: 14)
        statusLabel.text = L10n.str("lobby.status.default")

        // 发现的主机列表
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "HostCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(playerNameField)
        view.addSubview(hostButton)
        view.addSubview(joinButton)
        view.addSubview(statusLabel)
        view.addSubview(tableView)

        hostButton.translatesAutoresizingMaskIntoConstraints = false
        joinButton.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            playerNameField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            playerNameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            playerNameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            playerNameField.heightAnchor.constraint(equalToConstant: 44),

            hostButton.topAnchor.constraint(equalTo: playerNameField.bottomAnchor, constant: 20),
            hostButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hostButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            hostButton.heightAnchor.constraint(equalToConstant: 50),

            joinButton.topAnchor.constraint(equalTo: hostButton.bottomAnchor, constant: 12),
            joinButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            joinButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            joinButton.heightAnchor.constraint(equalToConstant: 50),

            statusLabel.topAnchor.constraint(equalTo: joinButton.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            tableView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Actions
    @objc private func startHosting() {
        let name = playerNameField.text?.isEmpty == false ? playerNameField.text! : UIDevice.current.name
        isHosting = true
        NetworkManager.shared.startHosting(playerName: name)
        NetworkManager.shared.delegate = self
        statusLabel.text = L10n.str("lobby.status.hosting")
        hostButton.isEnabled = false
        joinButton.isEnabled = false
    }

    @objc private func startBrowsing() {
        statusLabel.text = L10n.str("lobby.status.scanning")
        NetworkManager.shared.browseForHosts()
        NetworkManager.shared.onHostsDiscovered = { [weak self] results in
            self?.discoveredHosts = results
            self?.tableView.reloadData()
            self?.statusLabel.text = results.isEmpty ? L10n.str("lobby.status.nohosts") : L10n.str("lobby.status.found", results.count)
        }
    }

    private func connectToHost(_ result: NWBrowser.Result) {
        let name = playerNameField.text?.isEmpty == false ? playerNameField.text! : UIDevice.current.name
        NetworkManager.shared.stopBrowsing()
        NetworkManager.shared.delegate = self
        NetworkManager.shared.connectToHost(result, playerName: name)
        statusLabel.text = L10n.str("lobby.status.connecting")
    }
}

// MARK: - TableView
extension LobbyViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return discoveredHosts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "HostCell", for: indexPath)
        let result = discoveredHosts[indexPath.row]
        if case .service(let name, _, _, _) = result.endpoint {
            cell.textLabel?.text = name
        } else {
            cell.textLabel?.text = result.endpoint.debugDescription
        }
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        connectToHost(discoveredHosts[indexPath.row])
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return discoveredHosts.isEmpty ? nil : L10n.str("lobby.section.hosts")
    }
}

// MARK: - NetworkManagerDelegate
extension LobbyViewController: NetworkManagerDelegate {
    func networkManager(_ manager: NetworkManager, didConnectPlayer player: NetworkPlayer) {
        statusLabel.text = L10n.str("lobby.status.joined", player.name)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            if manager.isHost {
                self.navigationController?.popViewController(animated: true)
            } else {
                self.statusLabel.text = L10n.str("lobby.status.connected.client")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }

    func networkManager(_ manager: NetworkManager, didDisconnectPlayer playerID: String) {
        statusLabel.text = L10n.str("lobby.status.disconnected")
        hostButton.isEnabled = true
        joinButton.isEnabled = true
        isHosting = false
    }

    func networkManager(_ manager: NetworkManager, didReceiveInput buttons: UInt16, playerIndex: Int, frame: UInt64) {}
    func networkManager(_ manager: NetworkManager, didReceiveStartGame romName: String) {}
    func networkManager(_ manager: NetworkManager, latencyUpdated ms: Double) {
        statusLabel.text = L10n.str("lobby.status.latency", Int(ms))
    }
}
