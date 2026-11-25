// WiFiTransferServer.swift
// 基于 POSIX socket 的 HTTP 服务器，绕过 Network.framework 权限限制

import Foundation
import Darwin

final class WiFiTransferServer {

    static let shared = WiFiTransferServer()
    private init() {}

    /// 默认 8080；本机压测时端口常被别的服务占着，允许调试参数覆盖
    var port: UInt16 = 8080
    private var serverSocket: Int32 = -1
    private var serverThread: Thread?
    private(set) var isRunning = false

    var onUploadProgress: ((String, Int, Int, Int, Int, Int) -> Void)?
    // 参数：(当前文件名, 当前文件已收字节, 当前文件总字节, 总已收字节, 总字节, 本批文件数)
    // 文件名只给日志用；进度行只报个数，名字跟着字节回调变会来回闪
    var onFileReceived: ((URL) -> Void)?
    var onExtractProgress: ((String, Int, Int) -> Void)?

    // MARK: - 启动/停止

    func start() {
        guard !isRunning else { return }

        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[WiFi] socket() 失败: \(errno)")
            return
        }

        // SO_REUSEADDR
        var yes: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // 绑定到所有接口
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            print("[WiFi] bind() 失败: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        guard listen(serverSocket, 10) == 0 else {
            print("[WiFi] listen() 失败: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        isRunning = true
        print("[WiFi] 服务器就绪，端口 \(port)，IP: \(localURL)")

        serverThread = Thread {
            self.acceptLoop()
        }
        serverThread?.name = "WiFiTransferServer"
        serverThread?.start()
    }

    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
    }

    var localURL: String {
        "http://\(Self.localIPAddress() ?? "127.0.0.1"):\(port)"
    }

