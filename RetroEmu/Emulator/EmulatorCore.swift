// EmulatorCore.swift
// 统一模拟器核心管理，桥接 C++ 核心与 Swift 层

import Foundation
import AVFoundation
import ImageIO

// MARK: - 模拟器核心协议
protocol EmulatorBridge: AnyObject {
    func loadROM(_ data: Data) -> Bool
    func loadROMFromPath(_ path: String) -> Bool   // 大文件（ISO/CSO）走路径，避免整体读入内存
    func runFrame()
    func reset()
    func getFrameBuffer() -> UnsafePointer<UInt32>?
    func getFrameWidth() -> Int
    func getFrameHeight() -> Int
    func setPlayer1Buttons(_ buttons: UInt16)
    func setPlayer2Buttons(_ buttons: UInt16)
    func getPlayer1Buttons() -> UInt16   // F14: 宏录制读取当前输入
    func getAudioBuffer() -> UnsafePointer<Int16>?
    func getAudioSampleCount() -> Int
    var sampleRate: Int { get }
    /// 音频缓冲的声道数：1 = 单声道，2 = 立体声交错
    var audioChannels: Int { get }
    func saveState() -> Data?
    func loadState(_ data: Data) -> Bool
    func writeByte(_ value: UInt8, at address: UInt32)
}

extension EmulatorBridge {
    /// 目前除 NES/GBC/GG/SMS/MD/GBA 这些单声道核心外，其余都输出立体声交错
    var audioChannels: Int { 2 }
}

// MARK: - 模拟器核心管理器
final class EmulatorCore {

    static let shared = EmulatorCore()

    private(set) var currentSystem: EmulatorSystem?
    private(set) var isRunning = false
    var bridge: EmulatorBridge?

    /// 当前核心的音频格式，AudioEngine 按它配置输出，否则会变调
    var audioSampleRate: Int { bridge?.sampleRate ?? 44100 }
    var audioChannels: Int { bridge?.audioChannels ?? 1 }

    // 帧回调：(frameBuffer, width, height)
    var onFrameReady: ((UnsafePointer<UInt32>, Int, Int) -> Void)?
    // 音频回调
    var onAudioReady: ((UnsafePointer<Int16>, Int) -> Void)?

    private var displayLink: CADisplayLink?
    private let emulationQueue = DispatchQueue(label: "com.retroemu.emulation", qos: .userInteractive)
    private var isFrameRunning = false

    // MARK: - 快进模式
    /// 快进倍率：1 = 正常，2 = 2倍速，4 = 4倍速
    var fastForwardMultiplier: Int = 1 {
        didSet {
            fastForwardMultiplier = max(1, min(8, fastForwardMultiplier))
        }
    }
    var isFastForwarding: Bool { fastForwardMultiplier > 1 }

    // MARK: - 自动存档（F1）
    /// 自动存档间隔（秒），0 = 关闭。默认 60 秒。
    var autoSaveInterval: TimeInterval = 60 {
        didSet { rescheduleAutoSave() }
    }
    private var autoSaveTimer: DispatchSourceTimer?

    private init() {}

    // MARK: - 加载 ROM
    func loadROM(from url: URL) throws {
        let ext = url.pathExtension.lowercased()

        // 对 .iso 文件读取文件头以精确识别系统（PSP / PS1 / Sega CD）
        let system: EmulatorSystem?
        if ext == "iso" {
            let header = (try? FileHandle(forReadingFrom: url)).flatMap { fh -> Data? in
                let data = fh.readData(ofLength: 16)
                fh.closeFile()
                return data.isEmpty ? nil : data
            }
            system = EmulatorSystem.system(for: ext, fileHeader: header)
        } else {
            system = EmulatorSystem.system(for: ext)
        }

        guard let system = system else {
            EmuLog.error("❌ 不支持的格式: .\(ext)，文件: \(url.lastPathComponent)")
            throw EmulatorError.unsupportedFormat(ext)
        }

        EmuLog.info("📂 加载 ROM: \(url.lastPathComponent)")
        EmuLog.info("   系统识别: \(system.rawValue)  扩展名: .\(ext)")
        EmuLog.info("   文件大小: \(fileSizeString(url))")
        EmuLog.info("   RETRO_NATIVE_CORE: \(nativeCoreEnabled ? "✅ 已启用" : "⚠️ 未启用（Stub 模式）")")

        currentSystem = system
        currentROMName = url.deletingPathExtension().lastPathComponent
        currentROMURL = url
        bridge = makeBridge(for: system)

        // 大文件（ISO/CSO/BIN > 32MB）走路径加载，避免整体读入内存
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let usesPathLoading = fileSize > 32 * 1024 * 1024

        let loadSuccess: Bool
        if usesPathLoading {
            EmuLog.info("   加载方式: 文件路径（大文件，\(fileSizeString(url))）")
            loadSuccess = bridge?.loadROMFromPath(url.path) == true
        } else {
            EmuLog.info("   加载方式: 内存 Data")
            let data = try Data(contentsOf: url)
            loadSuccess = bridge?.loadROM(data) == true
        }

        if !loadSuccess {
            EmuLog.error("❌ ROM 加载失败: \(url.lastPathComponent)  系统: \(system.rawValue)")
            throw EmulatorError.loadFailed
        }
        EmuLog.info("✅ ROM 加载成功: \(url.lastPathComponent)")
    }

