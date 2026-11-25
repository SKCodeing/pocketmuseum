// SaveStateManager.swift
// 存档/读档管理
// - 手动存档：无限槽位（列表形式）
// - 自动存档：最多保留 50 条，循环覆盖
// 支持 iCloud Drive 同步（需在 Capabilities 开启 iCloud Documents）

import Foundation

// 自动存档条目
struct AutoSaveEntry: Codable, Identifiable {
    let id: String          // UUID
    let romName: String
    let timestamp: Date
    let stateFileName: String
    let thumbFileName: String

    static func make(romName: String) -> AutoSaveEntry {
        let id = UUID().uuidString
        let safe = romName.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined()
        return AutoSaveEntry(
            id: id,
            romName: romName,
            timestamp: Date(),
            stateFileName: "\(safe)_auto_\(id).state",
            thumbFileName: "\(safe)_auto_\(id)_thumb.jpg"
        )
    }
}

final class SaveStateManager {

    static let shared = SaveStateManager()

    /// 自动存档最大保留条数
    static let maxAutoSaves = 50

    /// 手动存档槽位数量。存档选择页和展签的统计都读这里，别各写一份。
    static let manualSlotCount = 4

    private init() {
        setupiCloudObserver()
    }

    // MARK: - 目录

    // 路径解析比想象中贵：iCloud 容器查找会同步问系统，createDirectory 也是一次 syscall，
    // 而首屏统计/时光页会对每个 ROM 反复问路径（几百个 ROM × 5 次）。所以统一缓存下来，
    // iCloud 账号变化时再失效重算。
    private var cachedLocalSavesDir: URL?
    private var cachediCloudSavesDir: URL?
    private var didResolveiCloudDir = false

    // 本地存档目录（Documents/SaveStates/）
    private var localSavesDir: URL {
        if let cached = cachedLocalSavesDir { return cached }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("SaveStates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cachedLocalSavesDir = dir
        return dir
    }

    // 自动存档目录（Documents/SaveStates/Auto/<romName>/）
    // 读的时候不能建目录，否则一次统计会给几百个 ROM 各建一个空文件夹
    private func autoSavesDir(romName: String, create: Bool = false) -> URL {
        let safe = romName.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined()
        let dir = localSavesDir
            .appendingPathComponent("Auto", isDirectory: true)
            .appendingPathComponent(safe, isDirectory: true)
        if create {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // 自动存档索引文件路径
    private func autoSaveIndexURL(romName: String) -> URL {
        autoSavesDir(romName: romName).appendingPathComponent("index.json")
    }

    // iCloud 存档目录（iCloud Drive/RetroEmu/SaveStates/）
    private var iCloudSavesDir: URL? {
        if didResolveiCloudDir { return cachediCloudSavesDir }
        didResolveiCloudDir = true
        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) else { return nil }
        let dir = container.appendingPathComponent("Documents/SaveStates", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cachediCloudSavesDir = dir
        return dir
    }

    var iCloudAvailable: Bool { iCloudSavesDir != nil }

    // 当前使用的目录（优先 iCloud）
    private var savesDir: URL {
        iCloudSavesDir ?? localSavesDir
    }

    // MARK: - 自动存档（F1）

    /// 触发一次自动存档，保留最近 maxAutoSaves 条
    func autoSave(stateData: Data, romName: String, jpegData: Data?) {
        let entry = AutoSaveEntry.make(romName: romName)
        let dir = autoSavesDir(romName: romName, create: true)

        // 写入 state 文件
        let stateURL = dir.appendingPathComponent(entry.stateFileName)
        try? stateData.write(to: stateURL, options: .atomic)

        // 写入缩略图
        if let jpeg = jpegData {
            let thumbURL = dir.appendingPathComponent(entry.thumbFileName)
            try? jpeg.write(to: thumbURL, options: .atomic)
        }

        // 更新索引
        var entries = loadAutoSaveIndex(romName: romName)
        entries.insert(entry, at: 0)

        // 超出上限时删除最旧的
        while entries.count > SaveStateManager.maxAutoSaves {
            let old = entries.removeLast()
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(old.stateFileName))
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(old.thumbFileName))
        }

        saveAutoSaveIndex(entries, romName: romName)
    }

    /// 读取自动存档列表（按时间倒序）
    func autoSaveEntries(romName: String) -> [AutoSaveEntry] {
        loadAutoSaveIndex(romName: romName)
    }

    /// 读取自动存档 state 数据
    func loadAutoSave(entry: AutoSaveEntry) -> Data? {
        let url = autoSavesDir(romName: entry.romName).appendingPathComponent(entry.stateFileName)
        return try? Data(contentsOf: url)
    }

    /// 读取自动存档缩略图数据
    func loadAutoSaveThumb(entry: AutoSaveEntry) -> Data? {
        let url = autoSavesDir(romName: entry.romName).appendingPathComponent(entry.thumbFileName)
        return try? Data(contentsOf: url)
    }

    /// 删除单条自动存档
    func deleteAutoSave(entry: AutoSaveEntry) {
        let dir = autoSavesDir(romName: entry.romName)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.stateFileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(entry.thumbFileName))
        var entries = loadAutoSaveIndex(romName: entry.romName)
        entries.removeAll { $0.id == entry.id }
        saveAutoSaveIndex(entries, romName: entry.romName)
    }

