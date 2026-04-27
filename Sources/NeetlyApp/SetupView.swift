import SwiftUI

// MARK: - Screen Navigation

enum SetupScreen {
    case repoList
    case addRepo
    case editLayout(RepoConfig)
    case workspaceList(RepoConfig)
    case workspaceName(RepoConfig)
    case settings
    case activities
}

// MARK: - Root Setup View

struct SetupView: View {
    @State private var screen: SetupScreen
    @State private var repos: [RepoConfig] = []
    var onLaunch: (WorkspaceConfig) -> Void

    init(initialScreen: SetupScreen = .repoList, onLaunch: @escaping (WorkspaceConfig) -> Void) {
        _screen = State(initialValue: initialScreen)
        self.onLaunch = onLaunch
    }

    var body: some View {
        switch screen {
        case .repoList:
            RepoListScreen(
                repos: $repos,
                onSelectRepo: { repo in screen = .workspaceList(repo) },
                onAddRepo: { screen = .addRepo },
                onEditLayout: { repo in screen = .editLayout(repo) },
                onSettings: { screen = .settings },
                onActivities: { screen = .activities }
            )
            .onAppear { repos = RepoStore.shared.load() }

        case .addRepo:
            AddRepoScreen(
                onAdd: { repo in
                    RepoStore.shared.add(repo)
                    repos = RepoStore.shared.load()
                    screen = .workspaceName(repo)
                },
                onCancel: { screen = .repoList }
            )

        case .editLayout(let repo):
            EditLayoutScreen(
                repo: repo,
                onSave: { updated in
                    RepoStore.shared.update(updated)
                    repos = RepoStore.shared.load()
                    screen = .repoList
                },
                onCancel: { screen = .repoList }
            )

        case .workspaceList(let repo):
            WorkspaceListScreen(
                repo: repo,
                onSelectWorkspace: { workspaceName, worktreeName in
                    let parser = LayoutParser()
                    let dedented = dedent(repo.layoutText)
                    guard let layout = parser.parse(dedented) else { return }
                    let worktreePath = GitWorktree.worktreePath(repoName: repo.name, worktreeName: worktreeName)
                    let config = WorkspaceConfig(
                        repoPath: worktreePath,
                        repoName: repo.name,
                        workspaceName: workspaceName,
                        worktreeName: worktreeName,
                        layout: layout,
                        layoutText: repo.layoutText,
                        autoReloadOnFileChange: true
                    )
                    onLaunch(config)
                },
                onAddWorkspace: { screen = .workspaceName(repo) },
                onBack: { screen = .repoList }
            )

        case .workspaceName(let repo):
            WorkspaceNameScreen(
                repo: repo,
                onStart: { workspaceName, worktreeName, layoutText, autoReload, worktreePath in
                    let parser = LayoutParser()
                    let dedented = dedent(layoutText)
                    guard let layout = parser.parse(dedented) else { return }

                    NSLog("Workspace: using repoPath = \(worktreePath)")
                    let config = WorkspaceConfig(
                        repoPath: worktreePath,
                        repoName: repo.name,
                        workspaceName: workspaceName,
                        worktreeName: worktreeName,
                        layout: layout,
                        layoutText: layoutText,
                        autoReloadOnFileChange: autoReload
                    )
                    ActivityStore.shared.log(.workspaceCreated, repoName: repo.name, detail: workspaceName)
                    onLaunch(config)
                },
                onBack: { screen = .repoList }
            )

        case .settings:
            SettingsScreen(onBack: { screen = .repoList })

        case .activities:
            ActivityScreen(onBack: { screen = .repoList })
        }
    }

    private func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmpty.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return lines.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : $0 }
            .joined(separator: "\n")
    }
}

// MARK: - Window Sizer

/// Grows the hosting window downward to fit a target content height,
/// clamped to the screen's visible area (minus a bottom margin). Only
/// grows — never shrinks — so user manual resizes aren't fought.
private struct WindowHeightSizer: NSViewRepresentable {
    let targetHeight: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let target = targetHeight
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }

            let bottomMargin: CGFloat = 80
            let baseHeight: CGFloat = 600
            let maxHeight = max(baseHeight, screen.visibleFrame.height - bottomMargin)
            let clamped = min(max(target, baseHeight), maxHeight)

            let current = window.frame
            guard clamped > current.height + 1 else { return }

            // Keep the title bar fixed; extend downward. If that would push
            // the bottom off-screen, pin to the visible frame's minY.
            let topY = current.maxY
            let newY = max(topY - clamped, screen.visibleFrame.minY)
            let newFrame = NSRect(x: current.minX, y: newY, width: current.width, height: clamped)
            window.setFrame(newFrame, display: true, animate: true)
        }
    }
}

