// EmulatorViewController.swift
// 游戏运行界面：Metal 渲染 + 虚拟手柄 + 网络多人

import UIKit
import MetalKit
import Photos  // F2: 截图保存到相册

final class EmulatorViewController: UIViewController {

    private let rom: ROMInfo
    private let networkMode: NetworkMode
    /// 来自「时光」时间轴的待恢复存档
    private let pendingState: Data?

    private var mtkView: MTKView!
    private var renderer: MetalRenderer!
    private let gamepadView = GamepadView()

    // 悬浮工具条
    private let toolbar = UIView()
    private let backButton = RTGlassButton(symbol: "chevron.left", pointSize: 14)
    private let captureButton = RTGlassButton(symbol: "camera", pointSize: 14)
    private let fastForwardButton = RTGlassButton(symbol: "forward.fill", pointSize: 13)
    private let menuButton = RTGlassButton(symbol: "slider.horizontal.3", pointSize: 14)
    private let romPlaque = UILabel()
    private var isChromeVisible = true

    private let latencyLabel = UILabel()

    init(rom: ROMInfo, networkMode: NetworkMode = .none, pendingState: Data? = nil) {
        self.rom = rom
        self.networkMode = networkMode
        self.pendingState = pendingState
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetal()
        setupGamepad()
        setupToolbar()
        setupLatencyLabel()
        setupEmulator()
        setupNetwork()
        setupGamepadManager()   // F5: 外接手柄
        setupAirPlay()          // F4: AirPlay 投屏
        setupAchievements()     // F7: 成就系统
        setupSwipeGestures()    // F10: 快捷手势
        // 初始布局
        view.layoutIfNeeded()
        updateLayoutForCurrentOrientation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        RewindManager.shared.endRewind()   // F9: 确保倒带停止
        EmulatorCore.shared.stop()
        AudioEngine.shared.stop()
        NetworkManager.shared.disconnect()
        GameStatsManager.shared.endSession()
        AchievementManager.shared.stopPolling()  // TD-4
        navigationController?.setNavigationBarHidden(false, animated: false)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.updateLayoutForCurrentOrientation()
        })
    }

    private var isPortrait: Bool {
        view.bounds.height > view.bounds.width
    }

#if DEBUG
    /// 截图取证用：模拟器上的外接键盘有时会被判成控制器，手柄因此被自动隐藏。
    func forceShowVirtualPad() {
        gamepadView.setVirtualPadHidden(false)
        gamepadView.setNeedsLayout()
    }
