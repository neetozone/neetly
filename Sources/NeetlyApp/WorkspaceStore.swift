import Foundation

struct SavedWorkspace: Codable, Equatable {
    let repoPath: String
    let repoName: String
    let workspaceName: String
    let layoutText: String
    let autoReloadOnFileChange: Bool
}

class WorkspaceStore {
    static let shared = WorkspaceStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var configFile: URL {
        configDir.appendingPathComponent("workspaces.json")
    }

    func load() -> [SavedWorkspace] {
        guard let data = try? Data(contentsOf: configFile),
              let workspaces = try? JSONDecoder().decode([SavedWorkspace].self, from: data) else {
            return []
        }
        return workspaces
    }

    func save(_ workspaces: [SavedWorkspace]) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: configFile, options: .atomic)
        } catch {
            NSLog("WorkspaceStore: failed to save: \(error)")
        }
    }

    func add(_ ws: SavedWorkspace) {
        var all = load()
        all.removeAll { $0.repoPath == ws.repoPath && $0.workspaceName == ws.workspaceName }
        all.append(ws)
        save(all)
    }

    func remove(repoPath: String, workspaceName: String) {
        var all = load()
        all.removeAll { $0.repoPath == repoPath && $0.workspaceName == workspaceName }
        save(all)
    }
}
