// SkinDefinition.swift
// 虚拟手柄皮肤定义 — 自有 .retroskin 皮肤包格式（ZIP + info.json）
// 为兼容历史皮肤包，解析时也接受旧格式里的同名资源结构，但界面上只出现 .retroskin。

import UIKit

// MARK: - 皮肤 JSON 结构（对应 .retroskin 内的 info.json）

struct SkinDefinition: Codable {
    let name: String
    let identifier: String
    /// 适用平台标识，如 "retroemu.system.gba"、"gba"
    let systemIdentifier: String
    let debug: Bool?
    let representations: SkinRepresentations

    enum CodingKeys: String, CodingKey {
        case name, identifier, debug, representations
        case systemIdentifier
        /// 早期皮肤包使用的同义键，静默兼容
        case legacySystemIdentifier = "gameTypeIdentifier"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        identifier = try c.decode(String.self, forKey: .identifier)
        debug = try c.decodeIfPresent(Bool.self, forKey: .debug)
        representations = try c.decode(SkinRepresentations.self, forKey: .representations)

        if let value = try c.decodeIfPresent(String.self, forKey: .systemIdentifier) {
            systemIdentifier = value
        } else {
            systemIdentifier = try c.decode(String.self, forKey: .legacySystemIdentifier)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(identifier, forKey: .identifier)
        try c.encode(systemIdentifier, forKey: .systemIdentifier)
        try c.encodeIfPresent(debug, forKey: .debug)
        try c.encode(representations, forKey: .representations)
    }

    // MARK: - 平台标识解析

    /// 把任意写法（含历史皮肤包里的标识）解析成内置平台
    static func system(for identifier: String) -> EmulatorSystem? {
        let s = identifier.lowercased()

        if s.contains("gba") || s.contains("advance") { return .gba }
        if s.contains("gbc") || s.contains("color")      { return .gbc }
        if s.contains("snes") || s.contains("super")     { return .snes }
        if s.contains("nds") || s.contains("ds")         { return .nds }
        if s.contains("n64")                             { return .n64 }
        if s.contains("psp")                             { return .psp }
        if s.contains("ps1") || s.contains("playstation") { return .ps1 }
        if s.contains("genesis") || s.contains("megadrive")
            || s.hasSuffix(".md") || s.hasSuffix("md")   { return .md }
        if s.contains("gamegear") || s.hasSuffix("gg")   { return .gg }
        if s.contains("mastersystem") || s.hasSuffix("sms") { return .sms }
        if s.contains("nes") || s.contains("famicom")    { return .nes }
        if s.contains("32x")                             { return .sega32x }
        if s.contains("segacd") || s.contains("mega-cd") { return .segaCD }
        return nil
    }
}

struct SkinRepresentations: Codable {
    let iphone: SkinOrientations?
    let ipad: SkinOrientations?
}

struct SkinOrientations: Codable {
    let portrait: SkinLayout?
    let landscape: SkinLayout?
}

struct SkinLayout: Codable {
    let assets: SkinAssets
    let items: [SkinItem]
    let gameScreenFrame: SkinFrame?
    let extendedEdges: SkinEdges?
}

struct SkinAssets: Codable {
    let resizable: String?   // 可拉伸背景图文件名
    let small: String?       // 小尺寸背景图
    let medium: String?      // 中尺寸背景图
    let large: String?       // 大尺寸背景图
}

struct SkinItem: Codable {
    let inputs: SkinInputs
    let frame: SkinFrame
    let extendedEdges: SkinEdges?
}

struct SkinInputs: Codable {
    // 可以是单个字符串或字符串数组
    private let _inputs: InputValue

    enum InputValue: Codable {
        case single(String)
        case multiple([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .single(str)
            } else {
                self = .multiple(try container.decode([String].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let s):   try container.encode(s)
            case .multiple(let a): try container.encode(a)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        _inputs = try container.decode(InputValue.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(_inputs)
    }

    var inputNames: [String] {
        switch _inputs {
        case .single(let s):   return [s]
        case .multiple(let a): return a
        }
    }

    /// 把皮肤里的按键名映射到 GamepadSlot
    var gamepadSlots: [GamepadSlot] {
        inputNames.compactMap { name in
            switch name.lowercased() {
            case "a":      return .btnA
            case "b":      return .btnB
            case "x":      return .btnX
            case "y":      return .btnY
            case "start":  return .btnStart
            case "select": return .btnSelect
            case "up":     return .dpadUp
            case "down":   return .dpadDown
            case "left":   return .dpadLeft
            case "right":  return .dpadRight
            default:       return nil
            }
        }
    }
}

struct SkinFrame: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct SkinEdges: Codable {
    let top: CGFloat?
    let bottom: CGFloat?
    let left: CGFloat?
    let right: CGFloat?
}

// MARK: - 已安装皮肤的元数据

struct InstalledSkin: Codable, Identifiable {
    let id: String          // = SkinDefinition.identifier
    let name: String
    let system: String      // EmulatorSystem.rawValue
    let fileName: String    // 皮肤包文件名（存储在 Documents/Skins/）
    let previewImageName: String?  // 预览图文件名
}
