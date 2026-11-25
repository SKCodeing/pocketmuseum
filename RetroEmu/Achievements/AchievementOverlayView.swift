// AchievementOverlayView.swift
// 成就解锁弹窗（从顶部滑入，3 秒后自动消失）
// F7: 成就系统

import UIKit

final class AchievementOverlayView: UIView {

    // MARK: - 子视图

    private let containerView = UIView()
    private let iconView      = UIImageView()
    private let titleLabel    = UILabel()
    private let descLabel     = UILabel()
    private let pointsLabel   = UILabel()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        // 容器：毛玻璃效果
        let blur = UIBlurEffect(style: .systemMaterialDark)
        let blurView = UIVisualEffectView(effect: blur)
        blurView.layer.cornerRadius = 14
        blurView.clipsToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(blurView)

        containerView.layer.cornerRadius = 14
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOpacity = 0.4
        containerView.layer.shadowRadius = 8
        containerView.layer.shadowOffset = CGSize(width: 0, height: 4)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(containerView)

        // 图标
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 8
        iconView.clipsToBounds = true
        iconView.backgroundColor = .systemYellow.withAlphaComponent(0.2)
        iconView.image = UIImage(systemName: "trophy.fill")
        iconView.tintColor = .systemYellow
        iconView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconView)

        // 标题
        titleLabel.text = "成就解锁！"
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .systemYellow
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // 成就名称
        descLabel.font = .systemFont(ofSize: 14, weight: .bold)
        descLabel.textColor = .white
        descLabel.numberOfLines = 2
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descLabel)

        // 积分
        pointsLabel.font = .systemFont(ofSize: 11)
        pointsLabel.textColor = .systemYellow
        pointsLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(pointsLabel)

        NSLayoutConstraint.activate([
            // 容器居中，宽度 320，最大不超过屏幕
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
            containerView.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            blurView.topAnchor.constraint(equalTo: containerView.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            iconView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            descLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            pointsLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            pointsLabel.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 2),
            pointsLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -10),
        ])
    }

    // MARK: - 配置

    func configure(achievement: RAAchievement) {
        descLabel.text = achievement.title
        pointsLabel.text = "+\(achievement.points) 分"

        // 异步加载徽章图片
        let badgeURL = "https://media.retroachievements.org/Badge/\(achievement.badgeName).png"
        if let url = URL(string: badgeURL) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self?.iconView.image = image
                        self?.iconView.tintColor = nil
                    }
                }
            }.resume()
        }
    }

    // MARK: - 显示/隐藏动画

    /// 在指定视图中显示成就弹窗，3 秒后自动消失
    static func show(achievement: RAAchievement, in parentView: UIView) {
        let overlay = AchievementOverlayView()
        overlay.configure(achievement: achievement)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        parentView.addSubview(overlay)

        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: parentView.leadingAnchor, constant: 16),
            overlay.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -16),
            overlay.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor, constant: 8),
            overlay.heightAnchor.constraint(equalToConstant: 72),
        ])

        // 初始状态：在屏幕上方
        overlay.transform = CGAffineTransform(translationX: 0, y: -100)
        overlay.alpha = 0

        // 滑入
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7,
                       initialSpringVelocity: 0.5, options: []) {
            overlay.transform = .identity
            overlay.alpha = 1
        }

        // 3 秒后滑出
        UIView.animate(withDuration: 0.3, delay: 3.0, options: []) {
            overlay.transform = CGAffineTransform(translationX: 0, y: -100)
            overlay.alpha = 0
        } completion: { _ in
            overlay.removeFromSuperview()
        }
    }
}
