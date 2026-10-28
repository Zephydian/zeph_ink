import SwiftUI

/// Shows an editor's scroll view in SwiftUI. The view belongs to the `Editor` and outlives this
/// wrapper, so switching tabs only moves it in and out of the window.
struct EditorView: NSViewRepresentable {
    let editor: Editor

    func makeNSView(context: Context) -> NSScrollView {
        editor.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {}
}
