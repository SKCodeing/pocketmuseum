// ROMMetadata.swift
// 展签用的卡带档案：从文件头读出平台与容量，再算一枚入藏指纹。
// 全部离线解析，不联网、不依赖第三方库；读不出来的字段一律给 nil，
// 展签上就少一行，不会编造。

import Foundation

struct ROMMetadata {

    /// 文件头认出的格式名，认不出时为空
    let format: String?
    /// 卡带内的映射方式 / 卡带类型，例如 "Mapper 0" 或 "MBC5 + RAM + 电池"
    let board: String?
    /// 程序区与图形区大小（字节）
    let prgSize: Int?
    let chrSize: Int?
    /// 入藏指纹：文件前若干字节的 CRC32
    let fingerprint: String
    let fingerprintedBytes: Int
    /// 入藏时间：取文件创建时间，取不到退回修改时间
    let installedAt: Date?

    var installedText: String {
        guard let date = installedAt else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.str("meta.dateLocale"))
        f.dateFormat = L10n.str("meta.dateFormat")
        return f.string(from: date)
    }

    /// 指纹说明：大文件只取了前面一段，展签上要写清楚，别让人以为算的是整份
    var fingerprintNote: String? {
        guard fingerprintedBytes > 0 else { return nil }
        if fingerprintedBytes >= 8 * 1024 * 1024 {
            return L10n.str("meta.fingerprint.partial")
        }
        return nil
    }

    // MARK: - 读取

    /// 同步读文件头 + 算指纹。调用方请放到后台队列，别卡住主线程。
    static func read(url: URL, system: EmulatorSystem) -> ROMMetadata {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let installed = (attrs?[.creationDate] as? Date) ?? (attrs?[.modificationDate] as? Date)

        // 指纹只覆盖前 8 MB：PSP 的 ISO 上 GB，全量扫一遍没必要
        let limit = Int(min(size, 8 * 1024 * 1024))
        let (crc, scanned) = fingerprint(of: url, limit: limit)

        guard let head = readHead(url: url, count: 0x8000) else {
            return ROMMetadata(format: nil, board: nil, prgSize: nil, chrSize: nil,
                               fingerprint: crc, fingerprintedBytes: scanned, installedAt: installed)
        }

        var format: String?
        var board: String?
        var prg: Int?
        var chr: Int?

        switch system {
        case .nes:
            if head.count >= 16, head[0] == 0x4E, head[1] == 0x45, head[2] == 0x53, head[3] == 0x1A {
                format = (head[7] & 0x0C) == 0x08 ? "NES 2.0" : "iNES"
                prg = Int(head[4]) * 16_384
                chr = Int(head[5]) * 8_192
                // NES 2.0 把 mapper 的高 4 位挪到了第 8 字节
                var mapper = Int(head[6] >> 4) | Int(head[7] & 0xF0)
                if (head[7] & 0x0C) == 0x08 {
                    mapper |= Int(head[8] & 0x0F) << 8
                }
                board = L10n.str("meta.nes.mapper", mapper)
            }

        case .gbc:
            if head.count >= 0x150 {
                format = "Game Boy"
                let cart = head[0x147]
                board = gbCartName(cart)
                let romCode = Int(head[0x148])
                if romCode <= 8 {
                    prg = 32_768 << romCode
                }
                chr = prg   // GB 的图形和程序同在一片 ROM 里
            }

        case .gba:
            if head.count >= 0xC0 {
                format = "GBA Cartridge"
                let title = ascii(head, from: 0xA0, count: 12)
                if !title.isEmpty { board = title }
                let code = ascii(head, from: 0xAC, count: 4)
                if !code.isEmpty { format = "GBA · \(code)" }
                prg = Int(size)
                chr = prg
            }

        case .snes:
            if head.count >= 0x8000 {
                format = "SNES Cartridge"
                let title = ascii(head, from: 0x7FC0, count: 21)
                if !title.isEmpty { board = title }
                prg = Int(size)
                chr = prg
            }

        case .md, .sega32x, .segaCD:
            if head.count > 0x110, ascii(head, from: 0x100, count: 4) == "SEGA" {
                format = "Sega Mega Drive"
                let title = ascii(head, from: 0x120, count: 48)
                if !title.isEmpty { board = title }
            }

        default:
            break
        }

        return ROMMetadata(format: format, board: board, prgSize: prg, chrSize: chr,
                           fingerprint: crc, fingerprintedBytes: scanned, installedAt: installed)
    }

    // MARK: - 工具

    private static func readHead(url: URL, count: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: count)
    }

    private static func ascii(_ data: Data, from offset: Int, count: Int) -> String {
        guard data.count >= offset + count else { return "" }
        let slice = data[offset..<(offset + count)]
        let bytes = slice.prefix { $0 != 0 }
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func gbCartName(_ code: UInt8) -> String {
        switch code {
        case 0x00:              return "ROM only"
        case 0x01...0x03:       return "MBC1"
        case 0x05, 0x06:        return "MBC2"
        case 0x0F...0x13:       return "MBC3"
        case 0x19...0x1E:       return "MBC5"
        case 0x20:              return "MBC6"
        case 0x22:              return "MBC7"
        default:                return "Cartridge"
        }
    }

    /// CRC32（IEEE），查表实现：8 MB 大约几十毫秒
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    private static func fingerprint(of url: URL, limit: Int) -> (String, Int) {
        guard limit > 0, let handle = try? FileHandle(forReadingFrom: url) else { return ("—", 0) }
        defer { try? handle.close() }

        var crc: UInt32 = 0xFFFF_FFFF
        var scanned = 0
        while scanned < limit {
            let want = min(1 << 20, limit - scanned)
            guard let chunk = try? handle.read(upToCount: want), !chunk.isEmpty else { break }
            chunk.withUnsafeBytes { raw in
                for byte in raw.bindMemory(to: UInt8.self) {
                    crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
                }
            }
            scanned += chunk.count
        }
        return (String(format: "%08X", crc ^ 0xFFFF_FFFF), scanned)
    }
}
