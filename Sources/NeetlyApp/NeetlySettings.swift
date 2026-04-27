import Foundation

class NeetlySettings {
    static let shared = NeetlySettings()

    private let configDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/neetly")
    }()

    private var settingsFile: URL {
        configDir.appendingPathComponent("settings.json")
    }

    private struct Settings: Codable {
        var worktreeBaseDir: String
        var diffCommand: String?
        /// Shell command to run after a worktree is created. The variable
        /// `$WORKTREE_DIRECTORY` is set to the new worktree's absolute path.
        var postWorktreeCreateCommand: String?
    }

    static var defaultWorktreeBaseDir: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("neetly-worktrees").path
    }

    var worktreeBaseDir: String {
        load().worktreeBaseDir
    }

    func setWorktreeBaseDir(_ path: String) {
        var s = load()
        s.worktreeBaseDir = path
        save(s)
    }

    static let defaultDiffCommand = "lazygit"

    var diffCommand: String {
        load().diffCommand ?? Self.defaultDiffCommand
    }

    func setDiffCommand(_ command: String) {
        var s = load()
        s.diffCommand = command
        save(s)
    }

    var postWorktreeCreateCommand: String {
        load().postWorktreeCreateCommand ?? ""
    }

    func setPostWorktreeCreateCommand(_ command: String) {
        var s = load()
        s.postWorktreeCreateCommand = command
        save(s)
    }

    private func load() -> Settings {
        guard let data = try? Data(contentsOf: settingsFile),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings(worktreeBaseDir: Self.defaultWorktreeBaseDir)
        }
        return settings
    }

    private func save(_ settings: Settings) {
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(settings)
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            NSLog("NeetlySettings: failed to save: \(error)")
        }
    }
}
