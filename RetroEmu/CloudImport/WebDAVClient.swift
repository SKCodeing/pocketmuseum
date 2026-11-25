// WebDAVClient.swift
// WebDAV 客户端实现
// F3: 云导入 - WebDAV 协议支持
//
// 支持：Nextcloud / ownCloud / NAS（群晖/威联通）/ 任意 WebDAV 服务器

import Foundation
import Security

final class WebDAVClient: CloudProvider {

    // MARK: - 配置

    struct Config: Codable {
        var serverURL: String   // 例：https://cloud.example.com/remote.php/dav/files/user/
        var username: String
        var password: String    // 存储在 Keychain，此处仅用于传输
        var basePath: String    // 根路径，默认 "/"
    }

    private(set) var config: Config
    private let session: URLSession
    private var activeTasks: [URLSessionTask] = []
    private let taskLock = NSLock()

    var displayName: String { "WebDAV (\(config.serverURL))" }
    var isConnected: Bool { _isConnected }
    private var _isConnected = false

    // MARK: - Keychain Key

    private static let keychainService = "com.retroemu.webdav"

    // MARK: - Init

    init(config: Config) {
        self.config = config
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 30
        cfg.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 持久化（Keychain）

    static func savedConfig() -> Config? {
        guard let data = KeychainHelper.load(service: keychainService, account: "config"),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return config
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            KeychainHelper.save(data, service: Self.keychainService, account: "config")
        }
    }

    static func deleteConfig() {
        KeychainHelper.delete(service: keychainService, account: "config")
    }

    // MARK: - 连接测试

