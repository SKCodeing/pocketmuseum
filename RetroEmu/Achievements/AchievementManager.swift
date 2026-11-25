// AchievementManager.swift
// RetroAchievements.org 成就系统
// F7: 成就系统支持
//
// API 文档：https://api.retroachievements.org/
// 使用 RetroAchievements Web API（无需 rcheevos C 库，纯 Swift 实现）

import Foundation

// MARK: - 数据模型

struct RAUser: Codable {
    let username: String
    let apiKey: String
}

struct RAAchievement: Codable, Identifiable {
    let id: Int
    let title: String
    let description: String
    let points: Int
    let badgeName: String
    let numAwarded: Int?
    let numAwardedHardcore: Int?
    var isUnlocked: Bool = false
    var unlockedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case title = "Title"
        case description = "Description"
        case points = "Points"
        case badgeName = "BadgeName"
        case numAwarded = "NumAwarded"
        case numAwardedHardcore = "NumAwardedHardcore"
    }
}

struct RAGameInfo: Codable {
    let id: Int
    let title: String
    let achievements: [String: RAAchievement]?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case title = "Title"
        case achievements = "Achievements"
    }
}

// MARK: - 成就管理器

final class AchievementManager {

    static let shared = AchievementManager()

    private let baseURL = "https://retroachievements.org/API"
    private let session = URLSession.shared

    // 当前登录用户
    private(set) var currentUser: RAUser?

    // 当前游戏的成就列表
    private(set) var currentAchievements: [RAAchievement] = []
    private(set) var currentGameID: Int?

    // 成就解锁回调（供 AchievementOverlayView 使用）
    var onAchievementUnlocked: ((RAAchievement) -> Void)?

    private let userDefaultsKey = "ra_user_v1"

    private init() {
        loadUser()
    }

    // MARK: - 账号管理

    func login(username: String, apiKey: String, completion: @escaping (Result<Void, Error>) -> Void) {
        // 验证 API Key
        let url = apiURL("API_GetUserSummary.php", params: [
            "u": username,
            "y": apiKey,
            "g": "0",
            "a": "0"
        ])
        session.dataTask(with: url) { [weak self] data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["User"] != nil else {
                completion(.failure(AchievementError.authFailed))
                return
            }
            let user = RAUser(username: username, apiKey: apiKey)
            self?.currentUser = user
            self?.saveUser(user)
            completion(.success(()))
        }.resume()
    }

