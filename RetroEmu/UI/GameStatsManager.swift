// GameStatsManager.swift
// 游戏时长统计 + 最近游玩 + 收藏管理

import Foundation
import WidgetKit

struct GameStats: Codable {
    var totalSeconds: Double = 0
    var lastPlayedDate: Date?
    var isFavorite: Bool = false
    /// 开箱次数与其中最长的一次
    var sessions: Int = 0
    var longestSession: Double = 0
    /// 按天累计的游玩秒数，键为 yyyy-MM-dd。年度回顾靠它算「最勤的一天」「最忙的月份」。
    var dailySeconds: [String: Double] = [:]

    init() {}

    /// 手写解码：老版本存下的 JSON 没有后三个字段，不能因此整份丢弃
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try container.decodeIfPresent(Double.self, forKey: .totalSeconds) ?? 0
        lastPlayedDate = try container.decodeIfPresent(Date.self, forKey: .lastPlayedDate)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
        longestSession = try container.decodeIfPresent(Double.self, forKey: .longestSession) ?? 0
        dailySeconds = try container.decodeIfPresent([String: Double].self, forKey: .dailySeconds) ?? [:]
    }
}

final class GameStatsManager {

    static let shared = GameStatsManager()
    private let key = "game_stats_v1"
    private var store: [String: GameStats] = [:]

    // 当前正在计时的 ROM
    private var currentROM: String?
    private var sessionStart: Date?

    private init() { load() }

    // MARK: - 会话计时

    func beginSession(romName: String) {
        currentROM = romName
        sessionStart = Date()
        var stats = store[romName] ?? GameStats()
        stats.lastPlayedDate = Date()
        store[romName] = stats
        save()
        syncToAppGroup()  // F13: 同步到 Widget
    }

    func endSession() {
        guard let rom = currentROM, let start = sessionStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        var stats = store[rom] ?? GameStats()
        stats.totalSeconds += elapsed
        // 一闪而过的启动（导入后立刻退出）不计入开箱次数
        if elapsed >= 1 {
            stats.sessions += 1
            stats.longestSession = max(stats.longestSession, elapsed)
            stats.dailySeconds[Self.dayKey(Date()), default: 0] += elapsed
        }
        store[rom] = stats
        currentROM = nil
        sessionStart = nil
        save()
    }

    /// 当天键，固定用公历与 POSIX 格式，避免不同地区设置算出不同的键
    static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 全部统计快照，供年度回顾聚合
    func allStats() -> [String: GameStats] {
        store
    }

    // MARK: - 收藏

    func toggleFavorite(romName: String) {
        store[romName, default: GameStats()].isFavorite.toggle()
        save()
    }

    func isFavorite(_ romName: String) -> Bool {
        store[romName]?.isFavorite ?? false
    }

    // MARK: - 查询

    func stats(for romName: String) -> GameStats {
        store[romName] ?? GameStats()
    }

    /// 最近游玩（按时间倒序）
    func recentlyPlayed(limit: Int = 20) -> [String] {
        store
            .filter { $0.value.lastPlayedDate != nil }
            .sorted { ($0.value.lastPlayedDate ?? .distantPast) > ($1.value.lastPlayedDate ?? .distantPast) }
            .prefix(limit)
            .map { $0.key }
    }

    /// 收藏列表
    func favorites() -> [String] {
        store.filter { $0.value.isFavorite }.map { $0.key }
    }

    /// 格式化游玩时长
    func formattedPlayTime(romName: String) -> String {
        let secs = Int(store[romName]?.totalSeconds ?? 0)
        if secs < 60 { return L10n.str("stats.time.seconds", secs) }
        let mins = secs / 60
        if mins < 60 { return L10n.str("stats.time.minutes", mins) }
        return L10n.str("stats.time.hours", mins / 60, mins % 60)
    }

    // MARK: - 持久化
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: GameStats].self, from: data) else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - F13: 同步最近游玩到 App Group（供 Widget 读取）

    private func syncToAppGroup() {
        guard let defaults = UserDefaults(suiteName: "group.com.retroemu") else { return }
        let recent = recentlyPlayed(limit: 4)
        let entries: [[String: String]] = recent.compactMap { romName in
            guard let rom = ROMLibrary.shared.roms.first(where: { $0.name == romName }) else { return nil }
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let coverPath = docs
                .appendingPathComponent("CoverArt")
                .appendingPathComponent("\(rom.system.rawValue)_\(romName).png")
                .path
            return [
                "id":        romName,
                "name":      romName,
                "system":    rom.system.rawValue,
                "romPath":   rom.url.path,
                "coverPath": FileManager.default.fileExists(atPath: coverPath) ? coverPath : "",
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: entries) {
            defaults.set(data, forKey: "widget_recent_games")
        }
        // 通知 WidgetKit 刷新
        WidgetCenter.shared.reloadAllTimelines()
    }
}