#endif

    private func updateLayoutForCurrentOrientation() {
        updateAspectRatio()
        gamepadView.updateOrientation(portrait: isPortrait)
        updateMTKViewFrame()
    }

    private func updateMTKViewFrame() {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        let portrait = isPortrait
        let layout = ScreenLayoutSettings.shared.load(for: system, portrait: portrait)

        let screenW = view.bounds.width
        let screenH = view.bounds.height

        // 基础可用区域
        let baseW = screenW
        let baseH = portrait ? screenH * 0.45 : screenH

        // 按宽高比计算默认尺寸，再乘以用户 scale
        let (gameW, gameH) = gameNativeSize(system)
        let ar = gameW / gameH
        let fitW: CGFloat, fitH: CGFloat
        if baseW / baseH > ar {
            fitH = baseH; fitW = fitH * ar
        } else {
            fitW = baseW; fitH = fitW / ar
        }
        let finalW = fitW * layout.scale
        let finalH = fitH * layout.scale

        // 中心点 + 偏移
        let cx = screenW / 2 + layout.offsetX * screenW
        let cy = (portrait ? baseH / 2 : screenH / 2) + layout.offsetY * screenH

        mtkView.frame = CGRect(
            x: cx - finalW / 2,
            y: cy - finalH / 2,
            width: finalW,
            height: finalH
        )
    }

    private func gameNativeSize(_ system: EmulatorSystem) -> (CGFloat, CGFloat) {
        let size = system.nativeSize
        return (size.width, size.height)
    }

    // MARK: - 画面调整模式
    private var isAdjustingScreen = false
    private var adjustHint: UILabel?

    // 手势状态
    private var pinchBaseScale: CGFloat = 1.0
    private var panBaseOffset: CGPoint = .zero

    func enterScreenAdjustMode() {
        guard !isAdjustingScreen else { return }
        isAdjustingScreen = true

        let hint = UILabel()
        hint.text = L10n.str("emu.screenadjust.hint")
        hint.textColor = .white
        hint.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        hint.font = .systemFont(ofSize: 13)
        hint.textAlignment = .center
        hint.layer.cornerRadius = 8
        hint.clipsToBounds = true
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            hint.heightAnchor.constraint(equalToConstant: 32),
            hint.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
        adjustHint = hint

        // 高亮边框
        mtkView.layer.borderColor = UIColor.systemYellow.cgColor
        mtkView.layer.borderWidth = 2

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleScreenPinch(_:)))
        let pan   = UIPanGestureRecognizer(target: self, action: #selector(handleScreenPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let tap   = UITapGestureRecognizer(target: self, action: #selector(handleScreenDoubleTap(_:)))
        tap.numberOfTapsRequired = 2

        [pinch, pan, tap].forEach {
            $0.delegate = self
            view.addGestureRecognizer($0)
        }
    }

    func exitScreenAdjustMode() {
        guard isAdjustingScreen else { return }
        isAdjustingScreen = false
        adjustHint?.removeFromSuperview()
        adjustHint = nil
        mtkView.layer.borderWidth = 0

        // 保存当前布局
        saveCurrentScreenLayout()

        // 移除调整手势（保留其他手势）
        view.gestureRecognizers?
            .filter { $0 is UIPinchGestureRecognizer ||
                     ($0 is UIPanGestureRecognizer && ($0 as! UIPanGestureRecognizer).minimumNumberOfTouches == 2) ||
                     ($0 is UITapGestureRecognizer && ($0 as! UITapGestureRecognizer).numberOfTapsRequired == 2) }
            .forEach { view.removeGestureRecognizer($0) }
    }

    private func saveCurrentScreenLayout() {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        let portrait = isPortrait
        let screenW = view.bounds.width
        let screenH = view.bounds.height
        let baseH = portrait ? screenH * 0.45 : screenH

        // 反推 scale 和 offset
        let (gameW, gameH) = gameNativeSize(system)
        let ar = gameW / gameH
        let baseW = screenW
        let fitW: CGFloat, fitH: CGFloat
        if baseW / baseH > ar {
            fitH = baseH; fitW = fitH * ar
        } else {
            fitW = baseW; fitH = fitW / ar
        }
        let scale = mtkView.bounds.width / fitW
        let baseCY = portrait ? baseH / 2 : screenH / 2
        let offsetX = (mtkView.center.x - screenW / 2) / screenW
        let offsetY = (mtkView.center.y - baseCY) / screenH

        ScreenLayoutSettings.shared.save(
            .init(scale: scale, offsetX: offsetX, offsetY: offsetY),
            for: system, portrait: portrait
        )
    }

    @objc private func handleScreenPinch(_ gr: UIPinchGestureRecognizer) {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        let portrait = isPortrait
        switch gr.state {
        case .began:
            pinchBaseScale = ScreenLayoutSettings.shared.load(for: system, portrait: portrait).scale
        case .changed:
            let newScale = max(0.3, min(3.0, pinchBaseScale * gr.scale))
            var layout = ScreenLayoutSettings.shared.load(for: system, portrait: portrait)
            layout.scale = newScale
            ScreenLayoutSettings.shared.save(layout, for: system, portrait: portrait)
            updateMTKViewFrame()
        default: break
        }
    }

    @objc private func handleScreenPan(_ gr: UIPanGestureRecognizer) {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        let portrait = isPortrait
        switch gr.state {
        case .began:
            let l = ScreenLayoutSettings.shared.load(for: system, portrait: portrait)
            panBaseOffset = CGPoint(x: l.offsetX, y: l.offsetY)
        case .changed:
            let t = gr.translation(in: view)
            var layout = ScreenLayoutSettings.shared.load(for: system, portrait: portrait)
            layout.offsetX = panBaseOffset.x + t.x / view.bounds.width
            layout.offsetY = panBaseOffset.y + t.y / view.bounds.height
            ScreenLayoutSettings.shared.save(layout, for: system, portrait: portrait)
            updateMTKViewFrame()
        default: break
        }
    }

    @objc private func handleScreenDoubleTap(_ gr: UITapGestureRecognizer) {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        ScreenLayoutSettings.shared.reset(for: system, portrait: isPortrait)
        UIView.animate(withDuration: 0.25) { self.updateMTKViewFrame() }
        showToast(L10n.str("emu.toast.resetscreen"), icon: "arrow.counterclockwise")
    }

    // MARK: - Setup
    private func setupMetal() {
        mtkView = MTKView(frame: view.bounds)
        mtkView.autoresizingMask = []
        mtkView.contentScaleFactor = UIScreen.main.scale
        view.addSubview(mtkView)

        if let r = MetalRenderer(mtkView: mtkView) {
            // 正常 Metal 路径
            renderer = r
            updateAspectRatio()
        } else {
            // TD-3: Metal 不可用，降级到软件渲染
            mtkView.isHidden = true
            setupSoftwareRenderer()
            showToast(L10n.str("emu.toast.softwarefallback"), icon: "exclamationmark.triangle")
        }
    }

    // MARK: - TD-3: 软件渲染降级

    /// Metal 不可用时使用 UIImageView 显示帧缓冲
    private var softwareRenderView: UIImageView?

    private func setupSoftwareRenderer() {
        let imgView = UIImageView(frame: view.bounds)
        imgView.autoresizingMask = []
        imgView.contentMode = .scaleAspectFit
        imgView.backgroundColor = .black
        view.addSubview(imgView)
        softwareRenderView = imgView

        // 软件渲染：每帧将 frameBuffer 转为 UIImage
        EmulatorCore.shared.onFrameReady = { [weak self] buffer, width, height in
            guard let self = self else { return }
            if let cgImg = EmulatorCore.shared.frameBufferToImage(buffer, width: width, height: height) {
                DispatchQueue.main.async {
                    self.softwareRenderView?.image = UIImage(cgImage: cgImg)
                }
            }
        }
    }

    private func updateAspectRatio() {
        guard let system = EmulatorCore.shared.currentSystem else { return }
        let (w, h) = gameNativeSize(system)
        renderer?.setAspectRatio(width: w, height: h)
    }

    private func setupGamepad() {
        gamepadView.translatesAutoresizingMaskIntoConstraints = false
        gamepadView.delegate = self
        // 读取方向键样式设置
        let styleRaw = UserDefaults.standard.string(forKey: "dpad_style") ?? ""
        gamepadView.dpadStyle = DPadStyle(rawValue: styleRaw) ?? .dpad
        // 按平台决定面键数量（8/16 位机只用 A/B）
        gamepadView.configure(for: rom.system)
        view.addSubview(gamepadView)
        NSLayoutConstraint.activate([
            gamepadView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gamepadView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gamepadView.topAnchor.constraint(equalTo: view.topAnchor),
            gamepadView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - 悬浮工具条

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        view.addSubview(toolbar)

        let plaqueText = "\(rom.system.shortCode)  ·  \(rom.name)"
        romPlaque.attributedText = NSAttributedString(
            string: plaqueText,
            attributes: [.font: RT.Font.mono(10, weight: .semibold),
                         .foregroundColor: UIColor(white: 1, alpha: 0.9),
                         .kern: 1.2]
        )
        romPlaque.backgroundColor = UIColor(white: 0, alpha: 0.42)
        romPlaque.layer.cornerRadius = 15
        romPlaque.layer.cornerCurve = .continuous
        romPlaque.layer.borderWidth = 1
        romPlaque.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        romPlaque.clipsToBounds = true
        romPlaque.textAlignment = .center

        backButton.addTarget(self, action: #selector(exitGame), for: .touchUpInside)
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        fastForwardButton.addTarget(self, action: #selector(toggleFastForward), for: .touchUpInside)
        menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)

        let rightStack = UIStackView(arrangedSubviews: [captureButton, fastForwardButton, menuButton])
        rightStack.axis = .horizontal
        rightStack.spacing = 8
        rightStack.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubviews(backButton, romPlaque, rightStack)
        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            backButton.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),

            romPlaque.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 10),
            romPlaque.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            romPlaque.heightAnchor.constraint(equalToConstant: 30),
            romPlaque.trailingAnchor.constraint(lessThanOrEqualTo: rightStack.leadingAnchor, constant: -10),

            rightStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -14),
            rightStack.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
        ])

        // 轻点画面可隐藏 / 唤回工具条（沉浸模式）
        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        mtkView.addGestureRecognizer(tap)

        updateFastForwardAppearance()
    }

    @objc private func toggleChrome() {
        setChromeVisible(!isChromeVisible, animated: true)
    }

    private func setChromeVisible(_ visible: Bool, animated: Bool) {
        guard isChromeVisible != visible else { return }
        isChromeVisible = visible
        let changes = {
            self.toolbar.alpha = visible ? 1 : 0
            self.toolbar.transform = visible ? .identity : CGAffineTransform(translationX: 0, y: -12)
        }
        if animated {
            UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseInOut], animations: changes)
        } else {
            changes()
        }
    }

    @objc private func exitGame() {
        dismiss(animated: true)
    }

    @objc private func captureTapped() {
        takeScreenshot()
    }

    @objc private func toggleFastForward() {
        let next = EmulatorCore.shared.fastForwardMultiplier > 1 ? 1 : 4
        EmulatorCore.shared.fastForwardMultiplier = next
        updateFastForwardAppearance()
        RT.haptic()
        showToast(next > 1 ? L10n.str("emu.toast.fastforward", next) : L10n.str("emu.toast.normalspeed"),
                  icon: "forward.fill")
    }

    private func updateFastForwardAppearance() {
        let active = EmulatorCore.shared.fastForwardMultiplier > 1
        fastForwardButton.tintColor = active ? RT.accent : UIColor(white: 1, alpha: 0.92)
        fastForwardButton.backgroundColor = active
            ? RT.accent.withAlphaComponent(0.28)
            : UIColor(white: 0, alpha: 0.42)
    }

    private func setupLatencyLabel() {
        latencyLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        latencyLabel.textColor = .white.withAlphaComponent(0.6)
        latencyLabel.translatesAutoresizingMaskIntoConstraints = false
        latencyLabel.isHidden = networkMode == .none
        view.addSubview(latencyLabel)
        NSLayoutConstraint.activate([
            latencyLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            latencyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
        ])
    }

    private func setupEmulator() {
        EmuLog.info("🎮 setupEmulator: \(rom.name)  系统: \(rom.system.rawValue)  路径: \(rom.url.path)")

        // PSP：提前创建 CAMetalLayer，存入 PSPMetalLayerProvider
        // PSPBridgeWrapper 在 loadROM 时会从这里取
        if rom.system == .psp {
            let metalLayer = CAMetalLayer()
            metalLayer.frame = view.bounds
            metalLayer.contentsScale = UIScreen.main.scale
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
            view.layer.insertSublayer(metalLayer, at: 0)
            PSPMetalLayerProvider.shared.layer = metalLayer
        }

        do {
            try EmulatorCore.shared.loadROM(from: rom.url)
        } catch {
            EmuLog.error("❌ loadROM 抛出异常: \(error.localizedDescription)")
            showError(error.localizedDescription)
            return
        }

        // 按核心实际输出格式配置音频引擎（采样率/声道对不上会变调）
        let audioRate = EmulatorCore.shared.audioSampleRate
        let audioChannels = EmulatorCore.shared.audioChannels
        EmuLog.info("🔊 音频格式: \(audioRate)Hz  声道=\(audioChannels)")
        AudioEngine.shared.setup(sampleRate: Double(audioRate), channels: audioChannels)
        // 恢复上次音量设置
        AudioEngine.shared.volume = UserDefaults.standard.float(forKey: "audio_volume").nonZero ?? 1.0

        // PSP Vulkan 模式：PPSSPP 直接渲染到 metalLayer，隐藏 MTKView
        if rom.system == .psp {
            mtkView.isHidden = true
        }

        EmulatorCore.shared.onFrameReady = { [weak self] buffer, width, height in
            self?.renderer?.updateFrame(buffer, width: width, height: height)
        }

        EmulatorCore.shared.onAudioReady = { samples, count in
            AudioEngine.shared.pushSamples(samples, count: count)
        }

        // 陀螺仪输入（GBA 专用）
        gamepadView.onGyroInput = { [weak self] tiltX, _ in
            guard self?.rom.system == .gba else { return }
            // GBA 陀螺仪：映射到方向键（简化实现）
            var extra: EmulatorButton = []
            if tiltX < -0.4 { extra.insert(.left) }
            if tiltX >  0.4 { extra.insert(.right) }
            if !extra.isEmpty {
                EmulatorCore.shared.setButtons(extra, player: 0)
            }
        }

        EmulatorCore.shared.start()
        EmuLog.info("✅ 模拟器已启动，renderer=\(renderer == nil ? "nil(软件渲染)" : "Metal")")
        GameStatsManager.shared.beginSession(romName: rom.name)

        // 从「时光」时间轴进入：启动后恢复到选中存档
        if let state = pendingState {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
                guard let self = self else { return }
                _ = EmulatorCore.shared.bridge?.loadState(state)
                self.showToast(L10n.str("emu.toast.staterestored"), icon: "clock.arrow.circlepath")
            }
        }

        // 恢复上次滤镜设置
        let savedFilter = RenderFilter(rawValue: UserDefaults.standard.integer(forKey: "render_filter")) ?? .nearest
        renderer?.filter = savedFilter
    }

    private func setupNetwork() {
        guard networkMode != .none else { return }
        NetworkManager.shared.delegate = self
        if networkMode == .host {
            NetworkManager.shared.sendStartGame(romName: rom.name)
        }
    }

    // MARK: - F5: 外接手柄管理器

    private func setupGamepadManager() {
        GamepadManager.shared.delegate = self
        // 如果已有手柄连接，隐藏虚拟手柄
        if GamepadManager.shared.hasConnectedController {
            gamepadView.setVirtualPadHidden(true)
        }
    }

    // MARK: - F10: 快捷手势（双指滑动）

    private func setupSwipeGestures() {
        guard UserDefaults.standard.bool(forKey: "swipe_gestures_enabled") != false else { return }

        let directions: [(UISwipeGestureRecognizer.Direction, Selector)] = [
            (.up,    #selector(handleSwipeUp)),
            (.down,  #selector(handleSwipeDown)),
            (.left,  #selector(handleSwipeLeft)),
            (.right, #selector(handleSwipeRight)),
        ]
        for (_, sel) in directions {
            let gr = UISwipeGestureRecognizer(target: self, action: sel)
            gr.numberOfTouchesRequired = 2
            gr.delegate = self
            view.addGestureRecognizer(gr)
        }
    }

    @objc private func handleSwipeUp() {
        EmulatorCore.shared.saveState(slot: 0)
        showToast(L10n.str("emu.toast.quicksaved"), icon: "square.and.arrow.down")
    }

    @objc private func handleSwipeDown() {
        EmulatorCore.shared.loadState(slot: 0)
        showToast(L10n.str("emu.toast.quickloaded"), icon: "square.and.arrow.up")
    }

    @objc private func handleSwipeLeft() {
        let next = EmulatorCore.shared.fastForwardMultiplier > 1 ? 1 : 4
        EmulatorCore.shared.fastForwardMultiplier = next
        showToast(next > 1 ? L10n.str("emu.toast.fastforward", next) : L10n.str("emu.toast.normalspeed"),
                  icon: "forward.fill")
    }

    @objc private func handleSwipeRight() {
        takeScreenshot()
    }

    // MARK: - F4: AirPlay 投屏

    private func setupAirPlay() {
        ExternalDisplayManager.shared.delegate = self
        // 检查是否已有外部屏幕连接
        if let screen = UIScreen.screens.first(where: { $0 != UIScreen.main }) {
            ExternalDisplayManager.shared.setupExternalDisplay(screen: screen)
        }
    }

    // MARK: - F7: 成就系统

    private func setupAchievements() {
        guard AchievementManager.shared.isLoggedIn else { return }
        AchievementManager.shared.onAchievementUnlocked = { [weak self] achievement in
            guard let self = self else { return }
            AchievementOverlayView.show(achievement: achievement, in: self.view)
        }
        // TD-4: 启动服务器轮询
        AchievementManager.shared.startPolling()
    }

    // MARK: - F2: 截图

    func takeScreenshot() {
        guard let cgImage = EmulatorCore.shared.captureScreenshot() else {
            showToast(L10n.str("emu.toast.capturefailed"), icon: "camera")
            return
        }
        let image = UIImage(cgImage: cgImage)

        // 保存到相册
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self = self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.showToast(L10n.str("emu.toast.needphotolib"), icon: "photo.on.rectangle")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetChangeRequest.creationRequestForAsset(from: image)
                _ = req.placeholderForCreatedAsset
            }) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        // 同时弹出分享菜单
                        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                        if let pop = vc.popoverPresentationController { pop.sourceView = self.menuButton }
                        self.present(vc, animated: true)
                        self.showToast(L10n.str("emu.toast.capturesaved"), icon: "photo.badge.checkmark")
                    } else {
                        self.showToast(L10n.str("emu.toast.capturesavefailed"), icon: "camera")
                    }
                }
            }
        }
    }

    // MARK: - Menu

    @objc private func showMenu() {
        exitScreenAdjustMode()
        setChromeVisible(true, animated: true)
        EmulatorCore.shared.pause()

        let isFav = GameStatsManager.shared.isFavorite(rom.name)
        let ffMult = EmulatorCore.shared.fastForwardMultiplier
        let autoCount = SaveStateManager.shared.autoSaveEntries(romName: rom.name).count

        var actions: [RTMenuAction] = [
            RTMenuAction(title: L10n.str("emu.menu.save"),
                         subtitle: L10n.str("emu.menu.save.hint"),
                         icon: "square.and.arrow.down",
                         handler: { [weak self] in self?.presentSavePicker(.save) }),
            RTMenuAction(title: L10n.str("emu.menu.load"),
                         subtitle: L10n.str("emu.menu.load.hint"),
                         icon: "square.and.arrow.up.on.square",
                         handler: { [weak self] in self?.presentSavePicker(.load) }),
            RTMenuAction(title: L10n.str("emu.menu.autosave"),
                         subtitle: L10n.str("emu.menu.autosave.hint", autoCount),
                         icon: "clock.arrow.circlepath",
                         handler: { [weak self] in self?.presentSavePicker(.autoLoad) }),
            RTMenuAction(title: L10n.str("emu.menu.fastforward"),
                         subtitle: ffMult > 1
                            ? L10n.str("emu.menu.fastforward.active", ffMult)
                            : L10n.str("emu.menu.fastforward.off"),
                         icon: "forward.fill",
                         handler: { [weak self] in self?.showFastForwardMenu() }),
            RTMenuAction(title: L10n.str("emu.menu.turbo"),
                         subtitle: L10n.str("emu.menu.turbo.hint"),
                         icon: "bolt.horizontal",
                         handler: { [weak self] in self?.showTurboMenu() }),
            RTMenuAction(title: L10n.str("emu.menu.screenshot"),
                         icon: "camera",
                         handler: { [weak self] in self?.takeScreenshot() }),
            RTMenuAction(title: isFav ? L10n.str("emu.menu.unfavorite") : L10n.str("emu.menu.favorite"),
                         icon: isFav ? "star.slash" : "star",
                         handler: { [weak self] in
                guard let self = self else { return }
                GameStatsManager.shared.toggleFavorite(romName: self.rom.name)
                RTToast.show(GameStatsManager.shared.isFavorite(self.rom.name)
                                ? L10n.str("emu.toast.favorited")
                                : L10n.str("emu.toast.unfavorited"),
                             icon: "star", in: self.view)
            }),
            RTMenuAction(title: L10n.str("emu.menu.filter"),
                         subtitle: (renderer?.filter ?? .nearest).displayName,
                         icon: "camera.filters",
                         handler: { [weak self] in self?.showFilterMenu() }),
            RTMenuAction(title: L10n.str("emu.menu.cheat"),
                         icon: "wand.and.rays",
                         handler: { [weak self] in self?.showCheat() }),
        ]

        if rom.system == .gba {
            let gyro = gamepadView.isGyroEnabled
            actions.append(RTMenuAction(title: gyro ? L10n.str("emu.menu.gyro.on") : L10n.str("emu.menu.gyro.off"),
                                        icon: "gyroscope",
                                        handler: { [weak self] in
                guard let self = self else { return }
                self.gamepadView.enableGyro(!gyro)
                EmulatorCore.shared.start()
                RTToast.show(self.gamepadView.isGyroEnabled
                                ? L10n.str("emu.toast.gyro.on")
                                : L10n.str("emu.toast.gyro.off"),
                             icon: "gyroscope", in: self.view)
            }))
        }

        if AchievementManager.shared.isLoggedIn {
            actions.append(RTMenuAction(title: L10n.str("emu.menu.achievements"),
                                        icon: "trophy",
                                        handler: { [weak self] in
                let nav = UINavigationController(rootViewController: AchievementListViewController())
                nav.modalPresentationStyle = .pageSheet
                self?.present(nav, animated: true)
            }))
        }

        let recording = MacroManager.shared.isRecording
        actions.append(RTMenuAction(title: recording ? L10n.str("emu.menu.macro.stop")
                                                    : L10n.str("emu.menu.macro.record"),
                                    subtitle: L10n.str("emu.menu.macro.hint"),
                                    icon: recording ? "stop.circle" : "record.circle",
                                    destructive: false,
                                    handler: { [weak self] in
            if MacroManager.shared.isRecording {
                self?.stopMacroRecording()
            } else {
                MacroManager.shared.startRecording()
                EmulatorCore.shared.start()
                RTToast.show(L10n.str("emu.toast.macro.recording"), icon: "record.circle", in: self?.view)
            }
        }))

        if !MacroManager.shared.macros.isEmpty {
            actions.append(RTMenuAction(title: L10n.str("emu.menu.macro.play"),
                                        icon: "play.circle",
                                        handler: { [weak self] in self?.showMacroPlaybackMenu() }))
        }

        actions.append(contentsOf: [
            RTMenuAction(title: L10n.str("emu.menu.editpad"),
                         icon: "hand.tap",
                         handler: { [weak self] in
                EmulatorCore.shared.start()
                self?.gamepadView.enterEditMode()
            }),
            RTMenuAction(title: L10n.str("emu.menu.adjustscreen"),
                         icon: "arrow.up.left.and.arrow.down.right",
                         handler: { [weak self] in
                EmulatorCore.shared.start()
                self?.enterScreenAdjustMode()
                RTToast.show(L10n.str("emu.toast.screenadjust"), icon: "hand.draw", in: self?.view)
            }),
            RTMenuAction(title: L10n.str("emu.menu.reset"),
                         icon: "arrow.counterclockwise",
                         destructive: true,
                         handler: {
                EmulatorCore.shared.reset()
                EmulatorCore.shared.start()
            }),
            RTMenuAction(title: L10n.str("emu.menu.resume"),
                         icon: "play.fill",
                         handler: { EmulatorCore.shared.start() }),
            RTMenuAction(title: L10n.str("emu.menu.quit"),
                         icon: "xmark",
                         destructive: true,
                         handler: { [weak self] in self?.dismiss(animated: true) }),
        ])

        RTMenuSheetViewController.present(from: self,
                                          title: rom.name,
                                          message: "\(rom.system.displayName) · \(L10n.str("emu.menu.message"))",
                                          actions: actions,
                                          onDismiss: { EmulatorCore.shared.start() })
    }

    private func presentSavePicker(_ mode: SaveStatePickerMode) {
        let vc = SaveStatePickerViewController(romName: rom.name, mode: mode)
        vc.onComplete = { [weak self] in
            RTToast.show(L10n.str("emu.toast.saved"), icon: "checkmark", in: self?.view)
        }
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = mode == .autoLoad ? [.large()] : [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(nav, animated: true)
    }

    private func showCheat() {
        let vc = CheatViewController(romName: rom.name)
        let nav = UINavigationController(rootViewController: vc)
        nav.presentationController?.delegate = self
        present(nav, animated: true)
    }

    // MARK: - Turbo 菜单
    private func showTurboMenu() {
        let slots: [(String, GamepadSlot)] = [
            ("A", .btnA), ("B", .btnB), ("X", .btnX), ("Y", .btnY)
        ]
        var actions: [RTMenuAction] = slots.map { title, slot in
            let on = gamepadView.isTurboEnabled(for: slot)
            return RTMenuAction(title: L10n.str("emu.turbo.toggle", title),
                                subtitle: on ? L10n.str("emu.turbo.on") : L10n.str("emu.turbo.off"),
                                icon: "bolt.fill",
                                selected: on,
                                handler: { [weak self] in
                self?.gamepadView.toggleTurbo(for: slot)
                EmulatorCore.shared.start()
                self?.showToast(L10n.str("emu.toast.turbo", title), icon: "bolt.fill")
            })
        }
        actions.append(RTMenuAction(title: L10n.str("btn.done"),
                                    icon: "checkmark",
                                    handler: { EmulatorCore.shared.start() }))
        RTMenuSheetViewController.present(from: self,
                                          title: L10n.str("emu.turbo.title"),
                                          message: L10n.str("emu.turbo.message"),
                                          actions: actions)
    }

    // MARK: - 快进菜单
    private func showFastForwardMenu() {
        let current = EmulatorCore.shared.fastForwardMultiplier
        let options: [(String, Int)] = [
            (L10n.str("emu.fastforward.1x"), 1),
            (L10n.str("emu.fastforward.2x"), 2),
            (L10n.str("emu.fastforward.4x"), 4),
            (L10n.str("emu.fastforward.8x"), 8)
        ]
        let actions: [RTMenuAction] = options.map { title, mult in
            RTMenuAction(title: title,
                         icon: "forward.fill",
                         selected: current == mult,
                         handler: { [weak self] in
                EmulatorCore.shared.fastForwardMultiplier = mult
                self?.updateFastForwardAppearance()
                EmulatorCore.shared.start()
                if mult > 1 {
                    self?.showToast(L10n.str("emu.toast.fastforward", mult), icon: "forward.fill")
                }
            })
        }
        RTMenuSheetViewController.present(from: self,
                                          title: L10n.str("emu.fastforward.title"),
                                          message: L10n.str("emu.fastforward.message"),
                                          actions: actions,
                                          onDismiss: { EmulatorCore.shared.start() })
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    private func showToast(_ msg: String, icon: String = "checkmark") {
        RTToast.show(msg, icon: icon, in: view, position: .top)
    }

    private func showFilterMenu() {
        let current = renderer?.filter ?? .nearest
        let actions: [RTMenuAction] = RenderFilter.allCases.map { f in
            RTMenuAction(title: f.displayName,
                         icon: "camera.filters",
                         selected: f == current,
                         handler: { [weak self] in
                self?.renderer?.filter = f
                UserDefaults.standard.set(f.rawValue, forKey: "render_filter")
                EmulatorCore.shared.start()
            })
        }
        RTMenuSheetViewController.present(from: self,
                                          title: L10n.str("emu.filter.title"),
                                          actions: actions,
                                          onDismiss: { EmulatorCore.shared.start() })
    }

    private func showError(_ msg: String) {
        let alert = UIAlertController(title: L10n.str("emu.error.title"), message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L10n.str("emu.error.back"), style: .default) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate（KeymapVC 关闭时刷新）
extension EmulatorViewController: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        gamepadView.refreshLabels()
        EmulatorCore.shared.start()
    }
}

// MARK: - GamepadViewDelegate
extension EmulatorViewController: GamepadViewDelegate {
    func gamepadView(_ view: GamepadView, buttonsChanged buttons: EmulatorButton) {
        // 本地输入
        EmulatorCore.shared.setButtons(buttons, player: NetworkManager.shared.localPlayerIndex)
        // 网络同步
        if NetworkManager.shared.isConnected {
            NetworkManager.shared.sendInput(buttons: buttons.rawValue)
        }
    }
}

// MARK: - NetworkManagerDelegate
extension EmulatorViewController: NetworkManagerDelegate {
    func networkManager(_ manager: NetworkManager, didReceiveInput buttons: UInt16, playerIndex: Int, frame: UInt64) {
        let remoteIndex = playerIndex == 0 ? 1 : 0
        EmulatorCore.shared.setButtons(EmulatorButton(rawValue: buttons), player: remoteIndex)
    }

    func networkManager(_ manager: NetworkManager, didConnectPlayer player: NetworkPlayer) {
        latencyLabel.text = L10n.str("emu.network.p2connected", player.name)
    }

    func networkManager(_ manager: NetworkManager, didDisconnectPlayer playerID: String) {
        latencyLabel.text = L10n.str("emu.network.disconnected")
        // 清除 P2 输入
        EmulatorCore.shared.setButtons([], player: 1)
    }

    func networkManager(_ manager: NetworkManager, didReceiveStartGame romName: String) {
        // 客户端收到主机发来的游戏启动信号，ROM 已由主机选定，此处无需额外操作
        // EmulatorCore 已在 setupEmulator() 中加载了本地同名 ROM
    }

    func networkManager(_ manager: NetworkManager, latencyUpdated ms: Double) {
        latencyLabel.text = L10n.str("emu.network.latency", Int(ms))
    }
}

// MARK: - UIGestureRecognizerDelegate
extension EmulatorViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // 画面调整模式：捏合和双指拖动可以同时识别
        if isAdjustingScreen { return true }
        // 快捷手势（双指滑动）与虚拟手柄触摸不冲突
        if gr is UISwipeGestureRecognizer || other is UISwipeGestureRecognizer { return false }
        return false
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
        // 双指滑动优先于单指操作
        if gr is UISwipeGestureRecognizer && !(other is UISwipeGestureRecognizer) { return false }
        return false
    }
}

