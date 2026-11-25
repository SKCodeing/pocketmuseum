// RewindManager.swift
// 倒带/回放功能
// F9: 环形帧缓冲，保存最近 N 秒的 saveState 快照
//
// 设计：
//   - 每 2 帧保存一次 state（降频，减少 saveState 开销）
//   - 默认缓冲 10 秒 = 60fps / 2 * 10 = 300 个快照
//   - 倒带时每 tick 回退 2 个快照（2x 倒带速度）
//   - 倒带期间暂停音频输出，避免噪音

import Foundation

final class RewindManager {

    static let shared = RewindManager()

    // MARK: - 配置

    /// 缓冲时长（秒），0 = 关闭倒带功能
    var bufferDuration: Int = 10 {
        didSet {
            capacity = bufferDuration > 0 ? (60 / captureInterval) * bufferDuration : 0
            clear()
        }
    }

    /// 每隔多少帧保存一次（降频）
    private let captureInterval = 2

    /// 环形缓冲区容量
    private var capacity: Int = 300  // 10s * 30fps

    // MARK: - 状态

    private(set) var isRewinding = false

    // MARK: - 环形缓冲区

    private var buffer: [Data] = []   // 环形存储
    private var writeIndex = 0        // 下一个写入位置
    private var count = 0             // 当前有效快照数
    private var readIndex = 0         // 倒带读取位置（从最新往旧）

    private let lock = NSLock()

    // 帧计数器（用于降频）
    private var frameCounter = 0

    private init() {
        // 从 UserDefaults 读取配置
        let saved = UserDefaults.standard.integer(forKey: "rewind_buffer_duration")
        bufferDuration = saved > 0 ? saved : 10
    }

    // MARK: - 录制（每帧由 EmulatorCore.tick 调用）

    /// 在正常运行帧时调用，每 captureInterval 帧保存一次快照
    func captureFrame() {
        guard capacity > 0, !isRewinding else { return }
        frameCounter += 1
        guard frameCounter % captureInterval == 0 else { return }

        guard let data = EmulatorCore.shared.bridge?.saveState() else { return }

        lock.lock()
        defer { lock.unlock() }

        if buffer.count < capacity {
            buffer.append(data)
        } else {
            buffer[writeIndex] = data
        }
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    // MARK: - 倒带控制

    /// 开始倒带（按住倒带键时调用）
    func beginRewind() {
        guard capacity > 0, count > 0, !isRewinding else { return }
        isRewinding = true
        // 从最新快照开始往回读
        lock.lock()
        readIndex = (writeIndex - 1 + capacity) % capacity
        lock.unlock()
        // 暂停音频
        AudioEngine.shared.pause()
    }

    /// 执行一步倒带（每个 DisplayLink tick 调用一次）
    /// 返回 false 表示已到达缓冲区起点
    @discardableResult
    func stepRewind() -> Bool {
        guard isRewinding else { return false }

        lock.lock()
        guard count > 0 else {
            lock.unlock()
            endRewind()
            return false
        }
        let data = buffer[readIndex]
        // 向旧方向移动读指针
        readIndex = (readIndex - 1 + capacity) % capacity
        count -= 1
        lock.unlock()

        // 加载快照
        _ = EmulatorCore.shared.bridge?.loadState(data)

        // 渲染当前帧（不运行模拟，只读取帧缓冲）
        if let fb = EmulatorCore.shared.bridge?.getFrameBuffer(),
           let w  = EmulatorCore.shared.bridge?.getFrameWidth(),
           let h  = EmulatorCore.shared.bridge?.getFrameHeight() {
            EmulatorCore.shared.onFrameReady?(fb, w, h)
        }

        return count > 0
    }

    /// 结束倒带，恢复正向运行
    func endRewind() {
        guard isRewinding else { return }
        isRewinding = false
        // 恢复音频
        AudioEngine.shared.resume()
    }

    // MARK: - 工具

    func clear() {
        lock.lock()
        buffer.removeAll()
        writeIndex = 0
        count = 0
        readIndex = 0
        frameCounter = 0
        lock.unlock()
    }

    /// 游戏加载/切换时重置
    func reset() {
        clear()
        isRewinding = false
    }
}
