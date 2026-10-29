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

**Alignment.** Markdown has no alignment, so center and right are saved as HTML around the selected lines (lines typed with a single Return are one markdown paragraph, but align one by one), in the form GitHub renders: `<div align="center">`, a blank line, the paragraph, a blank line, `</div>`.

- `MarkdownAnalysis` marks the tag lines (`.alignTag`, symbols that hide in Clean mode, along with the blank lines inside) and gives the lines between them their alignment.
- Editing inside an aligned region always re-parses the whole text, because the tags may be outside the edited blocks.
- Changing some lines of an aligned block splits it, so the others keep their alignment. Align Left takes lines out of the wrapper. Format → Align Left / Center / Align Right (⌘{ ⌘| ⌘}) override NSText's own alignment actions to write this markdown.

**Return inside a style** (`*hel|lo*`): `MarkdownCommands.closeInlineStyles` closes the styles at the cursor before the line break, so the new line starts plain. swift-markdown reports one range for directly nested styles (`***both***`), so bold, italic and strikethrough take their ranges from their delimiter characters, and a nested style takes its parent's inside.

**Links.** ⌘K opens a popover (`LinkEditor`) to add a link, or to change the one the cursor is in. ⌘-click opens a link with a scheme in its app.

**Images.** Format → Image… or dropping image files onto a markdown document copies them into an `assets` folder next to the document and inserts `![name](assets/name.png)` on its own line. A name that's taken gets a number.

- The sandbox only gives the app the documents themselves. `FolderAccess` asks once per folder, with an Open panel already showing it, and remembers the answer with a security-scoped bookmark. This settles the plan's open question: the first image in a folder asks.
- An untitled document is saved first.
- An image alone on its line shows below that line, scaled to the column (never up). In Clean mode it stands in for its markdown. `ImageLoader` reads and caches images relative to the document's folder.
- Web images aren't loaded: the app stays offline.
- An image in a folder not yet allowed shows a dashed "Click to show images from this folder" box.

## Settings and the status bar

`Preferences` reads the settings from the user defaults. The Settings window (`SettingsWindowController`, SwiftUI) writes them with `@AppStorage`, and everything else follows `UserDefaults.didChangeNotification`:

- `AppDelegate` sets `NSApp.appearance` for the theme.
- Each editor compares a `Look` (accent, margins, Clean/Faded) and restyles or moves its text only when that changed.
- Accent colors are read live (`Theme.accent`), so fragments draw in the new color.
- `DocumentController.defaultType` picks markdown or plain text for new documents.

`StatusBar` shows the focused pane's `DocumentStats`:

- Words are counted the way macOS splits text into words, so markdown symbols and link addresses don't count. The count runs a quarter second after typing pauses, and again for the selection.
- Word-count goals are kept per file path in the defaults (`WordGoals`), never in the file.

## Front matter, outline, search and Quick Open

- **Front matter.** A YAML block at the top of a file (a `---` line, then lines up to the next `---` or `...`) isn't markdown. `MarkdownAnalysis` finds it first and gives the parser empty lines in its place, so the closing `---` can't turn the YAML into a heading, and the lines after it keep their numbers. Its lines become `.frontMatter` and draw as a card: keys in bold, a "Document info" header in place of the opening `---`. Clicking the header folds the card. Edits near the top always re-parse the whole text.
- **Sidebar** (`Workspace.sidebar`) sits beside the panes, in two modes:
  - **Outline** lists each editor's `Outline`, the headings from its analysis without their symbols. It refreshes a moment after typing and follows the cursor's heading. Clicking one calls `Editor.reveal`.
  - **Search** (`DocumentSearch`) looks through every open document in every window as you type (case- and accent-insensitive, up to 200 matches per document). Clicking a match brings its window and tab forward and selects it.
- **Quick Open** is a sheet listing open documents and `NSDocumentController.recentDocumentURLs`, ranked by a fuzzy match. A name's letters must appear in order, and matches at the start of a word or in a row score higher.

## Focus, typewriter and synced scrolling

These are switches in the defaults, toggled from the View menu, and each editor follows them:

