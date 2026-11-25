// ZipExtractor.swift
// 解压 ZIP 文件，支持逐条提取和进度回调

import Foundation
import zlib
import CoreFoundation

enum ZipError: Error {
    case invalidFormat
    case unsupportedCompression
    case decompressionFailed
    case noROMFound
}

struct ZipEntry {
    let filename: String
    let compressedSize: Int
    let uncompressedSize: Int
    let compressionMethod: UInt16
    let dataOffset: Int
}

final class ZipExtractor {

    static let romExtensions: Set<String> = [
        "nes", "gb", "gbc", "gg", "sms", "md", "bin", "gen", "gba"
    ]

    static func isROM(_ entry: ZipEntry) -> Bool {
        let ext = (entry.filename as NSString).pathExtension.lowercased()
        return romExtensions.contains(ext)
            && !entry.filename.hasPrefix("__MACOSX")
            && !entry.filename.contains("/.") // 跳过隐藏文件
    }

    // MARK: - 列出所有条目

    static func listEntries(zipURL: URL) throws -> [ZipEntry] {
        let data = try Data(contentsOf: zipURL)
        return try parseEntries(data: data)
    }

    // MARK: - 提取单个条目

    static func extractEntry(_ entry: ZipEntry, from zipURL: URL, to destDir: URL) throws -> URL {
        let data = try Data(contentsOf: zipURL)
        let filename = (entry.filename as NSString).lastPathComponent
        let destURL = destDir.appendingPathComponent(filename)
        let fileData = try extractEntryData(entry: entry, from: data)
        try fileData.write(to: destURL, options: .atomic)
        return destURL
    }

    // MARK: - 一次性解压所有 ROM（兼容旧接口）

    static func extract(zipURL: URL, to destDir: URL) throws -> [URL] {
        let data = try Data(contentsOf: zipURL)
        let entries = try parseEntries(data: data)
        let romEntries = entries.filter { isROM($0) }
        guard !romEntries.isEmpty else { throw ZipError.noROMFound }

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        var results: [URL] = []
        for entry in romEntries {
            let filename = (entry.filename as NSString).lastPathComponent
            let destURL = destDir.appendingPathComponent(filename)
            let fileData = try extractEntryData(entry: entry, from: data)
            try fileData.write(to: destURL, options: .atomic)
            results.append(destURL)
        }
        return results
    }

    // MARK: - ZIP 解析

    private static func parseEntries(data: Data) throws -> [ZipEntry] {
        var entries: [ZipEntry] = []
        var offset = 0

        while offset + 30 <= data.count {
            let sig = data.readUInt32LE(at: offset)
            guard sig == 0x04034b50 else { break }

            let compression    = data.readUInt16LE(at: offset + 8)
            let generalFlag    = data.readUInt16LE(at: offset + 6)
            let compressedSize   = Int(data.readUInt32LE(at: offset + 18))
            let uncompressedSize = Int(data.readUInt32LE(at: offset + 22))
            let filenameLen    = Int(data.readUInt16LE(at: offset + 26))
            let extraLen       = Int(data.readUInt16LE(at: offset + 28))

            guard offset + 30 + filenameLen <= data.count else { break }
            let filenameData = data[offset + 30 ..< offset + 30 + filenameLen]

            // bit 11 = Language encoding flag，置位表示 UTF-8
            let isUTF8 = (generalFlag & 0x0800) != 0
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(0x0632))
            let filename: String
            if isUTF8 {
                filename = String(data: filenameData, encoding: .utf8) ?? "unknown_\(offset)"
            } else {
                filename = String(data: filenameData, encoding: .utf8)
                        ?? String(data: filenameData, encoding: gb18030)
                        ?? String(data: filenameData, encoding: .shiftJIS)
                        ?? String(data: filenameData, encoding: .isoLatin1)
                        ?? "unknown_\(offset)"
            }

            let dataOffset = offset + 30 + filenameLen + extraLen

            // 跳过目录条目
            if !filename.hasSuffix("/") {
                entries.append(ZipEntry(
                    filename: filename,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    compressionMethod: compression,
                    dataOffset: dataOffset
                ))
            }

            offset = dataOffset + compressedSize
        }

        return entries
    }

    static func extractEntryData(entry: ZipEntry, from data: Data) throws -> Data {
        guard entry.dataOffset + entry.compressedSize <= data.count else {
            throw ZipError.invalidFormat
        }
        let compressedData = data[entry.dataOffset ..< entry.dataOffset + entry.compressedSize]

        switch entry.compressionMethod {
        case 0:
            return Data(compressedData)
        case 8:
            return try inflate(data: Data(compressedData), expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression
        }
    }

    // MARK: - Deflate 解压

    private static func inflate(data: Data, expectedSize: Int) throws -> Data {
        let bufferSize = max(expectedSize, data.count * 4, 65536)
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var stream = z_stream()
        let initResult = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initResult == Z_OK else { throw ZipError.decompressionFailed }
        defer { inflateEnd(&stream) }

        stream.next_out  = buffer
        stream.avail_out = uInt(bufferSize)

        let inflateResult = data.withUnsafeBytes { (inputPtr: UnsafeRawBufferPointer) -> Int32 in
            stream.next_in  = UnsafeMutablePointer(mutating: inputPtr.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(data.count)
            return zlib.inflate(&stream, Z_FINISH)
        }

        guard inflateResult == Z_STREAM_END || inflateResult == Z_OK else {
            throw ZipError.decompressionFailed
        }

        return Data(bytes: buffer, count: Int(stream.total_out))
    }
}

// MARK: - Data 读取工具
private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }
    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
             | (UInt32(self[offset + 1]) << 8)
             | (UInt32(self[offset + 2]) << 16)
             | (UInt32(self[offset + 3]) << 24)
    }
}
