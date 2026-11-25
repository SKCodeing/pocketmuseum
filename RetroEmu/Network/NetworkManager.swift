// NetworkManager.swift
// 局域网多人游戏，基于 Network.framework + Bonjour 服务发现

import Foundation
import Network

// MARK: - 网络消息类型
enum NetMessage: Codable {
    case inputState(playerIndex: Int, buttons: UInt16, frame: UInt64)
    case ping(timestamp: Double)
    case pong(timestamp: Double)
    case playerInfo(name: String, playerIndex: Int)
    case startGame(romName: String)
    case syncFrame(frame: UInt64)

    private enum CodingKeys: String, CodingKey {
        case type, playerIndex, buttons, frame, timestamp, name, romName
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .inputState(let pi, let btn, let fr):
            try c.encode("input", forKey: .type)
            try c.encode(pi, forKey: .playerIndex)
            try c.encode(btn, forKey: .buttons)
            try c.encode(fr, forKey: .frame)
        case .ping(let ts):
            try c.encode("ping", forKey: .type)
            try c.encode(ts, forKey: .timestamp)
        case .pong(let ts):
            try c.encode("pong", forKey: .type)
            try c.encode(ts, forKey: .timestamp)
        case .playerInfo(let name, let pi):
            try c.encode("playerInfo", forKey: .type)
            try c.encode(name, forKey: .name)
            try c.encode(pi, forKey: .playerIndex)
        case .startGame(let rom):
            try c.encode("startGame", forKey: .type)
            try c.encode(rom, forKey: .romName)
        case .syncFrame(let fr):
            try c.encode("syncFrame", forKey: .type)
            try c.encode(fr, forKey: .frame)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "input":
            self = .inputState(
                playerIndex: try c.decode(Int.self, forKey: .playerIndex),
                buttons: try c.decode(UInt16.self, forKey: .buttons),
                frame: try c.decode(UInt64.self, forKey: .frame)
            )
        case "ping":
            self = .ping(timestamp: try c.decode(Double.self, forKey: .timestamp))
        case "pong":
            self = .pong(timestamp: try c.decode(Double.self, forKey: .timestamp))
        case "playerInfo":
            self = .playerInfo(
                name: try c.decode(String.self, forKey: .name),
                playerIndex: try c.decode(Int.self, forKey: .playerIndex)
            )
        case "startGame":
            self = .startGame(romName: try c.decode(String.self, forKey: .romName))
        case "syncFrame":
            self = .syncFrame(frame: try c.decode(UInt64.self, forKey: .frame))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unknown type"))
        }
    }
}

// MARK: - 网络管理器委托
protocol NetworkManagerDelegate: AnyObject {
    func networkManager(_ manager: NetworkManager, didReceiveInput buttons: UInt16, playerIndex: Int, frame: UInt64)
    func networkManager(_ manager: NetworkManager, didConnectPlayer player: NetworkPlayer)
    func networkManager(_ manager: NetworkManager, didDisconnectPlayer playerID: String)
    func networkManager(_ manager: NetworkManager, didReceiveStartGame romName: String)
    func networkManager(_ manager: NetworkManager, latencyUpdated ms: Double)
}

// MARK: - 网络管理器
final class NetworkManager: NSObject {

    static let shared = NetworkManager()

    weak var delegate: NetworkManagerDelegate?

    private(set) var isHost = false
    private(set) var isConnected = false
    private(set) var localPlayerIndex = 0
    private(set) var remotePlayer: NetworkPlayer?
    private(set) var latencyMs: Double = 0

    // Network.framework
    private var listener: NWListener?
    private var connection: NWConnection?
    private let netQueue = DispatchQueue(label: "com.retroemu.network", qos: .userInteractive)

    // Bonjour
    private var browser: NWBrowser?
    private let serviceType = "_retroemu._tcp"

    // 帧计数
    private(set) var frameCount: UInt64 = 0

    // 发现的主机回调
    var onHostsDiscovered: (([NWBrowser.Result]) -> Void)?

    private override init() {}

    // MARK: - 主机模式
    func startHosting(playerName: String) {
        isHost = true
        localPlayerIndex = 0

        let params = NWParameters.tcp
        params.includePeerToPeer = true

        do {
            listener = try NWListener(using: params, on: 7890)
            listener?.service = NWListener.Service(type: serviceType)
            listener?.stateUpdateHandler = { [weak self] state in
                print("[Network] Listener state: \(state)")
                if case .failed(let err) = state {
                    print("[Network] Listener error: \(err)")
                    self?.stopHosting()
                }
            }
            listener?.newConnectionHandler = { [weak self] conn in
                self?.acceptConnection(conn, playerName: playerName)
            }
            listener?.start(queue: netQueue)
            print("[Network] 开始监听，等待玩家加入...")
        } catch {
            print("[Network] 创建 Listener 失败: \(error)")
        }
    }

