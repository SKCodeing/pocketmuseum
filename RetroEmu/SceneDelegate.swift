// SceneDelegate.swift

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        window = UIWindow(windowScene: windowScene)

        // 先把主题套到 window 上再显示：否则深色主题的首帧会先用系统色板画一遍，淡到白再变深
        AppThemeManager.shared.applyStored(to: window)

        window?.rootViewController = RetroRootViewController()
        window?.makeKeyAndVisible()

        // Debug 巡检：-captureShots 时自动逐页截图到 Documents/Shots
        #if DEBUG
        RTShotRunner.runIfRequested(in: window)
        #endif

        // 冷启动时通过文件打开（如从微信点击 ROM）
        if let urlContext = connectionOptions.urlContexts.first {
            handleOpenURL(urlContext.url)
        }
    }

    // 热启动：App 已在后台时收到文件打开请求（普通文件 + retroemu:// deep link 统一处理）
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        let url = urlContext.url
        if url.scheme == "retroemu" {
            handleDeepLink(url)
        } else {
            handleOpenURL(url)
        }
    }

    // F12: Spotlight 搜索结果点击
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if SpotlightManager.handleUserActivity(userActivity) { return }
        if let url = userActivity.webpageURL { handleDeepLink(url) }
    }

    // MARK: - F13: Widget / F12: Spotlight Deep Link

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "retroemu", url.host == "launch" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let romPath = components.queryItems?.first(where: { $0.name == "rom" })?.value else { return }
        let romURL = URL(fileURLWithPath: romPath)
        guard FileManager.default.fileExists(atPath: romURL.path) else { return }
        if let rom = ROMLibrary.shared.roms.first(where: { $0.url.path == romPath }) {
            launchGame(rom)
        }
    }

    // MARK: - 处理外部文件打开

    private func handleOpenURL(_ url: URL) {
        // 获取安全访问权限
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ext = url.pathExtension.lowercased()

        // ZIP 文件：解压后导入所有 ROM
        if ext == "zip" {
            importZIP(url)
            return
        }

        // 直接是 ROM 文件
        guard EmulatorSystem.system(for: ext) != nil else { return }
        importAndLaunch(url)
    }

    private func importZIP(_ url: URL) {
        Task.detached {
            guard let entries = try? ZipExtractor.listEntries(zipURL: url) else { return }
            let romEntries = entries.filter { ZipExtractor.isROM($0) }
            guard !romEntries.isEmpty else { return }

            var importedROMs: [ROMInfo] = []
            for entry in romEntries {
                if let destURL = try? ZipExtractor.extractEntry(entry, from: url, to: ROMLibrary.shared.romsDirectory) {
                    try? ROMLibrary.shared.importROM(from: destURL)
                    ROMLibrary.shared.scan()
                    if let rom = ROMLibrary.shared.roms.first(where: { $0.url.lastPathComponent == destURL.lastPathComponent }) {
                        importedROMs.append(rom)
                    }
                }
            }

            let captured = importedROMs
            await MainActor.run { [weak self] in
                NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
                if captured.count == 1 {
                    self?.launchGame(captured[0])
                }
            }
        }
    }

    private func importAndLaunch(_ url: URL) {
        Task.detached {
            do {
                try ROMLibrary.shared.importROM(from: url)
                ROMLibrary.shared.scan()
                let romName = url.deletingPathExtension().lastPathComponent
                let rom = ROMLibrary.shared.roms.first { $0.name == romName }

                await MainActor.run { [weak self] in
                    NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
                    if let rom = rom {
                        self?.launchGame(rom)
                    }
                }
            } catch {
                print("[SceneDelegate] 导入失败: \(error)")
            }
        }
    }

    private func launchGame(_ rom: ROMInfo) {
        guard let root = window?.rootViewController else { return }
        // 如果当前有弹层（如导入面板/错误提示），先关闭
        if let presented = root.presentedViewController {
            presented.dismiss(animated: false)
        }
        if let root = root as? RetroRootViewController {
            root.presentGame(rom)
        } else {
            let vc = EmulatorViewController(rom: rom)
            vc.modalPresentationStyle = .fullScreen
            root.present(vc, animated: true)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {}
    func sceneDidBecomeActive(_ scene: UIScene) {}
    func sceneWillResignActive(_ scene: UIScene) {}
    func sceneWillEnterForeground(_ scene: UIScene) {}
    func sceneDidEnterBackground(_ scene: UIScene) {}
}
