import AppKit

/// Holds the runtime state for one workspace.
class Workspace {
    let config: WorkspaceConfig
    let socketServer: SocketServer
    let splitTree: SplitTreeController
    var fileWatcher: FileWatcher?

    init(config: WorkspaceConfig) {
        self.socketServer = SocketServer()
        self.splitTree = SplitTreeController(
            layout: config.layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )
        self.config = config

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

    func stop() {
        fileWatcher?.stop()
        socketServer.stop()
    }
}

// MARK: - Workspace Tab Bar

class WorkspaceTabBar: NSView {
    var onSelectWorkspace: ((Int) -> Void)?
    var onCloseWorkspace: ((Int) -> Void)?
    var onNewWorkspace: (() -> Void)?
    private var tabViews: [NSView] = []
    private let plusButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        plusButton.title = "+"
        plusButton.toolTip = "New Workspace"
        plusButton.bezelStyle = .recessed
        plusButton.font = .systemFont(ofSize: 14, weight: .medium)
        plusButton.target = self
        plusButton.action = #selector(plusClicked)
        plusButton.frame = NSRect(x: 0, y: 3, width: 28, height: 24)
        addSubview(plusButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(workspaces: [(repoName: String, workspaceName: String, isActive: Bool)]) {
        tabViews.forEach { $0.removeFromSuperview() }
        tabViews.removeAll()

        plusButton.removeFromSuperview()

        var x: CGFloat = 4
        for (i, ws) in workspaces.enumerated() {
            let tab = WorkspaceTab(
                index: i, repoName: ws.repoName, workspaceName: ws.workspaceName, isActive: ws.isActive,
                onSelect: { [weak self] idx in self?.onSelectWorkspace?(idx) },
                onClose: { [weak self] idx in self?.onCloseWorkspace?(idx) }
            )
            tab.frame.origin = CGPoint(x: x, y: 2)
            addSubview(tab)
            tabViews.append(tab)
            x += tab.frame.width + 4
        }

        plusButton.frame.origin.x = x
        plusButton.frame.origin.y = 9
        addSubview(plusButton)
    }

    @objc private func plusClicked() {
        onNewWorkspace?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class WorkspaceTab: NSView {
    let index: Int
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let closeBtn: NSButton
    private var trackingArea: NSTrackingArea?

    init(index: Int, repoName: String, workspaceName: String, isActive: Bool,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.index = index
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeBtn = NSButton(frame: NSRect(x: 0, y: 10, width: 18, height: 18))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.backgroundColor = isActive
            ? NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            : NSColor.clear.cgColor

        // Repo name (top line, smaller, secondary color)
        let repoLabel = NSTextField(labelWithString: repoName)
        repoLabel.font = .systemFont(ofSize: 10)
        repoLabel.textColor = .secondaryLabelColor
        repoLabel.lineBreakMode = .byTruncatingTail
        repoLabel.frame = NSRect(x: 8, y: 20, width: 120, height: 14)
        addSubview(repoLabel)

        // Workspace name (bottom line, bolder)
        let wsLabel = NSTextField(labelWithString: workspaceName)
        wsLabel.font = .systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
        wsLabel.lineBreakMode = .byTruncatingTail
        wsLabel.frame = NSRect(x: 8, y: 4, width: 120, height: 16)
        addSubview(wsLabel)

        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close workspace")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        addSubview(closeBtn)

        let textWidth = max(repoLabel.intrinsicContentSize.width, wsLabel.intrinsicContentSize.width)
        let width = min(textWidth + 38, 180)
        frame.size = NSSize(width: width, height: 38)
        repoLabel.frame.size.width = width - 34
        wsLabel.frame.size.width = width - 34
        closeBtn.frame.origin.x = width - 22
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

class WorkspaceWindowController: NSWindowController {
    private var workspaces: [Workspace] = []
    private var activeIndex: Int = -1
    private let workspaceTabBar = WorkspaceTabBar(frame: .zero)
    private let contentArea = NSView()
    var onNewWorkspace: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        window.setFrameAutosaveName("WorkspaceWindow")
        super.init(window: window)
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout() {
        guard let contentView = window?.contentView else { return }

        workspaceTabBar.translatesAutoresizingMaskIntoConstraints = false
        workspaceTabBar.onSelectWorkspace = { [weak self] i in self?.selectWorkspace(at: i) }
        workspaceTabBar.onCloseWorkspace = { [weak self] i in self?.closeWorkspace(at: i) }
        workspaceTabBar.onNewWorkspace = { [weak self] in self?.onNewWorkspace?() }
        contentView.addSubview(workspaceTabBar)

        contentArea.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentArea)

        NSLayoutConstraint.activate([
            workspaceTabBar.topAnchor.constraint(equalTo: contentView.topAnchor),
            workspaceTabBar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            workspaceTabBar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            workspaceTabBar.heightAnchor.constraint(equalToConstant: 42),

            contentArea.topAnchor.constraint(equalTo: workspaceTabBar.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    func addWorkspace(config: WorkspaceConfig) {
        let ws = Workspace(config: config)
        ws.setupSocketHandler { [weak self, weak ws] command in
            guard let ws = ws else { return nil }
            return self?.handleSocketCommand(command, workspace: ws)
        }
        workspaces.append(ws)
        selectWorkspace(at: workspaces.count - 1)
    }

    private func selectWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }

        // Remove current content
        if activeIndex >= 0 && activeIndex < workspaces.count {
            workspaces[activeIndex].splitTree.view.removeFromSuperview()
        }

        activeIndex = index
        let ws = workspaces[index]
        ws.splitTree.view.frame = contentArea.bounds
        ws.splitTree.view.autoresizingMask = [.width, .height]
        contentArea.addSubview(ws.splitTree.view)

        window?.title = "neetly -\(ws.config.workspaceName)"
        refreshTabBar()
    }

    private func closeWorkspace(at index: Int) {
        guard index >= 0 && index < workspaces.count else { return }

        if index == activeIndex {
            workspaces[index].splitTree.view.removeFromSuperview()
        }

        workspaces[index].stop()
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            activeIndex = -1
            window?.title = "neetly1"
            onNewWorkspace?()
        } else {
            activeIndex = min(activeIndex, workspaces.count - 1)
            selectWorkspace(at: activeIndex)
        }
    }

    private func refreshTabBar() {
        let repoName = { (path: String) in URL(fileURLWithPath: path).lastPathComponent }
        let tabs = workspaces.enumerated().map { (i, ws) in
            (repoName: repoName(ws.config.repoPath), workspaceName: ws.config.workspaceName, isActive: i == activeIndex)
        }
        workspaceTabBar.update(workspaces: tabs)
    }

    /// Get the active workspace's split tree for menu actions.
    func getSplitTree() -> SplitTreeController? {
        guard activeIndex >= 0 && activeIndex < workspaces.count else { return nil }
        return workspaces[activeIndex].splitTree
    }

    // MARK: - Socket Command Handling

    private func handleSocketCommand(_ command: SocketCommand, workspace ws: Workspace) -> Data? {
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

        default:
            return nil
        }
    }

    private func resolvePane(_ command: SocketCommand, in ws: Workspace) -> PaneViewController? {
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
