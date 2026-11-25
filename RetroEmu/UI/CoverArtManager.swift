// CoverArtManager.swift
// 游戏封面图管理：本地缓存 + libretro thumbnails 下载
// TD-2: 新增失败重试机制（指数退避，最多 3 次）

import UIKit

final class CoverArtManager {

    static let shared = CoverArtManager()
    private init() { setupCacheDir() }

    // MARK: - 目录

    private var cacheDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("CoverArt", isDirectory: true)
    }

    private func setupCacheDir() {
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 失败记录（TD-2）

    /// key: cacheFilename，value: (失败次数, 最后失败时间)
    private var failureRecord: [String: (count: Int, lastFail: Date)] = [:]
    private let failureLock = NSLock()

    /// 指数退避等待时间（秒）：第1次5s，第2次30s，第3次300s
    private let retryDelays: [TimeInterval] = [5, 30, 300]
    private let maxRetries = 3

    private func canRetry(key: String) -> Bool {
        failureLock.lock()
        defer { failureLock.unlock() }
        guard let record = failureRecord[key] else { return true }
        if record.count >= maxRetries { return false }
        let delay = retryDelays[min(record.count - 1, retryDelays.count - 1)]
        return Date().timeIntervalSince(record.lastFail) >= delay
    }

    private func recordFailure(key: String) {
        failureLock.lock()
        defer { failureLock.unlock() }
        let current = failureRecord[key]
        failureRecord[key] = (count: (current?.count ?? 0) + 1, lastFail: Date())
    }

    private func clearFailure(key: String) {
        failureLock.lock()
        defer { failureLock.unlock() }
        failureRecord.removeValue(forKey: key)
    }

    // MARK: - 读取封面（优先本地缓存）

    func coverArt(for rom: ROMInfo, completion: @escaping (UIImage?) -> Void) {
        let filename = cacheFilename(rom)
        let localURL = cacheDir.appendingPathComponent(filename)

        // 命中本地缓存
        if let data = try? Data(contentsOf: localURL), let img = UIImage(data: data) {
            completion(img)
            return
        }

        // 检查是否允许重试
        guard canRetry(key: filename) else {
            completion(nil)
            return
        }

        downloadCover(for: rom, cacheKey: filename, completion: completion)
    }

    // MARK: - 下载

    private func downloadCover(for rom: ROMInfo, cacheKey: String, completion: @escaping (UIImage?) -> Void) {
        let repoBase = "https://thumbnails.libretro.com"
        let systemFolder = libretroSystemFolder(rom.system)
        let gameName = sanitize(rom.name)
        let urlStr = "\(repoBase)/\(systemFolder)/Named_Boxarts/\(gameName).png"
        guard let url = URL(string: urlStr) else {
            recordFailure(key: cacheKey)
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            // 网络错误或非 200
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, statusCode == 200,
                  let data = data, let img = UIImage(data: data) else {
                self.recordFailure(key: cacheKey)
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // 成功：写入缓存，清除失败记录
            let dest = self.cacheDir.appendingPathComponent(cacheKey)
            try? data.write(to: dest, options: .atomic)
            self.clearFailure(key: cacheKey)
            DispatchQueue.main.async { completion(img) }
        }.resume()
    }

    // MARK: - 辅助

    private func cacheFilename(_ rom: ROMInfo) -> String {
        "\(rom.system.rawValue)_\(sanitize(rom.name)).png"
    }

    private func sanitize(_ name: String) -> String {
        var result = name
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_()"))
        result = result.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
        while result.contains("__") { result = result.replacingOccurrences(of: "__", with: "_") }
        return result.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? result
    }

    private func libretroSystemFolder(_ system: EmulatorSystem) -> String {
        switch system {
        case .nes:     return "Nintendo%20-%20Nintendo%20Entertainment%20System"
        case .gbc:     return "Nintendo%20-%20Game%20Boy%20Color"
        case .gg:      return "Sega%20-%20Game%20Gear"
        case .sms:     return "Sega%20-%20Master%20System%20-%20Mark%20III"
        case .md:      return "Sega%20-%20Mega%20Drive%20-%20Genesis"
        case .gba:     return "Nintendo%20-%20Game%20Boy%20Advance"
        case .snes:    return "Nintendo%20-%20Super%20Nintendo%20Entertainment%20System"
        case .nds:     return "Nintendo%20-%20Nintendo%20DS"
        case .sega32x: return "Sega%20-%2032X"
        case .segaCD:  return "Sega%20-%20Mega-CD"
        case .n64:     return "Nintendo%20-%20Nintendo%2064"
        case .ps1:     return "Sony%20-%20PlayStation"
        case .psp:     return "Sony%20-%20PlayStation%20Portable"
        }
    }

    /// 清除所有封面缓存（同时重置失败记录）
    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
        setupCacheDir()
        failureLock.lock()
        failureRecord.removeAll()
        failureLock.unlock()
    }
}
