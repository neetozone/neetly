import Foundation

/// Watches a directory for frontend file changes by polling modification times.
/// Checks every 2 seconds. Reliable on all macOS versions.
class FileWatcher {
    private var timer: DispatchSourceTimer?
    private let repoPath: String
    private var lastCheckTime: Date
    var onChange: (() -> Void)?

    private let watchExtensions: Set<String> = [
        "js", "jsx", "ts", "tsx", "css", "scss", "html", "vue", "svelte",
        "rb", "erb", "haml", "slim", "json", "yaml", "yml",
    ]

    private let ignoreDirs: Set<String> = [
        "node_modules", ".git", "tmp", "log", ".build", "dist", "build", ".next", ".cache",
        "public/packs", "public/assets",
    ]

    init(repoPath: String) {
        self.repoPath = repoPath
        self.lastCheckTime = Date()
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()
        self.timer = timer
        NSLog("FileWatcher: polling \(repoPath) every 2s")
    }

    private func poll() {
        NSLog("FileWatcher: polling...")
        let checkTime = lastCheckTime
        let found = hasRecentChanges(in: repoPath, since: checkTime)
        lastCheckTime = Date()
        if found {
            NSLog("FileWatcher: change detected, reloading browsers")
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        }
    }

    private var pollCount = 0

    private func hasRecentChanges(in dir: String, since: Date) -> Bool {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: dir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            NSLog("FileWatcher: could not create enumerator for \(dir)")
            return false
        }

        var filesChecked = 0
        while let url = enumerator.nextObject() as? URL {
            let lastComponent = url.lastPathComponent
            if ignoreDirs.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard watchExtensions.contains(ext) else { continue }
            filesChecked += 1

            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate else { continue }

            if modDate > since {
                NSLog("FileWatcher: \(url.path) modified at \(modDate) (checking since \(since))")
                return true
            }
        }

        pollCount += 1
        if pollCount <= 3 {
            NSLog("FileWatcher: scanned \(filesChecked) files, no changes since \(since)")
        }

        return false
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stop()
    }
}
