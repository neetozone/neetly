import Foundation

enum WorktreeResult {
    case success(path: String)
    case failure(message: String)
}

class GitWorktree {
    let repoPath: String
    let repoName: String

    init(repoPath: String) {
        self.repoPath = repoPath
        self.repoName = URL(fileURLWithPath: repoPath).lastPathComponent
    }

    /// Returns names of existing worktrees under the configured base directory.
    /// Only returns directories that are actual git worktrees (have a .git file).
    static func listWorktrees(for repoName: String) -> [String] {
        let base = "\(NeetlySettings.shared.worktreeBaseDir)/\(repoName)"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: base) else {
            return []
        }
        return entries
            .filter { !$0.hasPrefix(".") }
            .filter {
                // A valid git worktree has a `.git` file (not a directory) that points back
                // to the parent repo's worktrees folder.
                let gitPath = "\(base)/\($0)/.git"
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir)
                return exists && !isDir.boolValue
            }
            .sorted()
    }

    /// Returns the on-disk worktree path for a given workspace name.
    static func worktreePath(repoName: String, workspaceName: String) -> String {
        return "\(NeetlySettings.shared.worktreeBaseDir)/\(repoName)/\(workspaceName)"
    }

    /// Returns (additions, deletions) of uncommitted changes vs HEAD, or nil on error.
    static func diffStats(worktreePath: String) -> (added: Int, deleted: Int)? {
        guard FileManager.default.fileExists(atPath: worktreePath) else { return nil }
        let helper = GitWorktree(repoPath: worktreePath)
        let result = helper.shell("git diff --numstat HEAD", in: worktreePath)
        guard result.success else { return nil }
        var added = 0
        var deleted = 0
        for line in result.output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }
            // Binary files show "-" instead of numbers
            added += Int(parts[0]) ?? 0
            deleted += Int(parts[1]) ?? 0
        }
        return (added, deleted)
    }

    /// Returns the short commit SHA of the worktree's current HEAD, or nil.
    static func headShortSha(worktreePath: String) -> String? {
        guard FileManager.default.fileExists(atPath: worktreePath) else { return nil }
        let helper = GitWorktree(repoPath: worktreePath)
        let result = helper.shell("git rev-parse --short HEAD", in: worktreePath)
        guard result.success else { return nil }
        let sha = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    /// Returns the GitHub commit URL for the worktree's current HEAD, or nil
    /// if the remote is not a GitHub URL.
    static func headCommitURL(worktreePath: String) -> String? {
        guard FileManager.default.fileExists(atPath: worktreePath) else { return nil }
        let helper = GitWorktree(repoPath: worktreePath)
        let shaRes = helper.shell("git rev-parse HEAD", in: worktreePath)
        let remoteRes = helper.shell("git remote get-url origin", in: worktreePath)
        guard shaRes.success, remoteRes.success else { return nil }
        let sha = shaRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteRes.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sha.isEmpty, !remote.isEmpty else { return nil }
        guard let repoURL = githubRepoURL(fromRemote: remote) else { return nil }
        return "\(repoURL)/commit/\(sha)"
    }

    /// Convert a git remote URL to a https://github.com/owner/repo URL, or nil.
    private static func githubRepoURL(fromRemote remote: String) -> String? {
        var path: String
        if remote.hasPrefix("git@github.com:") {
            path = String(remote.dropFirst("git@github.com:".count))
        } else if remote.hasPrefix("https://github.com/") {
            path = String(remote.dropFirst("https://github.com/".count))
        } else if remote.hasPrefix("ssh://git@github.com/") {
            path = String(remote.dropFirst("ssh://git@github.com/".count))
        } else {
            return nil
        }
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        guard !path.isEmpty else { return nil }
        return "https://github.com/\(path)"
    }

    /// Delete a worktree: run `git worktree remove --force` from the parent repo,
    /// then `rm -rf` as a fallback if anything is left.
    static func deleteWorktree(parentRepoPath: String, repoName: String, workspaceName: String) -> Bool {
        let path = worktreePath(repoName: repoName, workspaceName: workspaceName)

        // Try git worktree remove first (proper way — also unregisters from parent repo)
        let helper = GitWorktree(repoPath: parentRepoPath)
        let result = helper.shell("git worktree remove --force '\(path)'", in: parentRepoPath)
        NSLog("GitWorktree: remove → \(result)")

        // Fall back to rm -rf if directory still exists
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        return !FileManager.default.fileExists(atPath: path)
    }

    func createWorktree(workspaceName: String, pullMain: Bool = true) -> WorktreeResult {
        // Sanitize workspace name for git branch: replace spaces with hyphens, strip invalid chars
        let branchName = workspaceName
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "..", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "/" || $0 == "." }

        let worktreePath = "\(NeetlySettings.shared.worktreeBaseDir)/\(repoName)/\(branchName)"

        // If worktree already exists, just use it
        if FileManager.default.fileExists(atPath: worktreePath) {
            NSLog("GitWorktree: worktree already exists at \(worktreePath)")
            return .success(path: worktreePath)
        }

        let defaultBranch = detectDefaultBranch()
        NSLog("GitWorktree: default branch = \(defaultBranch)")

        if pullMain {
            // Stash any uncommitted changes
            let stashResult = shell("git stash --include-untracked", in: repoPath)
            NSLog("GitWorktree: stash: \(stashResult)")
            let didStash = stashResult.success && !stashResult.output.contains("No local changes")

            let checkoutResult = shell("git checkout \(defaultBranch)", in: repoPath)
            NSLog("GitWorktree: checkout: \(checkoutResult)")

            let pullResult = shell("git pull", in: repoPath)
            NSLog("GitWorktree: pull: \(pullResult)")

            if !pullResult.success {
                // Restore stashed changes before aborting
                if didStash {
                    let popResult = shell("git stash pop", in: repoPath)
                    NSLog("GitWorktree: stash pop: \(popResult)")
                }
                return .failure(message: "git pull failed: \(pullResult.output)")
            }

            // Restore stashed changes
            if didStash {
                let popResult = shell("git stash pop", in: repoPath)
                NSLog("GitWorktree: stash pop: \(popResult)")
            }
        }

        // Create parent directory
        let parentDir = (worktreePath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Try creating worktree with new branch
        let cmd1 = "git worktree add -b '\(branchName)' '\(worktreePath)' \(defaultBranch)"
        let result1 = shell(cmd1, in: repoPath)
        NSLog("GitWorktree: \(cmd1) → \(result1)")

        if result1.success {
            return .success(path: worktreePath)
        }

        // Branch might already exist — try without -b
        let cmd2 = "git worktree add '\(worktreePath)' '\(branchName)'"
        let result2 = shell(cmd2, in: repoPath)
        NSLog("GitWorktree: \(cmd2) → \(result2)")

        if result2.success {
            return .success(path: worktreePath)
        }

        return .failure(message: "Failed: \(result1.output) / \(result2.output)")
    }

    private func detectDefaultBranch() -> String {
        let result = shell("git symbolic-ref refs/remotes/origin/HEAD", in: repoPath)
        if result.success {
            let ref = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if let last = ref.split(separator: "/").last {
                return String(last)
            }
        }

        let mainCheck = shell("git rev-parse --verify main", in: repoPath)
        if mainCheck.success { return "main" }

        return "master"
    }

    private struct ShellResult: CustomStringConvertible {
        let success: Bool
        let output: String
        var description: String { success ? "OK" : "FAIL: \(output)" }
    }

    /// Run a shell command via /bin/zsh -c to get proper PATH and env.
    private func shell(_ command: String, in directory: String) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return ShellResult(success: false, output: error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        let combined = (out + err).trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellResult(success: process.terminationStatus == 0, output: combined)
    }
}
