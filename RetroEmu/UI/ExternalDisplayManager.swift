// ExternalDisplayManager.swift
// AirPlay / 外接显示器管理
// F4: AirPlay 投屏支持
//
// 工作原理：
//   - 连接外部屏幕时，将 MetalRenderer 的 MTKView 移至外部 UIWindow
//   - 手机端切换为"控制器模式"：隐藏游戏画面，只显示虚拟手柄
//   - 断开时恢复手机全屏模式

import UIKit
import MetalKit

protocol ExternalDisplayManagerDelegate: AnyObject {
    /// 外部屏幕已连接，应切换到控制器模式
    func externalDisplayDidConnect(_ manager: ExternalDisplayManager)
    /// 外部屏幕已断开，应恢复全屏模式
    func externalDisplayDidDisconnect(_ manager: ExternalDisplayManager)
}

final class ExternalDisplayManager {

    static let shared = ExternalDisplayManager()

    weak var delegate: ExternalDisplayManagerDelegate?

    private(set) var isExternalDisplayActive = false
    private(set) var externalWindow: UIWindow?
    private var externalMTKView: MTKView?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidConnect(_:)),
            name: UIScreen.didConnectNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenDidDisconnect(_:)),
            name: UIScreen.didDisconnectNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 屏幕连接/断开

    @objc private func screenDidConnect(_ note: Notification) {
        guard let screen = note.object as? UIScreen else { return }
        DispatchQueue.main.async { self.setupExternalDisplay(screen: screen) }
    }

    @objc private func screenDidDisconnect(_ note: Notification) {
        DispatchQueue.main.async { self.teardownExternalDisplay() }
    }

    // MARK: - 建立外部显示

    func setupExternalDisplay(screen: UIScreen) {
        guard externalWindow == nil else { return }

        // 创建绑定到外部屏幕的 UIWindow
        let window = UIWindow(frame: screen.bounds)
        window.screen = screen
        window.backgroundColor = .black

        // 创建全屏 MTKView 用于外部显示
        let mtkView = MTKView(frame: screen.bounds)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.backgroundColor = .black

        // 将 MetalRenderer 的渲染目标切换到外部 MTKView
        if let renderer = currentRenderer() {
            renderer.attachToExternalView(mtkView)
        }

        let vc = ExternalDisplayViewController(mtkView: mtkView)
        window.rootViewController = vc
        window.isHidden = false

        externalWindow = window
        externalMTKView = mtkView
        isExternalDisplayActive = true

        delegate?.externalDisplayDidConnect(self)
        NotificationCenter.default.post(name: .externalDisplayDidConnect, object: nil)
    }

    func teardownExternalDisplay() {
        guard externalWindow != nil else { return }

        // 将渲染目标切回手机屏幕
        if let renderer = currentRenderer() {
            renderer.detachFromExternalView()
        }

        externalMTKView = nil
        externalWindow?.isHidden = true
        externalWindow = nil
        isExternalDisplayActive = false

        delegate?.externalDisplayDidDisconnect(self)
        NotificationCenter.default.post(name: .externalDisplayDidDisconnect, object: nil)
    }

    // MARK: - 工具

    private func currentRenderer() -> MetalRenderer? {
        // 通过 EmulatorViewController 获取当前 renderer
        // 实际项目中可通过 NotificationCenter 或弱引用传递
        return nil  // 由 EmulatorViewController 在 delegate 回调中处理
    }
}

// MARK: - 外部显示 ViewController（纯黑背景 + MTKView）

final class ExternalDisplayViewController: UIViewController {

    private let mtkView: MTKView

    init(mtkView: MTKView) {
        self.mtkView = mtkView
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: view.topAnchor),
            mtkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mtkView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

// MARK: - MetalRenderer 扩展：支持外部显示切换

extension MetalRenderer {

    /// 将渲染输出切换到外部 MTKView
    func attachToExternalView(_ view: MTKView) {
        view.device = self.device
        view.delegate = self
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        // 暂停内部 mtkView 的渲染（避免双重渲染）
        self.mtkView?.isPaused = true
    }

    /// 恢复渲染到手机屏幕
    func detachFromExternalView() {
        self.mtkView?.isPaused = false
    }

    // 暴露 device 和 mtkView 给扩展使用
    var device: MTLDevice { _device }
    var mtkView: MTKView? { _mtkView }
}

// MARK: - Notification

extension Notification.Name {
    static let externalDisplayDidConnect    = Notification.Name("externalDisplayDidConnect")
    static let externalDisplayDidDisconnect = Notification.Name("externalDisplayDidDisconnect")
}
