// ROMLibrary.swift
// ROM 文件管理，扫描 Documents 目录

import Foundation

final class ROMLibrary {

    static let shared = ROMLibrary()
    private(set) var roms: [ROMInfo] = []

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 对外暴露 ROM 存储目录（供 SceneDelegate 使用）
    var romsDirectory: URL { documentsURL }

    private init() {}

    /// 把内置的原创示例卡带放进 Documents。
    /// App Store 版首次启动就能在机柜里看到内容，审核员不必自己去找 ROM。
    /// 用 UserDefaults 记住已投放：用户主动删掉之后不再塞回来。
    private func seedBundledDemo() {
        let flag = "didSeedBundledDemoROM"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: flag) else { return }
        guard let src = Bundle.main.url(forResource: "PocketMuseumDemo", withExtension: "nes") else {
            NSLog("[RetroEmu] bundle 里没有内置示例卡带")
            return
        }

        let dest = documentsURL.appendingPathComponent(src.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: src, to: dest)
            } catch {
                NSLog("[RetroEmu] 内置示例卡带复制失败：%@", error.localizedDescription)
                return                      // 不置标记，下次扫描再试
            }
        }
        defaults.set(true, forKey: flag)
    }

    // 扫描 Documents 目录下所有支持的 ROM（递归）
    func scan() {
        seedBundledDemo()
        let fm = FileManager.default
        let allExts = Set(EmulatorSystem.allCases.flatMap { $0.fileExtensions })

        var found: [ROMInfo] = []
        let enumerator = fm.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let ext = url.pathExtension.lowercased()
            guard allExts.contains(ext) else { continue }

            // 对 .iso 文件读取文件头以精确识别系统
            let system: EmulatorSystem?
            if ext == "iso" {
                let header = (try? FileHandle(forReadingFrom: url)).flatMap { fh -> Data? in
                    let data = fh.readData(ofLength: 16)
                    fh.closeFile()
                    return data.isEmpty ? nil : data
                }
                system = EmulatorSystem.system(for: ext, fileHeader: header)
            } else {
                system = EmulatorSystem.system(for: ext)
            }
            guard let system = system else { continue }

            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            found.append(ROMInfo(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                system: system,
                fileSize: Int64(size)
            ))
        }
        roms = found.sorted { $0.name < $1.name }
        // 只在主线程发通知，避免重入
        if Thread.isMainThread {
            NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .romLibraryDidUpdate, object: nil)
            }
        }
    }

    // 将 ROM 复制到 Documents，支持 .zip 自动解压
    func importROM(from sourceURL: URL) throws {
        if sourceURL.pathExtension.lowercased() == "zip" {
            try importZip(from: sourceURL)
        } else {
            let dest = documentsURL.appendingPathComponent(sourceURL.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            scan()
        }
    }

    // 解压 zip，提取 ROM，删除 zip
    func importZip(from zipURL: URL) throws {
        let extracted = try ZipExtractor.extract(zipURL: zipURL, to: documentsURL)
        // 如果 zip 在 Documents 里，解压完删掉
        if zipURL.deletingLastPathComponent().standardized == documentsURL.standardized {
            try? FileManager.default.removeItem(at: zipURL)
        }
        if extracted.isEmpty { throw ZipError.noROMFound }
        scan()
    }

    func deleteROM(_ rom: ROMInfo) throws {
        try FileManager.default.removeItem(at: rom.url)
        scan()
    }
}

extension Notification.Name {
    static let romLibraryDidUpdate = Notification.Name("romLibraryDidUpdate")
}