    // MARK: - 自动存档索引持久化

    private func loadAutoSaveIndex(romName: String) -> [AutoSaveEntry] {
        let url = autoSaveIndexURL(romName: romName)
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([AutoSaveEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private func saveAutoSaveIndex(_ entries: [AutoSaveEntry], romName: String) {
        // 写之前把目录建好（读路径故意不建目录）
        let url = autoSavesDir(romName: romName, create: true).appendingPathComponent("index.json")
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - 手动存档/读档（无限槽位）

    func save(data: Data, romName: String, slot: Int) throws {
        let url = slotURL(romName: romName, slot: slot)
        try data.write(to: url, options: .atomic)
        // 同时写本地备份（iCloud 可能延迟）
        if iCloudSavesDir != nil {
            let localURL = localSlotURL(romName: romName, slot: slot)
            try? data.write(to: localURL, options: .atomic)
        }
    }

    func load(romName: String, slot: Int) throws -> Data {
        // 优先读 iCloud，fallback 本地
        let url = slotURL(romName: romName, slot: slot)
        if FileManager.default.fileExists(atPath: url.path) {
            return try Data(contentsOf: url)
        }
        let localURL = localSlotURL(romName: romName, slot: slot)
        return try Data(contentsOf: localURL)
    }

    func hasSave(romName: String, slot: Int) -> Bool {
        FileManager.default.fileExists(atPath: slotURL(romName: romName, slot: slot).path) ||
        FileManager.default.fileExists(atPath: localSlotURL(romName: romName, slot: slot).path)
    }

    func deleteSave(romName: String, slot: Int) throws {
        for url in [slotURL(romName: romName, slot: slot),
                    localSlotURL(romName: romName, slot: slot)] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - 存档截图（纯 Data，不依赖 UIKit）

    func saveScreenshotData(_ jpegData: Data, romName: String, slot: Int) {
        let url = thumbURL(romName: romName, slot: slot)
        try? jpegData.write(to: url, options: [.atomic])
    }

    func loadScreenshotData(romName: String, slot: Int) -> Data? {
        let url = thumbURL(romName: romName, slot: slot)
        return try? Data(contentsOf: url)
    }

    private func thumbURL(romName: String, slot: Int) -> URL {
        let name = slotFileName(romName: romName, slot: slot)
            .replacingOccurrences(of: ".sav", with: "_thumb.jpg")
        return localSavesDir.appendingPathComponent(name)
    }

    func saveDate(romName: String, slot: Int) -> Date? {
        let urls = [slotURL(romName: romName, slot: slot),
                    localSlotURL(romName: romName, slot: slot)]
        return urls.compactMap {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }.max()
    }

    // MARK: - iCloud 手动同步

    /// 把本地存档上传到 iCloud
    func uploadToiCloud(romName: String, completion: @escaping (Int) -> Void) {
        guard let cloudDir = iCloudSavesDir else { completion(0); return }
        var count = 0
        for slot in 0..<4 {
            let local = localSlotURL(romName: romName, slot: slot)
            guard FileManager.default.fileExists(atPath: local.path),
                  let data = try? Data(contentsOf: local) else { continue }
            let cloud = cloudDir.appendingPathComponent(slotFileName(romName: romName, slot: slot))
            try? data.write(to: cloud, options: .atomic)
            count += 1
        }
        completion(count)
    }

    /// 把 iCloud 存档下载到本地
    func downloadFromiCloud(romName: String, completion: @escaping (Int) -> Void) {
        guard let cloudDir = iCloudSavesDir else { completion(0); return }
        var count = 0
        for slot in 0..<4 {
            let cloud = cloudDir.appendingPathComponent(slotFileName(romName: romName, slot: slot))
            guard FileManager.default.fileExists(atPath: cloud.path),
                  let data = try? Data(contentsOf: cloud) else { continue }
            let local = localSlotURL(romName: romName, slot: slot)
            try? data.write(to: local, options: .atomic)
            count += 1
        }
        completion(count)
    }

    // MARK: - iCloud 变更监听

    private func setupiCloudObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        // 切 iCloud 账号后容器路径会变，缓存的目录得重算
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudIdentityDidChange),
            name: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }

    @objc private func iCloudIdentityDidChange() {
        cachediCloudSavesDir = nil
        didResolveiCloudDir = false
    }

    @objc private func iCloudDidChange(_ note: Notification) {
        NotificationCenter.default.post(name: .saveStateDidSyncFromiCloud, object: nil)
    }

    // MARK: - 路径工具

    private func slotFileName(romName: String, slot: Int) -> String {
        let safe = romName.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined()
        return "\(safe)_slot\(slot).sav"
    }

    private func slotURL(romName: String, slot: Int) -> URL {
        savesDir.appendingPathComponent(slotFileName(romName: romName, slot: slot))
    }

    private func localSlotURL(romName: String, slot: Int) -> URL {
        localSavesDir.appendingPathComponent(slotFileName(romName: romName, slot: slot))
    }
}

extension Notification.Name {
    static let saveStateDidSyncFromiCloud = Notification.Name("saveStateDidSyncFromiCloud")
}

// MARK: - 导出/导入存档

extension SaveStateManager {

    /// 把指定 ROM 的所有存档打包为 ZIP，返回临时文件 URL
    func exportSaves(romName: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
        let zipURL = tmpDir.appendingPathComponent("\(sanitize(romName))_saves.zip")

        // 收集所有存档文件
        var files: [(name: String, data: Data)] = []
        for slot in 0..<4 {
            let savURL = localSlotURL(romName: romName, slot: slot)
            if let data = try? Data(contentsOf: savURL) {
                files.append((slotFileName(romName: romName, slot: slot), data))
            }
            let thumbURL = self.thumbURL(romName: romName, slot: slot)
            if let data = try? Data(contentsOf: thumbURL) {
                files.append((thumbURL.lastPathComponent, data))
            }
        }

        guard !files.isEmpty else {
            throw SaveExportError.noSavesFound
        }

        let zipData = try buildZip(files: files)
        try zipData.write(to: zipURL, options: .atomic)
        return zipURL
    }

    /// 从 ZIP 导入存档（覆盖本地）
    func importSaves(from zipURL: URL, romName: String) throws -> Int {
        let data = try Data(contentsOf: zipURL)
        let entries = try ZipExtractor.listEntries(zipURL: zipURL)
        var count = 0
        for entry in entries {
            let fileData = try ZipExtractor.extractEntryData(entry: entry, from: data)
            let dest = localSavesDir.appendingPathComponent(entry.filename.lastPathComponent)
            try fileData.write(to: dest, options: .atomic)
            count += 1
        }
        return count
    }

    // MARK: - 简单 ZIP 构建（Store 模式，无压缩）
    private func buildZip(files: [(name: String, data: Data)]) throws -> Data {
        var zip = Data()
        var centralDir = Data()
        var offsets: [UInt32] = []

        for file in files {
            let nameData = file.name.data(using: .utf8) ?? Data()
            let offset = UInt32(zip.count)
            offsets.append(offset)

            // Local file header
            zip.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // signature
            zip.appendLE16(20)       // version needed
            zip.appendLE16(0)        // flags
            zip.appendLE16(0)        // compression: store
            zip.appendLE16(0)        // mod time
            zip.appendLE16(0)        // mod date
            zip.appendLE32(crc32(file.data))
            zip.appendLE32(UInt32(file.data.count))
            zip.appendLE32(UInt32(file.data.count))
            zip.appendLE16(UInt16(nameData.count))
            zip.appendLE16(0)        // extra length
            zip.append(nameData)
            zip.append(file.data)

            // Central directory entry
            centralDir.append(contentsOf: [0x50, 0x4B, 0x01, 0x02])
            centralDir.appendLE16(20); centralDir.appendLE16(20)
            centralDir.appendLE16(0); centralDir.appendLE16(0)
            centralDir.appendLE16(0); centralDir.appendLE16(0); centralDir.appendLE16(0)
            centralDir.appendLE32(crc32(file.data))
            centralDir.appendLE32(UInt32(file.data.count))
            centralDir.appendLE32(UInt32(file.data.count))
            centralDir.appendLE16(UInt16(nameData.count))
            centralDir.appendLE16(0); centralDir.appendLE16(0)
            centralDir.appendLE16(0); centralDir.appendLE16(0)
            centralDir.appendLE32(0)
            centralDir.appendLE32(offset)
            centralDir.append(nameData)
        }

        let cdOffset = UInt32(zip.count)
        zip.append(centralDir)

        // End of central directory
        zip.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        zip.appendLE16(0); zip.appendLE16(0)
        zip.appendLE16(UInt16(files.count))
        zip.appendLE16(UInt16(files.count))
        zip.appendLE32(UInt32(centralDir.count))
        zip.appendLE32(cdOffset)
        zip.appendLE16(0)

        return zip
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    private func sanitize(_ name: String) -> String {
        name.components(separatedBy: .init(charactersIn: "/\\:*?\"<>|")).joined(separator: "_")
    }
}

enum SaveExportError: LocalizedError {
    case noSavesFound
    var errorDescription: String? { "该游戏没有任何存档" }
}

private extension Data {
    mutating func appendLE16(_ v: UInt16) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8(v >> 8)])
    }
    mutating func appendLE32(_ v: UInt32) {
        append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
                             UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }
}

private extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
}
