# Architecture

How Zeph#Ink's window, documents and editor fit together.

## App shell: AppKit, with SwiftUI views

`App/ZephInkApp.swift` starts a plain `NSApplication` with a menu bar built in code (`App/MainMenu.swift`), not a SwiftUI `App`:

- SwiftUI's document scenes (`DocumentGroup`) give every document its own window, while Zeph#Ink keeps documents as tabs in one window, side by side.
- AppKit's document menu items (Open Recent, Revert to Saved, Browse All Versions, Rename, Move To) work only in a main menu AppKit can see and fill in.

Everything inside the window (tab bar, and later the toolbar, status bar and settings) is SwiftUI.

## Documents: `NSDocument`, without windows of their own

`MarkdownDocument` is an `NSDocument`, so macOS provides autosave in place, Versions, crash recovery, the "Edited" state, Open Recent and file coordination. The same class opens `.md`/`.markdown` files and `.txt` files (`isPlainText`, from the document's type). `NSDocumentController` opens and creates documents and stops a file from being opened twice. It's subclassed (`DocumentController`) for one change: quitting never asks "Do you want to save?". Every changed document is autosaved instead, untitled ones into the app's container, and comes back at the next launch (see Session).

A document doesn't make a window:

| `NSDocument` hook | What Zeph#Ink does |
| --- | --- |
| `makeWindowControllers()` | Adds the document as a tab to the frontmost workspace (`WorkspaceWindowController.forNewDocument()`), or a new one. |
| `showWindows()` | Selects its tab and brings the window forward (also when you open a file that's already open). |
| `windowForSheet` | The workspace window, so Save and "Do you want to save" sheets attach to it. |
| `close()` | Removes its tab. The window closes after its last tab. |

The document isn't in the workspace window controller's `windowControllers`. Instead, the controller sets its own `document` to the **selected tab's** document. That puts the document in the responder chain (so Save, Duplicate and Revert act on the tab you're in), and the window's `windowWillReturnUndoManager` returns that document's undo manager (so typing marks the right document as edited).

Closing a tab calls `canClose(withDelegate:…)` first, which asks about unsaved changes when macOS needs to. The window's close button closes the tabs one at a time the same way, and stops if you cancel.

**Changes made by other apps.** AppKit tells every open document when its file changes (`presentedItemDidChange`), but only reloads documents that have windows of their own. `MarkdownDocument` does it itself:

- A document without unsaved changes reloads quietly.
- A document with changes asks: Keep My Version or Reload.

## The text is the file

Each document owns an `NSTextStorage`. Its editor's TextKit 2 text view (`NSTextContentStorage` → `NSTextLayoutManager` → `NSTextContainer` → `ZephTextView`) edits that storage directly, and `data(ofType:)` writes its string back as UTF-8.

The document keeps the bytes it last read or wrote. If the text hasn't changed, saving writes those exact bytes. `ZephInkTests` checks this with the files in `Fixtures/`.

`FileText` records how a file stores its text: its encoding, its byte order mark and its line breaks.

- **Reading:** a byte order mark decides the encoding (UTF-8 or UTF-16). Without one, the file is read as UTF-8 if it's valid UTF-8, otherwise as Windows Latin 1, then Mac Roman.
- **Saving an edit:** the same encoding, mark and line breaks. Text the encoding can't hold (an emoji in a Latin 1 file) switches the file to UTF-8 rather than losing characters.
- **Typing and pasting:** Return, Shift-Return and pasted text all use the file's own line break (`\r\n`, `\r` or `\n`).

## `.txt` files

A `.txt` file shows as plain JetBrains Mono, with no styling, no list or checkbox handling and no source view. File → Convert to Markdown saves `name.md` next to `name.txt` and opens it in the same tab and pane. The `.txt` is never changed. The sandbox allows writing the copy because markdown is declared a related type (`NSIsRelatedItemType`), and the write is coordinated through a file presenter whose primary item is the `.txt`. That presenter stays registered while the converted document is open, because the access ends when it's removed. If a `name.md` already exists, or the folder can't be written, a save panel asks where to put the copy.

## Workspace

- **`Workspace`** (`@Observable`, no AppKit) holds the tabs in order and the panes: up to three, side by side, each showing a different tab. The focused pane is the one you type in, and its tab is the selected one. Each `Tab` pairs a document with its `Editor`. The rules are in its methods and tested in `WorkspaceTests`:
  - Choosing a tab that's already in a pane focuses that pane; otherwise the tab shows in the focused pane.
  - Split Right shows the next tab that isn't on screen, or a new document when every tab is showing.
  - Closing a pane keeps its tab. Closing a tab shown in a split closes its pane.
  - A fourth pane is refused with a notice.
- **`Editor`** is one document's text view and scroll view. It lives as long as the tab, even when the tab moves to another window, so the selection, scroll position, undo history and page/source setting go with it.
- **`PaneSplitView`** (an `NSSplitView`) holds one `PaneContainer` per pane:
  - The focused pane gets a thin accent line along its top while the window is split.
  - A tab dragged over a pane tints the half it would open beside.
  - Double-clicking a divider makes the panes equal.
  - Pane widths are applied in `layout()`, once the split view knows its size.
- **`WorkspaceWindowController`** is the window (full-size content, transparent title bar, tab bar beside the window buttons) and the glue above. It watches the workspace to keep the window's document, title, edited dot and focus in step with the focused pane, and saves the session shortly after anything changes. ⌘W closes the focused pane when the window is split, otherwise the tab.
- **`TabBar`** shows the tabs and the + button. Its empty space drags the window, and double-clicking it zooms (following the Desktop & Dock setting). Tabs are dragged with a SwiftUI `DragGesture`:
  - Along the bar, a tab reorders live.
  - Pulled below the bar, it hands over to the controller, which uses the pointer's screen position. Dropped on a pane (in this window or another), it opens beside it. Dropped on another window, it moves there. Dropped anywhere else, it gets a window of its own.

Native window tabs are turned off (`tabbingMode = .disallowed`): they can't show documents side by side.

## Session

`Session` records every window: its frame, its tabs, which tabs its panes show, the pane widths, and each tab's page/source setting.

- **When it's saved:** a second after any change. When quitting is confirmed, it's saved one last time and frozen, because the windows closing on the way out would otherwise save an empty session.
- **How documents are remembered:** saved files by security-scoped bookmark (the `files.bookmarks.app-scope` entitlement). Untitled documents by their autosave, which stays in the app's container.
- **At launch:** `AppDelegate` reopens the session before any file the app was asked to open, and skips the new untitled document when something came back. A restored file keeps its security scope until its document closes.

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

## Formatting: toolbar, Format menu, shortcuts

Every formatting action only inserts or removes markdown characters:

- **`MarkdownCommands`** (`Editor/Commands.swift`, no AppKit) works out each action as edits plus the selection afterwards: toggling bold, italic, strikethrough and inline code, setting a paragraph style, toggling lists, inserting a divider or image on its own line, and writing a link. `CommandsTests` covers them with marked-up before/after text.
- **`ZephTextView+Formatting`** has an `@objc` action for each, applying the edits as one undoable change (`shouldChangeText(inRanges:…)`). The Format menu's items target the first responder, so they reach the focused text view, and `validateMenuItem` ticks the styles that are on and turns everything off in `.txt` files.
- **`FormattingState`** (`@Observable`, one per editor) holds what's on at the selection: paragraph style, inline styles, list kind, whether it's in a link, and page/source. The editor updates it on every selection change.
- **`Toolbar`** (SwiftUI, under the tabs) calls the same actions on the focused editor and reads its `FormattingState`. View → Hide Toolbar (⌘⌥T) stores `showsToolbar` in the defaults.

**Highlight** (`==text==`) isn't standard markdown, so swift-markdown leaves it as text. `MarkdownAnalysis` finds it with a pattern on text lines, outside code spans, and adds the same spans and markers as for bold. **Clear Formatting** removes the selected lines' block markers and every inline marker inside the selection.

**Alignment.** Markdown has no alignment, so center and right are saved as HTML around the paragraph, in the form GitHub renders: `<div align="center">`, a blank line, the paragraph, a blank line, `</div>`.

- `MarkdownAnalysis` marks the tag lines (`.alignTag`, symbols that hide in Clean mode, along with the blank lines inside) and gives the lines between them their alignment.
- Editing inside an aligned region always re-parses the whole text, because the tags may be outside the edited blocks.
- Align Left removes the wrapper. Format → Align Left / Center / Align Right (⌘{ ⌘| ⌘}) override NSText's own alignment actions to write this markdown.

**Return inside a style** (`*hel|lo*`): `MarkdownCommands.closeInlineStyles` closes the styles at the cursor before the line break, so the new line starts plain. swift-markdown reports one range for directly nested styles (`***both***`), so bold, italic and strikethrough take their ranges from their delimiter characters, and a nested style takes its parent's inside.

**Links.** ⌘K opens a popover (`LinkEditor`) to add a link, or to change the one the cursor is in. ⌘-click opens a link with a scheme in its app.

**Images.** Format → Image… or dropping image files onto a markdown document copies them into an `assets` folder next to the document and inserts `![name](assets/name.png)` on its own line. A name that's taken gets a number.

- The sandbox only gives the app the documents themselves. `FolderAccess` asks once per folder, with an Open panel already showing it, and remembers the answer with a security-scoped bookmark. This settles the plan's open question: the first image in a folder asks.
- An untitled document is saved first.
- An image alone on its line shows below that line, scaled to the column (never up). In Clean mode it stands in for its markdown. `ImageLoader` reads and caches images relative to the document's folder.
- Web images aren't loaded: the app stays offline.
- An image in a folder not yet allowed shows a dashed "Click to show images from this folder" box.

## Theme

Color tokens are light/dark pairs in `Assets.xcassets`, collected in `Editor/Theme.swift`. Theme loads them by name rather than through Xcode's generated symbols, because those can only be used on the main thread, and TextKit 2 may draw on other threads. SwiftUI views use the generated symbols (`Color(.ink)`).

Fonts are bundled (`Resources/Fonts`) and registered for the app at launch (`Fonts.register()`). Literata (the page) and JetBrains Mono (code and source view) are variable fonts: weights and Literata's optical size come from their axes. Small headings use SF in small capitals, so the text itself isn't changed.

The page is drawn by `ZephTextView.drawBackground(in:)`: a centered page on the desk, at most 720 pt wide, with 72 pt of padding. The padding and the desk margins shrink in narrow windows.
