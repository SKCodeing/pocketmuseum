// MuseumReportViewController.swift
// 年度回顾页：把 MuseumReportCanvas 放在滚动页里读，底部一键导出长图。
// 页面本身不做统计——数字全部来自 MuseumReport，这里只负责呈现和分享。

import UIKit

final class MuseumReportViewController: UIViewController {

    private let canvas: MuseumReportCanvas

    private let scrollView = UIScrollView()
    private let closeButton = UIButton(type: .system)
    private let shareButton = UIButton(type: .system)

    // 宽屏居中列：窄屏下常量为 0，与改造前的行为完全一致
    private var closeTrailingInset: NSLayoutConstraint?
    private var shareLeadingInset: NSLayoutConstraint?
    private var shareTrailingInset: NSLayoutConstraint?
    private var lastLaidOutWidth: CGFloat = 0

    init(report: MuseumReport = .make()) {
        self.canvas = MuseumReportCanvas(report: report)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = RT.canvas
        setupSheet()
        setupLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateWideLayout()
        // 画布是 frame 排版：宽屏收成居中阅读栏，高度由内容算出来
        let full = scrollView.bounds.width
        guard full > 0 else { return }
        let column = RT.Metric.readingColumnWidth(for: full)
        let height = canvas.layout(inWidth: column)
        let target = CGRect(x: (full - column) / 2, y: 0, width: column, height: height)
        guard canvas.frame != target else { return }
        canvas.frame = target
        scrollView.contentSize = CGSize(width: full, height: height)
    }

    /// 宽屏（iPad 横屏、Duo 展开内屏）把关闭按钮与分享条对齐到居中列的边缘。
    private func updateWideLayout() {
        let width = view.bounds.width
        guard width != lastLaidOutWidth else { return }
        lastLaidOutWidth = width
        let inset = RT.Metric.readingColumnInset(for: width)
        closeTrailingInset?.constant = -RT.Metric.screenPadding - inset
        shareLeadingInset?.constant = RT.Metric.screenPadding + inset
        shareTrailingInset?.constant = -RT.Metric.screenPadding - inset
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

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
        scrollView.backgroundColor = RT.canvas
        view.addSubview(scrollView)
        scrollView.addSubview(canvas)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)),
                             for: .normal)
        closeButton.tintColor = RT.textSecondary
        closeButton.backgroundColor = RT.surfaceHigh
        closeButton.layer.cornerRadius = 17
        closeButton.addTarget(self, action: #selector(dismissSelf), for: .touchUpInside)
        view.addSubview(closeButton)

        configureShareButton()
        view.addSubview(shareButton)

        closeTrailingInset = closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                                  constant: -RT.Metric.screenPadding)
        shareLeadingInset = shareButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                                 constant: RT.Metric.screenPadding)
        shareTrailingInset = shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                                  constant: -RT.Metric.screenPadding)
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            // 横向贴安全区：Duo 展开后的内屏右侧有系统侧置状态栏，贴 view 边会被盖住。
            // 宽屏时再向里让出居中列的边距，让按钮与正文对齐。
            closeTrailingInset!,
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34),

            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: shareButton.topAnchor, constant: -12),

            shareLeadingInset!, shareTrailingInset!,
            shareButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
        ])
    }

    // MARK: - 分享

    private func configureShareButton() {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = RT.accent
        config.baseForegroundColor = RT.accentInk
        config.cornerStyle = .capsule
        config.attributedTitle = AttributedString(
            L10n.str("report.share"),
            attributes: AttributeContainer([.font: RT.Font.headline(16)])
        )
        config.image = UIImage(systemName: "square.and.arrow.up")
        config.imagePadding = 8
        shareButton.configuration = config
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        shareButton.addAction(UIAction { [weak self] _ in
            self?.shareReport()
        }, for: .touchUpInside)
    }

    private func shareReport() {
        guard let image = canvas.renderImage() else {
            RTToast.show(L10n.str("report.share.fail"), icon: "exclamationmark.triangle")
            return
        }
        RT.haptic(.medium)

        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX,
                                                                  y: view.bounds.maxY - 60,
                                                                  width: 1, height: 1)
        present(activity, animated: true)
        // 分享面板收起后画布恢复成屏幕宽度，别带着导出时的 362pt 尺寸留在页面上
        activity.completionWithItemsHandler = { [weak self] _, _, _, _ in
            guard let self = self else { return }
            self.canvas.frame = .zero
            self.view.setNeedsLayout()
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }
}