// MARK: - F5: GamepadManagerDelegate（外接手柄）
extension EmulatorViewController: GamepadManagerDelegate {

    func gamepadManager(_ manager: GamepadManager, didUpdateButtons buttons: EmulatorButton, playerIndex: Int) {
        EmulatorCore.shared.setButtons(buttons, player: playerIndex)
        if NetworkManager.shared.isConnected && playerIndex == NetworkManager.shared.localPlayerIndex {
            NetworkManager.shared.sendInput(buttons: buttons.rawValue)
        }
    }

    func gamepadManager(_ manager: GamepadManager, controllerDidConnect name: String, playerIndex: Int) {
        showToast(L10n.str("emu.toast.padconnected", name, playerIndex + 1), icon: "gamecontroller")
        // 有外接手柄时隐藏虚拟手柄
        gamepadView.setVirtualPadHidden(true)
    }

    func gamepadManager(_ manager: GamepadManager, controllerDidDisconnect name: String) {
        showToast(L10n.str("emu.toast.paddisconnected", name), icon: "gamecontroller")
        // 没有手柄时恢复虚拟手柄
        if !GamepadManager.shared.hasConnectedController {
            gamepadView.setVirtualPadHidden(false)
        }
    }
}

// MARK: - F4: ExternalDisplayManagerDelegate（AirPlay 投屏）
extension EmulatorViewController: ExternalDisplayManagerDelegate {

