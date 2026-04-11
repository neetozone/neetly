import Foundation

// neetly CLI — companion tool for neetly1
//
// Usage:
//   neetly tabs                     — list all tabs
//   neetly send <tab-id> <text>     — send text to a terminal tab
//   neetly visit <url>              — open a browser tab in the current pane
//   neetly run <command>            — open a terminal tab running <command>

let env = ProcessInfo.processInfo.environment

guard let socketPath = env["NEETLY_SOCKET"] else {
    fputs("Error: NEETLY_SOCKET not set. Are you running inside neetly1?\n", stderr)
    exit(1)
}

let paneId = env["NEETLY_PANE_ID"] ?? ""
let args = CommandLine.arguments

guard args.count >= 2 else {
    printUsage()
    exit(1)
}

let action = args[1]

var payload: [String: Any] = ["paneId": paneId]
var expectResponse = false

switch action {
case "tabs":
    payload["action"] = "tabs.list"
    expectResponse = true

case "send":
    guard args.count >= 4 else {
        fputs("Usage: neetly send <tab-id> <text>\n", stderr)
        exit(1)
    }
    payload["action"] = "tab.send"
    payload["tabId"] = args[2]
    payload["text"] = args[3...].joined(separator: " ")

case "visit":
    guard args.count >= 3 else {
        fputs("Usage: neetly visit <url>\n", stderr)
        exit(1)
    }
    payload["action"] = "browser.open"
    payload["url"] = args[2...].joined(separator: " ")

case "run":
    guard args.count >= 3 else {
        fputs("Usage: neetly run <command>\n", stderr)
        exit(1)
    }
    payload["action"] = "terminal.run"
    payload["command"] = args[2...].joined(separator: " ")

default:
    fputs("Unknown command: \(action)\n\n", stderr)
    printUsage()
    exit(1)
}

// Serialize and send
guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
    fputs("Error: failed to serialize command\n", stderr)
    exit(1)
}

let response = sendToSocket(socketPath: socketPath, data: data, expectResponse: expectResponse)

// Handle response
if action == "tabs", let response = response {
    printTabList(response)
}

// MARK: - Helpers

func printUsage() {
    fputs("Usage: neetly <command> [args]\n\n", stderr)
    fputs("Commands:\n", stderr)
    fputs("  tabs                     List all tabs\n", stderr)
    fputs("  send <tab-id> <text>     Send text to a terminal tab\n", stderr)
    fputs("  visit <url>              Open a browser tab\n", stderr)
    fputs("  run <command>            Open a terminal tab\n", stderr)
}

func printTabList(_ data: Data) {
    struct TabEntry: Codable {
        let tabId: String
        let paneId: String
        let type: String
        let title: String
        let isActive: Bool
    }

    guard let tabs = try? JSONDecoder().decode([TabEntry].self, from: data) else {
        fputs("Error: could not parse tab list\n", stderr)
        return
    }

    if tabs.isEmpty {
        print("No tabs.")
        return
    }

    // Print header
    let idW = 8  // show short IDs
    print(String(format: "%-\(idW)s  %-10s  %-8s  %s", "TAB", "PANE", "TYPE", "TITLE"))
    print(String(repeating: "-", count: 60))

    for tab in tabs {
        let shortTab = String(tab.tabId.prefix(8))
        let shortPane = String(tab.paneId.prefix(8))
        let active = tab.isActive ? " *" : ""
        print(String(format: "%-\(idW)s  %-10s  %-8s  %s%s",
                      shortTab, shortPane, tab.type, tab.title, active))
    }
}

func sendToSocket(socketPath: String, data: Data, expectResponse: Bool) -> Data? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        fputs("Error: could not create socket\n", stderr)
        exit(1)
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

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        fputs("Error: could not connect to neetly1 at \(socketPath)\n", stderr)
        fputs("       \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        exit(1)
    }

    // Send command
    data.withUnsafeBytes { bytes in
        _ = write(fd, bytes.baseAddress!, data.count)
    }

    // Signal we're done writing so server knows the request is complete
    shutdown(fd, SHUT_WR)

    // Read response if expected
    var response: Data?
    if expectResponse {
        var respData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            respData.append(contentsOf: buffer[0..<n])
        }
        if !respData.isEmpty {
            response = respData
        }
    }

    close(fd)
    return response
}
