// GamepadManager.swift
// 统一管理所有外接手柄（MFi / DualShock 4&5 / Xbox / Switch Pro / Joy-Con）
// 支持最多 4 个手柄同时接入，自动分配玩家编号
// F5：手柄扩展支持

import GameController
import UIKit
import CoreHaptics

protocol GamepadManagerDelegate: AnyObject {
    /// 手柄输入更新，playerIndex 0-based
    func gamepadManager(_ manager: GamepadManager, didUpdateButtons buttons: EmulatorButton, playerIndex: Int)
    /// 手柄连接/断开通知（用于显示 Toast）
    func gamepadManager(_ manager: GamepadManager, controllerDidConnect name: String, playerIndex: Int)
    func gamepadManager(_ manager: GamepadManager, controllerDidDisconnect name: String)
}

final class GamepadManager {

    static let shared = GamepadManager()

    weak var delegate: GamepadManagerDelegate?

    /// 是否有任何手柄连接
    var hasConnectedController: Bool { !connectedControllers.isEmpty }

    /// 当前连接的手柄（按玩家编号排序）
    private var connectedControllers: [GCController] = []
    /// 上一帧各玩家的按键状态（用于检测新按下，触发震动）
    private var lastButtons: [Int: EmulatorButton] = [:]

    private init() {
        setupNotifications()
        // 处理 App 启动时已连接的手柄
        GCController.controllers().forEach { connect($0) }
    }

    // MARK: - 通知监听

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        connect(controller)
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        disconnect(controller)
    }

    // MARK: - 连接/断开

    private func connect(_ controller: GCController) {
        guard !connectedControllers.contains(controller) else { return }
        connectedControllers.append(controller)
        let playerIndex = connectedControllers.count - 1
        controller.playerIndex = GCControllerPlayerIndex(rawValue: playerIndex) ?? .indexUnset

        setupInputHandlers(for: controller, playerIndex: playerIndex)

        let name = controllerDisplayName(controller)
        DispatchQueue.main.async {
            self.delegate?.gamepadManager(self, controllerDidConnect: name, playerIndex: playerIndex)
        }
    }

    private func disconnect(_ controller: GCController) {
        let name = controllerDisplayName(controller)
        connectedControllers.removeAll { $0 == controller }
        // 重新分配玩家编号
        for (i, c) in connectedControllers.enumerated() {
            c.playerIndex = GCControllerPlayerIndex(rawValue: i) ?? .indexUnset
        }
        DispatchQueue.main.async {
            self.delegate?.gamepadManager(self, controllerDidDisconnect: name)
        }
    }

    // MARK: - 输入处理

    private func setupInputHandlers(for controller: GCController, playerIndex: Int) {
        // 优先使用 extendedGamepad（Xbox / DualShock / Switch Pro）
        if let pad = controller.extendedGamepad {
            setupExtendedGamepad(pad, playerIndex: playerIndex)
        } else if let pad = controller.microGamepad {
            setupMicroGamepad(pad, playerIndex: playerIndex)
        }
    }

    private func setupExtendedGamepad(_ pad: GCExtendedGamepad, playerIndex: Int) {
        pad.valueChangedHandler = { [weak self] _, _ in
            guard let self = self else { return }
            let buttons = self.translateExtendedGamepad(pad)
            // 新按下的按键触发手柄震动
            let prevButtons = self.lastButtons[playerIndex] ?? []
            let newlyPressed = buttons.rawValue & ~prevButtons.rawValue
            if newlyPressed != 0 {
                self.triggerHaptic(for: pad.controller)
            }
            self.lastButtons[playerIndex] = buttons
            self.delegate?.gamepadManager(self, didUpdateButtons: buttons, playerIndex: playerIndex)
        }
    }

    private func setupMicroGamepad(_ pad: GCMicroGamepad, playerIndex: Int) {
        pad.valueChangedHandler = { [weak self] _, _ in
            guard let self = self else { return }
            let buttons = self.translateMicroGamepad(pad)
            self.delegate?.gamepadManager(self, didUpdateButtons: buttons, playerIndex: playerIndex)
        }
    }

    // MARK: - 按键映射（ExtendedGamepad → EmulatorButton）

    private func translateExtendedGamepad(_ pad: GCExtendedGamepad) -> EmulatorButton {
        var result: EmulatorButton = []

        // 方向键（D-Pad）
        if pad.dpad.up.isPressed    { result.insert(.up) }
        if pad.dpad.down.isPressed  { result.insert(.down) }
        if pad.dpad.left.isPressed  { result.insert(.left) }
        if pad.dpad.right.isPressed { result.insert(.right) }

        // 左摇杆也映射方向（阈值 0.5）
        if pad.leftThumbstick.yAxis.value >  0.5 { result.insert(.up) }
        if pad.leftThumbstick.yAxis.value < -0.5 { result.insert(.down) }
        if pad.leftThumbstick.xAxis.value < -0.5 { result.insert(.left) }
        if pad.leftThumbstick.xAxis.value >  0.5 { result.insert(.right) }

        // 面板按键（A/B/X/Y → 经过 KeymapSettings 重映射）
        let km = KeymapSettings.shared
        if pad.buttonA.isPressed { result.insert(km.button(for: .btnA)) }
        if pad.buttonB.isPressed { result.insert(km.button(for: .btnB)) }
        if pad.buttonX.isPressed { result.insert(km.button(for: .btnX)) }
        if pad.buttonY.isPressed { result.insert(km.button(for: .btnY)) }

        // Start / Select（Options / Menu / Share / Minus / Plus）
        if pad.buttonMenu.isPressed    { result.insert(.start) }
        if pad.buttonOptions?.isPressed == true { result.insert(.select) }

        return result
    }

    private func translateMicroGamepad(_ pad: GCMicroGamepad) -> EmulatorButton {
        var result: EmulatorButton = []
        if pad.dpad.up.isPressed    { result.insert(.up) }
        if pad.dpad.down.isPressed  { result.insert(.down) }
        if pad.dpad.left.isPressed  { result.insert(.left) }
        if pad.dpad.right.isPressed { result.insert(.right) }
        if pad.buttonA.isPressed    { result.insert(.a) }
        if pad.buttonX.isPressed    { result.insert(.b) }
        return result
    }

    // MARK: - 工具

    private func triggerHaptic(for controller: GCController?) {
        guard #available(iOS 14.0, *), let ctrl = controller else { return }
        if let engine = ctrl.haptics?.createEngine(withLocality: .default) {
            try? engine.start()
            let event = CHHapticEvent(eventType: .hapticTransient, parameters: [], relativeTime: 0)
            if let player = try? engine.makePlayer(with: CHHapticPattern(events: [event], parameters: [])) {
                try? player.start(atTime: 0)
            }
        }
    }

    private func controllerDisplayName(_ controller: GCController) -> String {
        let category = controller.productCategory
        if !category.isEmpty {
            return category
        }
        // 根据 vendorName 推断品牌
        let vendor = controller.vendorName ?? "手柄"
        if vendor.lowercased().contains("dualshock") || vendor.lowercased().contains("dualsense") {
            return "PlayStation 手柄"
        } else if vendor.lowercased().contains("xbox") {
            return "Xbox 手柄"
        } else if vendor.lowercased().contains("joy-con") {
            return "Joy-Con"
        } else if vendor.lowercased().contains("pro controller") {
            return "Switch Pro 手柄"
        }
        return vendor
    }
}
