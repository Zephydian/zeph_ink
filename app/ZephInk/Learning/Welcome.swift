import AppKit
import SwiftUI

/// The welcome window, shown the first time Zeph#Ink opens (Help → Welcome to Zeph#Ink shows it
/// again): what a markdown editor is, what it can't do, and a way into the markdown guide. After a big
/// update (the first two version numbers change) it shows once more with what's new, when there are
/// notes for that version.
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()
    static let hasBeenShownKey = "hasSeenWelcome"
    /// The version (major.minor) the welcome or its "What's new" was last shown for.
    static let versionKey = "welcomedVersion"

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Zeph#Ink"
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func show(whatsNew: [String]? = nil) {
        shared.window?.contentViewController = NSHostingController(rootView: WelcomeView(whatsNew: whatsNew, version: featureVersion))
        shared.window?.setContentSize(NSSize(width: 560, height: 460))
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
    }

    enum Showing: Equatable {
        case welcome
        case whatsNew([String])
    }

    /// What to show at launch: the welcome the first time, "What's new" after a big update with notes,
    /// or nothing.
    static func showing(hasSeen: Bool, lastVersion: String?, current: String, notes: [String: [String]]) -> Showing? {
        guard hasSeen else { return .welcome }
        guard let lastVersion, lastVersion != current, let new = notes[current] else { return nil }
        return .whatsNew(new)
    }

    /// At launch: the welcome the first time, "What's new" after a big update.
    static func showAtLaunch() {
        guard !Session.isRunningTests else { return }
        let defaults = UserDefaults.standard
        let showing = showing(hasSeen: defaults.bool(forKey: hasBeenShownKey), lastVersion: defaults.string(forKey: versionKey),
                              current: featureVersion, notes: WhatsNew.notes)
        defaults.set(true, forKey: hasBeenShownKey)
        defaults.set(featureVersion, forKey: versionKey)
        switch showing {
        case .welcome: show()
        case .whatsNew(let notes): show(whatsNew: notes)
        case nil: break
        }
    }

    /// The version's first two numbers (`1.2` for 1.2.3): a change there is a big update.
    static var featureVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return version.split(separator: ".").prefix(2).joined(separator: ".")
    }
}

/// What a big update brings, by feature version (`1.1`), a few short lines each. A version with no
/// notes doesn't show the welcome again.
enum WhatsNew {
    static let notes: [String: [String]] = [:]
}

struct WelcomeView: View {
    /// After a big update: what's new, shown in place of the introduction.
    var whatsNew: [String]?
    var version = ""

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text(whatsNew == nil ? "Welcome to Zeph#Ink" : "What's new in Zeph#Ink \(version)")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 10)
            Text("A markdown editor and viewer, by Zephydian.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                if let whatsNew {
                    ForEach(whatsNew, id: \.self) { line in
                        point("sparkles", .accentColor, line, nil)
                    }
                } else {
                    point("doc.text", .green, "Your writing stays plain text.",
                          "Files are .md or .txt, so they open in any app, on any computer, years from now.")
                    point("textformat", .green, "Write with buttons, or type markdown.",
                          "The toolbar and shortcuts add markdown like **bold** and ## Heading for you, and the symbols hide as you write.")
                    point("exclamationmark.circle", .orange, "Markdown has its limits.",
                          "No fonts, colors or page layout, and Zeph#Ink doesn't open Word files. Centered and right-aligned text is saved as HTML, which some apps ignore.")
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 44)

            Spacer(minLength: 20)

            HStack(spacing: 10) {
                Button("Learn Markdown") {
                    WelcomeWindowController.shared.close()
                    MarkdownGuideWindowController.show()
                }
                .controlSize(.large)
                Button(whatsNew == nil ? "Start Writing" : "Continue") {
                    WelcomeWindowController.shared.close()
                    WorkspaceWindowController.bringForward()
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
            Text("You can open this again from the Help menu.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 10)
        }
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 560, height: 460)
    }

    private func point(_ symbol: String, _ color: Color, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
