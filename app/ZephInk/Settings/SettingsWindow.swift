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
    @AppStorage(Preferences.Key.whitePage) private var whitePage = false
    @AppStorage(Preferences.Key.textSize) private var textSize = 12.0
    @AppStorage(Preferences.Key.accent) private var accent = Preferences.Accent.system.rawValue
    @AppStorage(Preferences.Key.margins) private var margins = Preferences.Margins.normal.rawValue
    @AppStorage(MarkdownSymbols.key) private var symbols = MarkdownSymbols.clean.rawValue
    @AppStorage(Preferences.Key.defaultType) private var defaultType = Preferences.DocumentType.markdown.rawValue
    @AppStorage(Preferences.Key.pageStyle) private var pageStyle = Preferences.PageStyle.continuous.rawValue
    @AppStorage(Preferences.Key.paperSize) private var paperSize = Preferences.PaperSize.automatic.rawValue
    @AppStorage(Preferences.Key.pageNumbers) private var pageNumbers = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    ForEach(Preferences.Theme.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                Toggle("White page", isOn: $whitePage)
                    .disabled(!(Preferences.Theme(rawValue: theme)?.hasWhitePageOption ?? true))
                    .help("Keeps the page white, like paper, in Sepia, Dark and Midnight. In System, when the Mac is dark.")
                LabeledContent("Accent color") {
                    AccentPicker(selection: $accent)
                }
            }
            Section("Page") {
                Picker("Body text size", selection: $textSize) {
                    ForEach(Preferences.textSizes, id: \.self) { size in
                        Text(size.formatted() + " pt").tag(Double(size))
                    }
                }
                Picker("Page style", selection: $pageStyle) {
                    ForEach(Preferences.PageStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                switch Preferences.PageStyle(rawValue: pageStyle) ?? .continuous {
                case .continuous:
                    Text("One page that grows as you write, with no page breaks.").font(.caption).foregroundStyle(.secondary)
                case .paper:
                    Picker("Paper size", selection: $paperSize) {
                        ForEach(Preferences.PaperSize.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Text("Pages with breaks between them, like a printed document. Automatic uses your region's paper.")
                        .font(.caption).foregroundStyle(.secondary)
                case .square:
                    Text("Square pages with breaks between them.").font(.caption).foregroundStyle(.secondary)
                case .custom:
                    CustomPageSize()
                }
                Picker("Margins", selection: $margins) {
                    ForEach(Preferences.Margins.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
            Section("PDF") {
                Picker("PDF page size", selection: $paperSize) {
                    ForEach(Preferences.PaperSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Page numbers", isOn: $pageNumbers)
                Text("File → Export as PDF uses this paper and the margins above, on a white page with markdown symbols hidden.")
                    .font(.caption).foregroundStyle(.secondary)
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
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Width and height for the Custom Size page style, in inches or centimeters (the region's default).
private struct CustomPageSize: View {
    @AppStorage(Preferences.Key.customPageWidth) private var width = 432.0
    @AppStorage(Preferences.Key.customPageHeight) private var height = 648.0
    @State private var usesCentimeters = Locale.current.measurementSystem != .us

    /// Points in one unit.
    private var unit: Double { usesCentimeters ? 72 / 2.54 : 72 }

    var body: some View {
        LabeledContent("Size") {
            HStack(spacing: 6) {
                field($width)
                Text("×").foregroundStyle(.secondary)
                field($height)
                Picker("", selection: $usesCentimeters) {
                    Text("in").tag(false)
                    Text("cm").tag(true)
                }
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    /// A size in the chosen unit, stored in points (2 to 40 inches).
    private func field(_ points: Binding<Double>) -> some View {
        TextField("", value: Binding(get: { (points.wrappedValue / unit * 100).rounded() / 100 },
                                     set: { points.wrappedValue = min(max($0 * unit, 144), 2880) }),
                  format: .number.precision(.fractionLength(0...2)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
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
