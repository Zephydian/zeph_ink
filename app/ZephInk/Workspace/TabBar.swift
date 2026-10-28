import AppKit
import SwiftUI

/// One tab per open document, then a + button for a new one. The empty space drags the window.
struct TabBar: View {
    let workspace: Workspace
    let controller: WorkspaceWindowController

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.tabs) { tab in
                        TabButton(document: tab.document,
                                  isSelected: tab.id == workspace.selectedID,
                                  select: { controller.select(tab.document) },
                                  close: { controller.close(tab.document) })
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)

            Button {
                NSDocumentController.shared.newDocument(nil)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverButtonStyle())
            .help("New document (⌘N)")
            .accessibilityLabel("New document")

            Spacer(minLength: 0)
        }
        .padding(.leading, Theme.trafficLightsWidth)
        .padding(.trailing, 10)
        .background(WindowDragArea())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open documents")
    }
}

/// A document's tab: its name, its extension dimmed, and a close button that shows a dot while the
/// document has unsaved changes (the ✕ comes back on hover).
private struct TabButton: View {
    let document: MarkdownDocument
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                Text(document.name)
                    .foregroundStyle(Color(isSelected ? .ink : .inkSecondary))
                    .truncationMode(.tail)
                Text(document.fileExtension)
                    .foregroundStyle(Color(.marker))
            }
            .lineLimit(1)
            .font(.system(size: 12.5))

            Button(action: close) {
                ZStack {
                    if document.isEdited && !isCloseHovered {
                        Circle().fill(Color(.inkSecondary)).frame(width: 7, height: 7)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(.inkSecondary))
                    }
                }
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 4).fill(isCloseHovered ? Color(.hover) : .clear))
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
                .fill(isSelected ? Color(.page) : isHovered ? Color(.hover) : .clear)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Color(.line), lineWidth: 1)
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
            .foregroundStyle(Color(.inkSecondary))
            .background(RoundedRectangle(cornerRadius: 7).fill(isHovered || configuration.isPressed ? Color(.hover) : .clear))
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
