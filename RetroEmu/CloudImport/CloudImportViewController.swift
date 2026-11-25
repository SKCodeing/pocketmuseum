// CloudImportViewController.swift
// 云端文件浏览器 UI
// F3: 云导入 - 支持 WebDAV 目录浏览和 ROM 下载

import UIKit

final class CloudImportViewController: UIViewController {

    // MARK: - 属性

    private let provider: CloudProvider
    private var currentPath: String
    private var entries: [CloudEntry] = []
    private var isLoading = false

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private let emptyLabel = UILabel()

    // 下载进度弹窗
    private var progressAlert: UIAlertController?

    // MARK: - Init

    init(provider: CloudProvider, path: String = "/") {
        self.provider = provider
        self.currentPath = path
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = provider.displayName
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupEmptyLabel()
        setupActivityIndicator()

        loadDirectory()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(dismiss_)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh, target: self, action: #selector(refresh)
        )
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.text = "此目录为空"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 16)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func setupActivityIndicator() {
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // MARK: - 加载目录

    private func loadDirectory() {
        guard !isLoading else { return }
        isLoading = true
        activityIndicator.startAnimating()
        emptyLabel.isHidden = true

        provider.listDirectory(path: currentPath) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoading = false
                self.activityIndicator.stopAnimating()

                switch result {
                case .success(let entries):
                    // 目录在前，文件在后；ROM 文件高亮
                    self.entries = entries.sorted {
                        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    self.tableView.reloadData()
                    self.emptyLabel.isHidden = !self.entries.isEmpty

                case .failure(let error):
                    self.showError(error)
                }
            }
        }
    }

    // MARK: - 下载 ROM

    private func downloadROM(entry: CloudEntry) {
        // 显示进度弹窗
        let alert = UIAlertController(title: "正在下载", message: entry.name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.provider.cancelAll()
        })
        progressAlert = alert
        present(alert, animated: true)

        provider.downloadFile(entry: entry, progress: { [weak self] progress in
            DispatchQueue.main.async {
                self?.progressAlert?.message = "\(entry.name)\n\(Int(progress * 100))%"
            }
        }) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.progressAlert?.dismiss(animated: true)
                self.progressAlert = nil

                switch result {
                case .success(let tmpURL):
                    self.importROM(from: tmpURL, originalName: entry.name)
                case .failure(let error):
                    if case CloudError.cancelled = error { return }
                    self.showError(error)
                }
            }
        }
    }

    private func importROM(from url: URL, originalName: String) {
        let docsROMs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ROMs", isDirectory: true)
        try? FileManager.default.createDirectory(at: docsROMs, withIntermediateDirectories: true)

        let destURL = docsROMs.appendingPathComponent(originalName)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                // 询问是否覆盖
                let alert = UIAlertController(
                    title: "文件已存在",
                    message: "是否覆盖 \(originalName)？",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "覆盖", style: .destructive) { [weak self] _ in
                    try? FileManager.default.removeItem(at: destURL)
                    self?.finishImport(from: url, to: destURL, name: originalName)
                })
                alert.addAction(UIAlertAction(title: "跳过", style: .cancel))
                present(alert, animated: true)
            } else {
                finishImport(from: url, to: destURL, name: originalName)
            }
        }
    }

    private func finishImport(from src: URL, to dest: URL, name: String) {
        do {
            try FileManager.default.moveItem(at: src, to: dest)
            NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
            showSuccess("「\(name)」已导入游戏库")
        } catch {
            showError(error)
        }
    }

    // MARK: - 操作

    @objc private func dismiss_() {
        provider.cancelAll()
        dismiss(animated: true)
    }

    @objc private func refresh() {
        loadDirectory()
    }

    // MARK: - 提示

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: "错误", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func showSuccess(_ message: String) {
        let alert = UIAlertController(title: "✅ 导入成功", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension CloudImportViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let entry = entries[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = entry.name

        if entry.isDirectory {
            config.image = UIImage(systemName: "folder.fill")
            config.imageProperties.tintColor = .systemYellow
            cell.accessoryType = .disclosureIndicator
        } else if entry.isROM {
            config.image = UIImage(systemName: "gamecontroller.fill")
            config.imageProperties.tintColor = .systemBlue
            // 显示文件大小
            if entry.size > 0 {
                config.secondaryText = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
            }
            cell.accessoryType = .none
        } else {
            config.image = UIImage(systemName: "doc")
            config.imageProperties.tintColor = .secondaryLabel
            cell.accessoryType = .none
            cell.selectionStyle = .none
        }

        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = entries[indexPath.row]

        if entry.isDirectory {
            // 进入子目录
            let vc = CloudImportViewController(provider: provider, path: entry.path)
            vc.title = entry.name
            navigationController?.pushViewController(vc, animated: true)
        } else if entry.isROM {
            downloadROM(entry: entry)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        currentPath == "/" ? "根目录" : (currentPath as NSString).lastPathComponent
    }
}

// MARK: - WebDAV 配置入口

final class WebDAVSetupViewController: UIViewController {

    var onConnected: ((WebDAVClient) -> Void)?

    private let serverField   = UITextField()
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let connectButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "连接 WebDAV"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )
        setupUI()

        // 恢复已保存的配置
        if let saved = WebDAVClient.savedConfig() {
            serverField.text   = saved.serverURL
            usernameField.text = saved.username
            passwordField.text = saved.password
        }
    }

    private func setupUI() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        func makeField(_ placeholder: String, secure: Bool = false) -> UITextField {
            let f = UITextField()
            f.placeholder = placeholder
            f.borderStyle = .roundedRect
            f.autocapitalizationType = .none
            f.autocorrectionType = .no
            f.isSecureTextEntry = secure
            f.heightAnchor.constraint(equalToConstant: 44).isActive = true
            return f
        }

        serverField.placeholder   = "服务器地址（如 https://cloud.example.com/dav/）"
        serverField.borderStyle   = .roundedRect
        serverField.autocapitalizationType = .none
        serverField.autocorrectionType = .no
        serverField.keyboardType  = .URL
        serverField.heightAnchor.constraint(equalToConstant: 44).isActive = true

        usernameField.placeholder = "用户名"
        usernameField.borderStyle = .roundedRect
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        usernameField.heightAnchor.constraint(equalToConstant: 44).isActive = true

        passwordField.placeholder = "密码"
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.heightAnchor.constraint(equalToConstant: 44).isActive = true

        connectButton.setTitle("连接", for: .normal)
        connectButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        connectButton.backgroundColor = .systemBlue
        connectButton.setTitleColor(.white, for: .normal)
        connectButton.layer.cornerRadius = 10
        connectButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        connectButton.addTarget(self, action: #selector(connect), for: .touchUpInside)

        let hint = UILabel()
        hint.text = "支持 Nextcloud、ownCloud、群晖 NAS 等 WebDAV 服务"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabel
        hint.numberOfLines = 0
        hint.textAlignment = .center

        [serverField, usernameField, passwordField, connectButton, hint].forEach { stack.addArrangedSubview($0) }

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 20),
        ])
    }

    @objc private func connect() {
        guard let server = serverField.text, !server.isEmpty,
              let username = usernameField.text, !username.isEmpty,
              let password = passwordField.text, !password.isEmpty else {
            showAlert("请填写所有字段")
            return
        }

        connectButton.isEnabled = false
        activityIndicator.startAnimating()

        let config = WebDAVClient.Config(serverURL: server, username: username, password: password, basePath: "/")
        let client = WebDAVClient(config: config)

        client.testConnection { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.connectButton.isEnabled = true
                self.activityIndicator.stopAnimating()

                switch result {
                case .success:
                    client.saveConfig()
                    self.onConnected?(client)
                case .failure(let error):
                    self.showAlert("连接失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @objc private func cancel() { dismiss(animated: true) }

    private func showAlert(_ msg: String) {
        let alert = UIAlertController(title: nil, message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}


