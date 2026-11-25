// SkinManager.swift
// 手柄皮肤包（.retroskin）的安装、解析与缓存

import UIKit

final class SkinManager {

    static let shared = SkinManager()

    // MARK: - 目录

    private var skinsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Skins", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private let indexKey = "installed_skins_v1"

    // MARK: - 已安装皮肤列表

    private(set) var installedSkins: [InstalledSkin] = []

    private init() {
        loadIndex()
        installBuiltinSkinsIfNeeded()
    }

    // MARK: - 安装皮肤（.retroskin 皮肤包）

    /// 皮肤包统一后缀；历史皮肤包后缀仅用于静默兼容，不在界面暴露
    static let skinExtension = "retroskin"
    /// 只保留本 App 自己的旧后缀。其他 App 的皮肤包后缀不要加回来：
    /// 它会以字符串常量的形式留在二进制里，和「自有皮肤格式」的对外说明冲突。
    private static let legacyExtensions: Set<String> = ["retroemuskin"]

    /// 从 URL 安装皮肤
    func installSkin(from url: URL, completion: @escaping (Result<InstalledSkin, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                let skin = try self.parseSkin(from: url)
                // 复制到 Skins 目录
                let dest = self.skinsDir.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)

                // 更新索引
                self.installedSkins.removeAll { $0.id == skin.id }
                self.installedSkins.append(skin)
                self.saveIndex()

                DispatchQueue.main.async { completion(.success(skin)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// 删除皮肤
    func deleteSkin(_ skin: InstalledSkin) {
        let url = skinsDir.appendingPathComponent(skin.fileName)
        try? FileManager.default.removeItem(at: url)
        installedSkins.removeAll { $0.id == skin.id }
        saveIndex()
    }

    // MARK: - 加载皮肤资源

    /// 加载指定皮肤的布局（用于 GamepadView 渲染）
    func loadLayout(skin: InstalledSkin, system: EmulatorSystem, portrait: Bool) -> SkinLayout? {
        let url = skinsDir.appendingPathComponent(skin.fileName)
        guard let def = try? parseSkinDefinition(from: url) else { return nil }
        let reps = def.representations
        let orientations = reps.iphone  // 优先 iPhone
        return portrait ? orientations?.portrait : orientations?.landscape
    }

    /// 加载皮肤背景图
    func loadBackgroundImage(skin: InstalledSkin, layout: SkinLayout, portrait: Bool) -> UIImage? {
        let url = skinsDir.appendingPathComponent(skin.fileName)
        // 优先 resizable，其次 large/medium/small
        let assetName = layout.assets.resizable
            ?? layout.assets.large
            ?? layout.assets.medium
            ?? layout.assets.small
        guard let name = assetName else { return nil }
        return loadImageFromSkin(url: url, imageName: name)
    }

    /// 加载皮肤预览图
    func loadPreviewImage(skin: InstalledSkin) -> UIImage? {
        guard let name = skin.previewImageName else { return nil }
        let url = skinsDir.appendingPathComponent(skin.fileName)
        return loadImageFromSkin(url: url, imageName: name)
    }

    // MARK: - 当前激活皮肤

    private let activeSkinKey = "active_skin_id"

    func activeSkin(for system: EmulatorSystem) -> InstalledSkin? {
        let key = "\(activeSkinKey)_\(system.rawValue)"
        guard let id = UserDefaults.standard.string(forKey: key) else { return nil }
        return installedSkins.first { $0.id == id }
    }

    func setActiveSkin(_ skin: InstalledSkin?, for system: EmulatorSystem) {
        let key = "\(activeSkinKey)_\(system.rawValue)"
        UserDefaults.standard.set(skin?.id, forKey: key)
        NotificationCenter.default.post(name: .skinDidChange, object: system)
    }

    // MARK: - 内置皮肤

    private func installBuiltinSkinsIfNeeded() {
        // 内置皮肤打包在 App Bundle 中，优先 .retroskin
        let builtins = ["RetroClassic", "RetroGray"]
        for name in builtins {
            let candidates = ["\(name).\(Self.skinExtension)"]
                + Self.legacyExtensions.map { "\(name).\($0)" }

            for fileName in candidates {
                guard let url = Bundle.main.url(forResource: (fileName as NSString).deletingPathExtension,
                                                withExtension: (fileName as NSString).pathExtension),
                      !FileManager.default.fileExists(atPath: skinsDir.appendingPathComponent(fileName).path)
                else { continue }

                let dest = skinsDir.appendingPathComponent(fileName)
                guard (try? FileManager.default.copyItem(at: url, to: dest)) != nil,
                      let skin = try? parseSkin(from: dest) else { continue }
                installedSkins.removeAll { $0.id == skin.id }
                installedSkins.append(skin)
                break
            }
        }
        saveIndex()
    }

    // MARK: - 私有工具

    private func parseSkin(from url: URL) throws -> InstalledSkin {
        let def = try parseSkinDefinition(from: url)
        let system = SkinDefinition.system(for: def.systemIdentifier)?.rawValue ?? "unknown"
        return InstalledSkin(
            id: def.identifier,
            name: def.name,
            system: system,
            fileName: url.lastPathComponent,
            previewImageName: "preview.png"
        )
    }

    private func parseSkinDefinition(from url: URL) throws -> SkinDefinition {
        // 皮肤包是 ZIP：读取其中的 info.json
        let entries = try ZipExtractor.listEntries(zipURL: url)
        guard let infoEntry = entries.first(where: { $0.filename.hasSuffix("info.json") }) else {
            throw SkinError.missingInfoJSON
        }
        let zipData = try Data(contentsOf: url)
        let jsonData = try ZipExtractor.extractEntryData(entry: infoEntry, from: zipData)
        return try JSONDecoder().decode(SkinDefinition.self, from: jsonData)
    }

    private func loadImageFromSkin(url: URL, imageName: String) -> UIImage? {
        guard let entries = try? ZipExtractor.listEntries(zipURL: url),
              let entry = entries.first(where: { $0.filename.hasSuffix(imageName) }),
              let zipData = try? Data(contentsOf: url),
              let imgData = try? ZipExtractor.extractEntryData(entry: entry, from: zipData) else {
            return nil
        }
        return UIImage(data: imgData)
    }

    // MARK: - 索引持久化

    private func loadIndex() {
        guard let data = UserDefaults.standard.data(forKey: indexKey),
              let skins = try? JSONDecoder().decode([InstalledSkin].self, from: data) else { return }
        installedSkins = skins
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(installedSkins) {
            UserDefaults.standard.set(data, forKey: indexKey)
        }
    }
}

enum SkinError: LocalizedError {
    case missingInfoJSON
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .missingInfoJSON: return L10n.str("skin.err.missinginfo")
        case .invalidFormat:   return L10n.str("skin.err.invalid")
        }
    }
}

extension Notification.Name {
    static let skinDidChange = Notification.Name("skinDidChange")
}
