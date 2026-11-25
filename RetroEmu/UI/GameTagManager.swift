// GameTagManager.swift
// 游戏自定义分组/标签管理
// F11: 游戏分组/标签

import Foundation

// MARK: - 数据模型

struct GameTag: Codable, Identifiable, Equatable {
    let id: String          // UUID
    var name: String
    var emoji: String       // 标签图标，如 "✅" "🎮" "⏳"
    var romNames: [String]  // 属于此标签的 ROM 名称列表（有序）

    static func make(name: String, emoji: String = "🏷") -> GameTag {
        GameTag(id: UUID().uuidString, name: name, emoji: emoji, romNames: [])
    }
}

// MARK: - 内置标签

extension GameTag {
    static let builtinIDs = ["builtin_done", "builtin_playing", "builtin_todo"]

    static var builtins: [GameTag] = [
        GameTag(id: "builtin_done",    name: "通关了",  emoji: "✅", romNames: []),
        GameTag(id: "builtin_playing", name: "进行中",  emoji: "🎮", romNames: []),
        GameTag(id: "builtin_todo",    name: "待玩",    emoji: "⏳", romNames: []),
    ]
}

// MARK: - 管理器

final class GameTagManager {

    static let shared = GameTagManager()
    private let key = "game_tags_v1"
    private let orderKey = "game_custom_order_v1"

    private(set) var tags: [GameTag] = []

    /// 自定义排序：romName -> 排序索引（仅在「全部」Tab 生效）
    private var customOrder: [String: Int] = [:]

    private init() {
        load()
        if tags.isEmpty {
            // 首次启动，写入内置标签
            tags = GameTag.builtins
            save()
        }
    }

    // MARK: - 标签 CRUD

    func createTag(name: String, emoji: String = "🏷") -> GameTag {
        let tag = GameTag.make(name: name, emoji: emoji)
        tags.append(tag)
        save()
        return tag
    }

    func updateTag(_ tag: GameTag) {
        if let i = tags.firstIndex(where: { $0.id == tag.id }) {
            tags[i] = tag
            save()
        }
    }

    func deleteTag(id: String) {
        guard !GameTag.builtinIDs.contains(id) else { return }  // 内置标签不可删除
        tags.removeAll { $0.id == id }
        save()
    }

    // MARK: - ROM ↔ 标签

    func addROM(_ romName: String, to tagID: String) {
        guard let i = tags.firstIndex(where: { $0.id == tagID }) else { return }
        if !tags[i].romNames.contains(romName) {
            tags[i].romNames.append(romName)
            save()
        }
    }

    func removeROM(_ romName: String, from tagID: String) {
        guard let i = tags.firstIndex(where: { $0.id == tagID }) else { return }
        tags[i].romNames.removeAll { $0 == romName }
        save()
    }

    func toggleROM(_ romName: String, in tagID: String) {
        guard let i = tags.firstIndex(where: { $0.id == tagID }) else { return }
        if tags[i].romNames.contains(romName) {
            tags[i].romNames.removeAll { $0 == romName }
        } else {
            tags[i].romNames.append(romName)
        }
        save()
    }

    /// 返回某 ROM 所属的所有标签
    func tags(for romName: String) -> [GameTag] {
        tags.filter { $0.romNames.contains(romName) }
    }

    /// 返回某标签下的 ROM 名称列表
    func romNames(in tagID: String) -> [String] {
        tags.first(where: { $0.id == tagID })?.romNames ?? []
    }

    // MARK: - 自定义排序（拖拽）

    func setOrder(_ romNames: [String]) {
        customOrder = Dictionary(uniqueKeysWithValues: romNames.enumerated().map { ($1, $0) })
        UserDefaults.standard.set(customOrder, forKey: orderKey)
    }

    func sortedByCustomOrder(_ roms: [ROMInfo]) -> [ROMInfo] {
        roms.sorted {
            let a = customOrder[$0.name] ?? Int.max
            let b = customOrder[$1.name] ?? Int.max
            return a < b
        }
    }

    // MARK: - 持久化

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([GameTag].self, from: data) {
            tags = decoded
        }
        customOrder = UserDefaults.standard.dictionary(forKey: orderKey) as? [String: Int] ?? [:]
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
