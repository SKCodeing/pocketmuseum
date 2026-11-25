// EmuLog.swift
// 模拟器统一日志工具
// 日志同时输出到 Xcode Console（NSLog）和内存环形缓冲区（供 UI 展示）

import Foundation
import os.log

enum EmuLog {

    // MARK: - 日志级别
    enum Level: String {
        case debug = "🔍 DEBUG"
        case info  = "ℹ️ INFO "
        case warn  = "⚠️ WARN "
        case error = "❌ ERROR"
    }

    // MARK: - 内存环形缓冲（最近 200 条，供调试界面展示）
    private static let bufferLock = NSLock()
    private static var _buffer: [String] = []
    private static let maxBuffer = 200

    static var recentLogs: [String] {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        return _buffer
    }

    // MARK: - 日志回调（可接入 UI 实时展示）
    static var onLog: ((Level, String) -> Void)?

    // MARK: - 核心日志方法
    static func log(_ level: Level, _ message: String,
                    file: String = #file, function: String = #function, line: Int = #line) {
        let filename = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = logTimestamp()
        let entry = "[\(timestamp)] \(level.rawValue) [\(filename):\(line)] \(message)"

        // 输出到 Xcode Console
        NSLog("%@", entry)

        // 写入环形缓冲
        bufferLock.lock()
        _buffer.append(entry)
        if _buffer.count > maxBuffer { _buffer.removeFirst() }
        bufferLock.unlock()

        // 回调（主线程）
        if let cb = onLog {
            if Thread.isMainThread {
                cb(level, entry)
            } else {
                DispatchQueue.main.async { cb(level, entry) }
            }
        }
    }

    // MARK: - 便捷方法
    static func debug(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, msg, file: file, function: function, line: line)
    }
    static func info(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, msg, file: file, function: function, line: line)
    }
    static func warn(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warn, msg, file: file, function: function, line: line)
    }
    static func error(_ msg: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, msg, file: file, function: function, line: line)
    }

    // MARK: - 导出日志到文件（供用户发送给开发者）
    static func exportToFile() -> URL? {
        let logs = recentLogs.joined(separator: "\n")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("emu_debug_log.txt")
        do {
            try logs.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            NSLog("[EmuLog] 导出失败: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - 清空
    static func clear() {
        bufferLock.lock()
        _buffer.removeAll()
        bufferLock.unlock()
    }

    // MARK: - 私有
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static func logTimestamp() -> String {
        dateFormatter.string(from: Date())
    }
}
