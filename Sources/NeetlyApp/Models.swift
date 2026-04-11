import Foundation

// MARK: - Layout Model

enum SplitDirection {
    case columns  // left | right
    case rows     // top / bottom
}

indirect enum LayoutNode {
    case run(command: String)
    case visit(url: String)
    case split(direction: SplitDirection, first: LayoutNode, second: LayoutNode)
    case tabs([LayoutNode])  // multiple run/visit in one pane as tabs
}

// MARK: - Workspace Config

struct WorkspaceConfig {
    let repoPath: String
    let workspaceName: String
    let layout: LayoutNode
    let autoReloadOnFileChange: Bool
}

// MARK: - Repo Config (persisted)

struct RepoConfig: Codable, Identifiable {
    let id: UUID
    let path: String
    let name: String
    let layoutText: String

    init(path: String, layoutText: String) {
        self.id = UUID()
        self.path = path
        self.name = URL(fileURLWithPath: path).lastPathComponent
        self.layoutText = layoutText
    }
}

// MARK: - Socket Command

struct SocketCommand: Codable {
    let action: String
    let paneId: String?
    let paneSeq: Int?
    let url: String?
    let command: String?
    let tabId: String?
    let text: String?
    let background: Bool?
}

/// Info about a single tab, returned by tabs.list
struct TabListEntry: Codable {
    let tabId: String
    let tabSeq: Int
    let paneId: String
    let paneSeq: Int
    let type: String      // "terminal" or "browser"
    let title: String
    let isActive: Bool
}

// MARK: - Sequential ID Counter (resets on restart)

class SeqCounter {
    static let shared = SeqCounter()
    private var next = 1

    func nextId() -> Int {
        let id = next
        next += 1
        return id
    }
}

// MARK: - Pane Tab

enum PaneTabKind {
    case terminal
    case browser
}
