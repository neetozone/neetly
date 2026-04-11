import Foundation

// neetly CLI — companion tool for neetly
//
// Usage:
//   neetly tabs                     — list all tabs
//   neetly send <tab-id> <text>     — send text to a terminal tab
//   neetly visit <url>              — open a browser tab in the current pane
//   neetly run <command>            — open a terminal tab running <command>

let env = ProcessInfo.processInfo.environment

guard let socketPath = env["NEETLY_SOCKET"] else {
    fputs("Error: NEETLY_SOCKET not set. Are you running inside neetly?\n", stderr)
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
    let rawText = args[3...].joined(separator: " ")
    // Convert escape sequences: \n → newline, \t → tab
    payload["text"] = rawText
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "\\t", with: "\t")
    expectResponse = true

case "browser":
    guard args.count >= 4, args[2] == "open" else {
        fputs("Usage: neetly browser open <url> [--pane N] [--background]\n", stderr)
        exit(1)
    }
    payload["action"] = "browser.open"
    let parsed = parseFlags(Array(args[3...]))
    payload["url"] = parsed.positional
    if let pane = parsed.flags["pane"] { payload["paneSeq"] = Int(pane) ?? 0 }
    if parsed.boolFlags.contains("background") { payload["background"] = true }

case "visit":
    // Short alias for: browser open
    guard args.count >= 3 else {
        fputs("Usage: neetly visit <url> [--pane N] [--background]\n", stderr)
        exit(1)
    }
    payload["action"] = "browser.open"
    let parsed = parseFlags(Array(args[2...]))
    payload["url"] = parsed.positional
    if let pane = parsed.flags["pane"] { payload["paneSeq"] = Int(pane) ?? 0 }
    if parsed.boolFlags.contains("background") { payload["background"] = true }

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
switch action {
case "tabs":
    if let response = response {
        printTabList(response)
    } else {
        fputs("No response from neetly. Is the app running?\n", stderr)
    }

case "send":
    if let response = response,
       let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] {
        if json["ok"] as? Bool == true {
            print("Sent to \(args[2])")
        } else {
            let err = json["error"] as? String ?? "unknown error"
            fputs("Error: \(err)\n", stderr)
            exit(1)
        }
    } else {
        fputs("No response from neetly.\n", stderr)
    }

default:
    break
}

// MARK: - Helpers

func printUsage() {
    fputs("Usage: neetly <command> [args]\n\n", stderr)
    fputs("Commands:\n", stderr)
    fputs("  tabs                                   List all tabs\n", stderr)
    fputs("  send <tab#> <text>                     Send text to a terminal tab\n", stderr)
    fputs("  browser open <url> [--pane N] [--background]  Open a browser tab\n", stderr)
    fputs("  visit <url> [--pane N] [--background]  Alias for browser open\n", stderr)
    fputs("  run <command>                          Open a terminal tab\n", stderr)
}

/// Parse positional args and --flags from an argument list.
func parseFlags(_ args: [String]) -> (positional: String, flags: [String: String], boolFlags: Set<String>) {
    var positional: [String] = []
    var flags: [String: String] = [:]
    var boolFlags: Set<String> = []
    var i = 0
    while i < args.count {
        let arg = args[i]
        if arg.hasPrefix("--") {
            let name = String(arg.dropFirst(2))
            if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                flags[name] = args[i + 1]
                i += 2
            } else {
                boolFlags.insert(name)
                i += 1
            }
        } else {
            positional.append(arg)
            i += 1
        }
    }
    return (positional.joined(separator: " "), flags, boolFlags)
}

func printTabList(_ data: Data) {
    struct TabEntry: Codable {
        let tabId: String
        let tabSeq: Int
        let paneId: String
        let paneSeq: Int
        let type: String
        let title: String
        let isActive: Bool
    }

    guard var tabs = try? JSONDecoder().decode([TabEntry].self, from: data) else {
        fputs("Error: could not parse tab list\n", stderr)
        return
    }

    if tabs.isEmpty {
        print("No tabs.")
        return
    }

    tabs.sort { $0.tabSeq < $1.tabSeq }

    print("TAB  PANE  TYPE      TITLE")
    print(String(repeating: "-", count: 50))

    for tab in tabs {
        let tabNum = String(tab.tabSeq).padding(toLength: 3, withPad: " ", startingAt: 0)
        let paneNum = String(tab.paneSeq).padding(toLength: 4, withPad: " ", startingAt: 0)
        let type = tab.type.padding(toLength: 8, withPad: " ", startingAt: 0)
        let active = tab.isActive ? " *" : ""
        print("\(tabNum)  \(paneNum)  \(type)  \(tab.title)\(active)")
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
        fputs("Error: could not connect to neetly at \(socketPath)\n", stderr)
        fputs("       \(String(cString: strerror(errno)))\n", stderr)
        close(fd)
        exit(1)
    }

    // Set a read timeout so we don't hang forever
    var tv = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

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
        response = respData.isEmpty ? nil : respData
    }

    close(fd)
    return response
}