    func externalDisplayDidConnect(_ manager: ExternalDisplayManager) {
        // 切换到控制器模式：隐藏游戏画面，只显示虚拟手柄
        UIView.animate(withDuration: 0.3) {
            self.mtkView.alpha = 0
        }
        showToast(L10n.str("emu.toast.externalconnected"), icon: "airplayvideo")
        // 将 renderer 输出切换到外部屏幕
        if let externalView = manager.externalWindow?.rootViewController?.view.subviews
            .compactMap({ $0 as? MTKView }).first {
            renderer?.attachToExternalView(externalView)
        }
    }

    func externalDisplayDidDisconnect(_ manager: ExternalDisplayManager) {
        // 恢复手机全屏模式
        renderer?.detachFromExternalView()
        UIView.animate(withDuration: 0.3) {
            self.mtkView.alpha = 1
        }
        showToast(L10n.str("emu.toast.externaldisconnected"), icon: "iphone")
    }
}

// MARK: - F8: 快捷键处理（由 GamepadView 触发）
extension EmulatorViewController {
    /// GamepadView 在检测到快捷键槽位按下时调用此方法
    func handleShortcutActions(_ actions: [ShortcutAction]) {
        for action in actions {
            switch action {
            case .screenshot:
                takeScreenshot()
            case .toggleFastForward:
                let next = EmulatorCore.shared.fastForwardMultiplier > 1 ? 1 : 4
                EmulatorCore.shared.fastForwardMultiplier = next
                updateFastForwardAppearance()
                showToast(next > 1 ? L10n.str("emu.toast.fastforward", next) : L10n.str("emu.toast.normalspeed"),
                          icon: "forward.fill")
            case .quickSave:
                EmulatorCore.shared.saveState(slot: 0)
                showToast(L10n.str("emu.toast.quicksaved"), icon: "square.and.arrow.down")
            case .quickLoad:
                EmulatorCore.shared.loadState(slot: 0)
                showToast(L10n.str("emu.toast.quickloaded"), icon: "square.and.arrow.up")
            case .openMenu:
                showMenu()
            case .rewind:
                // 倒带是"按住"触发，此处仅作为开始信号
                if !RewindManager.shared.isRewinding {
                    RewindManager.shared.beginRewind()
                    showToast(L10n.str("emu.toast.rewinding"), icon: "backward.fill")
                }
            }
        }
    }

