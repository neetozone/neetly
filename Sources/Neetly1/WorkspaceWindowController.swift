import AppKit

class WorkspaceWindowController: NSWindowController {
    let config: WorkspaceConfig
    let socketServer: SocketServer
    var splitTree: SplitTreeController!

    init(config: WorkspaceConfig, socketServer: SocketServer) {
        self.config = config
        self.socketServer = socketServer

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly1 - \(config.projectName)"
        window.center()
        window.setFrameAutosaveName("WorkspaceWindow")
        super.init(window: window)

        setupContent()
        setupSocketHandler()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupContent() {
        splitTree = SplitTreeController(
            layout: config.layout,
            repoPath: config.repoPath,
            socketServer: socketServer
        )

        // Load the split tree view
        splitTree.loadViewIfNeeded()
        splitTree.view.frame = window!.contentView!.bounds
        splitTree.view.autoresizingMask = [.width, .height]
        window!.contentView!.addSubview(splitTree.view)
    }

    private func setupSocketHandler() {
        socketServer.onCommand = { [weak self] command -> Data? in
            self?.handleSocketCommand(command)
        }
    }

    private func handleSocketCommand(_ command: SocketCommand) -> Data? {
        switch command.action {
        case "browser.open":
            guard let url = command.url else { return nil }
            let paneId = command.paneId ?? ""
            if let pane = splitTree.pane(for: paneId) {
                pane.addBrowserTab(url: url)
            } else if let firstPane = splitTree.paneControllers.values.first {
                firstPane.addBrowserTab(url: url)
            }
            return nil

        case "terminal.run":
            guard let cmd = command.command else { return nil }
            let paneId = command.paneId ?? ""
            if let pane = splitTree.pane(for: paneId) {
                pane.addTerminalTab(command: cmd)
            }
            return nil

        case "tabs.list":
            var allTabs: [TabListEntry] = []
            for pane in splitTree.paneControllers.values {
                allTabs.append(contentsOf: pane.listTabs())
            }
            return try? JSONEncoder().encode(allTabs)

        case "tab.send":
            guard let tabId = command.tabId, let text = command.text else {
                return jsonResponse(["ok": false, "error": "missing tabId or text"])
            }
            for pane in splitTree.paneControllers.values {
                if pane.sendTextToTab(tabId: tabId, text: text) {
                    return jsonResponse(["ok": true])
                }
            }
            return jsonResponse(["ok": false, "error": "tab not found: \(tabId)"])

        default:
            NSLog("Unknown socket command: \(command.action)")
            return nil
        }
    }

    private func jsonResponse(_ dict: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: dict)
    }
}
