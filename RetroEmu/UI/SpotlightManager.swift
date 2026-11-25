// SpotlightManager.swift
// Spotlight 搜索集成
// F12: 在 iOS 系统搜索中显示游戏，点击直接启动

import CoreSpotlight
import UIKit

final class SpotlightManager {

    static let shared = SpotlightManager()
    private init() {}

    private let domainIdentifier = "com.retroemu.games"

    // MARK: - 索引更新

    /// 将 ROM 库全量同步到 Spotlight 索引
    func indexAll(_ roms: [ROMInfo]) {
        let items = roms.map { makeSearchableItem(for: $0) }
        CSSearchableIndex.default().indexSearchableItems(items) { error in
            if let error = error {
                print("[Spotlight] 索引失败: \(error.localizedDescription)")
            }
        }
    }

    /// 新增单个 ROM 到索引
    func index(_ rom: ROMInfo) {
        let item = makeSearchableItem(for: rom)
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    /// 从索引删除单个 ROM
    func deindex(_ rom: ROMInfo) {
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [spotlightID(for: rom)]
        ) { _ in }
    }

    /// 清空所有 RetroEmu 的 Spotlight 条目
    func deindexAll() {
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [domainIdentifier]
        ) { _ in }
    }

    // MARK: - 构建 CSSearchableItem

    private func makeSearchableItem(for rom: ROMInfo) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: .item)
        attrs.title = rom.name
        attrs.contentDescription = "\(rom.system.rawValue) · \(ByteCountFormatter.string(fromByteCount: rom.fileSize, countStyle: .file))"
        attrs.keywords = [rom.name, rom.system.rawValue, "retro", "emulator", "game"]

        // 封面图（如果本地有缓存）
        let coverPath = coverCachePath(for: rom)
        if FileManager.default.fileExists(atPath: coverPath) {
            attrs.thumbnailURL = URL(fileURLWithPath: coverPath)
        }

        let item = CSSearchableItem(
            uniqueIdentifier: spotlightID(for: rom),
            domainIdentifier: domainIdentifier,
            attributeSet: attrs
        )
        item.expirationDate = .distantFuture
        return item
    }

    // MARK: - Deep Link 处理

    /// 从 NSUserActivity 解析 ROM 路径并启动游戏
    /// 在 AppDelegate/SceneDelegate 的 continue userActivity 中调用
    static func handleUserActivity(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return false
        }
        // id 格式：com.retroemu.game.<system>.<romName>
        let parts = id.components(separatedBy: ".")
        guard parts.count >= 4 else { return false }
        let romName = parts.dropFirst(3).joined(separator: ".")

        // 在 ROM 库中查找并启动
        if let rom = ROMLibrary.shared.roms.first(where: { $0.name == romName }) {
            NotificationCenter.default.post(name: .spotlightLaunchROM, object: rom)
            return true
        }
        return false
    }

    // MARK: - 工具

    private func spotlightID(for rom: ROMInfo) -> String {
        "com.retroemu.game.\(rom.system.rawValue).\(rom.name)"
    }

    private func coverCachePath(for rom: ROMInfo) -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs
            .appendingPathComponent("CoverArt")
            .appendingPathComponent("\(rom.system.rawValue)_\(rom.name).png")
            .path
    }
}

// MARK: - Notification

extension Notification.Name {
    static let spotlightLaunchROM = Notification.Name("spotlightLaunchROM")
}