    /// 快捷键槽位松开时调用（结束倒带）
    func handleShortcutReleased(_ actions: [ShortcutAction]) {
        if actions.contains(.rewind) && RewindManager.shared.isRewinding {
            RewindManager.shared.endRewind()
            EmulatorCore.shared.start()
        }
    }
}

// MARK: - F14: 宏录制
extension EmulatorViewController {

    private func stopMacroRecording() {
        let alert = UIAlertController(title: L10n.str("emu.macro.savetitle"),
                                      message: L10n.str("emu.macro.savedesc"),
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = L10n.str("emu.macro.nameph")
            tf.text = L10n.str("emu.macro.defaultname", MacroManager.shared.macros.count + 1)
        }
        alert.addAction(UIAlertAction(title: L10n.str("btn.save"), style: .default) { [weak self, weak alert] _ in
            let raw = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespaces) ?? ""
            let name = raw.isEmpty ? L10n.str("emu.macro.unnamed") : raw
            if let macro = MacroManager.shared.stopRecording(name: name) {
                EmulatorCore.shared.start()
                self?.showToast(L10n.str("emu.toast.macrosaved",
                                        macro.name,
                                        String(format: "%.1f", macro.durationSeconds)),
                                icon: "record.circle")
            }
        })
        alert.addAction(UIAlertAction(title: L10n.str("emu.macro.discard"), style: .destructive) { _ in
            MacroManager.shared.cancelRecording()
            EmulatorCore.shared.start()
        })
        present(alert, animated: true)
    }

    private func showMacroPlaybackMenu() {
        let macros = MacroManager.shared.macros
        guard !macros.isEmpty else {
            showToast(L10n.str("emu.toast.nomacro"), icon: "record.circle")
            EmulatorCore.shared.start()
            return
        }
        let actions: [RTMenuAction] = macros.map { macro in
            RTMenuAction(title: macro.name,
                         subtitle: L10n.str("emu.macro.seconds", String(format: "%.1f", macro.durationSeconds)),
                         icon: "play.circle",
                         handler: { [weak self] in
                MacroManager.shared.startPlayback(macro: macro)
                EmulatorCore.shared.start()
                self?.showToast(L10n.str("emu.toast.macroplay", macro.name), icon: "play.circle")
            })
        }
        RTMenuSheetViewController.present(from: self,
                                          title: L10n.str("emu.macro.pick"),
                                          actions: actions,
                                          onDismiss: { EmulatorCore.shared.start() })
    }
}
