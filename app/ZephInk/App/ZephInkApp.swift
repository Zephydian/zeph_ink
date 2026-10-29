import AppKit

/// Zeph#Ink starts here.
///
/// The app shell is AppKit rather than a SwiftUI `App`: every document is a tab in one workspace window,
/// which SwiftUI's document scenes can't do, and AppKit's own File menu (Open Recent, Revert To, Browse
/// All Versions) works only with a main menu it can see. The views inside the window are SwiftUI.
@main
enum ZephInkApp {
    static func main() {
        Fonts.register()
        let app = NSApplication.shared
        _ = DocumentController()   // the first document controller made becomes the shared one
        let delegate = AppDelegate()
        app.delegate = delegate
        app.mainMenu = MainMenu.make()
        withExtendedLifetime(delegate) { app.run() }   // the app holds its delegate weakly
    }
}
