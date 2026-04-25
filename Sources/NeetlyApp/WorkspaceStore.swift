import Foundation

struct SavedWorkspace: Codable, Equatable {
    let repoPath: String
    let repoName: String
    /// Free-form display label.
    let workspaceName: String
    /// Sanitized identity / on-disk directory name. Unique within a repo.
    let worktreeName: String
    let layoutText: String
    let autoReloadOnFileChange: Bool
    var prInfo: GitHubPRInfo? = nil
    /// True if currently attached. Drives auto-restore on app launch.
    /// Detached workspaces stay in the store so they remain in the list.
    var isOpen: Bool = true
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
        all.removeAll { $0.repoPath == ws.repoPath && $0.worktreeName == ws.worktreeName }
        all.append(ws)
        save(all)
    }

    func remove(repoPath: String, worktreeName: String) {
        var all = load()
        all.removeAll { $0.repoPath == repoPath && $0.worktreeName == worktreeName }
        save(all)
    }

    /// Mark a workspace as detached so it doesn't auto-restore next launch,
    /// but keep its entry so it stays visible in the workspace list.
    func markClosed(repoPath: String, worktreeName: String) {
        var all = load()
        guard let idx = all.firstIndex(where: {
            $0.repoPath == repoPath && $0.worktreeName == worktreeName
        }) else { return }
        all[idx].isOpen = false
        save(all)
    }

    func updatePRInfo(repoPath: String, worktreeName: String, prInfo: GitHubPRInfo?) {
        var all = load()
        guard let idx = all.firstIndex(where: {
            $0.repoPath == repoPath && $0.worktreeName == worktreeName
        }) else { return }
        all[idx].prInfo = prInfo
        save(all)
    }
}
