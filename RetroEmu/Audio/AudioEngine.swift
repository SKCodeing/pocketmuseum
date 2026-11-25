// AudioEngine.swift
// 音频输出 - 使用环形缓冲区 + AVAudioSourceNode 拉取模式
// 避免 scheduleBuffer 堆积导致的杂音

import AVFoundation

final class AudioEngine {

    static let shared = AudioEngine()

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var isSetup = false

    // 环形缓冲区，容量 = 8 帧，足够平滑抖动
    private var ringBuffer: [Int16] = []
    private var writePos = 0
    private var readPos  = 0
    private var available = 0  // 可读的 Int16 个数（已按声道交错）
    private let lock = NSLock()

    private var sampleRate: Double = 44100
    /// 核心输出的声道数：1 = 单声道，2 = 立体声交错
    private var channels = 2

    /// 音量 0.0 ~ 1.0，实时生效
    var volume: Float = 1.0

    private init() {}

    /// 采样率与声道数必须按核心来配置：NES/GBC 是 44100 单声道，GBA 32768、SNES 32000。
    /// 采样率对不上会整段变调；单声道当立体声播则是两帧才吃掉一个样本，听起来像降了一个八度。
    func setup(sampleRate: Double = 44100, channels: Int = 2) {
        let inputChannels = max(1, min(2, channels))
        if isSetup {
            let sameRate = abs(self.sampleRate - sampleRate) < 0.5
            guard !sameRate || self.channels != inputChannels else { return }
            stop()   // 参数变了必须重建引擎，沿用上一次的格式就会变调
        }
        self.sampleRate = sampleRate
        self.channels = inputChannels

        // 环形缓冲：8 帧 × 声道数
        let capacity = (Int(sampleRate) / 60 + 16) * inputChannels * 8
        ringBuffer = [Int16](repeating: 0, count: capacity)
        writePos = 0
        readPos = 0
        available = 0

        // 输出固定双声道；核心只给单声道时在回调里复制到左右两路
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        sourceNode = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            guard let ptrL = ablPointer[0].mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            let ptrR = ablPointer.count >= 2
                ? ablPointer[1].mData?.assumingMemoryBound(to: Float.self)
                : nil

            self.lock.lock()
            let capacity = self.ringBuffer.count
            let inputChannels = self.channels
            let volume = self.volume
            var read = self.readPos
            var avail = self.available

            for i in 0..<frames {
                guard avail >= inputChannels else {
                    ptrL[i] = 0
                    ptrR?[i] = 0
                    continue
                }
                let left = Float(self.ringBuffer[read]) / 32768.0
                read = (read + 1) % capacity
                avail -= 1

                var right = left
                if inputChannels == 2 {
                    right = Float(self.ringBuffer[read]) / 32768.0
                    read = (read + 1) % capacity
                    avail -= 1
                }

                ptrL[i] = left * volume
                ptrR?[i] = right * volume
            }

            self.readPos = read
            self.available = avail
            self.lock.unlock()
            return noErr
        }

        engine.attach(sourceNode!)
        engine.connect(sourceNode!, to: engine.mainMixerNode, format: format)

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default,
                                                             options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setPreferredIOBufferDuration(1.0 / 60.0)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isSetup = true
        } catch {
            print("[AudioEngine] 启动失败: \(error)")
        }
    }

    // 模拟器每帧调用，把立体声 PCM 数据写入环形缓冲区
    // count = int16 总数（L+R 交错，偶数）
    func pushSamples(_ samples: UnsafePointer<Int16>, count: Int) {
        guard isSetup, count > 0, !isPaused else { return }
        lock.lock()
        defer { lock.unlock() }

        let capacity = ringBuffer.count
        // 缓冲区快满时丢弃最旧数据（保持低延迟），按整帧对齐
        if available + count > capacity {
            var drop = available + count - capacity
            drop = ((drop + channels - 1) / channels) * channels
            if drop >= capacity {
                writePos = 0
                readPos = 0
                available = 0
            } else {
                readPos = (readPos + drop) % capacity
                available -= drop
            }
        }

        for i in 0..<count {
            ringBuffer[writePos] = samples[i]
            writePos = (writePos + 1) % capacity
        }
        available += count
    }

    func stop() {
        engine.stop()
        if let node = sourceNode {
            engine.detach(node)
        }
        sourceNode = nil
        isSetup = false
        lock.lock()
        writePos  = 0
        readPos   = 0
        available = 0
        lock.unlock()
    }

    // MARK: - F9: 倒带时暂停/恢复音频

    private var isPaused = false

    /// 倒带开始时调用，静音但不停止引擎
    func pause() {
        isPaused = true
        // 清空缓冲区，避免倒带结束后播放残留噪音
        lock.lock()
        writePos  = 0
        readPos   = 0
        available = 0
        lock.unlock()
    }

    /// 倒带结束时调用，恢复正常输出
    func resume() {
        isPaused = false
    }
}
