// KeymapSettings.swift
// 按键重映射配置，持久化到 UserDefaults

import Foundation

// 虚拟手柄上的物理位置槽位
enum GamepadSlot: String, CaseIterable, Codable {
    case dpadUp    = "dpad_up"
    case dpadDown  = "dpad_down"
    case dpadLeft  = "dpad_left"
    case dpadRight = "dpad_right"
    case btnA      = "btn_a"
    case btnB      = "btn_b"
    case btnX      = "btn_x"   // 可选第三键
    case btnY      = "btn_y"   // 可选第四键
    case btnStart  = "btn_start"
    case btnSelect = "btn_select"

    var displayName: String {
        switch self {
        case .dpadUp:    return "↑"
        case .dpadDown:  return "↓"
        case .dpadLeft:  return "←"
        case .dpadRight: return "→"
        case .btnA:      return "A"
        case .btnB:      return "B"
        case .btnX:      return "X"
        case .btnY:      return "Y"
        case .btnStart:  return "START"
        case .btnSelect: return "SEL"
        }
    }
}

// 默认映射：槽位 → EmulatorButton
private let defaultMap: [GamepadSlot: EmulatorButton] = [
    .dpadUp:    .up,
    .dpadDown:  .down,
    .dpadLeft:  .left,
    .dpadRight: .right,
    .btnA:      .a,
    .btnB:      .b,
    .btnX:      .b,      // 默认 X 也映射到 B
    .btnY:      .a,      // 默认 Y 也映射到 A
    .btnStart:  .start,
    .btnSelect: .select,
]

final class KeymapSettings {

    static let shared = KeymapSettings()
    private let key = "keymap_v1"

    // slot → EmulatorButton rawValue
    private var map: [String: UInt16] = [:]

    private init() { load() }

    // MARK: - 读写

    func button(for slot: GamepadSlot) -> EmulatorButton {
        if let raw = map[slot.rawValue] {
            return EmulatorButton(rawValue: raw)
        }
        return defaultMap[slot] ?? []
    }

    func setButton(_ button: EmulatorButton, for slot: GamepadSlot) {
        map[slot.rawValue] = button.rawValue
        save()
    }

    func reset() {
        map = [:]
        save()
    }

    // MARK: - 持久化

    private func load() {
        guard let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: UInt16] else { return }
        map = saved
    }

    private func save() {
        UserDefaults.standard.set(map, forKey: key)
    }

    // MARK: - 工具

    // 把 GamepadSlot 的按下状态转换为 EmulatorButton 集合
    func translate(pressedSlots: Set<GamepadSlot>) -> EmulatorButton {
        var result: EmulatorButton = []
        for slot in pressedSlots {
            result.insert(button(for: slot))
        }
        return result
    }

    // 所有可映射的目标按键（用于 UI 选择）
    static let mappableButtons: [(label: String, button: EmulatorButton)] = [
        ("A",      .a),
        ("B",      .b),
        ("Start",  .start),
        ("Select", .select),
        ("↑",      .up),
        ("↓",      .down),
        ("←",      .left),
        ("→",      .right),
        ("无",     []),
    ]
}

// MARK: - 快捷键绑定（F8）

/// 手柄快捷键绑定：将 ShortcutAction 绑定到一个 GamepadSlot（可选）
final class ShortcutKeymap {

    static let shared = ShortcutKeymap()
    private let key = "shortcut_keymap_v1"

    // ShortcutAction.rawValue → GamepadSlot.rawValue
    private var map: [String: String] = [:]

    private init() { load() }

    // MARK: - 读写

    func slot(for action: ShortcutAction) -> GamepadSlot? {
        guard let raw = map[action.rawValue] else { return nil }
        return GamepadSlot(rawValue: raw)
    }

    func setSlot(_ slot: GamepadSlot?, for action: ShortcutAction) {
        if let slot = slot {
            map[action.rawValue] = slot.rawValue
        } else {
            map.removeValue(forKey: action.rawValue)
        }
        save()
    }

    func reset() {
        map = [:]
        save()
    }

    /// 根据当前按下的槽位集合，返回触发的快捷操作列表
    func triggeredActions(for pressedSlots: Set<GamepadSlot>) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { action in
            guard let bound = slot(for: action) else { return false }
            return pressedSlots.contains(bound)
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let saved = UserDefaults.standard.dictionary(forKey: key) as? [String: String] else { return }
        map = saved
    }

    private func save() {
        UserDefaults.standard.set(map, forKey: key)
    }
}
