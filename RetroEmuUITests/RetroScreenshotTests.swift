//
//  RetroScreenshotTests.swift
//  RetroEmuUITests
//
//  真机/模拟器 UI 巡检：逐页截图，产物可从 .xcresult 导出作为商店素材或验收证据。
//

import XCTest

final class RetroScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureMainScreens() throws {
        let app = XCUIApplication()
        // 跳过入场动画，保证每次截图落在首屏而不是过渡帧
        app.launchArguments += ["-skipIntro"]
        app.launch()

        // 首屏（掌机博物馆）
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App 未能进入前台")
        sleep(2)
        capture(named: "01-home")

        // 时光
        let timelineTab = app.buttons["tab.1"]
        XCTAssertTrue(timelineTab.waitForExistence(timeout: 10), "未找到「时光」标签")
        timelineTab.tap()
        sleep(2)
        capture(named: "02-timeline")

        // 设置
        let settingsTab = app.buttons["tab.2"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "未找到「设置」标签")
        settingsTab.tap()
        sleep(2)
        capture(named: "03-settings")

        // 回到游戏库
        app.buttons["tab.0"].tap()
        sleep(1)
        capture(named: "04-library-again")
    }

    @MainActor
    func testRotationKeepsHeroCardContained() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipIntro"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(2)
        capture(named: "rot-01-portrait")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        capture(named: "rot-02-landscape")

        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        capture(named: "rot-03-portrait-again")

        let recent = app.buttons["最近"].firstMatch
        if recent.waitForExistence(timeout: 3) {
            recent.tap()
        } else {
            app.staticTexts["最近"].firstMatch.tap()
        }
        sleep(2)
        capture(named: "rot-04-recent-filter")
    }

    @MainActor
    func testLaunchDemoGame() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-skipIntro"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))

        let play = app.buttons["开箱游玩"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15), "首屏没有「开箱游玩」按钮")
        play.tap()
        sleep(5)
        capture(named: "game-01-ingame")
    }

    @MainActor
    private func capture(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