    private var nativeCoreEnabled: Bool {
        #if RETRO_NATIVE_CORE
        return true
        #else
        return false
        #endif
    }

    private func fileSizeString(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        if bytes > 1024 * 1024 * 1024 { return String(format: "%.1f GB", Double(bytes) / 1_073_741_824) }
        if bytes > 1024 * 1024        { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        return "\(bytes / 1024) KB"
    }

    // MARK: - 控制
    func start() {
        guard bridge != nil, !isRunning else {
            EmuLog.warn("start() 忽略：bridge=\(bridge == nil ? "nil" : "ok")  isRunning=\(isRunning)")
            return
        }
        EmuLog.info("▶️ 模拟器启动  系统: \(currentSystem?.rawValue ?? "nil")")
        isRunning = true
        scheduleDisplayLink()
        rescheduleAutoSave()
    }

    func pause() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        autoSaveTimer?.cancel()
        autoSaveTimer = nil
    }

    func reset() {
        bridge?.reset()
    }

    func stop() {
        pause()
        RewindManager.shared.reset()
        bridge = nil
        currentSystem = nil
        currentROMName = nil
        currentROMURL = nil
        _frameCount = 0
        _firstFrameLogged = false
        EmuLog.info("⏹ 模拟器停止")
    }

    // MARK: - 输入
    func setButtons(_ buttons: EmulatorButton, player: Int) {
        let raw = buttons.rawValue
        if player == 0 {
            bridge?.setPlayer1Buttons(raw)
        } else {
            bridge?.setPlayer2Buttons(raw)
        }
    }

    // MARK: - 存档/读档
    func saveState(slot: Int) {
        guard let rom = currentROMName, let data = bridge?.saveState() else { return }
        try? SaveStateManager.shared.save(data: data, romName: rom, slot: slot)
        // 同时保存当前帧截图（转为 JPEG Data）
        if let fb = bridge?.getFrameBuffer(),
           let w = bridge?.getFrameWidth(), let h = bridge?.getFrameHeight(),
           let jpegData = frameBufferToJPEG(fb, width: w, height: h) {
            SaveStateManager.shared.saveScreenshotData(jpegData, romName: rom, slot: slot)
        }
    }

    func loadState(slot: Int) {
        guard let rom = currentROMName,
              let data = try? SaveStateManager.shared.load(romName: rom, slot: slot) else { return }
        _ = bridge?.loadState(data)
    }

