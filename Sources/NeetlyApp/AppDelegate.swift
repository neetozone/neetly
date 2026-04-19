import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var setupWindowController: SetupWindowController?
    var workspaceWindowController: WorkspaceWindowController?
    private var escapeMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Shorten AppKit's default ~1.5s tooltip delay.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])

        setAppIcon()
        setupMainMenu()
        setupEscapeKeyMonitor()

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

    private func showSetupWindow(initialScreen: SetupScreen = .repoList) {
        setupWindowController = SetupWindowController(initialScreen: initialScreen)
        setupWindowController?.onLaunch = { [weak self] config in
            self?.launchWorkspace(config)
        }
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        showSetupWindow(initialScreen: .settings)
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

    /// Install a local key-event monitor that catches Escape and exits
    /// maximize mode if a pane is currently maximized. Escape is ignored
    /// otherwise, so terminals still receive it for their own handling.
    private func setupEscapeKeyMonitor() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // 53 = Escape
            guard let splitTree = self?.workspaceWindowController?.getSplitTree(),
                  splitTree.isMaximized else { return event }
            splitTree.toggleMaximizeForActivePane()
            return nil  // consume the event
        }
    }

    /// Set the Dock/Cmd+Tab icon from the bundled resource. Needed for
    /// dev runs (`swift run neetly-app`) where there's no .app bundle to
    /// pick up CFBundleIconFile.
    private func setAppIcon() {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
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
        let settingsItem = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
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
        paneMenu.addItem(withTitle: "Maximize / Restore", action: #selector(toggleMaximize), keyEquivalent: "m")
        paneMenu.items.last?.keyEquivalentModifierMask = [.command, .shift]
        paneMenu.addItem(.separator())
        paneMenu.addItem(withTitle: "Diff (lazygit)", action: #selector(openDiff), keyEquivalent: "d")
        paneMenu.addItem(withTitle: "Close Diff", action: #selector(closeDiff), keyEquivalent: "z")
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
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "neetly",
            .applicationVersion: version,
            .version: "",
            .credits: NSAttributedString(
                string: "Copyright \u{00A9} 2026 \u{2014} Neeto",
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: 11),
                ]
            ),
        ]
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            options[.applicationIcon] = icon
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func toggleMaximize() {
        guard let splitTree = workspaceWindowController?.getSplitTree() else { return }
        if splitTree.isMaximized {
            splitTree.toggleMaximizeForActivePane()
        } else if let pane = findFocusedPane() {
            splitTree.toggleMaximize(pane)
        }
    }

    @objc private func openDiff() {
        guard let splitTree = workspaceWindowController?.getSplitTree() else { return }

        // Find the last pane (rightmost/bottommost) by seqId
        guard let pane = splitTree.paneControllers.values.max(by: { $0.seqId < $1.seqId }) else { return }

        // Add a lazygit terminal tab and select it
        pane.addTerminalTab(command: "lazygit")

        // Maximize the pane after a short delay to let the tab initialize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if !splitTree.isMaximized {
                splitTree.toggleMaximize(pane)
            }
        }
    }

    @objc private func closeDiff() {
        guard let splitTree = workspaceWindowController?.getSplitTree() else { return }

        // Unmaximize first if maximized
        if splitTree.isMaximized {
            splitTree.toggleMaximizeForActivePane()
        }

        // Close the active tab (kills the lazygit process cleanly)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let pane = self?.findFocusedPane() {
                pane.closeActiveTab()
            }
        }
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