- **Focus Mode** fades every block but the one with the cursor. It uses TextKit 2 rendering attributes (`setRenderingAttributes`), which change how text is drawn, not the text or its styling. The toolbar hides.
- **Typewriter Mode** gives the scroll view half a window of content inset at the top and bottom, and scrolls the cursor's line to the middle after each selection change.
- **Synced Scrolling** has the window controller watch each pane's clip view, delivered at once (not queued), and scroll the other panes to the same fraction of their documents. Positions are as exact as TextKit 2's height estimates for text that isn't laid out yet.

## Theme

`Theme` holds four palettes: Light, Sepia, Dark (neutral charcoal) and Midnight (deep blue). System picks Light or Dark from the Mac. Every color is an `NSColor(name:dynamicProvider:)` that looks up the theme when it's drawn, so a theme change only needs a redraw: editors restyle (which redraws TextKit's fragments) and the SwiftUI views take a new identity.

- **Chrome colors** (`chrome`, `chromeInk`, `chromeLine`, `chromeSurface`, `hover`, `desk`) always follow the theme.
- **Page colors** (`page`, `ink`, `marker`, `rule`, `codeBackground`, `highlight`, `pageAccent`) follow it too, unless White Page keeps the page light in a darker theme.
- `pageAccent` is the accent resolved in light mode on a white page.
- `NSApp.appearance` is light for Light and Sepia and dark for Dark and Midnight, so standard controls match.

Increase Contrast swaps faded symbols for the secondary ink.

## Text size

`Preferences.textSize` is the body text size (12 points by default). The toolbar's size box, Format → Bigger Text / Smaller Text and Settings all set it. Markdown can't store sizes, so it's one size for every document.

- `Theme.bodySize` reads it, and sizes body text, lists, quotes, code (`sourceSize`), line heights, list indents and checkboxes.
- Headings use a fixed `Theme.headingBase` (12), so titles and headings stay the same size.
- The Continuous page is 51 times the body size wide (612 points at 12 pt), so lines stay a comfortable length. Paper, Square and Custom pages keep their real sizes.
- When the document has body text, `BodyTextSize` asks before changing the size (with "Don't ask again").

Zoom magnifies on top of this.

## Zoom

Zoom is the scroll view's magnification (`allowsMagnification`), from 50% to 300%. One setting (`Preferences.zoom`) applies to every editor: the status bar's control, View → Zoom In and Zoom Out, and pinches (written back when the pinch ends) all set it. Magnifying changes the clip view's bounds, not its frame, so the editor keeps the text view as wide as the clip view's bounds. The page is then laid out in page points for what's shown, and stays centered. Fit Page Width picks the zoom at which the page and its desk fill the focused pane.

## Smart paste

`RichPaste` turns the clipboard's HTML (or RTF, through HTML) into markdown by walking the tidied HTML: headings, bold, italic, strikethrough (including Google Docs' styled spans), code, links, lists, quotes, code blocks and dividers. When it finds nothing markdown can keep (a code editor's colored spans), the plain text is pasted instead. ⌘⇧V always pastes plain text.

Fonts are bundled (`Resources/Fonts`) and registered for the app at launch (`Fonts.register()`). Literata (the page) and JetBrains Mono (code and source view) are variable fonts: weights and Literata's optical size come from their axes. Small headings use SF in small capitals, so the text itself isn't changed.

## Pages

`PageGeometry` works out the pages for the current page style and the editor's width. `ZephTextView` draws them in `drawBackground(in:)`, and puts the text inside them with `textContainerInset`.

- **Continuous** is one page up to 720 pt wide, at least as tall as the window, with no breaks.
- **Paper** (Letter or A4; Automatic follows the region), **Square** (720 pt) and **Custom Size** are pages of that size in points, one under another, 24 pt apart. Margins apply on all four sides.
- A page wider than the window gets narrower; its height stays.

**Page breaks.** Text flows from page to page through exclusion paths. Each page break is a band in the text container covering the bottom margin, the gap and the next page's top margin, so TextKit 2 places no line there. A long paragraph splits across the break like in a word processor.

- **How many bands:** there's one band for each page the text reaches. The count comes from `usageBoundsForTextContainer`, and is checked again when the text's length or the view's size changes.
- **Relayout:** TextKit 2 keeps lines it already placed, so after the bands change, the layout is invalidated from the first band that changed.

The padding and desk margins shrink in narrow windows.