    // MARK: - 帧缓冲转 JPEG Data（纯 CoreGraphics，不依赖 UIKit）
    func frameBufferToJPEG(_ buffer: UnsafePointer<UInt32>, width: Int, height: Int) -> Data? {
        let bytesPerRow = width * 4
        guard let ctx = CGContext(
            data: UnsafeMutableRawPointer(mutating: buffer),
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ), let cgImg = ctx.makeImage() else { return nil }

        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImg, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    // MARK: - 帧缓冲转 CGImage（供外部使用）
    func frameBufferToImage(_ buffer: UnsafePointer<UInt32>, width: Int, height: Int) -> CGImage? {
        let bytesPerRow = width * 4
        guard let ctx = CGContext(
            data: UnsafeMutableRawPointer(mutating: buffer),
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        return ctx.makeImage()
    }

    private(set) var currentROMName: String?
    private(set) var currentROMURL: URL?

    // MARK: - 作弊码内存写入
    func writeByte(_ value: UInt8, at address: UInt32) {
        bridge?.writeByte(value, at: address)
    }
    private func scheduleDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFramesPerSecond = 60
        displayLink?.add(to: .main, forMode: .common)
    }

    // MARK: - 自动存档定时器

    private func rescheduleAutoSave() {
        autoSaveTimer?.cancel()
        autoSaveTimer = nil
        guard autoSaveInterval > 0, isRunning, currentROMName != nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: emulationQueue)
        timer.schedule(deadline: .now() + autoSaveInterval, repeating: autoSaveInterval)
        timer.setEventHandler { [weak self] in
            self?.performAutoSave()
        }
        timer.resume()
        autoSaveTimer = timer
    }

    private func performAutoSave() {
        guard let rom = currentROMName,
              let stateData = bridge?.saveState() else { return }
        let jpegData: Data?
        if let fb = bridge?.getFrameBuffer(),
           let w = bridge?.getFrameWidth(), let h = bridge?.getFrameHeight() {
            jpegData = frameBufferToJPEG(fb, width: w, height: h)
        } else {
            jpegData = nil
        }
        SaveStateManager.shared.autoSave(stateData: stateData, romName: rom, jpegData: jpegData)
    }

    // MARK: - 截图（F2）

    /// 截取当前帧，返回 CGImage（供 EmulatorViewController 保存到相册）
    func captureScreenshot() -> CGImage? {
        guard let fb = bridge?.getFrameBuffer(),
              let w = bridge?.getFrameWidth(),
              let h = bridge?.getFrameHeight() else { return nil }
        return frameBufferToImage(fb, width: w, height: h)
    }

    private var _frameCount: Int = 0
    private var _firstFrameLogged = false

    @objc private func tick() {
        guard isRunning, let bridge = bridge, !isFrameRunning else { return }

        // F9: 倒带模式
        if RewindManager.shared.isRewinding {
            isFrameRunning = true
            emulationQueue.async { [weak self] in
                defer { DispatchQueue.main.async { self?.isFrameRunning = false } }
                RewindManager.shared.stepRewind()
            }
            return
        }

        isFrameRunning = true
        emulationQueue.async { [weak self] in
            guard let self = self else { return }
            defer { DispatchQueue.main.async { self.isFrameRunning = false } }
            let frames = self.fastForwardMultiplier
            for i in 0..<frames {
                // F14: 宏回放覆盖输入
                if MacroManager.shared.isPlaying,
                   let macroButtons = MacroManager.shared.nextPlaybackButtons() {
                    bridge.setPlayer1Buttons(macroButtons)
                }

                bridge.runFrame()
                self._frameCount += 1

                // 首帧日志
                if !self._firstFrameLogged {
                    self._firstFrameLogged = true
                    let w = bridge.getFrameWidth()
                    let h = bridge.getFrameHeight()
                    let hasFB = bridge.getFrameBuffer() != nil
                    EmuLog.info("🖼 首帧渲染: \(w)×\(h)  frameBuffer=\(hasFB ? "✅" : "❌nil")")
                    EmuLog.info("   bridge 类型: \(type(of: bridge))")
                }

                // F14: 宏录制
                if MacroManager.shared.isRecording {
                    let currentButtons = bridge.getPlayer1Buttons()
                    MacroManager.shared.recordFrame(buttons: currentButtons)
                }

                if let rom = self.currentROMName {
                    CheatManager.shared.applyActive(for: rom)
                }
                if i == frames - 1 {
                    if let audio = bridge.getAudioBuffer() {
                        self.onAudioReady?(audio, bridge.getAudioSampleCount())
                    } else if self._frameCount <= 5 {
                        EmuLog.warn("⚠️ 第\(self._frameCount)帧：getAudioBuffer() 返回 nil")
                    }
                }
            }
            if let fb = bridge.getFrameBuffer() {
                self.onFrameReady?(fb, bridge.getFrameWidth(), bridge.getFrameHeight())
            } else if self._frameCount <= 5 {
                EmuLog.warn("⚠️ 第\(self._frameCount)帧：getFrameBuffer() 返回 nil，画面不会更新")
            }
            // F9: 录制倒带快照
            RewindManager.shared.captureFrame()
        }
    }

