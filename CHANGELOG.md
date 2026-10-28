# Changelog

All notable changes to Zeph#Ink are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The app: documents open as tabs in one window, with autosave, Versions and crash recovery from macOS.
- Markdown styles as you type, on a centered page: headings, bold, italic, strikethrough, code, code blocks, quotes, lists, checklists, links and dividers. The file stays plain markdown.
- Markdown symbols hide except on the line you're editing (View → Markdown Symbols → Clean), or always show faded (Faded).
- View → Show Markdown Source (⌘/) shows the raw file in a monospaced font.
- Lists continue when you press Return, and Return on an empty item ends the list. Tab and Shift-Tab nest list items. Click a checkbox to tick it.
- Literata and JetBrains Mono are bundled, with light and dark themes.
- Up to three documents side by side: View → Split Right (`⌘\`), or drag a tab onto the left or right half of an editor. Drag the dividers to resize, double-click one to even them out, and move between panes with ⌘⌥← and ⌘⌥→.
- Drag tabs to reorder them, onto another window to move them, or out of the window to give them their own.
- Open windows, tabs and splits come back when you reopen Zeph#Ink, untitled documents included. Quitting never asks you to save.
- `.txt` files open as plain text. File → Convert to Markdown saves a `.md` copy next to the `.txt` (which stays as it was) and opens it.
- Files keep their encoding (UTF-8, UTF-16, Windows Latin 1, Mac Roman) and line breaks. Return and paste use the file's own line breaks.
- When another app changes an open file, Zeph#Ink reloads it, or asks first if you have unsaved changes.
- A one-row toolbar: paragraph styles, bold, italic, strikethrough, inline code, link, lists, checklist, quote, divider, image, and the MD switch. Buttons light up for the styles at the cursor, and each tooltip shows its shortcut and markdown. View → Hide Toolbar (⌘⌥T) hides it.
- A Format menu with every style and its shortcut: Title to Small Heading (⌘1–⌘4), Body (⌘0), Quote (⌘⇧.), Bold (⌘B), Italic (⌘I), Strikethrough (⌘⇧X), Inline Code (⌘E), Link (⌘K), lists (⌘⇧8, ⌘⇧7, ⌘⇧9), Divider and Image.
- Links: ⌘K adds or edits a link in a small popover, and ⌘-click opens one.
- Images: add them from the toolbar or by dropping them on the page. They're copied into an "assets" folder next to the document and shown on the page. Zeph#Ink asks once per folder for permission.
- In `.txt` files, the formatting tools are dimmed and a Convert to Markdown button appears.
- Highlight (`==text==`, ⌘⇧H), Clear Formatting, and toolbar buttons for undo, redo and the emoji picker.
- Align lines left, center or right (⌘{ ⌘| ⌘}), each line on its own. Markdown has no alignment, so center and right are saved as `<div align="center">` around the lines, which GitHub and many apps show centered.
- Pressing Return inside bold, italic or other styles closes them, so the new line starts plain.
- Pressing Return on an empty line at the end of centered or right-aligned text steps out of it, so the next line starts on the left.
- A status bar: words and reading time (or the selection's words), characters on hover, and whether the document is saved.
- Word-count goals: click the word count to set one, and a small ring fills as you write.
- Focus Mode (View, ⌘⇧F) fades everything but the paragraph you're writing and hides the toolbar. Typewriter Mode keeps the line you're typing in the middle of the window. Synced Scrolling makes panes side by side scroll together.
- Page styles (Settings, or View → Page Style): Continuous (one page that grows), Paper (Letter or A4 pages with page breaks, like a printed document), Square, or Custom Size in inches or centimeters.
- Themes: Light, Sepia (warm tan), Dark (neutral charcoal) and Midnight (deep blue), or System to follow the Mac. White Page keeps the page white in the darker themes.
- Pasting formatted text from a web page, Word, Google Docs or Pages turns it into markdown (headings, bold, italic, links, lists, quotes, code). Edit → Paste as Plain Text (⌘⇧V) pastes the words only.
- View → Bigger Text (⌘+), Smaller Text (⌘−) and Actual Size. Increase Contrast makes faded markdown symbols darker, and Reduce Motion turns off animations.
- Settings (⌘,): theme, accent color (the Mac's, Zephydian Ink, or a fixed color), margins (narrow, normal, wide; also under View → Margins), markdown symbols, and whether new documents are markdown or plain text.
