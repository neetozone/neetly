import Foundation

struct Activity: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let kind: Kind
    let repoName: String
    let detail: String
    var prURL: String?
    var prState: String?

    enum Kind: String, Codable {
        case workspaceCreated
        case workspaceDeleted
        case prOpened
    }

    var description: String {
        switch kind {
        case .workspaceCreated:
            return "Created workspace \(detail) for repo \(repoName)."
        case .workspaceDeleted:
            return "Deleted workspace \(detail) from repo \(repoName)."
        case .prOpened:
            let state = prState.map { " (\($0))" } ?? ""
            return "Opened PR #\(detail)\(state) for repo \(repoName)."
        }
    }
}

class ActivityStore {
    static let shared = ActivityStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var configFile: URL {
        configDir.appendingPathComponent("activities.json")
    }

    func load() -> [Activity] {
        guard let data = try? Data(contentsOf: configFile),
              let activities = try? JSONDecoder().decode([Activity].self, from: data) else {
            return []
        }
        return activities.sorted { $0.timestamp > $1.timestamp }
    }

    private func save(_ activities: [Activity]) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(activities)
            try data.write(to: configFile, options: .atomic)
        } catch {
            NSLog("ActivityStore: failed to save: \(error)")
        }
    }

    func log(_ kind: Activity.Kind, repoName: String, detail: String, prURL: String? = nil) {
        var all = load()
        let activity = Activity(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            repoName: repoName,
            detail: detail,
            prURL: prURL
        )
        all.insert(activity, at: 0)
        // Keep last 200 activities
        if all.count > 200 { all = Array(all.prefix(200)) }
        save(all)
    }

    /// Update the state of an existing PR activity (e.g., from Open to Merged).
    func updatePRState(repoName: String, prNumber: String, state: String, url: String?) {
        var all = load()
        if let idx = all.firstIndex(where: {
            $0.kind == .prOpened && $0.repoName == repoName && $0.detail == prNumber
        }) {
            all[idx].prState = state
            if let url = url { all[idx].prURL = url }
            save(all)
        }
    }
}
