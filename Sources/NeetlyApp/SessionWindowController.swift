import AppKit

/// Holds the runtime state for one session.
class Session {
    let config: SessionConfig
    let socketServer: SocketServer
    let splitTree: SplitTreeController
    var fileWatcher: FileWatcher?
    /// Status color for the session tab. nil = default, green = done, etc.
    var statusColor: NSColor?
    /// Resolved GitHub PR info. nil = no PR found or not yet fetched.
    var prInfo: GitHubPRInfo?
    /// Short commit SHA of the worktree's current HEAD.
    var commitSha: String?
    /// GitHub commit URL for the worktree's current HEAD, if the remote is GitHub.
    var commitURL: String?
    /// Uncommitted diff stats (lines added/deleted vs HEAD).
    var diffStats: (added: Int, deleted: Int)?
    var onStatusChanged: (() -> Void)?

    init(config: SessionConfig) {
        // If a previous Claude Code session exists for this worktree, append
        // --continue to any `claude` run command so re-attaching resumes the
        // session instead of starting a fresh one.
        let layout = GitWorktree.hasClaudeSession(forWorktreePath: config.repoPath)
            ? Self.appendingClaudeContinue(to: config.layout)
            : config.layout

        self.socketServer = SocketServer()
        self.splitTree = SplitTreeController(
            layout: layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )
        self.config = config
        self.commitSha = GitWorktree.headShortSha(worktreePath: config.repoPath)
        self.commitURL = GitWorktree.headCommitURL(worktreePath: config.repoPath)

        socketServer.start()
        splitTree.loadViewIfNeeded()

        if config.autoReloadOnFileChange {
            let watcher = FileWatcher(repoPath: config.repoPath)
            watcher.onChange = { [weak self] in
                self?.reloadAllBrowserTabs()
            }
            watcher.start()
            fileWatcher = watcher
        }
    }

    func setupSocketHandler(handler: @escaping (SocketCommand) -> Data?) {
        socketServer.onCommand = handler
    }

    func reloadAllBrowserTabs() {
        for pane in splitTree.paneControllers.values {
            for browser in pane.allBrowserTabs() {
                if browser.hasCompletedInitialLoad {
                    browser.forceReload()
                }
            }
        }
    }

    func refreshPRStatus() {
        let previousPR = prInfo
        GitHubPRResolver.resolve(worktreePath: config.repoPath) { [weak self] info in
            guard let self = self else { return }
            self.prInfo = info
            SessionStore.shared.updatePRInfo(
                repoPath: self.config.repoPath,
                worktreeName: self.config.worktreeName,
                prInfo: info
            )
            if let info = info {
                let stateLabel: String
                switch info.state {
                case .open:   stateLabel = "Open"
                case .draft:  stateLabel = "Draft"
                case .merged: stateLabel = "Merged"
                case .closed: stateLabel = "Closed"
                }

                if previousPR == nil {
                    // Log activity when a PR is first detected
                    ActivityStore.shared.log(
                        .prOpened,
                        repoName: self.config.repoName,
                        detail: "\(info.number)",
                        prURL: info.url
                    )
                }

                // Update state if it changed (e.g., Open → Merged)
                if previousPR?.state != info.state || previousPR == nil {
                    ActivityStore.shared.updatePRState(
                        repoName: self.config.repoName,
                        prNumber: "\(info.number)",
                        state: stateLabel,
                        url: info.url
                    )
                }
            }
            self.onStatusChanged?()
        }
    }

    /// Walk the layout and append `--continue` to any `.run` command whose
    /// first token is exactly `claude`. Skips commands that already include
    /// `--continue` or `--resume` to stay idempotent.
    private static func appendingClaudeContinue(to node: LayoutNode) -> LayoutNode {
        switch node {
        case .run(let command):
            return .run(command: appendContinueIfClaude(command))
        case .visit:
            return node
        case .split(let direction, let first, let second, let firstSize, let secondSize):
            return .split(
                direction: direction,
                first: appendingClaudeContinue(to: first),
                second: appendingClaudeContinue(to: second),
                firstSize: firstSize,
                secondSize: secondSize
            )
        case .tabs(let children):
            return .tabs(children.map(appendingClaudeContinue))
        }
    }

