// RTShotRunner.swift
// Debug 专用：以 -captureShots 启动时，依次切换各标签页并把画面写入 Documents/Shots；
// 以 -openROM 启动时直接打开库里第一张卡带，供游戏内截图取证。
// 用于真机 UI 巡检与上架素材取证；Release 包不包含这段代码。

#if DEBUG
import UIKit

enum RTShotRunner {

    static func runIfRequested(in window: UIWindow?) {
        let args = ProcessInfo.processInfo.arguments
        guard let window = window,
              let root = window.rootViewController as? RetroRootViewController else { return }

        if args.contains("-seedStats") {
            // 只用来验证年报版面（统计格 / 最忙月份 / 最常重开的卡带都非空）。
            // 写进 UserDefaults 后立即退出，下一轮启动由 GameStatsManager 正常读回。
            seedStats()
            exit(0)
        }
        if args.contains("-startWiFi") {
            // WiFi 传输压测：只起 HTTP 服务、不开界面，本机 curl 直接打进来
            // 8080 在开发机上常被别的服务占着，默认换 18080，可用 -wifiPort 指定
            let port = args.firstIndex(of: "-wifiPort").flatMap {
                $0 + 1 < args.count ? UInt16(args[$0 + 1]) : nil
            }
            WiFiTransferServer.shared.port = port ?? 18080
            WiFiTransferServer.shared.start()
            NSLog("[RetroEmu] -startWiFi：%@", WiFiTransferServer.shared.localURL)
            return
        }
        if args.contains("-openWiFi") {
            // 带界面压测：走上真实的 onFileReceived → 扫描 → 刷新首页那条链路
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                let nav = UINavigationController(rootViewController: WiFiTransferViewController())
                root.present(nav, animated: false)
                WiFiTransferServer.shared.port = 18080
                WiFiTransferServer.shared.start()
                NSLog("[RetroEmu] -openWiFi：%@", WiFiTransferServer.shared.localURL)
            }
            return
        }
        if args.contains("-openReport") {
            // 年度回顾取证：切到时光页再弹年报，背景是真实页面
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                root.tabs.select(index: 1, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    root.present(MuseumReportViewController(), animated: true)
                }
            }
            return
        }
        if args.contains("-openExhibit") {
            // 展签页取证：直接打开库里第一张卡带的展签
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let rom = ROMLibrary.shared.roms.first else {
                    NSLog("[RetroEmu] -openExhibit：Documents 里没有可用 ROM")
                    return
                }
                let vc = ROMDetailViewController(rom: rom)
                vc.onPlay = { rom in root.presentGame(rom) }
                root.present(vc, animated: true)
            }
            return
        }
        if args.contains("-makeHistory") {
            makeHistory(root: root)
            return
        }
        if args.contains("-openROM") {
            openFirstROM(root: root, autoStart: args.contains("-autoStart"))
            return
        }
        // App Store 要求按设备像素出图（6.3" 1206×2622、Duo 1398×2034、13" iPad 2064×2752），
        // 应用内 render 出来的尺寸对不上。这里只负责把页面切到位并留 READY 标记，
        // 真正的图由外部脚本用 simctl 原分辨率抓。
        if let flag = args.firstIndex(of: "-shotPage"), flag + 1 < args.count {
            shotPage(args[flag + 1], root: root)
            return
        }
        guard args.contains("-captureShots") else { return }

        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shots", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 每个标签页停留后再截图，避免截到过渡帧
        let steps: [(index: Int, name: String)] = [
            (0, "01-home"),
            (1, "02-timeline"),
            (2, "03-settings"),
        ]

        var delay: TimeInterval = 2.4
        for step in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                root.tabs.select(index: step.index, animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    save(window: window, to: dir.appendingPathComponent("\(step.name).png"))
                }
            }
            delay += 1.3
        }

        // 展签与年报是模态页：同样整窗渲染，保证六张截图顶部都是干净的画布
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            root.tabs.select(index: 0, animated: false)
            guard let rom = ROMLibrary.shared.roms.first else {
                NSLog("[RetroEmu] -captureShots：Documents 里没有可用 ROM，跳过展签与年报")
                markShotsReady("DONE.txt")
                return
            }
            let exhibit = ROMDetailViewController(rom: rom)
            // 截图里用整屏呈现：商店图上留一条被压暗的桌面不好看，内容本身是同一套页面
            exhibit.modalPresentationStyle = .fullScreen
            root.present(exhibit, animated: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                save(window: window, to: dir.appendingPathComponent("05-exhibit.png"))
                exhibit.dismiss(animated: false) {
                    let report = MuseumReportViewController()
                    report.modalPresentationStyle = .fullScreen
                    root.present(report, animated: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        save(window: window, to: dir.appendingPathComponent("06-report.png"))
                        report.dismiss(animated: false) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                markShotsReady("DONE.txt")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 把界面切到商店截图需要的某一页，并写 PAGE_READY.txt 给外部脚本。
    /// 页面停留时间给足，避免抓到 tab 切换的过渡帧。
    private static func shotPage(_ page: String, root: RetroRootViewController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            switch page {
            case "timeline":
                root.tabs.select(index: 1, animated: false)
            case "settings":
                root.tabs.select(index: 2, animated: false)
            case "exhibit":
                root.tabs.select(index: 0, animated: false)
                guard let rom = ROMLibrary.shared.roms.first else {
                    NSLog("[RetroEmu] -shotPage exhibit：Documents 里没有可用 ROM")
                    return
                }
                let exhibit = ROMDetailViewController(rom: rom)
                // 商店图上不留被压暗的桌面，直接用整屏呈现
                exhibit.modalPresentationStyle = .fullScreen
                root.present(exhibit, animated: false)
            case "report":
                root.tabs.select(index: 1, animated: false)
                let report = MuseumReportViewController()
                report.modalPresentationStyle = .fullScreen
                root.present(report, animated: false)
            default:
                root.tabs.select(index: 0, animated: false)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                markShotsReady("PAGE_READY.txt")
            }
        }
    }

    /// 打开库里第一张卡带。ROM 由外部先拷进 Documents，见 Tools/testrom。
    /// autoStart 为真时再补一次 START，用来截游戏内画面。
    private static func openFirstROM(root: RetroRootViewController, autoStart: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            root.tabs.select(index: 0, animated: false)
            guard let rom = ROMLibrary.shared.roms.first else {
                NSLog("[RetroEmu] -openROM：Documents 里没有可用 ROM")
                return
            }
            NSLog("[RetroEmu] -openROM：打开 %@", rom.name)
            root.presentGame(rom)

            // 模拟器上的外接键盘可能被判成控制器，虚拟手柄会被自动藏起来
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                (root.presentedViewController as? EmulatorViewController)?.forceShowVirtualPad()
            }

            guard autoStart else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                EmulatorCore.shared.setButtons(.start, player: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    EmulatorCore.shared.setButtons([], player: 0)
                }
                // 模拟器里模拟速度不受垂直同步约束，卡带落到底可能不到一秒，
                // 外部脚本再快也追不上。所以先暂停模拟器把画面定格，再发信号，
                // 截图拿到的就是暂停时那一帧，不会出现「漏接 2 次」的结束态。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    EmulatorCore.shared.pause()
                    RTShotRunner.markGameplayReady()
                }
            }
        }
    }

    /// 给外部脚本的信号：游戏已经进入可截图状态
    private static func markGameplayReady() {
        markShotsReady("GAME_READY.txt")
    }

    /// 造一份真实的存档历史，供「时光」页截图取证。
    /// 自动存档间隔临时压到 0.8 秒，打几秒就攒下几张带缩略图的存档，
    /// 然后退出游戏切到时光页，别让商店截图里出现一张空时间轴。
    private static func makeHistory(root: RetroRootViewController) {
        EmulatorCore.shared.autoSaveInterval = 0.8

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard let rom = ROMLibrary.shared.roms.first else {
                NSLog("[RetroEmu] -makeHistory：Documents 里没有可用 ROM")
                return
            }
            root.presentGame(rom)

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                EmulatorCore.shared.setButtons(.start, player: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    EmulatorCore.shared.setButtons([], player: 0)
                }
            }

            // 攒够几张存档再收工
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                EmulatorCore.shared.autoSaveInterval = 60
                root.dismiss(animated: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    root.tabs.select(index: 1, animated: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        markShotsReady("HISTORY_READY.txt")
                    }
                }
            }
        }
    }

    /// 只为验证年报版面：造几个月、几十次开箱的统计，让每个格子都有内容。
    /// 写完 UserDefaults 就退出，由下一轮启动正常读回——不碰 GameStatsManager 的内存态。
    private static func seedStats() {
        // 首屏改成惰性建页之后，这里可能在 ROMLibrary 扫描之前就跑到了，
        // 先确保库已扫过，否则找不到 ROM 会静默跳过。
        if ROMLibrary.shared.roms.isEmpty {
            ROMLibrary.shared.scan()
        }
        guard let rom = ROMLibrary.shared.roms.first else {
            NSLog("[RetroEmu] -seedStats：Documents 里没有可用 ROM")
            return
        }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        var stats = GameStats()
        stats.lastPlayedDate = Date()
        stats.sessions = 27
        stats.longestSession = 3_180
        var daily: [String: Double] = [:]
        let plan: [(month: Int, day: Int, seconds: Double)] = [
            (1, 6, 1_260), (2, 11, 2_900), (3, 3, 840), (3, 22, 1_480),
            (4, 17, 3_420), (5, 2, 1_560), (5, 19, 2_140), (6, 21, 660),
        ]
        for item in plan {
            daily[String(format: "%04d-%02d-%02d", year, item.month, item.day)] = item.seconds
        }
        stats.dailySeconds = daily
        stats.totalSeconds = daily.values.reduce(0, +)

        guard let data = try? JSONEncoder().encode([rom.name: stats]) else { return }
        UserDefaults.standard.set(data, forKey: "game_stats_v1")
        // 紧跟一句 exit(0)：不强制落盘的话，cfprefsd 可能还没来得及写入进程就退了，
        // 截图里就会出现「0m / 4 秒」这种没种上统计的脏数据。
        UserDefaults.standard.synchronize()
    }

    private static func markShotsReady(_ fileName: String) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "ready".write(to: dir.appendingPathComponent(fileName),
                           atomically: true, encoding: .utf8)
    }

    private static func save(window: UIWindow, to url: URL) {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: url)
    }
}
#endif
