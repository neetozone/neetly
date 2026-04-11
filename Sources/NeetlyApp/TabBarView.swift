import AppKit

/// Chrome-style horizontal tab bar at the top of each pane.
class TabBarView: NSView {
    var onSelectTab: ((Int) -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onNewTerminal: (() -> Void)?
    var onNewBrowser: (() -> Void)?
    var onSplitColumns: (() -> Void)?
    var onSplitRows: (() -> Void)?
    private var buttons: [NSView] = []
    private let newTerminalButton = NSButton()
    private let newBrowserButton = NSButton()
    private let splitColButton = NSButton()
    private let splitRowButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        // "+Terminal" button — right-aligned
        newTerminalButton.title = ">_"
        newTerminalButton.toolTip = "New Terminal"
        newTerminalButton.bezelStyle = .recessed
        newTerminalButton.font = .systemFont(ofSize: 11, weight: .medium)
        newTerminalButton.target = self
        newTerminalButton.action = #selector(newTerminalClicked)
        newTerminalButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newTerminalButton)

        // "+Browser" button — right of terminal button
        newBrowserButton.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "New Browser")
        newBrowserButton.toolTip = "New Browser"
        newBrowserButton.bezelStyle = .recessed
        newBrowserButton.imagePosition = .imageOnly
        newBrowserButton.target = self
        newBrowserButton.action = #selector(newBrowserClicked)
        newBrowserButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(newBrowserButton)

        // Split columns button
        splitColButton.image = NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "Split Columns")
        splitColButton.toolTip = "Split Columns"
        splitColButton.bezelStyle = .recessed
        splitColButton.imagePosition = .imageOnly
        splitColButton.target = self
        splitColButton.action = #selector(splitColClicked)
        splitColButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitColButton)

        // Split rows button
        splitRowButton.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split Rows")
        splitRowButton.toolTip = "Split Rows"
        splitRowButton.bezelStyle = .recessed
        splitRowButton.imagePosition = .imageOnly
        splitRowButton.target = self
        splitRowButton.action = #selector(splitRowClicked)
        splitRowButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitRowButton)

        NSLayoutConstraint.activate([
            splitRowButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            splitRowButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitRowButton.widthAnchor.constraint(equalToConstant: 28),
            splitRowButton.heightAnchor.constraint(equalToConstant: 22),

            splitColButton.trailingAnchor.constraint(equalTo: splitRowButton.leadingAnchor, constant: -2),
            splitColButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitColButton.widthAnchor.constraint(equalToConstant: 28),
            splitColButton.heightAnchor.constraint(equalToConstant: 22),

            newBrowserButton.trailingAnchor.constraint(equalTo: splitColButton.leadingAnchor, constant: -6),
            newBrowserButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newBrowserButton.widthAnchor.constraint(equalToConstant: 28),
            newBrowserButton.heightAnchor.constraint(equalToConstant: 22),

            newTerminalButton.trailingAnchor.constraint(equalTo: newBrowserButton.leadingAnchor, constant: -2),
            newTerminalButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTerminalButton.widthAnchor.constraint(equalToConstant: 32),
            newTerminalButton.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(tabs: [(title: String, icon: NSImage?, isActive: Bool)]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll()

        var x: CGFloat = 2
        for (i, tab) in tabs.enumerated() {
            let tabView = TabButton(
                index: i, title: tab.title, icon: tab.icon, isActive: tab.isActive,
                onSelect: { [weak self] idx in self?.onSelectTab?(idx) },
                onClose: { [weak self] idx in self?.onCloseTab?(idx) }
            )
            tabView.frame.origin = CGPoint(x: x, y: 2)
            addSubview(tabView)
            buttons.append(tabView)
            x += tabView.frame.width + 2
        }
    }

    @objc private func newTerminalClicked() {
        onNewTerminal?()
    }

    @objc private func newBrowserClicked() {
        onNewBrowser?()
    }

    @objc private func splitColClicked() {
        onSplitColumns?()
    }

    @objc private func splitRowClicked() {
        onSplitRows?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Bottom border
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }
}

private class TabButton: NSView {
    let tabIndex: Int
    private let onSelect: (Int) -> Void
    private let onClose: (Int) -> Void
    private let isActive: Bool
    private let closeBtn: NSButton
    private var trackingArea: NSTrackingArea?

    init(index: Int, title: String, icon: NSImage?, isActive: Bool,
         onSelect: @escaping (Int) -> Void, onClose: @escaping (Int) -> Void) {
        self.tabIndex = index
        self.isActive = isActive
        self.onSelect = onSelect
        self.onClose = onClose
        self.closeBtn = NSButton(frame: NSRect(x: 0, y: 3, width: 18, height: 18))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4

        if isActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }

        // Icon
        var x: CGFloat = 6
        if let icon = icon {
            let iconView = NSImageView(frame: NSRect(x: x, y: 5, width: 14, height: 14))
            let resized = NSImage(size: NSSize(width: 14, height: 14))
            resized.lockFocus()
            icon.draw(in: NSRect(x: 0, y: 0, width: 14, height: 14))
            resized.unlockFocus()
            iconView.image = resized
            addSubview(iconView)
            x += 18
        }

        // Title
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: isActive ? .semibold : .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: x, y: 4, width: 90, height: 16)
        addSubview(label)

        // Close button — hidden by default, shown on hover
        closeBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab")
        closeBtn.imagePosition = .imageOnly
        closeBtn.isBordered = false
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.imageScaling = .scaleProportionallyDown
        closeBtn.isHidden = true
        let closeX = x + label.frame.width + 4
        closeBtn.frame.origin.x = closeX
        addSubview(closeBtn)

        frame.size = NSSize(width: closeX + 22, height: 24)

        // Clamp width
        let minW: CGFloat = 80
        let maxW: CGFloat = 160
        frame.size.width = min(max(frame.width, minW), maxW)

        // Adjust label width to fit
        label.frame.size.width = frame.width - x - 26
        closeBtn.frame.origin.x = frame.width - 22
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        closeBtn.isHidden = false
    }

    override func mouseExited(with event: NSEvent) {
        closeBtn.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if loc.x < frame.width - 22 {
            onSelect(tabIndex)
        }
    }

    @objc private func closeClicked() {
        onClose(tabIndex)
    }
}
