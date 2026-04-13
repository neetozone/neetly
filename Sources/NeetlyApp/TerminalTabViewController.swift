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

        view = terminalView
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !hasStarted {
            hasStarted = true
            startProcess()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let escapedPath = self.repoPath.replacingOccurrences(of: "'", with: "'\\''")
            let cmd: String
            if self.command.isEmpty {
                cmd = "cd '\(escapedPath)'\n"
            } else {
                cmd = "cd '\(escapedPath)' && \(self.command)\n"
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
}
