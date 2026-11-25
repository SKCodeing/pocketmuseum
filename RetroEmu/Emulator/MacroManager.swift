// MacroManager.swift
// 宏录制与回放
// F14: 录制按键序列，一键回放/循环

import Foundation

// MARK: - 数据模型

/// 单帧按键状态（RLE 压缩：相同按键状态合并为多帧）
struct MacroFrame: Codable {
    let buttons: UInt16   // EmulatorButton.rawValue
    let frames: Int       // 持续帧数
}

struct MacroEntry: Codable, Identifiable {
    let id: String
    var name: String
    let system: String    // EmulatorSystem.rawValue，宏与平台绑定
    var frames: [MacroFrame]
    let createdAt: Date

    var totalFrames: Int { frames.reduce(0) { $0 + $1.frames } }
    var durationSeconds: Double { Double(totalFrames) / 60.0 }

    static func make(name: String, system: String, frames: [MacroFrame]) -> MacroEntry {
        MacroEntry(id: UUID().uuidString, name: name, system: system,
                   frames: frames, createdAt: Date())
    }
}

// MARK: - 管理器

final class MacroManager {

    static let shared = MacroManager()

    private let key = "macros_v1"
    private let maxMacros = 5
    private let maxFrames = 60 * 30  // 30 秒上限

    private(set) var macros: [MacroEntry] = []

    // MARK: - 录制状态

    private(set) var isRecording = false
    private var recordBuffer: [(buttons: UInt16, frame: Int)] = []  // (按键, 帧序号)
    private var recordFrame = 0
    private var lastButtons: UInt16 = 0

    // MARK: - 回放状态

    private(set) var isPlaying = false
    var loopPlayback = false
    private var playMacro: MacroEntry?
    private var playFrameIndex = 0   // 当前在 frames 数组中的位置
    private var playFrameCount = 0   // 当前 MacroFrame 已播放帧数

    private init() { load() }

    // MARK: - 录制

    func startRecording() {
        guard !isRecording, !isPlaying else { return }
        isRecording = true
        recordBuffer = []
        recordFrame = 0
        lastButtons = 0
    }

    /// 每帧调用，记录当前按键状态
    func recordFrame(buttons: UInt16) {
        guard isRecording else { return }
        recordBuffer.append((buttons: buttons, frame: recordFrame))
        recordFrame += 1
        if recordFrame >= maxFrames {
            // 超过上限自动停止
            _ = stopRecording(name: "宏 \(macros.count + 1)")
        }
    }

    /// 停止录制并保存
    @discardableResult
    func stopRecording(name: String) -> MacroEntry? {
        guard isRecording else { return nil }
        isRecording = false

        guard !recordBuffer.isEmpty else { return nil }

        // RLE 压缩
        var compressed: [MacroFrame] = []
        var i = 0
        while i < recordBuffer.count {
            let btn = recordBuffer[i].buttons
            var count = 1
            while i + count < recordBuffer.count && recordBuffer[i + count].buttons == btn {
                count += 1
            }
            compressed.append(MacroFrame(buttons: btn, frames: count))
            i += count
        }

        let system = EmulatorCore.shared.currentSystem?.rawValue ?? "unknown"
        let entry = MacroEntry.make(name: name, system: system, frames: compressed)

        // 超出上限时删除最旧的
        if macros.count >= maxMacros { macros.removeFirst() }
        macros.append(entry)
        save()
        return entry
    }

    func cancelRecording() {
        isRecording = false
        recordBuffer = []
    }

    // MARK: - 回放

    func startPlayback(macro: MacroEntry, loop: Bool = false) {
        guard !isRecording, !isPlaying else { return }
        guard !macro.frames.isEmpty else { return }
        isPlaying = true
        loopPlayback = loop
        playMacro = macro
        playFrameIndex = 0
        playFrameCount = 0
    }

    /// 每帧调用，返回当前帧应输入的按键（nil 表示回放结束）
    func nextPlaybackButtons() -> UInt16? {
        guard isPlaying, let macro = playMacro else { return nil }
        guard playFrameIndex < macro.frames.count else {
            if loopPlayback {
                // 循环：重置到开头
                playFrameIndex = 0
                playFrameCount = 0
            } else {
                stopPlayback()
                return nil
            }
            return nil
        }

        let frame = macro.frames[playFrameIndex]
        let buttons = frame.buttons
        playFrameCount += 1
        if playFrameCount >= frame.frames {
            playFrameIndex += 1
            playFrameCount = 0
        }
        return buttons
    }

    func stopPlayback() {
        isPlaying = false
        playMacro = nil
        playFrameIndex = 0
        playFrameCount = 0
    }

    // MARK: - 管理

    func deleteMacro(id: String) {
        macros.removeAll { $0.id == id }
        save()
    }

    func renameMacro(id: String, name: String) {
        if let i = macros.firstIndex(where: { $0.id == id }) {
            macros[i].name = name
            save()
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([MacroEntry].self, from: data) else { return }
        macros = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