    // MARK: - 工厂
    // 配置好 Bridging Header 后，RETRO_NATIVE_CORE 宏会自动启用真实核心
    // 在 Build Settings → Other Swift Flags 添加：-D RETRO_NATIVE_CORE
    private func makeBridge(for system: EmulatorSystem) -> EmulatorBridge {
        #if RETRO_NATIVE_CORE
        switch system {
        case .nes:     return NESBridgeWrapper()
        case .gbc:     return GBCBridgeWrapper()
        case .gg:      return GGBridgeWrapper()
        case .sms:     return SMSMDBridgeWrapper(system: .sms)
        case .md:      return SMSMDBridgeWrapper(system: .md)
        case .gba:     return GBABridgeWrapper()
        case .snes:    return SNESBridgeWrapper()
        case .nds:     return NDSBridgeWrapper()
        case .sega32x: return SMSMDBridgeWrapper(system: .sega32x)
        case .segaCD:  return SMSMDBridgeWrapper(system: .segaCD)
        case .n64:     return N64BridgeWrapper()
        case .ps1:     return PS1BridgeWrapper()
        case .psp:     return PSPBridgeWrapper()
        }
        #else
        switch system {
        case .nes:     return StubEmulatorCore(width: FrameSize.nesWidth,  height: FrameSize.nesHeight,  tint: (r: true,  g: false, b: false))
        case .gbc:     return StubEmulatorCore(width: FrameSize.gbcWidth,  height: FrameSize.gbcHeight,  tint: (r: false, g: true,  b: false))
        case .gg:      return StubEmulatorCore(width: FrameSize.ggWidth,   height: FrameSize.ggHeight,   tint: (r: false, g: false, b: true))
        case .sms:     return StubEmulatorCore(width: FrameSize.smsWidth,  height: FrameSize.smsHeight,  tint: (r: true,  g: true,  b: false))
        case .md:      return StubEmulatorCore(width: FrameSize.mdWidth,   height: FrameSize.mdHeight,   tint: (r: false, g: true,  b: true))
        case .gba:     return StubEmulatorCore(width: FrameSize.gbaWidth,  height: FrameSize.gbaHeight,  tint: (r: true,  g: false, b: true))
        case .snes:    return StubEmulatorCore(width: FrameSize.snesWidth, height: FrameSize.snesHeight, tint: (r: true,  g: true,  b: true))
        case .nds:     return StubEmulatorCore(width: FrameSize.ndsWidth,  height: FrameSize.ndsHeight,  tint: (r: false, g: true,  b: true))
        case .sega32x: return StubEmulatorCore(width: FrameSize.s32xWidth, height: FrameSize.s32xHeight, tint: (r: true,  g: false, b: false))
        case .segaCD:  return StubEmulatorCore(width: FrameSize.scdWidth,  height: FrameSize.scdHeight,  tint: (r: false, g: false, b: true))
        case .n64:     return StubEmulatorCore(width: FrameSize.n64Width,  height: FrameSize.n64Height,  tint: (r: true,  g: true,  b: false))
        case .ps1:     return StubEmulatorCore(width: FrameSize.ps1Width,  height: FrameSize.ps1Height,  tint: (r: false, g: true,  b: false))
        case .psp:     return StubEmulatorCore(width: FrameSize.pspWidth,  height: FrameSize.pspHeight,  tint: (r: true,  g: false, b: true))
        }
        #endif
    }
}

// MARK: - 错误类型
enum EmulatorError: LocalizedError {
    case unsupportedFormat(String)
    case loadFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "不支持的文件格式: .\(ext)"
        case .loadFailed: return "ROM 加载失败，文件可能已损坏"
        }
    }
}

// MARK: - Stub 核心（集成真实 C++ 核心前使用）
// NES=红色调 / GBC=绿色调 / GG=蓝色调 动态测试画面
final class StubEmulatorCore: EmulatorBridge {

    private let width: Int
    private let height: Int
    private let tint: (r: Bool, g: Bool, b: Bool)

    private let framePtr: UnsafeMutablePointer<UInt32>
    private let audioPtr: UnsafeMutablePointer<Int16>
    private var tick: UInt8 = 0
    private var romLoaded = false

