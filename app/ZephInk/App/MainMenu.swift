import AppKit

/// Builds the menu bar. Items with no target go to the first responder, so AppKit's own document and
/// text actions (Save, Revert, Undo, Find…) reach the document and text view of the tab you're in.
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
        menu.addItem(submenu(formatMenu()))
        menu.addItem(submenu(viewMenu()))
        let window = windowMenu()
        menu.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        menu.addItem(submenu(help))
        NSApp.helpMenu = help
        return menu
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Zeph#Ink")
        menu.addItem(item("About Zeph#Ink", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu(services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide Zeph#Ink", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Zeph#Ink", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("New Tab", #selector(NSDocumentController.newDocument(_:)), "t"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        // AppKit fills in this submenu because it holds the Clear Menu item.
        let recent = NSMenu(title: "Open Recent")
        recent.addItem(item("Clear Menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(WorkspaceWindowController.closeTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        menu.addItem(item("Save…", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Revert to Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(item("Browse All Versions…", #selector(NSDocument.browseVersions(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Convert to Markdown", #selector(WorkspaceWindowController.convertToMarkdown(_:))))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(submenu(findMenu()))
        return menu
    }

    /// The native find bar. Each item's tag is the `NSTextFinder.Action` it performs.
    private static func findMenu() -> NSMenu {
        let menu = NSMenu(title: "Find")
        let actions: [(String, NSTextFinder.Action, String, NSEvent.ModifierFlags)] = [
            ("Find…", .showFindInterface, "f", [.command]),
            ("Find and Replace…", .showReplaceInterface, "f", [.command, .option]),
            ("Find Next", .nextMatch, "g", [.command]),
            ("Find Previous", .previousMatch, "g", [.command, .shift]),
            ("Use Selection for Find", .setSearchString, "", [.command]),   // ⌘E is Inline Code
        ]
        for (title, action, key, modifiers) in actions {
            let entry = item(title, #selector(NSTextView.performTextFinderAction(_:)), key, modifiers)
            entry.tag = action.rawValue
            menu.addItem(entry)
        }
        return menu
    }

    /// Every formatting action, with the shortcuts the toolbar's tooltips show. They act on the text
    /// view that has the focus.
    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        let shiftCommand: NSEvent.ModifierFlags = [.command, .shift]
        menu.addItem(item("Title", #selector(ZephTextView.setTitleStyle(_:)), "1"))
        menu.addItem(item("Heading", #selector(ZephTextView.setHeadingStyle(_:)), "2"))
        menu.addItem(item("Subheading", #selector(ZephTextView.setSubheadingStyle(_:)), "3"))
        menu.addItem(item("Small Heading", #selector(ZephTextView.setSmallHeadingStyle(_:)), "4"))
        menu.addItem(item("Body", #selector(ZephTextView.setBodyStyle(_:)), "0"))
        menu.addItem(item("Quote", #selector(ZephTextView.toggleQuote(_:)), ".", shiftCommand))
        menu.addItem(item("Code Block", #selector(ZephTextView.toggleCodeBlock(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bold", #selector(ZephTextView.toggleBold(_:)), "b"))
        menu.addItem(item("Italic", #selector(ZephTextView.toggleItalic(_:)), "i"))
        menu.addItem(item("Strikethrough", #selector(ZephTextView.toggleStrikethrough(_:)), "x", shiftCommand))
        menu.addItem(item("Highlight", #selector(ZephTextView.toggleHighlight(_:)), "h", shiftCommand))
        menu.addItem(item("Inline Code", #selector(ZephTextView.toggleInlineCode(_:)), "e"))
        menu.addItem(item("Link…", #selector(ZephTextView.editLink(_:)), "k"))
        menu.addItem(item("Clear Formatting", #selector(ZephTextView.clearFormatting(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bulleted List", #selector(ZephTextView.toggleBulletedList(_:)), "8", shiftCommand))
        menu.addItem(item("Numbered List", #selector(ZephTextView.toggleNumberedList(_:)), "7", shiftCommand))
        menu.addItem(item("Checklist", #selector(ZephTextView.toggleChecklist(_:)), "9", shiftCommand))
        menu.addItem(item("Divider", #selector(ZephTextView.insertDivider(_:))))
        menu.addItem(item("Image…", #selector(ZephTextView.insertImage(_:))))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Hide Toolbar", #selector(AppDelegate.toggleToolbar(_:)), "t", [.command, .option]))
        menu.addItem(item("Show Markdown Source", #selector(WorkspaceWindowController.toggleSourceView(_:)), "/"))
        let symbols = NSMenu(title: "Markdown Symbols")
        for (title, value) in [("Clean", MarkdownSymbols.clean), ("Faded", MarkdownSymbols.faded)] {
            let entry = item(title, #selector(AppDelegate.setMarkdownSymbols(_:)))
            entry.representedObject = value.rawValue
            symbols.addItem(entry)
        }
        menu.addItem(submenu(symbols))
        menu.addItem(.separator())
        menu.addItem(item("Split Right", #selector(WorkspaceWindowController.splitRight(_:)), "\\"))
        menu.addItem(item("Close Split", #selector(WorkspaceWindowController.closeSplit(_:))))
        menu.addItem(item("Focus Left Pane", #selector(WorkspaceWindowController.focusPreviousPane(_:)),
                          String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option]))
        menu.addItem(item("Focus Right Pane", #selector(WorkspaceWindowController.focusNextPane(_:)),
                          String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Next Tab", #selector(WorkspaceWindowController.selectNextTab(_:)), "\t", [.control]))
        menu.addItem(item("Show Previous Tab", #selector(WorkspaceWindowController.selectPreviousTab(_:)), "\t", [.control, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func item(_ title: String, _ action: Selector, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