    func stopHosting() {
        listener?.cancel()
        listener = nil
    }

    private func acceptConnection(_ conn: NWConnection, playerName: String) {
        // 只支持 2 人，已有连接则拒绝
        guard connection == nil else { conn.cancel(); return }
        connection = conn
        setupConnection(conn)
        conn.start(queue: netQueue)

        // 发送本机玩家信息
        send(.playerInfo(name: playerName, playerIndex: 0))
    }

    // MARK: - 客户端模式
    func browseForHosts() {
        let params = NWParameters()
        params.includePeerToPeer = true
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: params)
        browser?.stateUpdateHandler = { state in
            print("[Network] Browser state: \(state)")
        }
        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.onHostsDiscovered?(Array(results))
            }
        }
        browser?.start(queue: netQueue)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    func connectToHost(_ result: NWBrowser.Result, playerName: String) {
        isHost = false
        localPlayerIndex = 1

        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let conn = NWConnection(to: result.endpoint, using: params)
        connection = conn
        setupConnection(conn)
        conn.start(queue: netQueue)

        // 等连接建立后发送玩家信息
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.send(.playerInfo(name: playerName, playerIndex: 1))
        }
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        remotePlayer = nil
    }

    // MARK: - 发送输入
    func sendInput(buttons: UInt16) {
        frameCount += 1
        send(.inputState(playerIndex: localPlayerIndex, buttons: buttons, frame: frameCount))
    }

    func sendStartGame(romName: String) {
        send(.startGame(romName: romName))
    }

    // MARK: - 连接管理
    private func setupConnection(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.startPingLoop()
                self?.receiveNext()
                print("[Network] 连接就绪")
            case .failed(let err):
                print("[Network] 连接失败: \(err)")
                self?.handleDisconnect()
            case .cancelled:
                self?.handleDisconnect()
            default: break
            }
        }
    }

    private func handleDisconnect() {
        isConnected = false
        if let player = remotePlayer {
            DispatchQueue.main.async {
                self.delegate?.networkManager(self, didDisconnectPlayer: player.id)
            }
        }
        remotePlayer = nil
        connection = nil
    }

    // MARK: - 收发数据（长度前缀帧协议）
    private func send(_ message: NetMessage) {
        guard let conn = connection else { return }
        guard let data = try? JSONEncoder().encode(message) else { return }
        var length = UInt32(data.count).bigEndian
        let header = Data(bytes: &length, count: 4)
        conn.send(content: header + data, completion: .idempotent)
    }

    private func receiveNext() {
        // 先读 4 字节长度头
        connection?.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, err in
            guard let self = self, let data = data, data.count == 4, err == nil else {
                if let err = err { print("[Network] 接收错误: \(err)") }
                return
            }
            let length = Int(UInt32(bigEndian: data.withUnsafeBytes { $0.load(as: UInt32.self) }))
            self.receiveBody(length: length)
        }
    }

    private func receiveBody(length: Int) {
        connection?.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, err in
            guard let self = self, let data = data, err == nil else { return }
            if let msg = try? JSONDecoder().decode(NetMessage.self, from: data) {
                self.handleMessage(msg)
            }
            self.receiveNext()
        }
    }

    private func handleMessage(_ msg: NetMessage) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch msg {
            case .inputState(let pi, let btn, let fr):
                self.delegate?.networkManager(self, didReceiveInput: btn, playerIndex: pi, frame: fr)
            case .ping(let ts):
                self.send(.pong(timestamp: ts))
            case .pong(let ts):
                let rtt = (Date().timeIntervalSince1970 - ts) * 1000
                self.latencyMs = rtt
                self.delegate?.networkManager(self, latencyUpdated: rtt)
            case .playerInfo(let name, let pi):
                let player = NetworkPlayer(id: UUID().uuidString, name: name, playerIndex: pi, isHost: pi == 0)
                self.remotePlayer = player
                self.delegate?.networkManager(self, didConnectPlayer: player)
            case .startGame(let rom):
                self.delegate?.networkManager(self, didReceiveStartGame: rom)
            case .syncFrame(let fr):
                self.frameCount = fr
            }
        }
    }

    // MARK: - Ping 延迟检测
    private func startPingLoop() {
        netQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.isConnected else { return }
            self.send(.ping(timestamp: Date().timeIntervalSince1970))
            self.startPingLoop()
        }
    }
}
