// AccessionStore.swift
// 馆藏登记簿：每张卡带的入藏编号、入藏日期与藏品笔记。
// 编号一次生成就固定下来，之后改名、换目录都不会变——它认的是文件名。

import Foundation

struct AccessionRecord: Codable {
    var romName: String
    var number: String
    var date: Date
    var note: String
}

final class AccessionStore {

    static let shared = AccessionStore()

    private var records: [String: AccessionRecord] = [:]
    private let fileName = "accessions.json"

    private init() { load() }

    // MARK: - 查询

    func record(for romName: String) -> AccessionRecord? {
        records[romName]
    }

    /// 取入藏记录，没有就当场登记一条。第一次打开展签时调用。
    @discardableResult
    func ensureRecord(for romName: String) -> AccessionRecord {
        if let existing = records[romName] { return existing }

        let record = AccessionRecord(romName: romName,
                                     number: nextNumber(),
                                     date: Date(),
                                     note: "")
        records[romName] = record
        save()
        return record
    }

    func updateNote(_ note: String, for romName: String) {
        guard var record = records[romName] else { return }
        record.note = note
        records[romName] = record
        save()
    }

    /// 删卡带时一并注销，免得编号被回收后跟新卡带撞号
    func remove(romName: String) {
        records.removeValue(forKey: romName)
        save()
    }

    var count: Int { records.count }

    // MARK: - 编号

    /// PM-26-0001：年份后两位 + 当年流水号
    private func nextNumber() -> String {
        let year = Calendar.current.component(.year, from: Date()) % 100
        let prefix = String(format: "PM-%02d-", year)
        let used = records.values
            .filter { $0.number.hasPrefix(prefix) }
            .compactMap { Int($0.number.dropFirst(prefix.count)) }
        let next = (used.max() ?? 0) + 1
        return prefix + String(format: "%04d", next)
    }

    // MARK: - 持久化

    private var storeURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Museum", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(fileName)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([String: AccessionRecord].self, from: data) else { return }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
