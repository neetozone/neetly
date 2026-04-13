import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var setupWindowController: SetupWindowController?
    var workspaceWindowController: WorkspaceWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        let saved = WorkspaceStore.shared.load()
        if saved.isEmpty {
            showSetupWindow()
        } else {
            restoreWorkspaces(saved)
        }
    }

    private func restoreWorkspaces(_ saved: [SavedWorkspace]) {
        let parser = LayoutParser()
        for ws in saved {
            let dedented = dedent(ws.layoutText)
            guard let layout = parser.parse(dedented) else { continue }
            let config = WorkspaceConfig(
                repoPath: ws.repoPath,
                repoName: ws.repoName,
                workspaceName: ws.workspaceName,
                layout: layout,
                layoutText: ws.layoutText,
                autoReloadOnFileChange: ws.autoReloadOnFileChange
            )
            launchWorkspace(config)
        }
    }

    private func dedent(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let minIndent = nonEmpty.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }.min() ?? 0
        return lines.map { $0.count >= minIndent ? String($0.dropFirst(minIndent)) : $0 }
            .joined(separator: "\n")
    }

    private func showSetupWindow() {
        // Always create fresh so it starts from repo list
        setupWindowController = SetupWindowController()
        setupWindowController?.onLaunch = { [weak self] config in
            self?.launchWorkspace(config)
        }
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func launchWorkspace(_ config: WorkspaceConfig) {
        setupWindowController?.close()

        if workspaceWindowController == nil {
            workspaceWindowController = WorkspaceWindowController()
            workspaceWindowController?.onNewWorkspace = { [weak self] in
                self?.showSetupWindow()
            }
            workspaceWindowController?.showWindow(nil)
        }

        workspaceWindowController?.addWorkspace(config: config)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About neetly", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        let checkItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(Updater.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkItem.target = Updater.shared
        appMenu.addItem(checkItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit neetly", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit menu (needed for text input to work in text fields)
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Pane menu
        let paneMenuItem = NSMenuItem()
        let paneMenu = NSMenu(title: "Pane")
        paneMenu.addItem(withTitle: "New Terminal", action: #selector(newTerminalTab), keyEquivalent: "t")
        paneMenu.addItem(withTitle: "New Browser", action: #selector(newBrowserTab), keyEquivalent: "t")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(withTitle: "Close Tab", action: #selector(closeCurrentTab), keyEquivalent: "w")
        paneMenu.addItem(withTitle: "Reload Browser", action: #selector(reloadBrowser), keyEquivalent: "r")
        paneMenu.addItem(withTitle: "Clear Terminal", action: #selector(clearTerminal), keyEquivalent: "k")
        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Next Tab", action: #selector(nextTab), keyEquivalent: "]")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(withTitle: "Previous Tab", action: #selector(previousTab), keyEquivalent: "[")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenuItem.submenu = paneMenu
        mainMenu.addItem(paneMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "neetly",
            .applicationVersion: version,
            .version: "",
            .credits: NSAttributedString(
                string: "A code editor with terminal, browser, split panes, and sensible notifications for building web applications with agents.",
                attributes: [.foregroundColor: NSColor.labelColor]
            ),
        ]
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func clearTerminal() {
        if let pane = findFocusedPane(), let terminal = pane.activeTerminalTab() {
            terminal.sendText("\u{0C}")
        }
    }

    @objc private func reloadBrowser() {
        if let pane = findFocusedPane(), let browser = pane.activeBrowserTab() {
            browser.forceReload()
        }
    }

    @objc private func closeCurrentTab() {
        if let pane = findFocusedPane(), pane.tabCount() > 0 {
            pane.closeActiveTab()
        }
    }

    @objc private func newTerminalTab() {
        if let pane = findFocusedPane() {
            pane.addTerminalTab(command: "")
        }
    }

    @objc private func newBrowserTab() {
        if let pane = findFocusedPane() {
            pane.addBrowserTab(url: "")
        }
    }

    @objc private func nextTab() {
        if let pane = findFocusedPane() {
            pane.selectNextTab()
        }
    }

    @objc private func previousTab() {
        if let pane = findFocusedPane() {
            pane.selectPreviousTab()
        }
    }

    private func findFocusedPane() -> PaneViewController? {
        guard let window = NSApp.keyWindow else { return nil }
        guard let firstResponder = window.firstResponder as? NSView else { return nil }

        var current: NSView? = firstResponder
        while let view = current {
            if let paneVC = workspaceWindowController?.getSplitTree()?
                .paneControllers.values.first(where: { $0.view == view || $0.view.isDescendant(of: view) || view.isDescendant(of: $0.view) }) {
                return paneVC
            }
            current = view.superview
        }

        return workspaceWindowController?.getSplitTree()?.paneControllers.values.first
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
