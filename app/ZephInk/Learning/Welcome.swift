import AppKit
import SwiftUI

/// The welcome window, shown the first time Zeph#Ink opens (Help → Welcome to Zeph#Ink shows it
/// again): what a markdown editor is, what it can't do, and a way into the markdown guide.
final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()
    static let hasBeenShownKey = "hasSeenWelcome"

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.title = "Welcome to Zeph#Ink"
        window.contentViewController = NSHostingController(rootView: WelcomeView())
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func show() {
        shared.showWindow(nil)
        shared.window?.makeKeyAndOrderFront(nil)
    }

    /// At launch: the first time only.
    static func showIfFirstLaunch() {
        guard !Session.isRunningTests, !UserDefaults.standard.bool(forKey: hasBeenShownKey) else { return }
        UserDefaults.standard.set(true, forKey: hasBeenShownKey)
        show()
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Welcome to Zeph#Ink")
                .font(.system(size: 24, weight: .semibold))
                .padding(.top, 10)
            Text("A markdown editor and viewer, by Zephydian.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 14) {
                point("doc.text", .green, "Your writing stays plain text.",
                      "Files are .md or .txt, so they open in any app, on any computer, years from now.")
                point("textformat", .green, "Write with buttons, or type markdown.",
                      "The toolbar and shortcuts add markdown like **bold** and ## Heading for you, and the symbols hide as you write.")
                point("exclamationmark.circle", .orange, "Markdown has its limits.",
                      "No fonts, colors or page layout, and Zeph#Ink doesn't open Word files. Centered and right-aligned text is saved as HTML, which some apps ignore.")
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
                Button("Start Writing") {
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

    private func point(_ symbol: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
