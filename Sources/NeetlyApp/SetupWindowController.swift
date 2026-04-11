import AppKit
import SwiftUI

class SetupWindowController: NSWindowController {
    var onLaunch: ((WorkspaceConfig) -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "neetly"
        window.center()
        self.init(window: window)

        let setupView = SetupView { [weak self] config in
            self?.onLaunch?(config)
        }
        window.contentView = NSHostingView(rootView: setupView)
    }
}
