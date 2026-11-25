// CloudProviderProtocol.swift
// 云存储提供商统一协议
// F3: 云导入支持

import Foundation

/// 云端文件/目录条目
struct CloudEntry {
    enum EntryType { case file, directory }
    let name: String
    let path: String        // 服务器上的完整路径
    let type: EntryType
    let size: Int64         // 文件大小（字节），目录为 -1
    let modifiedDate: Date?

    var isDirectory: Bool { type == .directory }
    var isROM: Bool {
        guard type == .file else { return false }
        let ext = (name as NSString).pathExtension.lowercased()
        return EmulatorSystem.allCases.flatMap { $0.fileExtensions }.contains(ext)
            || ext == "zip"
    }
}

/// 云存储提供商协议
protocol CloudProvider: AnyObject {
    var displayName: String { get }
    var isConnected: Bool { get }

    /// 列出指定路径下的文件和目录
    func listDirectory(path: String, completion: @escaping (Result<[CloudEntry], Error>) -> Void)

    /// 下载文件到本地临时目录，返回本地 URL
    func downloadFile(entry: CloudEntry,
                      progress: @escaping (Double) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void)

    /// 取消所有进行中的请求
    func cancelAll()
}

enum CloudError: LocalizedError {
    case notConnected
    case invalidURL
    case authFailed
    case serverError(Int, String)
    case parseError
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:        return "未连接到服务器"
        case .invalidURL:          return "服务器地址无效"
        case .authFailed:          return "认证失败，请检查用户名和密码"
        case .serverError(let c, let m): return "服务器错误 \(c): \(m)"
        case .parseError:          return "响应解析失败"
        case .cancelled:           return "已取消"
        }
    }
}
