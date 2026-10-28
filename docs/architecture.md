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

## Styling markdown

The text in the editor is always the raw markdown. Styling only sets attributes on it, never characters, so what's saved is exactly what was typed. Three pieces do the work:

1. **`MarkdownAnalysis`** parses the text with swift-markdown and records, for each line, what it is (body, heading, code, divider, table, blank), its quote depth, its list marker and checkbox, and where its block symbols are (`## `, `> `, `- `, code fences). It also records inline styles (bold, italic, strikethrough, code, links) and their symbols (`**`, `` ` ``, `](url)`). Positions are converted from swift-markdown's UTF-8 columns to UTF-16 offsets. It's a plain value with no AppKit, so it's easy to test.
2. **`MarkdownStyler`** turns a range of analyzed lines into attributes: fonts, colors, paragraph styles, and a `LineDecoration` for anything drawn rather than typed.
3. **`PageLayoutFragment`** (a TextKit 2 layout fragment) draws each line's decoration: quote bars, code block boxes, dividers, bullets and checkboxes.

### Hiding markdown symbols

Settings → Markdown Symbols (for now under View → Markdown Symbols):

- **Clean** (default) hides symbols except on the lines the selection is on, where they show faded.
- **Faded** always shows them dimmed.

Hidden symbols are drawn in a 0.01 pt font with a clear color, so they take no visible space. The characters stay in the text and the cursor still steps through them, but moving onto a line reveals its symbols, so you never edit around invisible characters. Other techniques were rejected:

- Removing characters from the displayed paragraph (`NSTextContentStorageDelegate`) breaks the mapping between the text and what's shown.
- Negative kerning depends on each glyph's width.
- Custom glyph drawing can't take a character's space away.

A bullet or checkbox is drawn over its symbol, which keeps its width but is clear, so the text doesn't move. The last character gets extra kerning for the room the drawing needs. Numbers in numbered lists are part of the text and are never hidden.

### Keeping up with typing

Each edit runs inside `NSTextStorageDelegate.textStorage(_:didProcessEditing:…)`, before layout, so new text never shows unstyled. `MarkdownAnalysis.updated(afterEditing:…)` re-parses only the blocks around the edit, plus one neighboring line on each side (an edit can join or split blocks), and restyles those lines. Edits that can affect far-away text fall back to a full parse: code fences, which open or close everything after them, and link definitions (`[x]: url`). A full parse also runs half a second after typing stops, restyling any line that differs. A randomized test checks that the incremental result always matches a full parse.

In a 10,000-word document, a keystroke costs about 2 ms in a Debug build, against about 30 ms for re-parsing everything.

### Source view

View → Show Markdown Source (⌘/) switches the selected tab to plain JetBrains Mono with no styling. Each tab keeps its own setting.

## Theme

Color tokens are light/dark pairs in `Assets.xcassets`, collected in `Editor/Theme.swift`. Theme loads them by name rather than through Xcode's generated symbols, because those can only be used on the main thread, and TextKit 2 may draw on other threads. SwiftUI views use the generated symbols (`Color(.ink)`).

Fonts are bundled (`Resources/Fonts`) and registered for the app at launch (`Fonts.register()`). Literata (the page) and JetBrains Mono (code and source view) are variable fonts: weights and Literata's optical size come from their axes. Small headings use SF in small capitals, so the text itself isn't changed.

The page is drawn by `ZephTextView.drawBackground(in:)`: a centered page on the desk, at most 720 pt wide, with 72 pt of padding. The padding and the desk margins shrink in narrow windows.
