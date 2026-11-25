// CheatManager.swift
// 作弊码管理：支持 Game Genie (NES/GBC) 和 GameShark/Pro Action Replay 格式

import Foundation

// MARK: - 作弊码类型
enum CheatType: String, Codable, CaseIterable {
    case gameGenie    = "Game Genie"
    case gameShark    = "GameShark"
    case rawAddress   = "Raw (ADDR:VAL)"
}

// MARK: - 单条作弊码
struct CheatCode: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var code: String        // 原始输入字符串
    var type: CheatType
    var enabled: Bool = true

    // 解析后的内存补丁 (address, value)
    var patches: [(address: UInt32, value: UInt8)] {
        CheatDecoder.decode(code: code, type: type)
    }
}

// MARK: - 作弊码管理器
final class CheatManager {

    static let shared = CheatManager()
    private let key = "cheats_v1"

    // romName → [CheatCode]
    private var store: [String: [CheatCode]] = [:]

    private init() { load() }

    // MARK: - CRUD

    func cheats(for romName: String) -> [CheatCode] {
        store[romName] ?? []
    }

    func add(_ cheat: CheatCode, for romName: String) {
        store[romName, default: []].append(cheat)
        save()
    }

    func update(_ cheat: CheatCode, for romName: String) {
        guard var list = store[romName],
              let idx = list.firstIndex(where: { $0.id == cheat.id }) else { return }
        list[idx] = cheat
        store[romName] = list
        save()
    }

    func delete(id: UUID, for romName: String) {
        store[romName]?.removeAll { $0.id == id }
        save()
    }

    func toggleEnabled(id: UUID, for romName: String) {
        guard var list = store[romName],
              let idx = list.firstIndex(where: { $0.id == id }) else { return }
        list[idx].enabled.toggle()
        store[romName] = list
        save()
        applyActive(for: romName)
    }

    // MARK: - 应用到模拟器

    /// 每帧调用，把启用的作弊码写入内存
    func applyActive(for romName: String) {
        let active = cheats(for: romName).filter { $0.enabled }
        for cheat in active {
            for patch in cheat.patches {
                EmulatorCore.shared.writeByte(patch.value, at: patch.address)
            }
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: [CheatCode]].self, from: data)
        else { return }
        store = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - 作弊码解码器
enum CheatDecoder {

    static func decode(code: String, type: CheatType) -> [(address: UInt32, value: UInt8)] {
        let clean = code.uppercased().replacingOccurrences(of: " ", with: "")
        switch type {
        case .gameGenie:    return decodeGameGenie(clean)
        case .gameShark:    return decodeGameShark(clean)
        case .rawAddress:   return decodeRaw(clean)
        }
    }

    // Game Genie NES: AAAA-BB 或 AAAA-BB-CC (6/8字符)
    // 简化：直接解析 hex address:value
    private static func decodeGameGenie(_ code: String) -> [(address: UInt32, value: UInt8)] {
        // 格式 XXXXXX (6位) 或 XXXXXXXX (8位)
        let hex = code.replacingOccurrences(of: "-", with: "")
        guard hex.count >= 6 else { return [] }
        // 取前6位：AAAAAV（4位地址+2位值）
        let addrStr = String(hex.prefix(4))
        let valStr  = String(hex.dropFirst(4).prefix(2))
        guard let addr = UInt32(addrStr, radix: 16),
              let val  = UInt8(valStr,  radix: 16) else { return [] }
        return [(address: addr, value: val)]
    }

    // GameShark: XXXXXXXX YYYY (地址+值)
    private static func decodeGameShark(_ code: String) -> [(address: UInt32, value: UInt8)] {
        let parts = code.components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }
        guard parts.count >= 2,
              let addr = UInt32(parts[0], radix: 16),
              let val  = UInt8(parts[1].suffix(2), radix: 16) else { return [] }
        return [(address: addr, value: val)]
    }

    // Raw: ADDR:VAL 或 ADDR=VAL
    private static func decodeRaw(_ code: String) -> [(address: UInt32, value: UInt8)] {
        let sep = code.contains(":") ? ":" : "="
        let parts = code.components(separatedBy: sep)
        guard parts.count == 2,
              let addr = UInt32(parts[0], radix: 16),
              let val  = UInt8(parts[1],  radix: 16) else { return [] }
        return [(address: addr, value: val)]
    }
}