    func testConnection(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = baseURL() else {
            completion(.failure(CloudError.invalidURL))
            return
        }
        var req = propfindRequest(url: url, depth: "0")
        req.timeoutInterval = 10
        let task = session.dataTask(with: req) { [weak self] _, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CloudError.parseError))
                return
            }
            if http.statusCode == 207 || http.statusCode == 200 {
                self?._isConnected = true
                completion(.success(()))
            } else if http.statusCode == 401 {
                completion(.failure(CloudError.authFailed))
            } else {
                completion(.failure(CloudError.serverError(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))))
            }
        }
        task.resume()
    }

    // MARK: - CloudProvider: 列目录

    func listDirectory(path: String, completion: @escaping (Result<[CloudEntry], Error>) -> Void) {
        guard let url = url(for: path) else {
            completion(.failure(CloudError.invalidURL))
            return
        }
        let req = propfindRequest(url: url, depth: "1")
        let task = session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(CloudError.parseError))
                return
            }
            guard http.statusCode == 207, let data = data else {
                completion(.failure(CloudError.serverError(http.statusCode, "")))
                return
            }
            do {
                let entries = try self.parseMultiStatus(data: data, basePath: path)
                completion(.success(entries))
            } catch {
                completion(.failure(error))
            }
        }
        addTask(task)
        task.resume()
    }

    // MARK: - CloudProvider: 下载文件

    func downloadFile(entry: CloudEntry,
                      progress: @escaping (Double) -> Void,
                      completion: @escaping (Result<URL, Error>) -> Void) {
        guard let url = url(for: entry.path) else {
            completion(.failure(CloudError.invalidURL))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addAuthHeader(to: &req)

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((entry.name as NSString).pathExtension)

        let delegate = DownloadProgressDelegate(
            expectedSize: entry.size,
            progressHandler: progress,
            completionHandler: { result in
                switch result {
                case .success(let location):
                    do {
                        if FileManager.default.fileExists(atPath: tmpURL.path) {
                            try FileManager.default.removeItem(at: tmpURL)
                        }
                        try FileManager.default.moveItem(at: location, to: tmpURL)
                        completion(.success(tmpURL))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        )

        let downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = downloadSession.downloadTask(with: req)
        addTask(task)
        task.resume()
    }

    func cancelAll() {
        taskLock.lock()
        activeTasks.forEach { $0.cancel() }
        activeTasks.removeAll()
        taskLock.unlock()
    }

    // MARK: - 私有工具

    private func baseURL() -> URL? {
        var urlStr = config.serverURL
        if !urlStr.hasSuffix("/") { urlStr += "/" }
        return URL(string: urlStr)
    }

    private func url(for path: String) -> URL? {
        guard let base = baseURL() else { return nil }
        let clean = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent(clean)
    }

    private func propfindRequest(url: URL, depth: String) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "PROPFIND"
        req.setValue(depth, forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <D:propfind xmlns:D="DAV:">
          <D:prop>
            <D:displayname/>
            <D:getcontentlength/>
            <D:getlastmodified/>
            <D:resourcetype/>
          </D:prop>
        </D:propfind>
        """.data(using: .utf8)
        addAuthHeader(to: &req)
        return req
    }

    private func addAuthHeader(to req: inout URLRequest) {
        let credentials = "\(config.username):\(config.password)"
        if let data = credentials.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            req.setValue("Basic \(base64)", forHTTPHeaderField: "Authorization")
        }
    }

    private func addTask(_ task: URLSessionTask) {
        taskLock.lock()
        activeTasks.append(task)
        taskLock.unlock()
    }

    // MARK: - XML 解析（WebDAV PROPFIND 响应）

    private func parseMultiStatus(data: Data, basePath: String) throws -> [CloudEntry] {
        let parser = WebDAVXMLParser(data: data)
        let responses = try parser.parse()

        // 过滤掉当前目录自身（第一条通常是自身）
        return responses.dropFirst().compactMap { resp -> CloudEntry? in
            guard let href = resp["href"] else { return nil }
            let name = (href as NSString).lastPathComponent.removingPercentEncoding ?? href
            guard !name.isEmpty else { return nil }
            let isDir = resp["resourcetype"]?.contains("collection") == true
            let size = Int64(resp["getcontentlength"] ?? "") ?? -1
            let dateStr = resp["getlastmodified"] ?? ""
            let date = Self.rfc1123Formatter.date(from: dateStr)
            return CloudEntry(
                name: name,
                path: href.removingPercentEncoding ?? href,
                type: isDir ? .directory : .file,
                size: size,
                modifiedDate: date
            )
        }
    }

    private static let rfc1123Formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()
}

// MARK: - 简单 WebDAV XML 解析器

private final class WebDAVXMLParser: NSObject, XMLParserDelegate {

    private let data: Data
    private var responses: [[String: String]] = []
    private var current: [String: String] = [:]
    private var currentElement = ""
    private var currentText = ""
    private var parseError: Error?

    init(data: Data) { self.data = data }

    func parse() throws -> [[String: String]] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        if let error = parseError { throw error }
        return responses
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName.lowercased()
            .replacingOccurrences(of: "d:", with: "")
            .replacingOccurrences(of: "dav:", with: "")
        currentText = ""
        if currentElement == "response" { current = [:] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let el = elementName.lowercased()
            .replacingOccurrences(of: "d:", with: "")
            .replacingOccurrences(of: "dav:", with: "")
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "href":               current["href"] = text
        case "getcontentlength":   current["getcontentlength"] = text
        case "getlastmodified":    current["getlastmodified"] = text
        case "collection":         current["resourcetype"] = "collection"
        case "displayname":        if !text.isEmpty { current["displayname"] = text }
        case "response":           if !current.isEmpty { responses.append(current) }
        default: break
        }
        currentText = ""
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - 下载进度代理

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    private let expectedSize: Int64
    private let progressHandler: (Double) -> Void
    private let completionHandler: (Result<URL, Error>) -> Void

    init(expectedSize: Int64,
         progressHandler: @escaping (Double) -> Void,
         completionHandler: @escaping (Result<URL, Error>) -> Void) {
        self.expectedSize = expectedSize
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        DispatchQueue.main.async { self.progressHandler(progress) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        completionHandler(.success(location))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                completionHandler(.failure(CloudError.cancelled))
            } else {
                completionHandler(.failure(error))
            }
        }
    }
}

// MARK: - Keychain 工具

enum KeychainHelper {
    static func save(_ data: Data, service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
        var addQuery = query
        addQuery[kSecValueData] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(service: String, account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      service,
            kSecAttrAccount:      account,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne,
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        return result as? Data
    }

    static func delete(service: String, account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
