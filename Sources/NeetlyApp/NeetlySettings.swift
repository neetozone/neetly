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
    }

    static var defaultWorktreeBaseDir: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("neetly").path
    }

    var worktreeBaseDir: String {
        load().worktreeBaseDir
    }

    func setWorktreeBaseDir(_ path: String) {
        var s = load()
        s.worktreeBaseDir = path
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
