import AppKit

/// NSSplitView subclass that applies an initial divider ratio after the first
/// layout pass (when bounds are non-zero). Without this, setting the divider
/// position immediately after creation is a no-op because the view has zero size.
class RatioSplitView: NSSplitView {
    var initialRatio: CGFloat?
    private var didApplyInitialRatio = false

    override func layout() {
        super.layout()
        guard !didApplyInitialRatio, let ratio = initialRatio else { return }
        let total = isVertical ? bounds.width : bounds.height
        guard total > 0 else { return }
        // Set the flag BEFORE calling setPosition, because setPosition triggers
        // another layout pass which re-enters this method.
        didApplyInitialRatio = true
        setPosition(total * ratio, ofDividerAt: 0)
    }
}

/// Recursively builds NSSplitView hierarchy from a LayoutNode tree.
class SplitTreeController: NSViewController {
    let layout: LayoutNode
    let repoPath: String
    let socketServer: SocketServer
    /// All pane controllers keyed by pane UUID, for socket command routing.
    private(set) var paneControllers: [UUID: PaneViewController] = [:]

    /// State for a maximized pane. Used to restore it on unmaximize.
    private struct MaximizedState {
        let pane: PaneViewController
        let placeholder: NSView
        let parentIsSplit: Bool
        let dividerPosition: CGFloat?
    }
    private var maximizedState: MaximizedState?

    var isMaximized: Bool { maximizedState != nil }

    init(layout: LayoutNode, repoPath: String, socketServer: SocketServer) {
        self.layout = layout
        self.repoPath = repoPath
        self.socketServer = socketServer
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// The actual split tree (NSSplitView or single pane view). It sits inside `view`
    /// so we can overlay a maximized pane on top of it without disturbing the tree.
    private var treeRoot: NSView!

    override func loadView() {
        let container = NSView()
        treeRoot = buildView(from: layout)
        treeRoot.frame = container.bounds
        treeRoot.autoresizingMask = [.width, .height]
        container.addSubview(treeRoot)
        view = container
    }

    private func buildView(from node: LayoutNode) -> NSView {
        switch node {
        case .run(let command):
            let pane = makePaneController()
            pane.addTerminalTab(command: command)
            return pane.view

        case .visit(let url):
            let pane = makePaneController()
            pane.addBrowserTab(url: url)
            return pane.view

        case .tabs(let children):
            let pane = makePaneController()
            for child in children {
                switch child {
                case .run(let command):
                    pane.addTerminalTab(command: command)
                case .visit(let url):
                    pane.addBrowserTab(url: url)
                default:
                    break
                }
            }
            // Select the first tab
            if !children.isEmpty { pane.selectTab(at: 0) }
            return pane.view

        case .split(let direction, let first, let second, let firstSize, let secondSize):
            let splitView = RatioSplitView()
            splitView.isVertical = (direction == .columns)
            splitView.dividerStyle = .thin
            splitView.autoresizingMask = [.width, .height]

            let firstView = buildView(from: first)
            let secondView = buildView(from: second)

            splitView.addArrangedSubview(firstView)
            splitView.addArrangedSubview(secondView)

            // Apply size: first size wins if specified; otherwise second size
            // determines the split; otherwise 50/50. This naturally handles
            // the "sizes don't add to 100%" case — second gets the remainder.
            let ratio: CGFloat
            if let s = firstSize {
                ratio = CGFloat(max(0.05, min(0.95, s)))
            } else if let s = secondSize {
                ratio = CGFloat(max(0.05, min(0.95, 1.0 - s)))
            } else {
                ratio = 0.5
            }
            splitView.initialRatio = ratio

            return splitView
        }
    }

    private func makePaneController() -> PaneViewController {
        let pane = PaneViewController(repoPath: repoPath, socketServer: socketServer)
        addChild(pane)
        paneControllers[pane.paneId] = pane
        pane.onSplit = { [weak self, weak pane] direction in
            guard let self, let pane else { return }
            self.splitPane(pane, direction: direction)
        }
        pane.onEmpty = { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.collapsePane(pane)
        }
        pane.onToggleMaximize = { [weak self, weak pane] in
            guard let self, let pane else { return }
            self.toggleMaximize(pane)
        }
        return pane
    }

    /// Split an existing pane into two. The original stays on one side,
    /// a new empty terminal pane appears on the other.
    func splitPane(_ pane: PaneViewController, direction: SplitDirection) {
        let oldView = pane.view
        guard let parent = oldView.superview else { return }

        // Create new pane
        let newPane = makePaneController()
        newPane.addTerminalTab(command: "")

        // Create split view
        let splitView = NSSplitView()
        splitView.isVertical = (direction == .columns)
        splitView.dividerStyle = .thin
        splitView.frame = oldView.frame
        splitView.autoresizingMask = oldView.autoresizingMask

        // Replace old view with split view
        parent.replaceSubview(oldView, with: splitView)

        // Add both panes to the split
        oldView.autoresizingMask = [.width, .height]
        newPane.view.autoresizingMask = [.width, .height]
        splitView.addArrangedSubview(oldView)
        splitView.addArrangedSubview(newPane.view)

        // Equal split
        DispatchQueue.main.async {
            let half = splitView.isVertical
                ? splitView.bounds.width / 2
                : splitView.bounds.height / 2
            splitView.setPosition(half, ofDividerAt: 0)
        }

        // Trigger viewDidAppear for the new pane's terminal
        newPane.view.window?.makeFirstResponder(newPane.view)
    }

    /// When the last tab of a pane is closed, collapse it:
    /// remove the empty pane and promote the sibling to take the parent split's place.
    func collapsePane(_ pane: PaneViewController) {
        let emptyView = pane.view
        guard let splitView = emptyView.superview as? NSSplitView else {
            // Not inside a split — it's the root pane, nothing to collapse
            return
        }

        // Find the sibling view (the other child of the split)
        let siblings = splitView.arrangedSubviews
        guard let sibling = siblings.first(where: { $0 !== emptyView }) else { return }

        // Remove the empty pane
        paneControllers.removeValue(forKey: pane.paneId)
        pane.removeFromParent()

        // Replace the NSSplitView with the sibling in the parent
        guard let parent = splitView.superview else { return }
        sibling.removeFromSuperview()
        sibling.frame = splitView.frame
        sibling.autoresizingMask = splitView.autoresizingMask
        parent.replaceSubview(splitView, with: sibling)

        // Focus the sibling
        sibling.window?.makeFirstResponder(sibling)
    }

    /// Find a pane controller by its UUID string.
    func pane(for id: String) -> PaneViewController? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return paneControllers[uuid]
    }

