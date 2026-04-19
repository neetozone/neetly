import AppKit
import WebKit

/// A pane is a leaf in the split tree. It has a horizontal tab bar and a content area.
/// Each tab is either a terminal or a browser.
class PaneViewController: NSViewController {
    let paneId = UUID()
    let seqId = SeqCounter.shared.nextId()
    private var tabs: [(kind: PaneTabKind, viewController: NSViewController)] = []
    private var activeTabIndex: Int = -1
    private let tabBar = TabBarView(frame: .zero)
    private let contentView = NSView()
    let repoPath: String
    let socketServer: SocketServer
    /// Called when user clicks split column/row button. SplitTreeController sets this.
    var onSplit: ((SplitDirection) -> Void)?
    /// Called when the last tab is closed. SplitTreeController collapses the pane.
    var onEmpty: (() -> Void)?
    /// Called when user clicks maximize/restore. SplitTreeController handles it.
    var onToggleMaximize: (() -> Void)?

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
        tabBar.onCloseTab = { [weak self] index in
            self?.closeTab(at: index)
        }
        tabBar.onNewTerminal = { [weak self] in
            self?.addTerminalTab(command: "")
        }
        tabBar.onNewBrowser = { [weak self] in
            self?.addBrowserTab(url: "")
        }
        tabBar.onSplitColumns = { [weak self] in
            self?.onSplit?(.columns)
        }
        tabBar.onSplitRows = { [weak self] in
            self?.onSplit?(.rows)
        }
        tabBar.onToggleMaximize = { [weak self] in
            self?.onToggleMaximize?()
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

    /// Called by SplitTreeController to update the maximize button icon.
    func setMaximizedState(_ isMaximized: Bool) {
        tabBar.setMaximized(isMaximized)
    }

    func addTerminalTab(command: String) {
        let vc = TerminalTabViewController(
            command: command,
            repoPath: repoPath,
            environment: socketEnvironment
        )
        vc.onProcessExited = { [weak self, weak vc] in
            guard let self, let vc else { return }
            if let idx = self.tabs.firstIndex(where: { $0.viewController === vc }) {
                self.closeTab(at: idx)
            }
        }
        addChild(vc)
        tabs.append((kind: .terminal, viewController: vc))
        selectTab(at: tabs.count - 1)
    }

    func addBrowserTab(url: String, background: Bool = false) {
        let vc = BrowserTabViewController(url: url)
        wireBrowserTab(vc)
        addChild(vc)
        tabs.append((kind: .browser, viewController: vc))
        if background {
            refreshTabBar()
        } else {
            selectTab(at: tabs.count - 1)
        }
    }

    /// Add a browser tab that wraps an existing WKWebView (e.g. one created
    /// by WebKit for a target=_blank link).
    private func addBrowserTab(withWebView webView: WKWebView) {
        let vc = BrowserTabViewController(url: "", preinstalledWebView: webView)
        wireBrowserTab(vc)
        addChild(vc)
        tabs.append((kind: .browser, viewController: vc))
        selectTab(at: tabs.count - 1)
    }

    private func wireBrowserTab(_ vc: BrowserTabViewController) {
        vc.onTitleChanged = { [weak self] in self?.refreshTabBar() }
        vc.onRequestNewTab = { [weak self] webView in
            self?.addBrowserTab(withWebView: webView)
        }
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

    func closeTab(at index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        // Remove from view if it's the active tab
        if index == activeTabIndex {
            tabs[index].viewController.view.removeFromSuperview()
        }

        let vc = tabs[index].viewController
        vc.removeFromParent()
        tabs.remove(at: index)

        // Adjust active index
        if tabs.isEmpty {
            activeTabIndex = -1
            onEmpty?()
            return
        } else if index <= activeTabIndex {
            activeTabIndex = max(0, activeTabIndex - 1)
            selectTab(at: activeTabIndex)
        } else {
            refreshTabBar()
        }
    }

    func closeActiveTab() {
        guard activeTabIndex >= 0 else { return }
        closeTab(at: activeTabIndex)
    }

    func tabCount() -> Int { tabs.count }

    func activeTerminalTab() -> TerminalTabViewController? {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex].viewController as? TerminalTabViewController
    }

    func activeBrowserTab() -> BrowserTabViewController? {
        guard activeTabIndex >= 0 && activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex].viewController as? BrowserTabViewController
    }

    /// Returns ALL browser tabs in this pane, not just the active one.
    func allBrowserTabs() -> [BrowserTabViewController] {
        tabs.compactMap { $0.viewController as? BrowserTabViewController }
    }

    /// Send SIGINT to all terminal processes in this pane.
    func interruptAllTerminals() {
        for tab in tabs {
            if let terminal = tab.viewController as? TerminalTabViewController {
                terminal.interruptProcess()
            }
        }
    }

    /// Returns info about all tabs in this pane for the tabs.list command.
    func listTabs() -> [TabListEntry] {
        return tabs.enumerated().map { (i, tab) in
            let tabId: String
            let tabSeq: Int
            let type: String
            let title: String
            switch tab.kind {
            case .terminal:
                let vc = tab.viewController as! TerminalTabViewController
                tabId = vc.tabId.uuidString
                tabSeq = vc.seqId
                type = "terminal"
                let cmd = vc.command
                title = cmd.isEmpty ? "Terminal" : cmd
            case .browser:
                let vc = tab.viewController as! BrowserTabViewController
                tabId = vc.tabId.uuidString
                tabSeq = vc.seqId
                type = "browser"
                title = vc.currentTitle
            }
            return TabListEntry(
                tabId: tabId,
                tabSeq: tabSeq,
                paneId: paneId.uuidString,
                paneSeq: seqId,
                type: type,
                title: title,
                isActive: i == activeTabIndex
            )
        }
    }

    /// Find a terminal tab by sequential ID, UUID, or UUID prefix, and send text to it.
    func sendTextToTab(tabId: String, text: String) -> Bool {
        let needle = tabId.uppercased()
        let seqNum = Int(tabId)
        for tab in tabs {
            if tab.kind == .terminal,
               let vc = tab.viewController as? TerminalTabViewController {
                let match = (seqNum != nil && vc.seqId == seqNum)
                    || vc.tabId.uuidString.hasPrefix(needle)
                if match {
                    vc.sendText(text)
                    return true
                }
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
        let tabInfos: [(title: String, icon: NSImage?, isActive: Bool)] = tabs.enumerated().map { (i, tab) in
            let title: String
            let icon: NSImage?
            switch tab.kind {
            case .terminal:
                let termCmd = (tab.viewController as! TerminalTabViewController).command
                title = termCmd.isEmpty ? "Terminal" : termCmd
                icon = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            case .browser:
                let vc = tab.viewController as! BrowserTabViewController
                title = vc.currentTitle
                icon = vc.favicon ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
            }
            return (title: title, icon: icon, isActive: i == activeTabIndex)
        }
        tabBar.update(tabs: tabInfos)
    }
}