    private static func appendContinueIfClaude(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) == "claude" else {
            return command
        }
        if command.contains("--continue") || command.contains("--resume") {
            return command
        }
        return command + " --continue"
    }

    func stop() {
        // SIGTERM foreground jobs and tear down shells so child processes
        // (servers, Ruby scripts, etc.) release ports before detach.
        for pane in splitTree.paneControllers.values {
            pane.terminateAllTerminals()
        }
        fileWatcher?.stop()
        socketServer.stop()
    }
}

// MARK: - Session Tab Bar

class SessionTabBar: NSView {
    var onSelectSession: ((Int) -> Void)?
    var onCloseSession: ((Int) -> Void)?
    var onNewSession: (() -> Void)?
    private var tabViews: [NSView] = []
    private var detailViews: [NSView] = []
    private let plusButton = NSButton()
    private static let tabRowHeight: CGFloat = 40
    static let detailRowHeight: CGFloat = 33

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        plusButton.title = "+"
        plusButton.toolTip = "New Session"
        plusButton.bezelStyle = .recessed
        plusButton.font = .systemFont(ofSize: 14, weight: .medium)
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        plusButton.frame = NSRect(x: 0, y: 0, width: 28, height: 24)
        addSubview(plusButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(sessions: [(repoName: String, sessionName: String, commitSha: String?, commitURL: String?, isActive: Bool, statusColor: NSColor?, prInfo: GitHubPRInfo?, diffStats: (added: Int, deleted: Int)?)]) {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()
        detailViews.forEach { $0.removeFromSuperview() }
        detailViews.removeAll()
        plusButton.removeFromSuperview()

        let tabRowY: CGFloat = Self.detailRowHeight

        // -- Tab row --
        var x: CGFloat = 4
        for (i, ws) in sessions.enumerated() {
            let tab = SessionTab(
                index: i, repoName: ws.repoName, sessionName: ws.sessionName,
                isActive: ws.isActive, statusColor: ws.statusColor,
                onSelect: { [weak self] idx in self?.onSelectSession?(idx) },
                onClose: { [weak self] idx in self?.onCloseSession?(idx) }
            )
            tab.frame.origin = CGPoint(x: x, y: tabRowY)
            addSubview(tab)
            tabViews.append(tab)
            x += tab.frame.width + 4
        }

        if sessions.isEmpty {
            plusButton.title = "+ Add new session"
            plusButton.font = .systemFont(ofSize: 14, weight: .medium)
            plusButton.sizeToFit()
        } else {
            plusButton.title = "+"
            plusButton.font = .systemFont(ofSize: 14, weight: .medium)
            plusButton.frame.size = NSSize(width: 28, height: 24)
        }
        plusButton.frame.origin.x = x
        plusButton.frame.origin.y = tabRowY + 8
        addSubview(plusButton)

        // -- Detail row (full width, for active session's SHA + PR) --
        guard let active = sessions.first(where: { $0.isActive }) else { return }

        let detailFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        let detailBoldFont = NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
        let itemHeight: CGFloat = 20
        let centerY: CGFloat = (Self.detailRowHeight - itemHeight) / 2

        var detailX: CGFloat = 8
        if let sha = active.commitSha {
            if let urlStr = active.commitURL, let url = URL(string: urlStr) {
                let attr = NSAttributedString(string: sha, attributes: [
                    .font: detailFont,
                    // Catppuccin Mocha: Overlay0 #6c7086
                    .foregroundColor: NSColor(red: 0x6c/255, green: 0x70/255, blue: 0x86/255, alpha: 1),
                ])
                let btn = NSButton(frame: .zero)
                btn.isBordered = false
                btn.attributedTitle = attr
                btn.target = self
                btn.action = #selector(openCommitURL(_:))
                btn.toolTip = "Open commit on GitHub"
                btn.sizeToFit()
                btn.frame = NSRect(x: detailX, y: centerY, width: btn.intrinsicContentSize.width, height: itemHeight)
                addSubview(btn)
                detailViews.append(btn)
                commitURL = url
                detailX += btn.frame.width + 12
            } else {
                let label = NSTextField(labelWithString: sha)
                label.font = detailFont
                // Catppuccin Mocha: Overlay0 #6c7086
                label.textColor = NSColor(red: 0x6c/255, green: 0x70/255, blue: 0x86/255, alpha: 1)
                label.sizeToFit()
                label.frame.origin = CGPoint(x: detailX, y: centerY)
                label.frame.size.height = itemHeight
                addSubview(label)
                detailViews.append(label)
                detailX += label.frame.width + 12
            }
        }

        if let pr = active.prInfo {
            let prColor = SessionTab.color(for: pr.state)
            let stateText = SessionTab.stateLabel(for: pr.state)

            let prAttr = NSMutableAttributedString()
            prAttr.append(NSAttributedString(string: " PR #\(pr.number) (\(stateText)) \u{2197} ", attributes: [
                .font: detailBoldFont,
                .foregroundColor: prColor,
            ]))

            let prBtn = NSButton(frame: .zero)
            prBtn.wantsLayer = true
            prBtn.layer?.cornerRadius = 4
            prBtn.layer?.backgroundColor = prColor.withAlphaComponent(0.10).cgColor
            prBtn.isBordered = false
            prBtn.attributedTitle = prAttr
            prBtn.target = self
            prBtn.action = #selector(openPRURL(_:))
            prBtn.toolTip = "#\(pr.number) \(pr.title)"
            prBtn.sizeToFit()
            prBtn.frame = NSRect(x: detailX, y: centerY, width: prBtn.intrinsicContentSize.width, height: itemHeight)
            addSubview(prBtn)
            detailViews.append(prBtn)
            prInfoURL = URL(string: pr.url)
            detailX += prBtn.frame.width + 12
        }

        // -- Diff stats (+N -M) --
        if let stats = active.diffStats, stats.added > 0 || stats.deleted > 0 {
            let diffAttr = NSMutableAttributedString()
            if stats.added > 0 {
                diffAttr.append(NSAttributedString(string: "+\(stats.added)", attributes: [
                    .font: detailBoldFont,
                    .foregroundColor: NSColor.systemGreen,
                ]))
            }
            if stats.added > 0 && stats.deleted > 0 {
                diffAttr.append(NSAttributedString(string: " ", attributes: [
                    .font: detailBoldFont,
                ]))
            }
            if stats.deleted > 0 {
                diffAttr.append(NSAttributedString(string: "-\(stats.deleted)", attributes: [
                    .font: detailBoldFont,
                    .foregroundColor: NSColor.systemRed,
                ]))
            }
            let diffLabel = NSTextField(labelWithAttributedString: diffAttr)
            diffLabel.sizeToFit()
            diffLabel.frame.origin = CGPoint(x: detailX, y: centerY)
            addSubview(diffLabel)
            detailViews.append(diffLabel)
        }
    }

    private var commitURL: URL?
    private var prInfoURL: URL?

    @objc private func openCommitURL(_ sender: Any?) {
        if let url = commitURL { NSWorkspace.shared.open(url) }
    }

    @objc private func openPRURL(_ sender: Any?) {
        if let url = prInfoURL { NSWorkspace.shared.open(url) }
    }

    @objc private func plusClicked() {
        onNewSession?()
    }

    static let activeTabColor = NSColor(red: 30/255, green: 30/255, blue: 46/255, alpha: 1.0)

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Detail row background — same color as active tab
        Self.activeTabColor.setFill()
        NSRect(x: 0, y: 1, width: bounds.width, height: Self.detailRowHeight - 1).fill()
        // Bottom border
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class SessionTab: NSView {
    let index: Int
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let closeBtn: NSButton
    private var trackingArea: NSTrackingArea?

    init(index: Int, repoName: String, sessionName: String,
         isActive: Bool, statusColor: NSColor?,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.index = index
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeBtn = NSButton(frame: NSRect(x: 0, y: 10, width: 18, height: 18))
        super.init(frame: .zero)
        wantsLayer = true

        layer?.cornerRadius = 6
        if let color = statusColor {
            layer?.backgroundColor = color.withAlphaComponent(0.45).cgColor
        } else if isActive {
            layer?.backgroundColor = SessionTabBar.activeTabColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        // Active tab merges into the detail row below it — square the bottom corners.
        if isActive {
            layer?.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
        }

        // Two-line layout: repo name (top) + session name (bottom)
        let totalHeight: CGFloat = 38
        let repoY: CGFloat = 20
        let wsY: CGFloat = 4

        let hasStatusColor = statusColor != nil
        let repoLabel = NSTextField(labelWithString: repoName)
        repoLabel.font = .systemFont(ofSize: 10)
        repoLabel.textColor = hasStatusColor ? .black.withAlphaComponent(0.6) : isActive ? NSColor(red: 0xa6/255, green: 0xad/255, blue: 0xc8/255, alpha: 1) : .secondaryLabelColor
        repoLabel.lineBreakMode = .byTruncatingTail
        repoLabel.frame = NSRect(x: 8, y: repoY, width: 140, height: 14)
        addSubview(repoLabel)

        let wsLabel = NSTextField(labelWithString: sessionName)
        wsLabel.font = .systemFont(ofSize: 14, weight: isActive ? .semibold : .regular)
        // Catppuccin Mocha: Text #cdd6f4
        wsLabel.textColor = hasStatusColor ? .black : isActive ? NSColor(red: 0xcd/255, green: 0xd6/255, blue: 0xf4/255, alpha: 1) : .labelColor
        wsLabel.lineBreakMode = .byTruncatingTail
        wsLabel.frame = NSRect(x: 8, y: wsY, width: 140, height: 17)
        addSubview(wsLabel)

        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Detach session")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.contentTintColor = hasStatusColor ? .black.withAlphaComponent(0.6) : isActive ? NSColor(red: 0xa6/255, green: 0xad/255, blue: 0xc8/255, alpha: 1) : .secondaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        closeBtn.toolTip = "Detach Session"
        closeBtn.frame = NSRect(x: 0, y: (totalHeight - 18) / 2, width: 18, height: 18)
        addSubview(closeBtn)

        let textWidth = max(
            repoLabel.intrinsicContentSize.width,
            wsLabel.intrinsicContentSize.width
        )
        let width = min(textWidth + 38, 200)
        frame.size = NSSize(width: width, height: totalHeight)
        repoLabel.frame.size.width = width - 34
        wsLabel.frame.size.width = width - 34
        closeBtn.frame.origin.x = width - 22
    }

    static func color(for state: PRState) -> NSColor {
        switch state {
        case .open:   return .systemGreen
        case .draft:  return .systemGray
        case .merged: return .systemPurple
        case .closed: return .systemRed
        }
    }

    static func stateLabel(for state: PRState) -> String {
        switch state {
        case .open:   return "Open"
        case .draft:  return "Draft"
        case .merged: return "Merged"
        case .closed: return "Closed"
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp], owner: self)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) { closeBtn.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeBtn.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < frame.width - 22 {
            onSelect(index)
        }
    }

    @objc private func closeClicked() { onClose(index) }
}

// MARK: - Window Controller

class SessionWindowController: NSWindowController {
    private var sessions: [Session] = []
    private var activeIndex: Int = -1
    private let sessionTabBar = SessionTabBar(frame: .zero)
    private let contentArea = NSView()
    private var prRefreshTimer: Timer?
    private var diffStatsTimer: Timer?
    var onNewSession: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        window.setFrameAutosaveName("SessionWindow")
        super.init(window: window)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        sessionTabBar.translatesAutoresizingMaskIntoConstraints = false
        sessionTabBar.onSelectSession = { [weak self] i in self?.selectSession(at: i) }
        sessionTabBar.onCloseSession = { [weak self] i in self?.closeSession(at: i) }
        sessionTabBar.onNewSession = { [weak self] in self?.onNewSession?() }
        contentView.addSubview(sessionTabBar)

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentArea)

        NSLayoutConstraint.activate([
            sessionTabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sessionTabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sessionTabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sessionTabBar.heightAnchor.constraint(equalToConstant: 75),

            contentArea.topAnchor.constraint(equalTo: sessionTabBar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func addSession(config: SessionConfig) {
        // If this session is already open, just switch to it
        if let existing = sessions.firstIndex(where: { $0.config.repoPath == config.repoPath }) {
            selectSession(at: existing)
            return
        }

        let ws = Session(config: config)
        ws.onStatusChanged = { [weak self] in
            self?.refreshTabBar()
        }
        ws.setupSocketHandler { [weak self, weak ws] command in
            guard let ws = ws else { return nil }
            return self?.handleSocketCommand(command, session: ws)
        }
        sessions.append(ws)
        selectSession(at: sessions.count - 1)

        // Persist to session store
        SessionStore.shared.add(SavedSession(
            repoPath: config.repoPath,
            repoName: config.repoName,
            sessionName: config.sessionName,
            worktreeName: config.worktreeName,
            layoutText: config.layoutText,
            autoReloadOnFileChange: config.autoReloadOnFileChange
        ))

        // Fetch PR status immediately
        ws.refreshPRStatus()

        // Start periodic PR refresh if not already running
        if prRefreshTimer == nil {
            prRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.refreshAllPRStatuses()
            }
        }

        // Start diff stats polling for active session
        if diffStatsTimer == nil {
            diffStatsTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.refreshActiveDiffStats()
            }
        }
    }

    private func refreshActiveDiffStats() {
        guard activeIndex >= 0 && activeIndex < sessions.count else { return }
        let ws = sessions[activeIndex]
        DispatchQueue.global(qos: .utility).async {
            let stats = GitWorktree.diffStats(worktreePath: ws.config.repoPath)
            let sha = GitWorktree.headShortSha(worktreePath: ws.config.repoPath)
            let url = GitWorktree.headCommitURL(worktreePath: ws.config.repoPath)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let statsChanged = ws.diffStats?.added != stats?.added || ws.diffStats?.deleted != stats?.deleted
                let shaChanged = ws.commitSha != sha
                ws.diffStats = stats
                ws.commitSha = sha
                ws.commitURL = url
                if statsChanged || shaChanged { self.refreshTabBar() }
            }
        }
    }

    private func refreshAllPRStatuses() {
        for ws in sessions {
            ws.refreshPRStatus()
        }
    }

    private func selectSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }

