import AppKit

/// Builds the menu bar. Items with no target go to the first responder, so AppKit's own document and
/// text actions (Save, Revert, Undo, Find…) reach the document and text view of the tab you're in.
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(appMenu()))
        menu.addItem(submenu(fileMenu()))
        menu.addItem(submenu(editMenu()))
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
            ("Use Selection for Find", .setSearchString, "e", [.command]),
        ]
        for (title, action, key, modifiers) in actions {
            let entry = item(title, #selector(NSTextView.performTextFinderAction(_:)), key, modifiers)
            entry.tag = action.rawValue
            menu.addItem(entry)
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Show Markdown Source", #selector(WorkspaceWindowController.toggleSourceView(_:)), "/"))
        let symbols = NSMenu(title: "Markdown Symbols")
        for (title, value) in [("Clean", MarkdownSymbols.clean), ("Faded", MarkdownSymbols.faded)] {
            let entry = item(title, #selector(AppDelegate.setMarkdownSymbols(_:)))
            entry.representedObject = value.rawValue
            symbols.addItem(entry)
        }
        menu.addItem(submenu(symbols))
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
