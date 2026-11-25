// MuseumReport.swift
// 年度回顾的数据侧：把散落在三处的记录（游玩时长、入藏登记、存档）汇成一份年报。
// 只统计真实存在的记录，没有数据的格子就少一行字——不编数字。

import Foundation

struct MuseumReport {

    let year: Int
    /// 馆藏总数与今年新入藏数
    let shelfCount: Int
    let accessionsThisYear: Int
    /// 今年在馆总时长、到馆天数、最忙的月份
    let secondsThisYear: Double
    let activeDays: Int
    let busiestMonth: Int?
    let busiestMonthSeconds: Double
    /// 今年待得最久的卡带
    let topGameName: String?
    let topGameSeconds: Double
    /// 累计：最长的一次、开箱次数、存档份数
    let longestSession: Double
    let sessions: Int
    let saveCount: Int

    var hasPlayData: Bool { secondsThisYear >= 1 }

    // MARK: - 汇总

    static func make(year: Int = Calendar.current.component(.year, from: Date())) -> MuseumReport {
        let stats = GameStatsManager.shared.allStats()
        let prefix = "\(year)-"

        var seconds: Double = 0
        var activeDayKeys = Set<String>()
        var perMonth: [Int: Double] = [:]
        var perGame: [String: Double] = [:]
        var longest: Double = 0
        var sessions = 0

        for (name, item) in stats {
            longest = max(longest, item.longestSession)
            sessions += item.sessions

            for (key, value) in item.dailySeconds where key.hasPrefix(prefix) {
                seconds += value
                activeDayKeys.insert(key)
                let month = Int(key.dropFirst(5).prefix(2)) ?? 0
                perMonth[month, default: 0] += value
                perGame[name, default: 0] += value
            }
        }

        let busiest = perMonth.max { $0.value < $1.value }
        let top = perGame.max { $0.value < $1.value }

        let accessions = AccessionStore.shared
        let accessionsThisYear = ROMLibrary.shared.roms.filter { rom in
            guard let record = accessions.record(for: rom.name) else { return false }
            return Calendar.current.component(.year, from: record.date) == year
        }.count

        var saveCount = 0
        for rom in ROMLibrary.shared.roms {
            saveCount += SaveStateManager.shared.autoSaveEntries(romName: rom.name).count
            saveCount += (0..<SaveStateManager.manualSlotCount)
                .filter { SaveStateManager.shared.hasSave(romName: rom.name, slot: $0) }
                .count
        }

        return MuseumReport(
            year: year,
            shelfCount: ROMLibrary.shared.roms.count,
            accessionsThisYear: accessionsThisYear,
            secondsThisYear: seconds,
            activeDays: activeDayKeys.count,
            busiestMonth: busiest?.key,
            busiestMonthSeconds: busiest?.value ?? 0,
            topGameName: top?.key,
            topGameSeconds: top?.value ?? 0,
            longestSession: longest,
            sessions: sessions,
            saveCount: saveCount
        )
    }

    // MARK: - 文案

    /// 「3 小时 12 分」这种粗颗粒写法，年报不需要精确到秒
    static func durationText(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total < 60 { return L10n.str("report.duration.seconds", total) }
        let minutes = total / 60
        if minutes < 60 { return L10n.str("report.duration.minutes", minutes) }
        return L10n.str("report.duration.hours", minutes / 60, minutes % 60)
    }

    static func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.str("report.monthLocale"))
        let index = max(0, min(11, month - 1))
        return formatter.monthSymbols[index]
    }
}
