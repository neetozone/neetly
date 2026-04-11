import AppKit

/// A pane is a leaf in the split tree. It has a horizontal tab bar and a content area.
/// Each tab is either a terminal or a browser.
class PaneViewController: NSViewController {
    let paneId = UUID()
    private var tabs: [(kind: PaneTabKind, viewController: NSViewController)] = []
    private var activeTabIndex: Int = -1
    private let tabBar = TabBarView(frame: .zero)
    private let contentView = NSView()
    let repoPath: String
    let socketServer: SocketServer

    /// Environment dict with this pane's own ID baked in
    var socketEnvironment: [String: String] {
        socketServer.environmentForPane(paneId)
    }

    init(repoPath: String, socketServer: SocketServer) {
        self.repoPath = repoPath
        self.socketServer = socketServer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onSelectTab = { [weak self] index in
            self?.selectTab(at: index)
        }
        tabBar.onNewTerminal = { [weak self] in
            self?.addTerminalTab(command: "")
        }
        tabBar.onNewBrowser = { [weak self] in
            self?.addBrowserTab(url: "")
        }
        container.addSubview(tabBar)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(contentView)

        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: container.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: 30),

            contentView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    // MARK: - Tab Management

    func addTerminalTab(command: String) {
        let vc = TerminalTabViewController(
            command: command,
            repoPath: repoPath,
            environment: socketEnvironment
        )
        addChild(vc)
        tabs.append((kind: .terminal, viewController: vc))
        selectTab(at: tabs.count - 1)
    }

    func addBrowserTab(url: String) {
        let vc = BrowserTabViewController(url: url)
        addChild(vc)
        tabs.append((kind: .browser, viewController: vc))
        selectTab(at: tabs.count - 1)
    }

    func selectTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        // Remove current content
        if activeTabIndex >= 0 && activeTabIndex < tabs.count {
            tabs[activeTabIndex].viewController.view.removeFromSuperview()
        }

        activeTabIndex = index
        let vc = tabs[index].viewController
        vc.view.frame = contentView.bounds
        vc.view.autoresizingMask = [.width, .height]
        contentView.addSubview(vc.view)

        // Trigger viewDidAppear for the tab
        vc.viewDidAppear()

        // Focus the content
        if let termVC = vc as? TerminalTabViewController {
            termVC.focusTerminal()
        }

        refreshTabBar()
    }

    func tabCount() -> Int { tabs.count }

    /// Returns info about all tabs in this pane for the tabs.list command.
    func listTabs() -> [TabListEntry] {
        return tabs.enumerated().map { (i, tab) in
            let tabId: String
            let type: String
            let title: String
            switch tab.kind {
            case .terminal:
                let vc = tab.viewController as! TerminalTabViewController
                tabId = vc.tabId.uuidString
                type = "terminal"
                let cmd = vc.command
                title = cmd.isEmpty ? "Terminal" : cmd
            case .browser:
                let vc = tab.viewController as! BrowserTabViewController
                tabId = vc.tabId.uuidString
                type = "browser"
                title = vc.currentTitle
            }
            return TabListEntry(
                tabId: tabId,
                paneId: paneId.uuidString,
                type: type,
                title: title,
                isActive: i == activeTabIndex
            )
        }
    }

    /// Find a terminal tab by its UUID (or prefix) and send text to it.
    func sendTextToTab(tabId: String, text: String) -> Bool {
        let needle = tabId.uppercased()
        for tab in tabs {
            if tab.kind == .terminal,
               let vc = tab.viewController as? TerminalTabViewController,
               vc.tabId.uuidString.hasPrefix(needle) {
                vc.sendText(text)
                return true
            }
        }
        return false
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex + 1) % tabs.count)
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        selectTab(at: (activeTabIndex - 1 + tabs.count) % tabs.count)
    }

    private func refreshTabBar() {
        let tabInfos: [(title: String, isActive: Bool)] = tabs.enumerated().map { (i, tab) in
            let title: String
            switch tab.kind {
            case .terminal:
                let termCmd = (tab.viewController as! TerminalTabViewController).command
                title = termCmd.isEmpty ? "Terminal" : termCmd
            case .browser:
                title = (tab.viewController as! BrowserTabViewController).currentTitle
            }
            return (title: title, isActive: i == activeTabIndex)
        }
        tabBar.update(tabs: tabInfos)
    }
}