    // MARK: - Maximize / Restore

    func toggleMaximize(_ pane: PaneViewController) {
        if let state = maximizedState {
            // Already maximized — unmaximize (regardless of which pane is clicked)
            unmaximize(state)
        } else {
            maximize(pane)
        }
    }

    /// Maximize via keyboard shortcut on the currently focused pane.
    func toggleMaximizeForActivePane() {
        if let state = maximizedState {
            unmaximize(state)
        }
    }

    private func maximize(_ pane: PaneViewController) {
        let paneView = pane.view
        guard let parent = paneView.superview else { return }

        // If the pane is the ONLY thing in the tree (no splits), maximize is a no-op.
        if paneView === treeRoot { return }

        let parentIsSplit = parent is NSSplitView

        // Save the divider position so we can restore the exact split ratio.
        var dividerPosition: CGFloat? = nil
        if let splitParent = parent as? NSSplitView, splitParent.subviews.count >= 2 {
            let firstView = splitParent.subviews[0]
            dividerPosition = splitParent.isVertical ? firstView.frame.width : firstView.frame.height
        }

        // Create a placeholder to hold the pane's slot in the tree.
        let placeholder = NSView(frame: paneView.frame)
        placeholder.translatesAutoresizingMaskIntoConstraints = true
        placeholder.autoresizingMask = [.width, .height]

        if let splitParent = parent as? NSSplitView {
            guard let idx = splitParent.arrangedSubviews.firstIndex(of: paneView) else { return }
            splitParent.insertArrangedSubview(placeholder, at: idx)
            paneView.removeFromSuperview()
        } else {
            parent.replaceSubview(paneView, with: placeholder)
        }

        // Hide the entire split tree and overlay the pane on the container using constraints.
        treeRoot.isHidden = true
        paneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(paneView)
        NSLayoutConstraint.activate([
            paneView.topAnchor.constraint(equalTo: view.topAnchor),
            paneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            paneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            paneView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        maximizedState = MaximizedState(pane: pane, placeholder: placeholder, parentIsSplit: parentIsSplit, dividerPosition: dividerPosition)
        pane.setMaximizedState(true)
    }

    private func unmaximize(_ state: MaximizedState) {
        let paneView = state.pane.view
        let placeholder = state.placeholder
        guard let parent = placeholder.superview else {
            maximizedState = nil
            return
        }

        // Remove pane from the container overlay (also removes its constraints)
        paneView.removeFromSuperview()

        // Restore autoresizing (maximize switched to constraint-based layout)
        paneView.translatesAutoresizingMaskIntoConstraints = true
        paneView.autoresizingMask = [.width, .height]

        // Show the split tree again
        treeRoot.isHidden = false

        // Put the pane back where the placeholder is
        if state.parentIsSplit, let splitParent = parent as? NSSplitView {
            guard let idx = splitParent.arrangedSubviews.firstIndex(of: placeholder) else { return }
            placeholder.removeFromSuperview()
            splitParent.insertArrangedSubview(paneView, at: idx)

            // Restore the original divider position (deferred so layout has occurred)
            if let pos = state.dividerPosition {
                DispatchQueue.main.async {
                    splitParent.setPosition(pos, ofDividerAt: 0)
                }
            }
        } else {
            parent.replaceSubview(placeholder, with: paneView)
        }

        state.pane.setMaximizedState(false)
        maximizedState = nil

        // Restore focus so Cmd+Shift+M continues to work
        paneView.window?.makeFirstResponder(paneView)
    }
}
