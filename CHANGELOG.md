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
