import Foundation

class SocketServer {
    let socketPath: String
    private var serverFd: Int32 = -1
    /// Handler returns optional response data to send back to the client.
    var onCommand: ((SocketCommand) -> Data?)?

    init() {
        let pid = ProcessInfo.processInfo.processIdentifier
        socketPath = "/tmp/neetly-\(pid).sock"
    }

    func start() {
        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            NSLog("SocketServer: failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathSize = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                let buf = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                strncpy(buf, cstr, pathSize)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("SocketServer: bind failed: \(String(cString: strerror(errno)))")
            return
        }

        guard listen(serverFd, 5) == 0 else {
            NSLog("SocketServer: listen failed")
            return
        }

        NSLog("SocketServer: listening on \(socketPath)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            while let self = self, self.serverFd >= 0 {
                let clientFd = accept(self.serverFd, nil, nil)
                guard clientFd >= 0 else { break }
                self.handleClient(clientFd)
            }
        }
    }

    private func handleClient(_ fd: Int32) {
        // Read request — client sends JSON then shutdown(SHUT_WR)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(contentsOf: buffer[0..<bytesRead])
        }

        guard !data.isEmpty else {
            Darwin.close(fd)
            return
        }

        guard let command = try? JSONDecoder().decode(SocketCommand.self, from: data) else {
            NSLog("SocketServer: failed to decode: \(String(data: data, encoding: .utf8) ?? "?")")
            Darwin.close(fd)
            return
        }

        // Dispatch to main thread for handler, wait for result
        let semaphore = DispatchSemaphore(value: 0)
        var response: Data?
        DispatchQueue.main.async { [weak self] in
            response = self?.onCommand?(command)
            semaphore.signal()
        }
        semaphore.wait()

        // Write response back to client
        if let resp = response, !resp.isEmpty {
            var written = 0
            while written < resp.count {
                let n = resp.withUnsafeBytes { bytes in
                    write(fd, bytes.baseAddress! + written, resp.count - written)
                }
                if n <= 0 { break }
                written += n
            }
        }

        Darwin.close(fd)
    }

    func environmentForPane(_ paneId: UUID) -> [String: String] {
        [
            "NEETLY_SOCKET": socketPath,
            "NEETLY_PANE_ID": paneId.uuidString,
        ]
    }

    func stop() {
        if serverFd >= 0 {
            Darwin.close(serverFd)
            serverFd = -1
        }
        unlink(socketPath)
    }

    deinit {
        stop()
    }
}