    // MARK: - Accept 循环

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverSocket, $0, &addrLen)
                }
            }
            guard clientSocket >= 0 else { continue }

            // 每个连接开一个线程处理
            let sock = clientSocket
            Thread.detachNewThread { self.handleClient(sock) }
        }
    }

    // MARK: - 处理客户端连接

    private func handleClient(_ sock: Int32) {
        defer { close(sock) }

        // 超时：上传大文件需要更长时间，设 300 秒
        var tv = timeval(tv_sec: 300, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let bufSize = 65536
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        // 只把 HTTP header 读入内存（最多 64KB）
        var headerData = Data()
        var headerEnd: Int? = nil
        while headerEnd == nil {
            let n = recv(sock, buf, bufSize, 0)
            guard n > 0 else { return }
            headerData.append(buf, count: n)
            if let range = headerData.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = range.upperBound
                break
            }
            if headerData.count > 64 * 1024 { return }  // header 过大，拒绝
        }

        guard let hEnd = headerEnd else { return }
        let headerStr = String(data: headerData.prefix(hEnd), encoding: .utf8) ?? ""

        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }
        let method = parts[0]
        let path = parts[1]

        if method == "GET" && path == "/" {
            sendHTML(sock)
        } else if method == "GET" && path.hasPrefix("/roms/") {
            let filename = String(path.dropFirst(6)).removingPercentEncoding ?? ""
            sendFile(sock, filename: filename)
        } else if method == "GET" && path == "/list" {
            sendROMList(sock)
        } else if method == "POST" && path == "/upload" {
            // 流式上传：header 已读完，body 部分（headerData[hEnd...]）+ 剩余 socket 数据
            let bodyPrefix = headerData.suffix(from: hEnd)
            handleUploadStreaming(sock: sock,
                                  headerStr: headerStr,
                                  bodyPrefix: bodyPrefix,
                                  buf: buf,
                                  bufSize: bufSize)
        } else {
            sendString(sock, "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found")
        }
    }

    // MARK: - 流式上传处理（不把文件内容全部读入内存）

    /// 请求体的结束位置只认 Content-Length。浏览器把最后一个 part 传完就停下来等响应，
    /// 既不继续发数据也不关连接；原先靠 recv 返回 0 判断结束，结果每个文件都要等满
    /// 300 秒超时才回响应，批量上传看起来就只成功了第一个。
    private func handleUploadStreaming(sock: Int32,
                                       headerStr: String,
                                       bodyPrefix: Data,
                                       buf: UnsafeMutablePointer<UInt8>,
                                       bufSize: Int) {
        // 解析 boundary
        guard let btRange = headerStr.range(of: "boundary=") else {
            sendString(sock, "HTTP/1.1 400 Bad Request\r\nContent-Length: 11\r\nConnection: close\r\n\r\nNo boundary")
            return
        }
        let boundaryStr = "--" + String(headerStr[btRange.upperBound...].prefix(while: { !$0.isNewline && !$0.isWhitespace }))
        let boundary     = Data(boundaryStr.utf8)
        let endBoundary  = Data((boundaryStr + "--").utf8)
        let crlf         = Data("\r\n".utf8)
        let crlfcrlf     = Data("\r\n\r\n".utf8)

        // Content-Length：当前请求体（一个 part）的准确长度
        var bodyLength = 0
        if let clRange = headerStr.range(of: "Content-Length:", options: .caseInsensitive) {
            let after = headerStr[clRange.upperBound...].trimmingCharacters(in: .whitespaces)
            bodyLength = Int(after.prefix(while: { $0.isNumber })) ?? 0
        }

        // 解析 X-Total-Size（JS 传来的所有文件总字节数，用于总体进度）
        var grandTotalBytes = bodyLength
        if let xtRange = headerStr.range(of: "X-Total-Size:", options: .caseInsensitive) {
            let after = headerStr[xtRange.upperBound...].trimmingCharacters(in: .whitespaces)
            grandTotalBytes = Int(after.prefix(while: { $0.isNumber })) ?? bodyLength
        }

        // 解析 X-Received-Before（本次请求前已传输的字节数）
        var receivedBefore = 0
        if let xrRange = headerStr.range(of: "X-Received-Before:", options: .caseInsensitive) {
            let after = headerStr[xrRange.upperBound...].trimmingCharacters(in: .whitespaces)
            receivedBefore = Int(after.prefix(while: { $0.isNumber })) ?? 0
        }

        // 解析 X-Total-Files（本批要传多少个），只为了把「已接收 N 个」显示成 N / 总
        var totalFiles = 0
        if let tfRange = headerStr.range(of: "X-Total-Files:", options: .caseInsensitive) {
            let after = headerStr[tfRange.upperBound...].trimmingCharacters(in: .whitespaces)
            totalFiles = Int(after.prefix(while: { $0.isNumber })) ?? 0
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var uploadedCount = 0

        // 滑动窗口缓冲区：从 header 之后的数据开始，找 boundary 时保留尾部
        var window = Data(bodyPrefix)          // 归一化 startIndex
        var remaining = bodyLength > 0 ? max(0, bodyLength - window.count) : Int.max
        var connectionBroken = false

        // 状态机
        enum State { case seekingPartHeader, writingFile }
        var state: State = .seekingPartHeader
        var currentFilename = ""
        var fileHandle: FileHandle? = nil
        var currentDest: URL? = nil

        func flushWindow(upTo index: Data.Index) {
            let end = min(max(index, window.startIndex), window.endIndex)
            guard end > window.startIndex else { return }
            window.removeSubrange(window.startIndex..<end)
        }

        /// 最多读一次，且绝不越过 Content-Length。
        /// 返回 false 表示请求体已读完（或连接断了），调用方不要再等数据。
        func pull() -> Bool {
            guard remaining > 0, !connectionBroken else { return false }
            let n = recv(sock, buf, min(bufSize, remaining), 0)
            if n <= 0 {
                connectionBroken = true
                return false
            }
            window.append(buf, count: n)
            remaining -= n
            return true
        }

        mainLoop: while true {
            // 窗口空了就补数据；补不到说明请求体已读完
            if window.isEmpty {
                if !pull() { break mainLoop }
                continue
            }

            switch state {
            case .seekingPartHeader:
                // 找 boundary
                guard let bRange = window.range(of: boundary) else {
                    // 当前窗口里没有 boundary：丢掉不可能构成 boundary 的前缀，只留可能被切断的尾巴
                    if window.count > boundary.count {
                        flushWindow(upTo: window.endIndex - (boundary.count - 1))
                    }
                    if !pull() { break mainLoop }
                    continue
                }

                // 结束 boundary 要先看到后面那两个 "--" 才能下结论
                let afterB = bRange.upperBound
                if window.endIndex - afterB < 2 {
                    if !pull() { break mainLoop }
                    continue
                }
                if window[afterB] == UInt8(ascii: "-") &&
                   window[afterB + 1] == UInt8(ascii: "-") {
                    break mainLoop  // 所有 part 处理完毕
                }

                // 跳过 boundary + \r\n，找 part header 结束位置
                flushWindow(upTo: afterB + 2)  // 跳过 \r\n

                // 读取 part header（直到 \r\n\r\n）
                while window.range(of: crlfcrlf) == nil {
                    if !pull() { break mainLoop }
                }
                guard let phEnd = window.range(of: crlfcrlf) else { break mainLoop }

                let partHeader = String(data: window[window.startIndex..<phEnd.lowerBound], encoding: .utf8) ?? ""
                flushWindow(upTo: phEnd.upperBound)

                // 解析文件名
                currentFilename = ""
                if let fnRange = partHeader.range(of: "filename=\"") {
                    if let fnEnd = partHeader[fnRange.upperBound...].firstIndex(of: "\"") {
                        currentFilename = String(partHeader[fnRange.upperBound..<fnEnd])
                    }
                }
                guard !currentFilename.isEmpty else { continue }
                // 只取最后一段，挡掉 ../ 之类的路径
                let safeName = (currentFilename as NSString).lastPathComponent
                guard !safeName.isEmpty else { continue }

                // 创建目标文件
                let dest = docs.appendingPathComponent(safeName)
                currentDest = dest
                FileManager.default.createFile(atPath: dest.path, contents: nil)
                fileHandle = try? FileHandle(forWritingTo: dest)
                try? fileHandle?.truncate(atOffset: 0)  // 同名文件重传要覆盖，不能接着追加
                fileHandle?.seekToEndOfFile()

                DispatchQueue.main.async {
                    self.onUploadProgress?(currentFilename, 0, bodyLength,
                                          receivedBefore, grandTotalBytes, totalFiles)
                }
                state = .writingFile

            case .writingFile:
                // 在窗口中查找 \r\n--boundary（part 结束标志）
                let endMarker = crlf + boundary
                if let endRange = window.range(of: endMarker) {
                    // 找到结束标志，写入最后一块数据
                    let chunk = window[window.startIndex..<endRange.lowerBound]
                    if !chunk.isEmpty {
                        fileHandle?.write(Data(chunk))
                    }
                    fileHandle?.closeFile()
                    fileHandle = nil
                    uploadedCount += 1

                    guard let dest = currentDest else { break mainLoop }
                    let fname = currentFilename
                    DispatchQueue.main.async {
                        self.onUploadProgress?(fname, bodyLength, bodyLength,
                                              receivedBefore + bodyLength, grandTotalBytes, totalFiles)
                    }

                    // 处理 ZIP 解压
                    if fname.lowercased().hasSuffix(".zip") {
                        let destCopy = dest
                        Task.detached { [weak self] in
                            do {
                                let entries = try ZipExtractor.listEntries(zipURL: destCopy)
                                let romEntries = entries.filter { ZipExtractor.isROM($0) }
                                for (i, entry) in romEntries.enumerated() {
                                    await MainActor.run {
                                        self?.onExtractProgress?(fname, i + 1, romEntries.count)
                                    }
                                    let extracted = try ZipExtractor.extractEntry(entry, from: destCopy, to: docs)
                                    await MainActor.run { self?.onFileReceived?(extracted) }
                                }
                                try? FileManager.default.removeItem(at: destCopy)
                            } catch {
                                await MainActor.run { self?.onFileReceived?(destCopy) }
                            }
                        }
                    } else {
                        DispatchQueue.main.async { self.onFileReceived?(dest) }
                    }

                    // 移动到 boundary 之后，继续处理下一个 part
                    flushWindow(upTo: endRange.lowerBound + crlf.count)
                    state = .seekingPartHeader

                } else {
                    // 没找到结束标志：写入确定不属于 boundary 的前缀，尾部留着继续匹配
                    let keep = endMarker.count
                    if window.count > keep {
                        let safeEnd = window.endIndex - keep
                        fileHandle?.write(Data(window[window.startIndex..<safeEnd]))
                        flushWindow(upTo: safeEnd)

                        // 更新进度
                        let fileReceived = bodyLength > 0 ? bodyLength - remaining : 0
                        DispatchQueue.main.async {
                            self.onUploadProgress?(currentFilename,
                                                   fileReceived, bodyLength,
                                                   receivedBefore + fileReceived, grandTotalBytes,
                                                   totalFiles)
                        }
                    }
                    if !pull() { break mainLoop }
                }
            }
        }

        // 收尾：写了一半的文件删掉，别把半截 ROM 留在书架上
        if state == .writingFile {
            fileHandle?.closeFile()
            fileHandle = nil
            if let dest = currentDest { try? FileManager.default.removeItem(at: dest) }
        } else {
            fileHandle?.closeFile()
        }

        let body = "OK:\(uploadedCount)"
        sendString(sock, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n\(body)")
    }

    // MARK: - 下载文件

    private func sendFile(_ sock: Int32, filename: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else {
            sendString(sock, "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found")
            return
        }
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Disposition: attachment; filename=\"\(filename)\"\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
        sendString(sock, header)
        sendData(sock, data)
    }

    // MARK: - ROM 列表

    private func sendROMList(_ sock: Int32) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exts = Set(EmulatorSystem.allCases.flatMap { $0.fileExtensions }.map { $0.lowercased() } + ["zip"])
        let files = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let roms = files.filter { exts.contains($0.pathExtension.lowercased()) }
        let items = roms.map { url -> String in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let kb = size / 1024
            let sizeStr = kb > 1024 ? "\(kb/1024) MB" : "\(kb) KB"
            let name = url.lastPathComponent.replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"name\":\"\(name)\",\"size\":\"\(sizeStr)\"}"
        }
        let json = "[" + items.joined(separator: ",") + "]"
        sendString(sock, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)")
    }

    // MARK: - HTML 页面

    private func sendHTML(_ sock: Int32) {
        let html = """
        <!DOCTYPE html>
        <html lang="zh">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>RetroEmu WiFi 传输</title>
        <style>
          body{font-family:-apple-system,sans-serif;max-width:700px;margin:0 auto;padding:20px;background:#1a1a2e;color:#eee}
          h1{color:#e94560;text-align:center}
          .card{background:#16213e;border-radius:12px;padding:20px;margin:16px 0}
          h2{color:#a8dadc;margin:0 0 12px}
          input[type=file]{width:100%;padding:10px;background:#0f3460;border:2px dashed #e94560;border-radius:8px;color:#eee;cursor:pointer;box-sizing:border-box}
          button{width:100%;padding:12px;background:#e94560;color:#fff;border:none;border-radius:8px;font-size:16px;cursor:pointer;margin-top:10px}
          button:disabled{background:#555;cursor:not-allowed}
          .progress-wrap{margin-top:12px}
          .progress-label{font-size:12px;color:#aaa;margin-bottom:4px}
          progress{width:100%;height:8px;border-radius:4px;appearance:none}
          progress::-webkit-progress-bar{background:#0f3460;border-radius:4px}
          progress::-webkit-progress-value{background:#e94560;border-radius:4px}
          #log{max-height:150px;overflow-y:auto;font-size:12px;color:#95d5b2;margin-top:8px;padding:8px;background:#0a0a1a;border-radius:6px}
          table{width:100%;border-collapse:collapse}
          td,th{padding:8px;text-align:left;border-bottom:1px solid #0f3460}
          th{color:#a8dadc}
          a{color:#e94560;text-decoration:none}
          .empty{text-align:center;color:#666;padding:20px}
        </style>
        </head>
        <body>
        <h1>🎮 RetroEmu WiFi 传输</h1>
        <div class="card">
          <h2>📤 上传 ROM</h2>
          <input type="file" id="file" accept=".nes,.gb,.gbc,.gba,.sfc,.smc,.nds,.z64,.n64,.v64,.gg,.sms,.md,.bin,.gen,.32x,.cue,.iso,.pbp,.cso,.zip" multiple>
          <button id="uploadBtn" onclick="upload()">上传到设备</button>
          <div class="progress-wrap">
            <div class="progress-label" id="progressLabel">选择文件后点击上传</div>
            <progress id="progressBar" value="0" max="100"></progress>
          </div>
          <div id="log"></div>
        </div>
        <div class="card">
          <h2>📂 已有 ROM</h2>
          <div id="list"><div class="empty">加载中...</div></div>
        </div>
        <script>
        function log(msg){const el=document.getElementById('log');el.innerHTML+=msg+'<br>';el.scrollTop=el.scrollHeight;}
        async function upload(){
          const files=Array.from(document.getElementById('file').files);
          if(!files.length){alert('请先选择文件');return;}
          const btn=document.getElementById('uploadBtn');
          const bar=document.getElementById('progressBar');
          const label=document.getElementById('progressLabel');
          btn.disabled=true;
          const totalSize=files.reduce((s,f)=>s+f.size,0);
          let doneSize=0, done=0, failed=0;
          for(const f of files){
            // 进度行只报个数：文件名在下面日志里逐条打，放到这里会随每个文件跳一次
            label.textContent='已接收 '+(done+failed)+' / '+files.length+' 个文件';
            bar.value=Math.round(doneSize/totalSize*100);
            const fd=new FormData();fd.append('file',f);
            try{
              const res=await fetch('/upload',{method:'POST',body:fd,headers:{
                'X-Total-Size':String(totalSize),
                'X-Received-Before':String(doneSize),
                'X-Total-Files':String(files.length)
              }});
              const text=(await res.text()).trim();
              // 服务端只回 OK:1 才算这个文件真的落盘了
              if(!res.ok || text!=='OK:1') throw new Error(text||('HTTP '+res.status));
              log('✅ '+f.name+' ('+fmtSize(f.size)+')');
              done++;
            }catch(e){log('❌ '+f.name+' — '+e.message);failed++;}
            doneSize+=f.size;
            bar.value=Math.round(doneSize/totalSize*100);
          }
          label.textContent=failed
            ? '⚠️ 完成：成功 '+done+' 个，失败 '+failed+' 个'
            : '✅ 完成！共 '+done+' 个文件，'+fmtSize(totalSize);
          btn.disabled=false;loadList();
        }
        function fmtSize(b){if(b<1024)return b+'B';if(b<1048576)return (b/1024).toFixed(1)+'KB';if(b<1073741824)return (b/1048576).toFixed(1)+'MB';return (b/1073741824).toFixed(2)+'GB';}
        function loadList(){
          fetch('/list').then(r=>r.json()).then(data=>{
            const el=document.getElementById('list');
            if(!data.length){el.innerHTML='<div class="empty">暂无文件</div>';return;}
            el.innerHTML='<table><tr><th>文件名</th><th>大小</th><th>下载</th></tr>'+
              data.map(f=>'<tr><td>'+f.name+'</td><td>'+f.size+'</td><td><a href="/roms/'+encodeURIComponent(f.name)+'">⬇️</a></td></tr>').join('')+'</table>';
          }).catch(()=>{});
        }
        loadList();
        </script>
        </body></html>
        """
        sendString(sock, "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)")
    }

    // MARK: - 发送工具

    private func sendString(_ sock: Int32, _ str: String) {
        guard let data = str.data(using: .utf8) else { return }
        sendData(sock, data)
    }

    private func sendData(_ sock: Int32, _ data: Data) {
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = send(sock, base.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    // MARK: - 获取本机 IP

    static func localIPAddress() -> String? {
        var wifiAddress: String?
        var fallbackAddress: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        defer { freeifaddrs(ifaddr) }
        var ptr = ifaddr
        while let ifa = ptr {
            defer { ptr = ifa.pointee.ifa_next }
            let flags = Int32(ifa.pointee.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING) else { continue }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(MemoryLayout<sockaddr_in>.size),
                              &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: hostname)
            let ifName = String(cString: ifa.pointee.ifa_name)
            // 优先 en0（WiFi）
            if ifName == "en0" {
                wifiAddress = ip
                break
            }
            // 其次 192.168.x.x
            if ip.hasPrefix("192.168.") { fallbackAddress = fallbackAddress ?? ip }
            // 再次其他局域网
            if ip.hasPrefix("172.") || ip.hasPrefix("10.") { fallbackAddress = fallbackAddress ?? ip }
        }
        return wifiAddress ?? fallbackAddress
    }
}