    func logout() {
        currentUser = nil
        currentAchievements = []
        currentGameID = nil
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    var isLoggedIn: Bool { currentUser != nil }

    // MARK: - 加载游戏成就

    /// 根据 ROM MD5 哈希查找游戏并加载成就
    func loadAchievements(romMD5: String, completion: @escaping (Result<[RAAchievement], Error>) -> Void) {
        guard let user = currentUser else {
            completion(.failure(AchievementError.notLoggedIn))
            return
        }
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let achievements = try await self.fetchAchievements(romMD5: romMD5, user: user)
                await MainActor.run { completion(.success(achievements)) }
            } catch {
                await MainActor.run { completion(.failure(error)) }
            }
        }
    }

    private func fetchAchievements(romMD5: String, user: RAUser) async throws -> [RAAchievement] {
        // 1. 通过 MD5 查找游戏
        let hashURL = apiURL("API_GetGameInfoByMD5.php", params: [
            "u": user.username, "y": user.apiKey, "m": romMD5
        ])
        let (hashData, _) = try await session.data(from: hashURL)
        let gameInfo = try JSONDecoder().decode(RAGameInfo.self, from: hashData)
        currentGameID = gameInfo.id

        // 2. 加载用户已解锁的成就
        let unlocked = await fetchUserUnlocks(gameID: gameInfo.id, user: user)
        var achievements: [RAAchievement] = gameInfo.achievements.map { Array($0.values) } ?? []
        for i in achievements.indices {
            achievements[i].isUnlocked = unlocked.contains(achievements[i].id)
        }
        achievements.sort { $0.id < $1.id }
        currentAchievements = achievements
        return achievements
    }

    private func fetchUserUnlocks(gameID: Int, user: RAUser) async -> Set<Int> {
        let url = apiURL("API_GetGameInfoAndUserProgress.php", params: [
            "u": user.username, "y": user.apiKey, "g": "\(gameID)"
        ])
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let achievements = json["Achievements"] as? [String: [String: Any]] else {
            return []
        }
        var unlocked = Set<Int>()
        for (idStr, info) in achievements {
            if let id = Int(idStr),
               let dateEarned = info["DateEarned"] as? String,
               !dateEarned.isEmpty {
                unlocked.insert(id)
            }
        }
        return unlocked
    }

    // MARK: - 成就检测（TD-4：服务器轮询版，每 30 秒检查一次）

    private var pollTimer: DispatchSourceTimer?

    /// 开始轮询（游戏启动后调用）
    func startPolling() {
        guard isLoggedIn, currentGameID != nil else { return }
        stopPolling()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.pollServerForUnlocks() }
        timer.resume()
        pollTimer = timer
    }

    /// 停止轮询（游戏退出后调用）
    func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    private func pollServerForUnlocks() {
        guard let user = currentUser, let gameID = currentGameID else { return }
        Task.detached { [weak self] in
            guard let self = self else { return }
            let unlocked = await self.fetchUserUnlocks(gameID: gameID, user: user)
            for i in self.currentAchievements.indices {
                let ach = self.currentAchievements[i]
                if !ach.isUnlocked && unlocked.contains(ach.id) {
                    self.currentAchievements[i].isUnlocked = true
                    self.currentAchievements[i].unlockedDate = Date()
                    let achievement = self.currentAchievements[i]
                    await MainActor.run {
                        self.onAchievementUnlocked?(achievement)
                    }
                }
            }
        }
    }

    // MARK: - 成就检测（内存轮询，需 rcheevos C 库）

    private var memoryWatchList: [(id: Int, address: UInt32, value: UInt8, condition: MemoryCondition)] = []

    enum MemoryCondition {
        case equals(UInt8)
        case greaterThan(UInt8)
        case changed
    }

    /// 每帧调用，检测成就触发
    func checkAchievements() {
        guard !currentAchievements.isEmpty else { return }
        // 简化实现：通过 EmulatorCore 读取内存，与预设条件比对
        // 完整实现需集成 rcheevos 库
        for _ in memoryWatchList {
            // TODO: 读取内存地址并比对条件
            // let currentValue = EmulatorCore.shared.readByte(at: watch.address)
            // if meetsCondition(currentValue, condition: watch.condition) { ... }
        }
    }

    // MARK: - 手动解锁（用于测试）

    func unlockAchievement(id: Int) {
        guard let idx = currentAchievements.firstIndex(where: { $0.id == id }),
              !currentAchievements[idx].isUnlocked else { return }
        currentAchievements[idx].isUnlocked = true
        currentAchievements[idx].unlockedDate = Date()
        let achievement = currentAchievements[idx]

        DispatchQueue.main.async {
            self.onAchievementUnlocked?(achievement)
        }

        // 提交到 RetroAchievements 服务器
        submitUnlock(achievementID: id)
    }

    private func submitUnlock(achievementID: Int) {
        guard let user = currentUser else { return }
        let url = apiURL("API_AwardAchievement.php", params: [
            "u": user.username,
            "y": user.apiKey,
            "a": "\(achievementID)",
            "h": "0"  // 0 = softcore, 1 = hardcore
        ])
        session.dataTask(with: url) { _, _, _ in }.resume()
    }

    // MARK: - 工具

    private func apiURL(_ endpoint: String, params: [String: String]) -> URL {
        var components = URLComponents(string: "\(baseURL)/\(endpoint)")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    // MARK: - 持久化

    private func loadUser() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let user = try? JSONDecoder().decode(RAUser.self, from: data) else { return }
        currentUser = user
    }

    private func saveUser(_ user: RAUser) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

// MARK: - ROM MD5 计算

import CryptoKit

extension AchievementManager {
    /// 计算 ROM 文件的 MD5（用于 RetroAchievements 游戏识别）
    static func md5(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return data.md5Hex
    }
}

private extension Data {
    var md5Hex: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 错误

enum AchievementError: LocalizedError {
    case notLoggedIn
    case authFailed
    case gameNotFound

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:  return "请先登录 RetroAchievements 账号"
        case .authFailed:   return "API Key 无效，请检查账号设置"
        case .gameNotFound: return "RetroAchievements 数据库中未找到此游戏"
        }
    }
}
