import AppKit
import SwiftUI

/// The editors side by side, one per pane, with dividers you can drag (double-click one to make the
/// panes equal).
final class PaneSplitView: NSSplitView, NSSplitViewDelegate {
    static let minimumPaneWidth: CGFloat = 260

    private(set) var containers: [PaneContainer] = []
    /// Pane widths to restore (as fractions of the whole) the next time the panes are laid out.
    var pendingFractions: [CGFloat]?

    init() {
        super.init(frame: .zero)
        isVertical = true
        dividerStyle = .thin
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var dividerColor: NSColor { Theme.line }

    /// Shows these panes, reusing the views of panes that stay so their widths and scroll positions do too.
    func update(panes: [(pane: Workspace.Pane, editor: Editor)], focused: Workspace.Pane.ID?) {
        let ids = panes.map(\.pane.id)
        let changed = ids != containers.map(\.paneID)
        let countChanged = ids.count != containers.count
        let existing = Dictionary(uniqueKeysWithValues: containers.map { ($0.paneID, $0) })
        containers = panes.map { item in
            let container = existing[item.pane.id] ?? PaneContainer(paneID: item.pane.id)
            container.show(item.editor)
            container.isHighlighted = panes.count > 1 && item.pane.id == focused
            return container
        }
        if changed {
            for view in arrangedSubviews where !containers.contains(where: { $0 === view }) { removeArrangedSubview(view); view.removeFromSuperview() }
            for (index, container) in containers.enumerated() {
                if arrangedSubviews.firstIndex(of: container) != index {
                    if container.superview === self { removeArrangedSubview(container) }
                    insertArrangedSubview(container, at: index)
                }
            }
        }
        if countChanged || pendingFractions != nil {
            let saved = pendingFractions.flatMap { $0.count == containers.count && $0.allSatisfy({ $0 > 0.1 }) ? $0 : nil }
            pendingWidths = saved ?? equalFractions
            pendingFractions = nil
            needsLayout = true
        }
    }

    /// Widths waiting for the next layout, when the split view knows its own size.
    private var pendingWidths: [CGFloat]?

    override func layout() {
        super.layout()
        if let widths = pendingWidths, bounds.width > 0 {
            pendingWidths = nil
            apply(widths)
        }
    }

    /// Each pane's share of the width, for saving the layout.
    var fractions: [CGFloat] {
        let total = containers.reduce(0) { $0 + $1.frame.width }
        guard total > 0 else { return equalFractions }
        return containers.map { $0.frame.width / total }
    }

    private var equalFractions: [CGFloat] {
        containers.map { _ in 1 / CGFloat(max(containers.count, 1)) }
    }

    /// Makes every pane the same width.
    func equalize() {
        apply(equalFractions)
    }

    /// Sizes the panes to these shares of the width, by setting their frames directly.
    private func apply(_ fractions: [CGFloat]) {
        guard containers.count > 1, fractions.count == containers.count else { return }
        let available = bounds.width - dividerThickness * CGFloat(containers.count - 1)
        var x: CGFloat = 0
        for (index, container) in containers.enumerated() {
            let width = index == containers.count - 1 ? bounds.width - x : (available * fractions[index]).rounded()
            container.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
            x += width + dividerThickness
        }
        adjustSubviews()
    }

    /// The pane under a point in window coordinates, and which half of it the point is in.
    func pane(at windowPoint: NSPoint) -> (container: PaneContainer, side: Workspace.Side)? {
        for container in containers {
            let point = container.convert(windowPoint, from: nil)
            guard container.bounds.contains(point) else { continue }
            return (container, point.x < container.bounds.midX ? .left : .right)
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let point = convert(event.locationInWindow, from: nil)
            let onDivider = containers.dropLast().contains { abs($0.frame.maxX + dividerThickness / 2 - point.x) <= 4 }
            if onDivider {
                equalize()
                return
            }
        }
        super.mouseDown(with: event)
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard containers.indices.contains(dividerIndex) else { return proposedMinimumPosition }
        return containers[dividerIndex].frame.minX + Self.minimumPaneWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard containers.indices.contains(dividerIndex + 1) else { return proposedMaximumPosition }
        return containers[dividerIndex + 1].frame.maxX - Self.minimumPaneWidth - dividerThickness
    }
}

/// One pane: an editor, a thin accent line along its top while it has the focus in a split, and a
/// highlight where a dragged tab would land.
final class PaneContainer: NSView {
    let paneID: Workspace.Pane.ID
    private weak var editor: Editor?
    private let focusLine = NSView()
    private let dropHighlight = NSView()

    var isHighlighted = false {
        didSet { focusLine.isHidden = !isHighlighted }
    }

    /// The half of the pane a dragged tab would open beside, shown tinted.
    var dropSide: Workspace.Side? {
        didSet { needsLayout = true; dropHighlight.isHidden = dropSide == nil }
    }

    init(paneID: Workspace.Pane.ID) {
        self.paneID = paneID
        super.init(frame: .zero)
        focusLine.wantsLayer = true
        focusLine.isHidden = true
        dropHighlight.wantsLayer = true
        dropHighlight.isHidden = true
        addSubview(focusLine)
        addSubview(dropHighlight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show(_ editor: Editor) {
        guard editor !== self.editor || editor.scrollView.superview !== self else { return }
        self.editor?.scrollView.removeFromSuperview()
        self.editor = editor
        editor.scrollView.removeFromSuperview()
        addSubview(editor.scrollView, positioned: .below, relativeTo: focusLine)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        editor?.scrollView.frame = bounds
        focusLine.frame = NSRect(x: 0, y: isFlipped ? 0 : bounds.height - 2, width: bounds.width, height: 2)
        focusLine.layer?.backgroundColor = Theme.accent.cgColor
        let half = NSRect(x: dropSide == .right ? bounds.midX : 0, y: 0, width: bounds.width / 2, height: bounds.height)
        dropHighlight.frame = half
        dropHighlight.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.12).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsLayout = true   // layer colors don't follow the appearance on their own
    }
}

/// Puts a workspace's panes into SwiftUI.
struct PaneSplitRepresentable: NSViewRepresentable {
    let splitView: PaneSplitView
    let panes: [(pane: Workspace.Pane, editor: Editor)]
    let focused: Workspace.Pane.ID?

    func makeNSView(context: Context) -> PaneSplitView { splitView }

    func updateNSView(_ view: PaneSplitView, context: Context) {
        view.update(panes: panes, focused: focused)
    }
}
