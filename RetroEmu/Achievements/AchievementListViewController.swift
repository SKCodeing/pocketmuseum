// AchievementListViewController.swift
// 成就列表页
// F7: 成就系统

import UIKit

final class AchievementListViewController: UIViewController {

    // MARK: - 属性

    private var achievements: [RAAchievement] = []
    private var filteredAchievements: [RAAchievement] = []
    private var showOnlyUnlocked = false

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerView = AchievementHeaderView()
    private let emptyLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .medium)

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "成就"
        view.backgroundColor = .systemBackground

        setupNavigationBar()
        setupTableView()
        setupEmptyLabel()
        setupActivityIndicator()

        loadAchievements()

        // 监听成就解锁
        AchievementManager.shared.onAchievementUnlocked = { [weak self] achievement in
            self?.handleUnlock(achievement)
        }
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close)
        )
        let filterButton = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain, target: self, action: #selector(toggleFilter)
        )
        navigationItem.rightBarButtonItem = filterButton
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(AchievementCell.self, forCellReuseIdentifier: AchievementCell.id)
        tableView.tableHeaderView = headerView
        headerView.frame = CGRect(x: 0, y: 0, width: 0, height: 100)
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
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
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

    // MARK: - 数据加载

    private func loadAchievements() {
        achievements = AchievementManager.shared.currentAchievements

        if achievements.isEmpty {
            // 尝试加载当前游戏的成就
            guard let romURL = currentROMURL() else {
                showEmpty("请先运行一款游戏")
                return
            }
            guard AchievementManager.shared.isLoggedIn else {
                showLoginPrompt()
                return
            }

            activityIndicator.startAnimating()
            let md5 = AchievementManager.md5(of: romURL) ?? ""
            AchievementManager.shared.loadAchievements(romMD5: md5) { [weak self] result in
                DispatchQueue.main.async {
                    self?.activityIndicator.stopAnimating()
                    switch result {
                    case .success(let list):
                        self?.achievements = list
                        self?.applyFilter()
                    case .failure(let error):
                        self?.showEmpty(error.localizedDescription)
                    }
                }
            }
        } else {
            applyFilter()
        }
    }

    private func applyFilter() {
        filteredAchievements = showOnlyUnlocked
            ? achievements.filter { $0.isUnlocked }
            : achievements
        updateHeader()
        tableView.reloadData()
        emptyLabel.isHidden = !filteredAchievements.isEmpty
        if filteredAchievements.isEmpty && showOnlyUnlocked {
            emptyLabel.text = "还没有解锁任何成就"
        }
    }

    private func updateHeader() {
        let total    = achievements.count
        let unlocked = achievements.filter { $0.isUnlocked }.count
        let points   = achievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points }
        headerView.configure(unlocked: unlocked, total: total, points: points)
    }

    private func handleUnlock(_ achievement: RAAchievement) {
        if let idx = achievements.firstIndex(where: { $0.id == achievement.id }) {
            achievements[idx] = achievement
        }
        applyFilter()
    }

    // MARK: - 操作

    @objc private func close() { dismiss(animated: true) }

    @objc private func toggleFilter() {
        showOnlyUnlocked.toggle()
        navigationItem.rightBarButtonItem?.image = UIImage(
            systemName: showOnlyUnlocked
                ? "line.3.horizontal.decrease.circle.fill"
                : "line.3.horizontal.decrease.circle"
        )
        applyFilter()
    }

    // MARK: - 空状态

    private func showEmpty(_ message: String) {
        emptyLabel.text = message
        emptyLabel.isHidden = false
    }

    private func showLoginPrompt() {
        let alert = UIAlertController(
            title: "登录 RetroAchievements",
            message: "请输入您的 RetroAchievements 账号和 API Key\n（在 retroachievements.org 个人设置中获取）",
            preferredStyle: .alert
        )
        alert.addTextField { $0.placeholder = "用户名" }
        alert.addTextField { tf in
            tf.placeholder = "API Key"
            tf.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "登录", style: .default) { [weak self, weak alert] _ in
            guard let username = alert?.textFields?[0].text, !username.isEmpty,
                  let apiKey   = alert?.textFields?[1].text, !apiKey.isEmpty else { return }
            AchievementManager.shared.login(username: username, apiKey: apiKey) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success: self?.loadAchievements()
                    case .failure(let e): self?.showEmpty(e.localizedDescription)
                    }
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.showEmpty("登录 RetroAchievements 后可查看成就")
        })
        present(alert, animated: true)
    }

    private func currentROMURL() -> URL? {
        guard let name = EmulatorCore.shared.currentROMName,
              let system = EmulatorCore.shared.currentSystem else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        for ext in system.fileExtensions {
            let url = romsDir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}

// MARK: - UITableViewDataSource / Delegate

extension AchievementListViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredAchievements.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: AchievementCell.id, for: indexPath) as! AchievementCell
        cell.configure(achievement: filteredAchievements[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 72 }
}