        // Detach every session's splitTree view from contentArea before adding
        // the new one. removeFromSuperview is a no-op when the view isn't
        // attached, so this is cheap — and it guarantees no stale view is left
        // behind if activeIndex ever got out of sync with what's in the hierarchy.
        for ws in sessions {
            ws.splitTree.view.removeFromSuperview()
        }

        activeIndex = index
        let ws = sessions[index]
        ws.statusColor = nil
        ws.splitTree.view.frame = contentArea.bounds
        ws.splitTree.view.autoresizingMask = [.width, .height]
        contentArea.addSubview(ws.splitTree.view)

        window?.title = "neetly - \(ws.config.repoName) - \(ws.config.sessionName)"
        refreshTabBar()
    }

    /// Close any session whose repoPath (worktree path) matches.
    /// Called when a worktree is deleted from the setup screen.
    func closeSessionByPath(_ path: String) {
        if let index = sessions.firstIndex(where: { $0.config.repoPath == path }) {
            closeSession(at: index)
        }
    }

    private func closeSession(at index: Int) {
        guard index >= 0 && index < sessions.count else { return }

        // Mark as detached (keep in store so it stays in the session list,
        // but won't auto-reopen on next app launch).
        let cfg = sessions[index].config
        SessionStore.shared.markClosed(repoPath: cfg.repoPath, worktreeName: cfg.worktreeName)

        // Detach the currently-active view from contentArea before we mutate
        // the array. Otherwise, if `index < activeIndex`, the removal shifts
        // activeIndex onto a different session and the previously-active
        // view stays stuck in contentArea.
        if activeIndex >= 0 && activeIndex < sessions.count {
            sessions[activeIndex].splitTree.view.removeFromSuperview()
        }

        sessions[index].stop()
        sessions.remove(at: index)

        // If a session before the active one was closed, the active one shifted down.
        if index < activeIndex {
            activeIndex -= 1
        }

        if sessions.isEmpty {
            activeIndex = -1
            window?.title = "neetly"
            prRefreshTimer?.invalidate()
            prRefreshTimer = nil
            diffStatsTimer?.invalidate()
            diffStatsTimer = nil
            refreshTabBar()
        } else {
            activeIndex = min(max(0, activeIndex), sessions.count - 1)
            selectSession(at: activeIndex)
        }
    }

    private func refreshTabBar() {
        let tabs = sessions.enumerated().map { (i, ws) in
            (repoName: ws.config.repoName, sessionName: ws.config.sessionName, commitSha: ws.commitSha, commitURL: ws.commitURL, isActive: i == activeIndex, statusColor: ws.statusColor, prInfo: ws.prInfo, diffStats: ws.diffStats)
        }
        sessionTabBar.update(sessions: tabs)
    }

    /// Get the active session's split tree for menu actions.
    func getSplitTree() -> SplitTreeController? {
        guard activeIndex >= 0 && activeIndex < sessions.count else { return nil }
        return sessions[activeIndex].splitTree
    }

    // MARK: - Socket Command Handling

    private func handleSocketCommand(_ command: SocketCommand, session ws: Session) -> Data? {
        switch command.action {
        case "browser.open":
            guard let url = command.url else { return nil }
            let bg = command.background ?? false
            let pane = resolvePane(command, in: ws)
            pane?.addBrowserTab(url: url, background: bg)
            return nil

        case "terminal.run":
            guard let cmd = command.command else { return nil }
            let pane = resolvePane(command, in: ws)
            pane?.addTerminalTab(command: cmd)
            return nil

        case "tabs.list":
            var allTabs: [TabListEntry] = []
            for pane in ws.splitTree.paneControllers.values {
                allTabs.append(contentsOf: pane.listTabs())
            }
            return try? JSONEncoder().encode(allTabs)

        case "tab.send":
            guard let tabId = command.tabId, let text = command.text else {
                return jsonResponse(["ok": false, "error": "missing tabId or text"])
            }
            for pane in ws.splitTree.paneControllers.values {
                if pane.sendTextToTab(tabId: tabId, text: text) {
                    return jsonResponse(["ok": true])
                }
            }
            return jsonResponse(["ok": false, "error": "tab not found: \(tabId)"])

        case "session.notify":
            let colorName = command.command ?? "green"
            let color: NSColor
            switch colorName {
            case "green": color = NSColor(red: 0.0, green: 0.5, blue: 0.0, alpha: 1.0)
            case "red": color = .systemRed
            case "yellow": color = .systemYellow
            case "blue": color = .systemBlue
            case "orange": color = .systemOrange
            case "clear", "none", "reset": ws.statusColor = nil; ws.onStatusChanged?(); return nil
            default: color = .systemGreen
            }
            ws.statusColor = color
            ws.onStatusChanged?()
            return nil

        default:
            return nil
        }
    }

    private func resolvePane(_ command: SocketCommand, in ws: Session) -> PaneViewController? {
        if let seq = command.paneSeq {
            if let pane = ws.splitTree.paneControllers.values.first(where: { $0.seqId == seq }) {
                return pane
            }
        }
        if let paneId = command.paneId, !paneId.isEmpty {
            if let pane = ws.splitTree.pane(for: paneId) {
                return pane
            }
        }
        return ws.splitTree.paneControllers.values.first
    }

    private func jsonResponse(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}
