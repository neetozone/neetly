import Foundation

/// Resolves GitHub PR status for a worktree using the `gh` CLI.
/// Tries three strategies: branch tracking, head branch match, then commit SHA match.
/// Merged/closed PRs only attach if the session HEAD matches the PR's head commit.
class GitHubPRResolver {

    static func resolve(worktreePath: String, completion: @escaping (GitHubPRInfo?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = resolveSync(worktreePath: worktreePath)
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private static let prFields = "number,title,url,state,isDraft,headRefName,headRefOid"

    private static func resolveSync(worktreePath: String) -> GitHubPRInfo? {
        let branch = getCurrentBranch(in: worktreePath)
        let headSHA = getHeadSHA(in: worktreePath)

        if let dict = fetchPRView(in: worktreePath),
           shouldAcceptPR(dict, localBranch: branch, headSHA: headSHA, requireSHAForMerged: false) {
            return prInfoFromDict(dict)
        }

        if let branch = branch {
            let dicts = fetchPRListByBranch(branch, in: worktreePath)
            let accepted = dicts.filter { shouldAcceptPR($0, localBranch: branch, headSHA: headSHA, requireSHAForMerged: false) }
            if let best = pickBest(from: accepted, headSHA: headSHA) {
                return prInfoFromDict(best)
            }
        }

        // SHA search returns any PR that *contains* the commit, so also require
        // the PR's headRefOid to exactly match our HEAD.
        if let sha = headSHA, let branch = branch {
            let dicts = fetchPRListBySHA(sha, in: worktreePath)
            let exactHeadMatches = dicts.filter { ($0["headRefOid"] as? String) == sha }
            let accepted = exactHeadMatches.filter { shouldAcceptPR($0, localBranch: branch, headSHA: headSHA, requireSHAForMerged: true) }
            if let best = pickBest(from: accepted, headSHA: headSHA) {
                return prInfoFromDict(best)
            }
        }

        return nil
    }

    // MARK: - Validation

    /// `requireSHAForMerged`: when true, merged/closed PRs only attach if local
    /// HEAD == PR's headRefOid. Used in the SHA-search fallback to avoid
    /// matching unrelated PRs that happen to contain our commit. The branch-name
    /// paths trust the branch identity and skip this check, so a merged PR
    /// keeps showing after a post-merge rebase.
    private static func shouldAcceptPR(_ dict: [String: Any], localBranch: String?, headSHA: String?, requireSHAForMerged: Bool) -> Bool {
        guard let localBranch = localBranch,
              let headRefName = dict["headRefName"] as? String,
              branchMatches(headRefName, localBranch: localBranch) else {
            return false
        }

        if requireSHAForMerged {
            let state = dict["state"] as? String ?? ""
            if state == "MERGED" || state == "CLOSED" {
                guard let sha = headSHA,
                      let prOid = dict["headRefOid"] as? String,
                      prOid == sha else {
                    return false
                }
            }
        }

        return true
    }

    private static func branchMatches(_ headRefName: String, localBranch: String) -> Bool {
        if headRefName == localBranch { return true }
        // Fork prefix: local "owner/feature" matches PR headRefName "feature"
        if localBranch.contains("/") && localBranch.hasSuffix("/\(headRefName)") {
            return true
        }
        return false
    }

    // MARK: - Fetchers

    private static func fetchPRView(in dir: String) -> [String: Any]? {
        let result = shell("gh pr view --json \(prFields)", in: dir)
        guard result.success,
              let data = result.output.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func fetchPRListByBranch(_ branch: String, in dir: String) -> [[String: Any]] {
        let result = shell("gh pr list --head '\(branch)' --state all --limit 20 --json \(prFields)", in: dir)
        guard result.success,
              let data = result.output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    private static func fetchPRListBySHA(_ sha: String, in dir: String) -> [[String: Any]] {
        let result = shell("gh pr list --search '\(sha) is:pr' --state all --limit 20 --json \(prFields)", in: dir)
        guard result.success,
              let data = result.output.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array
    }

    // MARK: - Sorting

    /// Picks the best PR: prefers HEAD SHA match, then OPEN > MERGED > CLOSED, then highest number.
    private static func pickBest(from array: [[String: Any]], headSHA: String?) -> [String: Any]? {
        guard !array.isEmpty else { return nil }

        let sorted = array.sorted { a, b in
            let aMatch = (a["headRefOid"] as? String) == headSHA
            let bMatch = (b["headRefOid"] as? String) == headSHA
            if aMatch != bMatch { return aMatch }

            let rank: [String: Int] = ["OPEN": 2, "MERGED": 1, "CLOSED": 0]
            let aRank = rank[a["state"] as? String ?? ""] ?? -1
            let bRank = rank[b["state"] as? String ?? ""] ?? -1
            if aRank != bRank { return aRank > bRank }

            return (a["number"] as? Int ?? 0) > (b["number"] as? Int ?? 0)
        }

        return sorted.first
    }

    // MARK: - Git helpers

    private static func getCurrentBranch(in dir: String) -> String? {
        let result = shell("git branch --show-current", in: dir)
        guard result.success else { return nil }
        let branch = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }

    private static func getHeadSHA(in dir: String) -> String? {
        let result = shell("git rev-parse HEAD", in: dir)
        guard result.success else { return nil }
        let sha = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    private static func prInfoFromDict(_ dict: [String: Any]) -> GitHubPRInfo? {
        guard let number = dict["number"] as? Int,
              let title = dict["title"] as? String,
              let url = dict["url"] as? String,
              let stateStr = dict["state"] as? String else {
            return nil
        }

        let isDraft = dict["isDraft"] as? Bool ?? false

        let state: PRState
        switch stateStr {
        case "OPEN":   state = isDraft ? .draft : .open
        case "MERGED": state = .merged
        case "CLOSED": state = .closed
        default:       state = .closed
        }

        return GitHubPRInfo(number: number, title: title, url: url, state: state)
    }

    // MARK: - Shell

    private struct ShellResult {
        let success: Bool
        let output: String
    }

    private static func shell(_ command: String, in directory: String) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return ShellResult(success: false, output: "")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(data: data, encoding: .utf8) ?? ""
        return ShellResult(success: process.terminationStatus == 0, output: out)
    }
}