// MARK: - Screen 1: Repo List

struct RepoListScreen: View {
    @Binding var repos: [RepoConfig]
    var onSelectRepo: (RepoConfig) -> Void
    var onAddRepo: () -> Void
    var onEditLayout: (RepoConfig) -> Void
    var onSettings: () -> Void
    var onActivities: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .trailing, spacing: 10) {
                HStack {
                    Text("neetly").font(.system(size: 48, weight: .bold, design: .monospaced))
                    Spacer()
                    Button(action: onAddRepo) {
                        Label("Add Repo", systemImage: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                HStack(spacing: 16) {
                    Button(action: onActivities) {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet.clipboard")
                            Text("Activities")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Activities")
                    Button(action: onSettings) {
                        HStack(spacing: 3) {
                            Image(systemName: "gearshape")
                            Text("Settings")
                        }
                        .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
            .padding(20)

            Divider()

            if repos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No repos added yet")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Click \"Add Repo\" to get started")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(repos.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) { repo in
                        Button(action: { onSelectRepo(repo) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(repo.name)
                                            .font(.system(size: 24, weight: .semibold))
                                        Menu {
                                            Button(action: { onEditLayout(repo) }) {
                                                Label("Settings", systemImage: "gearshape")
                                            }
                                            Divider()
                                            Button(role: .destructive, action: {
                                                RepoStore.shared.remove(id: repo.id)
                                                repos = RepoStore.shared.load()
                                            }) {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        } label: {
                                            Image(systemName: "ellipsis")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary.opacity(0.6))
                                                .frame(width: 26, height: 26)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .fill(Color.primary.opacity(0.001))
                                                )
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(HoverButtonStyle())
                                    }
                                    Text(repo.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                        .font(.system(size: 19, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        // Header + divider + list chrome ≈ 170pt; each row ≈ 80pt.
        // Overshooting is safe — WindowHeightSizer clamps to screen.
        .background(WindowHeightSizer(targetHeight: 170 + CGFloat(repos.count) * 80))
    }
}

// MARK: - Screen 2: Add Repo

struct AddRepoScreen: View {
    @State private var repoPath: String = ""
    @State private var layoutConfig: String = """
        split: columns
        left:
          size: 40%
          run: claude --dangerously-skip-permissions
        right:
          run: bin/setup-mise && bin/launch --neetly
        """
    @State private var pullMain: Bool = true
    @State private var errorMessage: String?
    var onAdd: (RepoConfig) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Text("Add Repo").font(.headline)
                Spacer()
            }

            HStack {
                TextField("/path/to/repo", text: $repoPath)
                    .textFieldStyle(.roundedBorder)
                Button("Browse...") { pickRepo() }
            }

            Toggle(isOn: $pullMain) {
                Text("Always start work from the main branch and always do a git pull on main branch before starting the work.")
                    .font(.system(size: 13))
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Layout")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextEditor(text: $layoutConfig)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 150)
                    .border(Color.gray.opacity(0.3))
            }

            if let error = errorMessage {
                Text(error).foregroundColor(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Add Repo") { addRepo() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500, height: 400)
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a repository directory"
        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url.path
        }
    }

    private func addRepo() {
        errorMessage = nil
        guard !repoPath.isEmpty else {
            errorMessage = "Please select a repository."
            return
        }
        let repo = RepoConfig(path: repoPath, layoutText: layoutConfig, pullMainBeforeWork: pullMain)
        onAdd(repo)
    }
}

// MARK: - Screen 3: Workspace Name

struct WorkspaceNameScreen: View {
    let repo: RepoConfig
    @State private var workspaceName: String = ""
    @State private var layoutText: String = ""
    @State private var autoReload: Bool = true
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool
    /// (workspaceName, worktreeName, layoutText, autoReload, worktreePath)
    var onStart: (String, String, String, Bool, String) -> Void
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Spacer()
            }

            Text(repo.name)
                .font(.system(size: 29, weight: .bold, design: .monospaced))

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("New Session Name")
                    .font(.system(size: 22, weight: .semibold))
                TextField("", text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 19))
                    .focused($isNameFocused)
                    .onSubmit { startWorkspace() }
                    .disabled(isLoading)
                    .onChange(of: workspaceName) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        if trimmed.count > 60 {
                            errorMessage = "Session name must be 60 characters or fewer (current: \(trimmed.count))."
                        } else {
                            errorMessage = nil
                        }
                    }
                Text("A session name could be the feature name or the GitHub issue number you are working on.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $autoReload) {
                    Text("Auto-reload browser on file changes")
                        .font(.system(size: 17))
                }
                Text("WKWebView doesn't support HMR. When enabled, browser tabs reload automatically when JavaScript files change in the repo.")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 6) {
                Text("Layout")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.top, 8)
                TextEditor(text: $layoutText)
                    .font(.system(size: 15, design: .monospaced))
                    .frame(minHeight: 100)
                    .border(Color.gray.opacity(0.3))
            }

            Spacer()

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 20))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.green)
                    Text("Creating worktree...")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Button("Start") { startWorkspace() }
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            isNameFocused = true
            layoutText = repo.layoutText
        }
    }

    private func startWorkspace() {
        guard !isLoading else { return }
        errorMessage = nil

        let name = workspaceName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "Please provide a session name."
            return
        }
        guard name.count <= 60 else {
            errorMessage = "Session name must be 60 characters or fewer (current: \(name.count))."
            return
        }

        let worktreeName = GitWorktree.uniqueWorktreeName(for: repo.name, baseName: name)
        guard !worktreeName.isEmpty else {
            errorMessage = "Session name produces an empty worktree slug — try different characters."
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async {
            // Create git worktree (runs git checkout, pull, worktree add)
            let git = GitWorktree(repoPath: repo.path)
            let result = git.createWorktree(worktreeName: worktreeName, pullMain: repo.pullMainBeforeWork)

            DispatchQueue.main.async {
                switch result {
                case .success(let path):
                    onStart(name, worktreeName, layoutText, autoReload, path)
                case .failure(let message):
                    errorMessage = message
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Screen 4: Edit Layout

struct EditLayoutScreen: View {
    let repo: RepoConfig
    @State private var layoutText: String = ""
    @State private var pullMain: Bool = true
    var onSave: (RepoConfig) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button(action: onCancel) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }

            Text(repo.name)
                .font(.system(size: 29, weight: .bold, design: .monospaced))

            Toggle(isOn: $pullMain) {
                Text("Always start work from the main branch and always do a git pull on main branch before starting the work.")
                    .font(.system(size: 13))
            }
            .padding(.top, 8)

            Text("Default Layout")
                .font(.system(size: 18, weight: .semibold))

            TextEditor(text: $layoutText)
                .font(.system(size: 15, design: .monospaced))
                .border(Color.gray.opacity(0.3))

            HStack {
                Spacer()
                Button("Save") {
                    let updated = RepoConfig(id: repo.id, path: repo.path, name: repo.name, layoutText: layoutText, pullMainBeforeWork: pullMain)
                    onSave(updated)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.bottom, 8)
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            layoutText = repo.layoutText
            pullMain = repo.pullMainBeforeWork
        }
    }
}

// MARK: - Screen 5: Workspace List (existing workspaces for a repo)

struct WorkspaceListEntry: Identifiable {
    let workspaceName: String
    let worktreeName: String
    var prInfo: GitHubPRInfo?
    var id: String { worktreeName }
}

struct WorkspaceListScreen: View {
    let repo: RepoConfig
    @State private var workspaces: [WorkspaceListEntry] = []
    @State private var workspaceToDelete: WorkspaceListEntry?
    /// Called with (workspaceName, worktreeName).
    var onSelectWorkspace: (String, String) -> Void
    var onAddWorkspace: () -> Void
    var onBack: () -> Void

    private func loadWorkspaces() -> [WorkspaceListEntry] {
        return WorkspaceStore.shared.load()
            .filter { $0.repoName == repo.name }
            .map { WorkspaceListEntry(workspaceName: $0.workspaceName, worktreeName: $0.worktreeName, prInfo: $0.prInfo) }
    }

    private func fetchMissingPRInfo() {
        let repoName = repo.name
        for entry in workspaces where entry.prInfo == nil {
            let worktreePath = GitWorktree.worktreePath(repoName: repoName, worktreeName: entry.worktreeName)
            let worktreeName = entry.worktreeName
            GitHubPRResolver.resolve(worktreePath: worktreePath) { info in
                guard let info = info else { return }
                if let idx = workspaces.firstIndex(where: { $0.worktreeName == worktreeName }) {
                    workspaces[idx].prInfo = info
                }
                WorkspaceStore.shared.updatePRInfo(
                    repoPath: worktreePath,
                    worktreeName: worktreeName,
                    prInfo: info
                )
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onAddWorkspace) {
                    Label("Add Session", systemImage: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)

            HStack {
                Text(repo.name)
                    .font(.system(size: 29, weight: .bold, design: .monospaced))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if workspaces.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("No sessions yet")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Click \"Add Session\" to create one")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(workspaces) { entry in
                        Button(action: { onSelectWorkspace(entry.workspaceName, entry.worktreeName) }) {
                            HStack {
                                HStack(spacing: 10) {
                                    Text(entry.workspaceName)
                                        .font(.system(size: 22, weight: .semibold))
                                    if let pr = entry.prInfo {
                                        PRBadge(prInfo: pr)
                                    }
                                    Menu {
                                        Button(role: .destructive, action: {
                                            workspaceToDelete = entry
                                        }) {
                                            Label("Delete Session", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.primary.opacity(0.6))
                                            .frame(width: 26, height: 26)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(HoverButtonStyle())
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            workspaces = loadWorkspaces()
            fetchMissingPRInfo()
        }
        .sheet(item: $workspaceToDelete) { target in
            DeleteWorktreeSheet(
                repoName: repo.name,
                workspaceName: target.workspaceName,
                worktreeName: target.worktreeName,
                onCancel: { workspaceToDelete = nil },
                onDelete: {
                    let workspaceLabel = target.workspaceName
                    let worktreeName = target.worktreeName
                    ActivityStore.shared.log(.workspaceDeleted, repoName: repo.name, detail: workspaceLabel)
                    workspaces.removeAll { $0.worktreeName == worktreeName }
                    workspaceToDelete = nil

                    // Close the workspace if currently open (must be on main thread)
                    let worktreePath = GitWorktree.worktreePath(repoName: repo.name, worktreeName: worktreeName)
                    WorkspaceStore.shared.remove(repoPath: worktreePath, worktreeName: worktreeName)
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.workspaceWindowController?.closeWorkspaceByPath(worktreePath)
                    }

                    // Run the actual deletion in the background
                    let repoPath = repo.path
                    let repoName = repo.name
                    DispatchQueue.global(qos: .userInitiated).async {
                        _ = GitWorktree.deleteWorktree(
                            parentRepoPath: repoPath,
                            repoName: repoName,
                            worktreeName: worktreeName
                        )
                    }
                }
            )
        }
    }
}

struct DeleteWorktreeSheet: View {
    let repoName: String
    let workspaceName: String
    let worktreeName: String
    var onCancel: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deleting \(workspaceName)?")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(white: 0.95))

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This will delete the worktree at:")
                        .font(.system(size: 14))
                    Text(GitWorktree.worktreePath(repoName: repoName, worktreeName: worktreeName)
                        .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Delete", role: .destructive, action: onDelete)
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .frame(width: 600)
    }
}

// MARK: - Settings

struct SettingsScreen: View {
    @State private var worktreeDir: String = NeetlySettings.shared.worktreeBaseDir
    @State private var diffCommand: String = NeetlySettings.shared.diffCommand
    @State private var postCreateCommand: String = NeetlySettings.shared.postWorktreeCreateCommand
    @State private var message: String?
    @State private var messageIsError: Bool = false
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)

            Text("neetly")
                .font(.system(size: 29, weight: .bold, design: .monospaced))
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.system(size: 22, weight: .semibold))
                        .padding(.top, 20)

                    // Worktree directory
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Worktree Directory")
                            .font(.system(size: 16, weight: .medium))
                        Text("The directory where neetly creates git worktrees for your sessions.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("", text: $worktreeDir)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 15, design: .monospaced))
                            Button("Browse...") { pickDirectory() }
                        }
                    }

                    // Post-create command
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Post-Create Command")
                            .font(.system(size: 16, weight: .medium))
                        Text("Runs after a new worktree is created. Use $WORKTREE_DIRECTORY for the worktree's absolute path. Leave blank to skip. A common use case is running mise trust $WORKTREE_DIRECTORY for the folks who use mise to manage their Ruby versions.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("e.g. mise trust $WORKTREE_DIRECTORY", text: $postCreateCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                    }

                    Divider()

                    // Cmd+D: Open Diff
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Open Diff")
                                .font(.system(size: 16, weight: .medium))
                            Text("Cmd+D")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text("Opens a terminal in the last pane with this command and maximizes it.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        TextField("", text: $diffCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 15, design: .monospaced))
                    }

                    // Cmd+Z: Close Diff (read-only)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("Close Diff")
                                .font(.system(size: 16, weight: .medium))
                            Text("Cmd+Z")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text("Unmaximizes the pane and closes the active tab. This is not configurable.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    if let msg = message {
                        Text(msg)
                            .font(.system(size: 13))
                            .foregroundColor(messageIsError ? .red : .green)
                    }

                    HStack {
                        Spacer()
                        Button("Save") { save() }
                            .keyboardShortcut(.return)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the directory for worktrees"
        if panel.runModal() == .OK, let url = panel.url {
            worktreeDir = url.path
        }
    }

    private func save() {
        message = nil
        let path = worktreeDir.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            message = "Please provide a directory path."
            messageIsError = true
            return
        }

        let expanded = NSString(string: path).expandingTildeInPath

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
            worktreeDir = expanded
            NeetlySettings.shared.setWorktreeBaseDir(expanded)

            let cmd = diffCommand.trimmingCharacters(in: .whitespaces)
            NeetlySettings.shared.setDiffCommand(cmd.isEmpty ? NeetlySettings.defaultDiffCommand : cmd)

            NeetlySettings.shared.setPostWorktreeCreateCommand(
                postCreateCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            message = "Settings saved."
            messageIsError = false
        } else {
            message = "Directory does not exist: \(expanded)"
            messageIsError = true
        }
    }
}

// MARK: - Activities

struct ActivityScreen: View {
    @State private var activities: [Activity] = []
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(20)

            HStack {
                Text("Activities")
                    .font(.system(size: 29, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Divider()

            if activities.isEmpty {
                Spacer()
                Text("No activities yet")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(activities) { activity in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: activityIcon(activity.kind))
                                .font(.system(size: 14))
                                .foregroundColor(activityColor(activity.kind))
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 4) {
                                activityText(activity)
                                    .font(.system(size: 15))
                                Text(formatDate(activity.timestamp))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .onAppear {
            activities = ActivityStore.shared.load()
        }
    }

    @ViewBuilder
    private func activityText(_ activity: Activity) -> some View {
        if activity.kind == .prOpened, let urlStr = activity.prURL, let url = URL(string: urlStr) {
            let state = activity.prState.map { " (\($0))" } ?? ""
            HStack(spacing: 0) {
                Text("Opened PR ")
                Text(verbatim: "#\(activity.detail)\(state)")
                    .foregroundColor(.blue)
                    .underline()
                    .onTapGesture { NSWorkspace.shared.open(url) }
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                Text(" for repo \(activity.repoName).")
            }
        } else {
            Text(activity.description)
        }
    }

    private func activityIcon(_ kind: Activity.Kind) -> String {
        switch kind {
        case .workspaceCreated: return "plus.circle.fill"
        case .workspaceDeleted: return "trash.circle.fill"
        case .prOpened:         return "arrow.triangle.pull"
        }
    }

    private func activityColor(_ kind: Activity.Kind) -> Color {
        switch kind {
        case .workspaceCreated: return .green
        case .workspaceDeleted: return .red
        case .prOpened:         return .purple
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - PR Badge

struct PRBadge: View {
    let prInfo: GitHubPRInfo

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "PR #\(prInfo.number) (\(stateLabel))")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .clipShape(Capsule())
        .help("#\(prInfo.number) \(prInfo.title)")
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onTapGesture {
            if let url = URL(string: prInfo.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var color: Color {
        switch prInfo.state {
        case .open:   return .green
        case .draft:  return .gray
        case .merged: return .purple
        case .closed: return .red
        }
    }

    private var stateLabel: String {
        switch prInfo.state {
        case .open:   return "Open"
        case .draft:  return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }
}

// MARK: - Hover Button Style

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
