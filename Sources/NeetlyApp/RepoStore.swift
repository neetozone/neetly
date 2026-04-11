import Foundation

class RepoStore {
    static let shared = RepoStore()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var configFile: URL {
        configDir.appendingPathComponent("repos.json")
    }

    func load() -> [RepoConfig] {
        guard let data = try? Data(contentsOf: configFile),
              let repos = try? JSONDecoder().decode([RepoConfig].self, from: data) else {
            return []
        }
        return repos
    }

    func save(_ repos: [RepoConfig]) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(repos)
            try data.write(to: configFile, options: .atomic)
        } catch {
            NSLog("RepoStore: failed to save: \(error)")
        }
    }

    func add(_ repo: RepoConfig) {
        var repos = load()
        // Don't add duplicates by path
        repos.removeAll { $0.path == repo.path }
        repos.append(repo)
        save(repos)
    }

    func remove(id: UUID) {
        var repos = load()
        repos.removeAll { $0.id == id }
        save(repos)
    }
}
