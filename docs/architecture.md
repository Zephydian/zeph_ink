# Architecture

How Zeph#Ink's window, documents and editor fit together.

## App shell: AppKit, with SwiftUI views

`App/ZephInkApp.swift` starts a plain `NSApplication` with a menu bar built in code (`App/MainMenu.swift`), not a SwiftUI `App`:

- SwiftUI's document scenes (`DocumentGroup`) give every document its own window, while Zeph#Ink keeps documents as tabs in one window, side by side.
- AppKit's document menu items (Open Recent, Revert to Saved, Browse All Versions, Rename, Move To) work only in a main menu AppKit can see and fill in.

Everything inside the window (tab bar, and later the toolbar, status bar and settings) is SwiftUI.

## Documents: `NSDocument`, without windows of their own

`MarkdownDocument` is an `NSDocument`, so macOS provides autosave in place, Versions, crash recovery, the "Edited" state, Open Recent and file coordination. `NSDocumentController.shared` (not subclassed) opens and creates documents, and stops a file from being opened twice.

A document doesn't make a window:

| `NSDocument` hook | What Zeph#Ink does |
| --- | --- |
| `makeWindowControllers()` | Adds the document as a tab to the frontmost workspace (`WorkspaceWindowController.forNewDocument()`), or a new one. |
| `showWindows()` | Selects its tab and brings the window forward (also when you open a file that's already open). |
| `windowForSheet` | The workspace window, so Save and "Do you want to save" sheets attach to it. |
| `close()` | Removes its tab. The window closes after its last tab. |

The document isn't in the workspace window controller's `windowControllers`. Instead, the controller sets its own `document` to the **selected tab's** document. That puts the document in the responder chain (so Save, Duplicate and Revert act on the tab you're in), and the window's `windowWillReturnUndoManager` returns that document's undo manager (so typing marks the right document as edited).

Closing a tab calls `canClose(withDelegate:…)` first, which asks about unsaved changes when macOS needs to. The window's close button closes the tabs one at a time the same way, and stops if you cancel.

## The text is the file

Each document owns an `NSTextStorage`. Its editor's TextKit 2 text view (`NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer` → `ZephTextView`) edits that storage directly, and `data(ofType:)` writes its string back as UTF-8.

The document keeps the bytes it last read or wrote. If the text hasn't changed, saving writes those exact bytes. A UTF-8 byte order mark is kept aside and written back. `ZephInkTests` checks this with the files in `Fixtures/`.

## Workspace

- `Workspace` (`@Observable`): the tabs in order and the selected one. Each `Tab` pairs a document with its `Editor`.
- `Editor`: one document's text view and scroll view. It lives as long as the tab, so switching tabs keeps the selection, scroll position and undo history. `EditorView` hands its scroll view to SwiftUI.
- `WorkspaceWindowController`: the window (full-size content, transparent title bar, tab bar beside the window buttons) and the glue above. It watches the workspace to keep the window's document, title, edited dot and focus in step with the selected tab.
- `TabBar`: the tabs and the + button. Its empty space drags the window, and double-clicking it zooms (following the Desktop & Dock setting).

Native window tabs are turned off (`tabbingMode = .disallowed`): they can't show documents side by side.

## Theme

Color tokens are light/dark pairs in `Assets.xcassets`, read through generated asset symbols (`NSColor(resource: .page)`, `Color(.ink)`) and collected in `Editor/Theme.swift`.