    let sampleRate: Int = 44100
    var audioChannels: Int { 1 }
    private var samplesPerFrame: Int { sampleRate / 60 }

    init(width: Int, height: Int, tint: (r: Bool, g: Bool, b: Bool)) {
        self.width = width
        self.height = height
        self.tint = tint
        framePtr = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)
        framePtr.initialize(repeating: 0xFF000000, count: width * height)
        let spf = sampleRate / 60
        audioPtr = UnsafeMutablePointer<Int16>.allocate(capacity: spf)
        audioPtr.initialize(repeating: 0, count: spf)
    }

    deinit {
        framePtr.deallocate()
        audioPtr.deallocate()
    }

    func loadROM(_ data: Data) -> Bool {
        romLoaded = data.count > 0
        return romLoaded
    }

    func loadROMFromPath(_ path: String) -> Bool {
        // Stub：路径加载等同于 Data 加载（只检查文件是否存在）
        let exists = FileManager.default.fileExists(atPath: path)
        romLoaded = exists
        EmuLog.info("[Stub] loadROMFromPath: \(path)  exists=\(exists)")
        return romLoaded
    }

    func runFrame() {
        guard romLoaded else { return }
        tick &+= 1
        let t = tick
        for y in 0..<height {
            for x in 0..<width {
                let r: UInt32 = tint.r ? UInt32(UInt8(x) &+ t) : 0
                let g: UInt32 = tint.g ? UInt32(UInt8(y) &+ t) : 0
                let b: UInt32 = tint.b ? UInt32(UInt8(x ^ y) &+ t) : 0
                framePtr[y * width + x] = 0xFF000000 | (b << 16) | (g << 8) | r
            }
        }
        let spf = samplesPerFrame
        for i in 0..<spf {
            let phase = Double(i + Int(t) * spf) / Double(sampleRate) * 440.0 * 2.0 * .pi
            audioPtr[i] = Int16(sin(phase) * 3000)
        }
    }

    func reset() { tick = 0 }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { UnsafePointer(framePtr) }
    func getFrameWidth() -> Int { width }
    func getFrameHeight() -> Int { height }
    func setPlayer1Buttons(_ buttons: UInt16) {}
    func setPlayer2Buttons(_ buttons: UInt16) {}
    func getPlayer1Buttons() -> UInt16 { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>? { UnsafePointer(audioPtr) }
    func getAudioSampleCount() -> Int { samplesPerFrame }
    func saveState() -> Data? { nil }
    func loadState(_ data: Data) -> Bool { false }
    func writeByte(_ value: UInt8, at address: UInt32) {}
}

// MARK: - 真实 ObjC++ 核心包装
// 只在 Build Settings → Other Swift Flags 加了 -D RETRO_NATIVE_CORE 时编译
// 同时需要配置 Bridging Header：RetroEmu/Core/Bridge/RetroEmu-Bridging-Header.h
#if RETRO_NATIVE_CORE

