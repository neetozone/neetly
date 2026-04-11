import SwiftUI

// MARK: - Screen Navigation

enum SetupScreen {
    case repoList
    case addRepo
    case workspaceName(RepoConfig)
}

// MARK: - Root Setup View

struct SetupView: View {
    @State private var screen: SetupScreen = .repoList
    @State private var repos: [RepoConfig] = []
    var onLaunch: (WorkspaceConfig) -> Void

    var body: some View {
        switch screen {
        case .repoList:
            RepoListScreen(
                repos: $repos,
                onSelectRepo: { repo in screen = .workspaceName(repo) },
                onAddRepo: { screen = .addRepo }
            )
            .onAppear { repos = RepoStore.shared.load() }

        case .addRepo:
            AddRepoScreen(
                onAdd: { repo in
                    RepoStore.shared.add(repo)
                    repos = RepoStore.shared.load()
                    screen = .repoList
                },
                onCancel: { screen = .repoList }
            )

        case .workspaceName(let repo):
            WorkspaceNameScreen(
                repo: repo,
                onStart: { workspaceName, layoutText, autoReload in
                    let parser = LayoutParser()
                    let dedented = dedent(layoutText)
                    guard let layout = parser.parse(dedented) else { return }
                    let config = WorkspaceConfig(
                        repoPath: repo.path,
                        workspaceName: workspaceName,
                        layout: layout,
                        autoReloadOnFileChange: autoReload
                    )
                    onLaunch(config)
                },
                onBack: { screen = .repoList }
            )
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

// MARK: - Screen 1: Repo List

struct RepoListScreen: View {
    @Binding var repos: [RepoConfig]
    var onSelectRepo: (RepoConfig) -> Void
    var onAddRepo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
            .padding(20)

            Divider()

            if repos.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No repos added yet")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Click \"Add Repo\" to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(repos) { repo in
                        Button(action: { onSelectRepo(repo) }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(repo.name)
                                        .font(.system(size: 24, weight: .semibold))
                                    Text(repo.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                                        .font(.system(size: 19, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            RepoStore.shared.remove(id: repos[i].id)
                        }
                        repos = RepoStore.shared.load()
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

// MARK: - Screen 2: Add Repo

struct AddRepoScreen: View {
    @State private var repoPath: String = ""
    @State private var layoutConfig: String = """
        split: columns
        left:
          run: claude --dangerously-skip-permissions
        right:
          tabs:
            run: bin/setup;bin/launch --neetly
            visit: http://localhost:3000
        """
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
        let repo = RepoConfig(path: repoPath, layoutText: layoutConfig)
        onAdd(repo)
    }
}

// MARK: - Screen 3: Workspace Name

struct WorkspaceNameScreen: View {
    let repo: RepoConfig
    @State private var workspaceName: String = ""
    @State private var layoutText: String = ""
    @State private var autoReload: Bool = true
    @FocusState private var isNameFocused: Bool
    var onStart: (String, String, Bool) -> Void
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
                Text("Workspace Name")
                    .font(.system(size: 22, weight: .semibold))
                TextField("", text: $workspaceName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 19))
                    .focused($isNameFocused)
                    .onSubmit {
                        let name = workspaceName.isEmpty ? "default" : workspaceName
                        onStart(name, layoutText, autoReload)
                    }
                Text("A workspace name could be the feature name or the GitHub issue number you are working on.")
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

            HStack {
                Spacer()
                Button("Start") {
                    let name = workspaceName.isEmpty ? "default" : workspaceName
                    onStart(name, layoutText, autoReload)
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
}
