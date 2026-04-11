import AppKit
import SwiftTerm

class TerminalTabViewController: NSViewController {
    let tabId = UUID()
    let seqId = SeqCounter.shared.nextId()
    let command: String
    let repoPath: String
    let environment: [String: String]
    private var terminalView: LocalProcessTerminalView!
    private var hasStarted = false

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

        // Build environment array: inherit current env + add our vars
        var env: [String] = []
        for (key, value) in ProcessInfo.processInfo.environment {
            env.append("\(key)=\(value)")
        }
        for (key, value) in environment {
            env.append("\(key)=\(value)")
        }

        // Add neetly CLI to PATH
        let execPath = ProcessInfo.processInfo.arguments[0]
        let execDir = URL(fileURLWithPath: execPath).deletingLastPathComponent().path
        if let existingPath = ProcessInfo.processInfo.environment["PATH"] {
            env.append("PATH=\(execDir):\(existingPath)")
        }

        terminalView.startProcess(executable: shell, args: ["-l"], environment: env)

        // Send the cd + command after shell initializes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let escapedPath = self.repoPath.replacingOccurrences(of: "'", with: "'\\''")
            let cmd: String
            if self.command.isEmpty {
                // Just cd to repo — plain shell
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

    /// Send text to the terminal's PTY as if the user typed it.
    func sendText(_ text: String) {
        let bytes = Array(text.utf8)
        terminalView.send(data: bytes[...])
    }
}