final class NESBridgeWrapper: EmulatorBridge {
    private let core = NESBridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

final class GBCBridgeWrapper: EmulatorBridge {
    private let core = GBCBridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

final class GGBridgeWrapper: EmulatorBridge {
    private let core = GGBridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

final class SMSMDBridgeWrapper: EmulatorBridge {
    private let core: SMSMDBridgeObjC
    init(system: EmulatorSystem) {
        let sysType: SMSMDSystemType
        switch system {
        case .md:      sysType = SMSMDSystemType(rawValue: 1)!  // SMSMDSystemTypeMD
        case .sega32x: sysType = SMSMDSystemType(rawValue: 2)!  // SMSMDSystemTypeSega32X
        case .segaCD:  sysType = SMSMDSystemType(rawValue: 3)!  // SMSMDSystemTypeSegaCD
        default:       sysType = SMSMDSystemType(rawValue: 0)!  // SMSMDSystemTypeSMS
        }
        core = SMSMDBridgeObjC(system: sysType)
    }
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

final class GBABridgeWrapper: EmulatorBridge {
    private let core = GBABridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

// Sprint 2: SNES (Snes9x)
final class SNESBridgeWrapper: EmulatorBridge {
    private let core = SNESBridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

// Sprint 2: NDS (melonDS)
final class NDSBridgeWrapper: EmulatorBridge {
    private let core = NDSBridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16              { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

// Sprint 6: N64 (Mupen64Plus)
final class N64BridgeWrapper: EmulatorBridge {
    private let core = N64BridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    func loadROMFromPath(_ path: String) -> Bool    { loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16               { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    var audioChannels: Int                           { 1 }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

// Sprint 6: PS1 (PCSX-ReARMed)
final class PS1BridgeWrapper: EmulatorBridge {
    private let core = PS1BridgeObjC()
    func loadROM(_ data: Data) -> Bool              { core.loadROM(data) }
    /// PS1 ISO 走路径加载，避免把整个 ISO 读入内存
    func loadROMFromPath(_ path: String) -> Bool {
        EmuLog.info("[PS1] loadROMFromPath: \(path)")
        // PS1Bridge 目前只接受 NSData，但 ISO 文件太大不能整体读入
        // 改为只读取必要的头部数据，实际加载由 Bridge 内部通过路径完成
        // 此处传入空 Data 触发 Bridge 内部的路径加载逻辑（需 PS1Bridge 支持）
        // 临时方案：小于 800MB 的 BIN 文件才整体读入
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        if fileSize < 800 * 1024 * 1024 {
            EmuLog.info("[PS1] 文件较小(\(fileSize/1024/1024)MB)，整体读入内存")
            return loadROM((try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data())
        }
        EmuLog.error("[PS1] ⚠️ ISO 文件过大(\(fileSize/1024/1024)MB)，PS1Bridge 暂不支持路径加载，请使用 .bin/.cue 格式")
        return false
    }
    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16               { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { core.sampleRate() }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

// Sprint 6: PSP (PPSSPP Vulkan/MoltenVK 硬件渲染 — App Store 合规)
final class PSPBridgeWrapper: EmulatorBridge {
    let core = PSPBridgeObjC()

    init() {
        core.useJIT = false
        // 从 Provider 取 Metal layer（由 EmulatorViewController 提前设置）
        if let layer = PSPMetalLayerProvider.shared.layer {
            core.metalLayer = layer
        }
    }

    func setMetalLayer(_ layer: CAMetalLayer) {
        core.metalLayer = layer
    }

    func loadROM(_ data: Data) -> Bool {
        let romURL = EmulatorCore.shared.currentROMURL
        let filename = romURL?.lastPathComponent ?? "game.iso"
        EmuLog.info("[PSP] loadROM(Data) filename=\(filename)  size=\(data.count/1024/1024)MB")
        return core.loadROM(data, filename: filename)
    }

    func loadROMFromPath(_ path: String) -> Bool {
        EmuLog.info("[PSP] loadROMFromPath: \(URL(fileURLWithPath: path).lastPathComponent)")
        return core.loadROM(fromPath: path)
    }

    func runFrame()                                  { core.runFrame() }
    func reset()                                     { core.reset() }
    func getFrameBuffer() -> UnsafePointer<UInt32>? { core.getFrameBuffer() }
    func getFrameWidth()  -> Int                     { core.frameWidth() }
    func getFrameHeight() -> Int                     { core.frameHeight() }
    func setPlayer1Buttons(_ b: UInt16)              { core.setPlayer1Buttons(b) }
    func setPlayer2Buttons(_ b: UInt16)              { core.setPlayer2Buttons(b) }
    func getPlayer1Buttons() -> UInt16               { 0 }
    func getAudioBuffer() -> UnsafePointer<Int16>?  { core.getAudioBuffer() }
    func getAudioSampleCount() -> Int                { core.audioSampleCount() }
    var sampleRate: Int                              { PSP_SAMPLE_RATE }
    func saveState() -> Data?                        { core.saveState() }
    func loadState(_ data: Data) -> Bool             { core.loadState(data) }
    func writeByte(_ value: UInt8, at address: UInt32) { core.writeByte(value, at: address) }
}

/// PSP Metal layer 的全局传递通道
/// EmulatorViewController 在加载 PSP ROM 前设置，PSPBridgeWrapper 在 init 时读取
final class PSPMetalLayerProvider {
    static let shared = PSPMetalLayerProvider()
    var layer: CAMetalLayer?
    private init() {}
}

private let PSP_SAMPLE_RATE = 44100

#endif
