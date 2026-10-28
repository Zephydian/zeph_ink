import AppKit
import SwiftUI

/// Zeph#Ink → Settings… (⌘,): a small window with every setting. Changes apply at once.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                              styleMask: [.titled, .closable], backing: .buffered, defer: true)
        window.title = "Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView())
        window.center()
        window.setFrameAutosaveName("Settings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

private struct SettingsView: View {
    @AppStorage(Preferences.Key.theme) private var theme = Preferences.Theme.system.rawValue
    @AppStorage(Preferences.Key.accent) private var accent = Preferences.Accent.system.rawValue
    @AppStorage(Preferences.Key.margins) private var margins = Preferences.Margins.normal.rawValue
    @AppStorage(MarkdownSymbols.key) private var symbols = MarkdownSymbols.clean.rawValue
    @AppStorage(Preferences.Key.defaultType) private var defaultType = Preferences.DocumentType.markdown.rawValue

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(Preferences.Theme.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent color") {
                    AccentPicker(selection: $accent)
                }
            }
            Section("Page") {
                Picker("Margins", selection: $margins) {
                    ForEach(Preferences.Margins.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section("Writing") {
                Picker("Markdown symbols", selection: $symbols) {
                    Text("Clean").tag(MarkdownSymbols.clean.rawValue)
                    Text("Faded").tag(MarkdownSymbols.faded.rawValue)
                }
                .pickerStyle(.segmented)
                Text(symbols == MarkdownSymbols.clean.rawValue
                     ? "Symbols like ** and ## hide, except on the line you're editing."
                     : "Symbols like ** and ## always show, dimmed.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("New documents", selection: $defaultType) {
                    ForEach(Preferences.DocumentType.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row of color swatches: the Mac's accent, Zephydian Ink, and the fixed colors.
private struct AccentPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Preferences.Accent.allCases) { accent in
                Button {
                    selection = accent.rawValue
                } label: {
                    ZStack {
                        if accent == .system {
                            Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                        } else {
                            Circle().fill(Color(nsColor: accent.color))
                        }
                        if selection == accent.rawValue {
                            Circle().fill(.white).frame(width: 6, height: 6)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12)))
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(accent.title)
                .accessibilityLabel(accent.title)
                .accessibilityAddTraits(selection == accent.rawValue ? .isSelected : [])
            }
        }
    }
}