// MARK: - AchievementHeaderView（进度概览）

private final class AchievementHeaderView: UIView {

    private let progressBar  = UIProgressView(progressViewStyle: .default)
    private let statsLabel   = UILabel()
    private let pointsLabel  = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        progressBar.progressTintColor = .systemYellow
        progressBar.trackTintColor = .systemFill
        progressBar.layer.cornerRadius = 3
        progressBar.clipsToBounds = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        statsLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statsLabel.textAlignment = .center
        statsLabel.translatesAutoresizingMaskIntoConstraints = false

        pointsLabel.font = .systemFont(ofSize: 12)
        pointsLabel.textColor = .secondaryLabel
        pointsLabel.textAlignment = .center
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false

        [progressBar, statsLabel, pointsLabel].forEach { addSubview($0) }
        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            statsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            progressBar.topAnchor.constraint(equalTo: statsLabel.bottomAnchor, constant: 8),
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            pointsLabel.topAnchor.constraint(equalTo: progressBar.bottomAnchor, constant: 6),
            pointsLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(unlocked: Int, total: Int, points: Int) {
        statsLabel.text = "已解锁 \(unlocked) / \(total) 个成就"
        progressBar.progress = total > 0 ? Float(unlocked) / Float(total) : 0
        pointsLabel.text = "已获得 \(points) 分"
    }
}

// MARK: - AchievementCell

private final class AchievementCell: UITableViewCell {
    static let id = "AchievementCell"

    private let badgeView   = UIImageView()
    private let titleLabel  = UILabel()
    private let descLabel   = UILabel()
    private let pointsLabel = UILabel()
    private let lockIcon    = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none

        badgeView.contentMode = .scaleAspectFit
        badgeView.layer.cornerRadius = 8
        badgeView.clipsToBounds = true
        badgeView.backgroundColor = .secondarySystemBackground
        badgeView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 2
        descLabel.translatesAutoresizingMaskIntoConstraints = false

        pointsLabel.font = .systemFont(ofSize: 11, weight: .medium)
        pointsLabel.textColor = .systemYellow
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false

        lockIcon.image = UIImage(systemName: "lock.fill")
        lockIcon.tintColor = .tertiaryLabel
        lockIcon.contentMode = .scaleAspectFit
        lockIcon.translatesAutoresizingMaskIntoConstraints = false

        [badgeView, titleLabel, descLabel, pointsLabel, lockIcon].forEach { contentView.addSubview($0) }

        NSLayoutConstraint.activate([
            badgeView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            badgeView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 48),
            badgeView.heightAnchor.constraint(equalToConstant: 48),

            titleLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: lockIcon.leadingAnchor, constant: -8),

            descLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 10),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(equalTo: lockIcon.leadingAnchor, constant: -8),

            pointsLabel.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 10),
            pointsLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 2),
            pointsLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -8),

            lockIcon.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            lockIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            lockIcon.widthAnchor.constraint(equalToConstant: 20),
            lockIcon.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(achievement: RAAchievement) {
        titleLabel.text = achievement.title
        descLabel.text  = achievement.description
        pointsLabel.text = "\(achievement.points) 分"
        lockIcon.isHidden = achievement.isUnlocked

        // 已解锁：正常显示；未解锁：灰色
        contentView.alpha = achievement.isUnlocked ? 1.0 : 0.5

        // 加载徽章图片
        let badgeURL = "https://media.retroachievements.org/Badge/\(achievement.badgeName)\(achievement.isUnlocked ? "" : "_lock").png"
        badgeView.image = UIImage(systemName: "trophy.fill")
        badgeView.tintColor = achievement.isUnlocked ? .systemYellow : .tertiaryLabel
        if let url = URL(string: badgeURL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async { self?.badgeView.image = image }
                }
            }.resume()
        }
    }
}
