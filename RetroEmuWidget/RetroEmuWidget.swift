// RetroEmuWidget.swift
// 主屏幕 Widget — 显示最近游玩的游戏封面
// F13: WidgetKit 小组件
//
// 配置步骤（Xcode）：
//   1. File → New → Target → Widget Extension，命名 RetroEmuWidget
//   2. 勾选 Include Configuration Intent
//   3. 在 App Target 和 Widget Target 都加入 App Group: group.com.retroemu
//   4. 将此文件替换 Widget Extension 的默认实现

import WidgetKit
import SwiftUI

// MARK: - App Group 共享数据

private let appGroupID = "group.com.retroemu"
private let recentGamesKey = "widget_recent_games"

/// 最近游玩游戏的轻量数据（存入 App Group UserDefaults）
struct RecentGameEntry: Codable, Identifiable {
    let id: String          // romName
    let name: String
    let system: String
    let romPath: String     // 用于 deep link
    let coverPath: String?  // 本地封面图路径
}

// MARK: - Widget Entry

struct GameWidgetEntry: TimelineEntry {
    let date: Date
    let games: [RecentGameEntry]
}

// MARK: - Timeline Provider

struct GameWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> GameWidgetEntry {
        GameWidgetEntry(date: Date(), games: placeholderGames())
    }

    func getSnapshot(in context: Context, completion: @escaping (GameWidgetEntry) -> Void) {
        completion(GameWidgetEntry(date: Date(), games: loadRecentGames()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GameWidgetEntry>) -> Void) {
        let entry = GameWidgetEntry(date: Date(), games: loadRecentGames())
        // 每 30 分钟刷新一次
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadRecentGames() -> [RecentGameEntry] {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: recentGamesKey),
              let games = try? JSONDecoder().decode([RecentGameEntry].self, from: data) else {
            return placeholderGames()
        }
        return Array(games.prefix(4))
    }

    private func placeholderGames() -> [RecentGameEntry] {
        [RecentGameEntry(id: "placeholder", name: "游戏名称", system: "NES", romPath: "", coverPath: nil)]
    }
}

// MARK: - Widget Views

struct GameWidgetEntryView: View {
    var entry: GameWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(game: entry.games.first)
        case .systemMedium:
            MediumWidgetView(games: Array(entry.games.prefix(2)))
        case .systemLarge:
            LargeWidgetView(games: Array(entry.games.prefix(4)))
        default:
            SmallWidgetView(game: entry.games.first)
        }
    }
}

// 小尺寸：1 款游戏
struct SmallWidgetView: View {
    let game: RecentGameEntry?

    var body: some View {
        ZStack {
            Color.black
            if let game = game {
                VStack(spacing: 4) {
                    GameCoverView(game: game)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(game.name)
                        .font(.caption2)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                    Text(game.system)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(8)
            } else {
                Image(systemName: "gamecontroller.fill")
                    .foregroundColor(.gray)
                    .font(.largeTitle)
            }
        }
        .widgetURL(game.map { deepLink(for: $0) })
    }
}

// 中尺寸：2 款游戏
struct MediumWidgetView: View {
    let games: [RecentGameEntry]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(games) { game in
                Link(destination: deepLink(for: game)) {
                    VStack(spacing: 4) {
                        GameCoverView(game: game)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Text(game.name)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(game.system)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black)
    }
}

// 大尺寸：4 款游戏
struct LargeWidgetView: View {
    let games: [RecentGameEntry]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(games) { game in
                Link(destination: deepLink(for: game)) {
                    VStack(spacing: 4) {
                        GameCoverView(game: game)
                            .aspectRatio(1, contentMode: .fit)
                        Text(game.name)
                            .font(.caption2)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(game.system)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.black)
    }
}

// 封面图视图
struct GameCoverView: View {
    let game: RecentGameEntry

    var body: some View {
        Group {
            if let path = game.coverPath,
               let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Deep Link

private func deepLink(for game: RecentGameEntry) -> URL {
    var components = URLComponents()
    components.scheme = "retroemu"
    components.host = "launch"
    components.queryItems = [URLQueryItem(name: "rom", value: game.romPath)]
    return components.url ?? URL(string: "retroemu://launch")!
}

// MARK: - Widget 定义

@main
struct RetroEmuWidgetBundle: WidgetBundle {
    var body: some Widget {
        RetroEmuWidget()
    }
}

struct RetroEmuWidget: Widget {
    let kind = "RetroEmuWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GameWidgetProvider()) { entry in
            GameWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("掌游模拟器")
        .description("快速启动最近游玩的游戏")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
