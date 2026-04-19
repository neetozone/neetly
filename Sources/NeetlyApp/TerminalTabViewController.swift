import AppKit
import SwiftTerm

class TerminalTabViewController: NSViewController, LocalProcessTerminalViewDelegate {
    let tabId = UUID()
    let seqId = SeqCounter.shared.nextId()
    let command: String
    let repoPath: String
    let environment: [String: String]
    private var terminalView: LocalProcessTerminalView!
    private var hasStarted = false
    private var mouseEventMonitor: Any?
    private var autoScrollTimer: Timer?
    private var isDragSelecting = false
    private var mouseDownPoint: NSPoint?
    /// Called when the shell process exits (e.g. user types `exit`).
    var onProcessExited: (() -> Void)?

    init(command: String, repoPath: String, environment: [String: String]) {
        self.command = command
        self.repoPath = repoPath
        self.environment = environment
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView.autoresizingMask = [.width, .height]

        let config = TerminalConfig.load()
        terminalView.font = config.font
        if let bg = config.bgColor {
            terminalView.nativeBackgroundColor = bg
        }
        if let fg = config.fgColor {
            terminalView.nativeForegroundColor = fg
        }
        if let sel = config.selColor {
            terminalView.selectedTextBackgroundColor = sel
        }
        // Increase scrollback (SwiftTerm default is only 500 lines)
        let scrollback = config.scrollback ?? 10000
        let term = terminalView.getTerminal()
        term.options = TerminalOptions(
            cols: term.cols,
            rows: term.rows,
            scrollback: scrollback
        )

        view = terminalView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasStarted {
            hasStarted = true
            startProcess()
        }
        installMouseMonitor()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        removeMouseMonitor()
    }

    // MARK: - Auto-scroll during selection drag

    /// SwiftTerm's public API doesn't let us override mouse methods, so we
    /// install a local event monitor that tracks mouseDown/Dragged/Up on our
    /// terminal view. While a drag is active outside the visible area, we
    /// start a timer that scrolls up/down so the user can extend the selection
    /// into scrollback — matches iTerm2/WezTerm behavior.
    private func installMouseMonitor() {
        guard mouseEventMonitor == nil else { return }
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func removeMouseMonitor() {
        if let m = mouseEventMonitor {
            NSEvent.removeMonitor(m)
            mouseEventMonitor = nil
        }
        stopAutoScrollTimer()
    }

    private func handleMouseEvent(_ event: NSEvent) {
        // Only react to events that target our terminal view
        guard let window = terminalView?.window, event.window === window else { return }
        let local = terminalView.convert(event.locationInWindow, from: nil)
        let inside = terminalView.bounds.contains(local)

        switch event.type {
        case .leftMouseDown:
            if inside {
                isDragSelecting = true
                mouseDownPoint = local
                startAutoScrollTimer()
            }
        case .leftMouseDragged:
            // keep timer running; dragging outside bounds is what triggers scrolling
            break
        case .leftMouseUp:
            isDragSelecting = false
            stopAutoScrollTimer()
            // Single click only (not double-click, not drag, not Cmd+Click) → check for URL
            if inside, event.clickCount == 1, let downPt = mouseDownPoint,
               !event.modifierFlags.contains(.command),
               abs(local.x - downPt.x) < 3 && abs(local.y - downPt.y) < 3 {
                openLinkAtPoint(local)
            }
            mouseDownPoint = nil
        default:
            break
        }
    }

    /// Check if the click position lands on a URL in the terminal and open it.
    private func openLinkAtPoint(_ localPoint: NSPoint) {
        let terminal = terminalView.getTerminal()
        guard let pixelSize = terminalView.cellSizeInPixels(source: terminal) else { return }
        let scale = terminalView.window?.backingScaleFactor ?? 2.0
        let cellWidth = CGFloat(pixelSize.width) / scale
        let cellHeight = CGFloat(pixelSize.height) / scale
        guard cellWidth > 0, cellHeight > 0 else { return }

        // AppKit y=0 at bottom; terminal row=0 at top.
        let col = Int(localPoint.x / cellWidth)
        let row = Int((terminalView.bounds.height - localPoint.y) / cellHeight)

        let pos = Position(col: col, row: row)
        if let link = terminal.link(at: .screen(pos), mode: .explicitAndImplicit),
           let url = URL(string: link),
           url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAutoScrollTimer() {
        stopAutoScrollTimer()
        autoScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.autoScrollTick()
        }
    }

    private func stopAutoScrollTimer() {
        autoScrollTimer?.invalidate()
        autoScrollTimer = nil
    }

    private func autoScrollTick() {
        guard isDragSelecting, let window = terminalView.window else { return }
        let globalPoint = NSEvent.mouseLocation
        let winPoint = window.convertPoint(fromScreen: globalPoint)
        let localPoint = terminalView.convert(winPoint, from: nil)

        // AppKit coordinates: y=0 at bottom, y=bounds.height at top.
        if localPoint.y > terminalView.bounds.height {
            terminalView.scrollUp(lines: 1)
        } else if localPoint.y < 0 {
            terminalView.scrollDown(lines: 1)
        }
    }

    private func startProcess() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        var env: [String] = []
        for (key, value) in ProcessInfo.processInfo.environment {
            env.append("\(key)=\(value)")
        }
        for (key, value) in environment {
            env.append("\(key)=\(value)")
        }

        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent().path
        if let existingPath = ProcessInfo.processInfo.environment["PATH"] {
            env.append("PATH=\(execDir):\(existingPath)")
        }

        terminalView.processDelegate = self
        terminalView.startProcess(executable: shell, args: ["-l"], environment: env)

        // Apply custom link color (overrides ANSI palette blue) by feeding
        // OSC 4 directly to the terminal (not via PTY).
        let config = TerminalConfig.load()
        if let osc = config.oscLinkColorSequence {
            terminalView.feed(text: osc)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let escapedPath = self.repoPath.replacingOccurrences(of: "'", with: "'\\''")
            // Prepend the neetly CLI directory to PATH at the shell prompt, so
            // it survives path_helper (which runs in /etc/zprofile for login
            // shells and wipes out env-level PATH additions).
            let escapedExecDir = execDir.replacingOccurrences(of: "'", with: "'\\''")
            let pathExport = "export PATH='\(escapedExecDir)':\"$PATH\""
            let cmd: String
            if self.command.isEmpty {
                cmd = "\(pathExport); cd '\(escapedPath)'\n"
            } else {
                cmd = "\(pathExport); cd '\(escapedPath)' && \(self.command)\n"
            }
            let bytes = Array(cmd.utf8)
            self.terminalView.send(data: bytes[...])
        }
    }

    func focusTerminal() {
        view.window?.makeFirstResponder(terminalView)
    }

    func sendText(_ text: String) {
        let bytes = Array(text.utf8)
        terminalView.send(data: bytes[...])
    }

    /// Send SIGINT to the shell process and its children (equivalent to Ctrl+C).
    func interruptProcess() {
        let pid = terminalView.process.shellPid
        guard pid > 0 else { return }
        // Send SIGINT to the process group so child processes (servers, etc.) also get it
        kill(-pid, SIGINT)
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.onProcessExited?()
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// Called when user clicks a URL in the terminal.
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    deinit {
        removeMouseMonitor()
    }
}
