// EmulatorTypes.swift
// 公共类型定义

import Foundation

// 支持的模拟器类型
enum EmulatorSystem: String, CaseIterable {
    case nes     = "NES"
    case gbc     = "GBC"
    case gg      = "GG"
    case sms     = "SMS"
    case md      = "MD"
    case gba     = "GBA"
    case snes    = "SNES"    // Sprint 2
    case nds     = "NDS"     // Sprint 2
    case sega32x = "32X"     // Sprint 6: Sega 32X
    case segaCD  = "MCD"     // Sprint 6: Sega CD / Mega-CD
    case n64     = "N64"     // Sprint 6: Nintendo 64
    case ps1     = "PS1"     // Sprint 6: PlayStation
    case psp     = "PSP"     // Sprint 6: PlayStation Portable

    var fileExtensions: [String] {
        switch self {
        case .nes:     return ["nes", "NES"]
        case .gbc:     return ["gb", "gbc", "GB", "GBC"]
        case .gg:      return ["gg", "GG"]
        case .sms:     return ["sms", "SMS"]
        case .md:      return ["md", "MD", "gen", "GEN"]
        case .gba:     return ["gba", "GBA"]
        case .snes:    return ["sfc", "smc", "SFC", "SMC"]
        case .nds:     return ["nds", "NDS"]
        case .sega32x: return ["32x", "32X"]
        case .segaCD:  return ["cue", "CUE"]          // Sega CD 只用 .cue（需配套 .bin/.iso）
        case .n64:     return ["z64", "Z64", "n64", "N64", "v64", "V64"]
        case .ps1:     return ["bin", "BIN", "pbp", "PBP"]  // PS1 用 .bin/.pbp（.cue 已归 segaCD）
        case .psp:     return ["iso", "ISO", "cso", "CSO"]  // PSP 独占 .iso/.cso
        }
    }

    /// 游戏画面原生分辨率
    var nativeSize: (width: CGFloat, height: CGFloat) {
        switch self {
        case .nes:     return (256, 240)
        case .gbc:     return (160, 144)
        case .gg:      return (160, 144)
        case .sms:     return (256, 192)
        case .md:      return (320, 224)
        case .gba:     return (240, 160)
        case .snes:    return (256, 224)
        case .nds:     return (256, 384)
        case .sega32x: return (320, 224)
        case .segaCD:  return (320, 224)
        case .n64:     return (320, 240)
        case .ps1:     return (320, 240)
        case .psp:     return (480, 272)
        }
    }

    static func system(for ext: String) -> EmulatorSystem? {
        let lowered = ext.lowercased()
        // 优先级明确的扩展名直接返回，避免歧义
        return allCases.first { $0.fileExtensions.contains(lowered) }
    }

    /// 根据文件头魔数辅助判断 ISO 归属（PS1 vs PSP vs Sega CD）
    /// 调用方在 .iso 文件无法通过扩展名唯一确定系统时使用
    static func system(for ext: String, fileHeader: Data?) -> EmulatorSystem? {
        let lowered = ext.lowercased()
        // 对于 .iso，通过文件头区分 PS1 / PSP / Sega CD
        if lowered == "iso", let header = fileHeader, header.count >= 16 {
            // PSP ISO (UDF): 扇区 16 偏移 0x8001 有 "CD001"，但更简单的方法是
            // 检查 PSP 的 PVD 标识或 EBOOT.PBP 特征
            // Sega CD: 前 16 字节含 "SEGADISCSYSTEM"
            let headerBytes = [UInt8](header.prefix(16))
            let segaMarker = "SEGADISCSYSTEM".utf8.map { UInt8($0) }
            if headerBytes.starts(with: segaMarker) {
                return .segaCD
            }
            // PS1 ISO: 系统区域含 "PLAYSTATION" 或 "Sony Computer Entertainment"
            // PSP ISO: 含 "PSP GAME" 或 UDF 结构
            // 默认 .iso 归 PSP（最常见用途）
            let headerStr = String(bytes: headerBytes, encoding: .ascii) ?? ""
            if headerStr.contains("PLAYSTATION") || headerStr.contains("Sony") {
                return .ps1
            }
            return .psp
        }
        return allCases.first { $0.fileExtensions.contains(lowered) }
    }
}

// 模拟器按键位掩码（NES 标准布局，其他系统映射到此）
struct EmulatorButton: OptionSet {
    let rawValue: UInt16
    static let a      = EmulatorButton(rawValue: 1 << 0)
    static let b      = EmulatorButton(rawValue: 1 << 1)
    static let select = EmulatorButton(rawValue: 1 << 2)
    static let start  = EmulatorButton(rawValue: 1 << 3)
    static let up     = EmulatorButton(rawValue: 1 << 4)
    static let down   = EmulatorButton(rawValue: 1 << 5)
    static let left   = EmulatorButton(rawValue: 1 << 6)
    static let right  = EmulatorButton(rawValue: 1 << 7)
}

// 帧缓冲区尺寸
enum FrameSize {
    static let nesWidth   = 256;  static let nesHeight   = 240
    static let gbcWidth   = 160;  static let gbcHeight   = 144
    static let ggWidth    = 160;  static let ggHeight    = 144
    static let smsWidth   = 256;  static let smsHeight   = 192
    static let mdWidth    = 320;  static let mdHeight    = 224
    static let gbaWidth   = 240;  static let gbaHeight   = 160
    static let snesWidth  = 256;  static let snesHeight  = 224
    static let ndsWidth   = 256;  static let ndsHeight   = 384
    static let s32xWidth  = 320;  static let s32xHeight  = 224   // Sprint 6
    static let scdWidth   = 320;  static let scdHeight   = 224   // Sprint 6
    static let n64Width   = 320;  static let n64Height   = 240   // Sprint 6
    static let ps1Width   = 320;  static let ps1Height   = 240   // Sprint 6
    static let pspWidth   = 480;  static let pspHeight   = 272   // Sprint 6
}

// ROM 信息
struct ROMInfo {
    let url: URL
    let name: String
    let system: EmulatorSystem
    let fileSize: Int64
}

// 网络玩家
struct NetworkPlayer {
    let id: String
    let name: String
    var playerIndex: Int  // 0 = P1, 1 = P2
    var isHost: Bool
}

// 快捷操作枚举（F8：自定义快捷键）
enum ShortcutAction: String, CaseIterable, Codable {
    case screenshot        = "shortcut_screenshot"
    case toggleFastForward = "shortcut_fast_forward"
    case quickSave         = "shortcut_quick_save"
    case quickLoad         = "shortcut_quick_load"
    case openMenu          = "shortcut_open_menu"
    case rewind            = "shortcut_rewind"   // F9: 倒带（按住触发，松开停止）

    var displayName: String {
        switch self {
        case .screenshot:        return "截图"
        case .toggleFastForward: return "切换快进"
        case .quickSave:         return "快速存档（槽1）"
        case .quickLoad:         return "快速读档（槽1）"
        case .openMenu:          return "打开菜单"
        case .rewind:            return "倒带（按住）"
        }
    }
}

extension Float {
    /// 返回非零值，否则返回 nil（用于 UserDefaults 默认值处理）
    var nonZero: Float? { self == 0 ? nil : self }
}
