import AppKit
import SwiftUI

/// One tab per open document with a + for a new one right after them, and an Open button on the
/// right. The empty space drags the window.
///
/// Drag a tab along the bar to reorder it. Drag it down onto an editor to open it beside that pane
/// (the half it would go to is tinted), onto another window to move it there, or anywhere else to
/// give it a window of its own.
struct TabBar: View {
    let workspace: Workspace
    let controller: WorkspaceWindowController
    let height: CGFloat

    @State private var tabFrames: [Tab.ID: CGRect] = [:]
    @State private var dragged: Tab.ID?
    /// Where the dragged tab's middle was when the drag began, in the bar.
    @State private var dragStart: CGFloat = 0
    @State private var dragTranslation: CGSize = .zero

    /// How far below the bar a tab must be dragged before it leaves it.
    private var leaveDistance: CGFloat { height * 0.8 }

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.tabs) { tab in
                        TabButton(document: tab.document,
                                  isSelected: tab.id == workspace.selectedID,
                                  isShownElsewhere: tab.id != workspace.selectedID && workspace.pane(showing: tab.id) != nil,
                                  select: { controller.select(tab.document) },
                                  close: { controller.close(tab.document) })
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: TabFrames.self, value: [tab.id: proxy.frame(in: .named(Self.space))])
                            })
                            .offset(offset(of: tab.id))
                            .opacity(dragged == tab.id && isOutside ? 0.5 : 1)
                            .zIndex(dragged == tab.id ? 1 : 0)
                            .gesture(drag(tab))
                    }
                    // New tab, right after the last one (like a browser).
                    Button {
                        NSDocumentController.shared.newDocument(nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(HoverButtonStyle())
                    .help("New document — ⌘N")
                    .accessibilityLabel("New document")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Spacer(minLength: 0)

            // Open sits on the right, where the window's own buttons would be.
            Button {
                NSDocumentController.shared.openDocument(nil)
            } label: {
                Label("Open", systemImage: "folder")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .help("Open a markdown or text file — ⌘O")
            .accessibilityLabel("Open a file")
        }
        .padding(.leading, Theme.trafficLightsWidth)
        .padding(.trailing, 10)
        .frame(height: height)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(TabFrames.self) { tabFrames = $0 }
        .background(WindowDragArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open documents")
    }

    private static let space = "TabBar"

    private var isOutside: Bool { dragTranslation.height > leaveDistance }

    /// The dragged tab follows the pointer: along the bar, or anywhere once it has left it.
    private func offset(of id: Tab.ID) -> CGSize {
        guard dragged == id, let frame = tabFrames[id] else { return .zero }
        let x = dragStart + dragTranslation.width - frame.midX
        return CGSize(width: x, height: isOutside ? dragTranslation.height : 0)
    }

    private func drag(_ tab: Tab) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if dragged != tab.id {
                    dragged = tab.id
                    dragStart = tabFrames[tab.id]?.midX ?? value.startLocation.x
                    controller.select(tab.document)
                }
                dragTranslation = value.translation
                if isOutside {
                    controller.tabDragMoved(tab.document, to: NSEvent.mouseLocation)
                } else {
                    controller.tabDragMoved(tab.document, to: .init(x: -10_000, y: -10_000))   // clears any highlight
                    reorder(tab.id, center: dragStart + value.translation.width)
                }
            }
            .onEnded { _ in
                let wasOutside = isOutside
                dragged = nil
                dragTranslation = .zero
                if wasOutside { controller.tabDragEnded(tab.document, at: NSEvent.mouseLocation) }
            }
    }

    /// Moves the dragged tab past any neighbour whose middle it has crossed.
    private func reorder(_ id: Tab.ID, center: CGFloat) {
        guard let index = workspace.tabs.firstIndex(where: { $0.id == id }) else { return }
        var target = index
        for (other, tab) in workspace.tabs.enumerated() where tab.id != id {
            guard let frame = tabFrames[tab.id] else { continue }
            if other < index, center < frame.midX { target = min(target, other) }
            if other > index, center > frame.midX { target = max(target, other) }
        }
        guard target != index else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            workspace.moveTab(id, to: target)
        } else {
            withAnimation(.easeOut(duration: 0.15)) { workspace.moveTab(id, to: target) }
        }
    }
}

private struct TabFrames: PreferenceKey {
    static let defaultValue: [Tab.ID: CGRect] = [:]
    static func reduce(value: inout [Tab.ID: CGRect], nextValue: () -> [Tab.ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A document's tab: its name, its extension dimmed, and a close button that shows a dot while the
/// document has unsaved changes (the ✕ comes back on hover).
private struct TabButton: View {
    let document: MarkdownDocument
    let isSelected: Bool
    /// Showing in another pane of a split window.
    let isShownElsewhere: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(document.name)
                    .foregroundStyle(Color(nsColor: isSelected ? Theme.chromeInk : Theme.chromeInkSecondary))
                    .truncationMode(.tail)
                Text(document.fileExtension)
                    .foregroundStyle(Color(nsColor: Theme.chromeMarker))
            }
            .lineLimit(1)
            .font(.system(size: 12.5))

            Button(action: close) {
                ZStack {
                    if document.isEdited && !isCloseHovered {
                        Circle().fill(Color(nsColor: Theme.chromeInkSecondary)).frame(width: 7, height: 7)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
                    }
                }
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(isCloseHovered ? Color(nsColor: Theme.hover) : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .help("Close tab (⌘W)")
            .accessibilityLabel("Close \(document.name)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxWidth: 200, minHeight: 28, maxHeight: 28)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color(nsColor: Theme.chromeSurface) : isHovered || isShownElsewhere ? Color(nsColor: Theme.hover) : .clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: Theme.chromeLine), lineWidth: 1)
                    }
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(document.name + document.fileExtension + (document.isEdited ? ", edited" : ""))
        .accessibilityAction(named: "Close", close)
        .accessibilityAction(.default, select)
    }
}

/// A small button that shows a hover background, like the prototype's chrome buttons.
private struct HoverButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color(nsColor: Theme.chromeInkSecondary))
            .background(RoundedRectangle(cornerRadius: 7).fill(isHovered || configuration.isPressed ? Color(nsColor: Theme.hover) : .clear))
            .onHover { isHovered = $0 }
    }
}

/// Empty title bar space: dragging it moves the window, and double-clicking it zooms (or minimizes,
/// following the person's Desktop & Dock setting).
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")
                if action == "Minimize" { window.performMiniaturize(nil) } else if action != "None" { window.performZoom(nil) }
            } else {
                window.performDrag(with: event)
            }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
}
