# Contributing to Zeph#Ink

Thanks for your interest! Zeph#Ink is a free, open-source markdown editor for the Mac. Contributions of any size are welcome, from typo fixes to new features.

## Ground rules

- Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).
- **The file is the truth.** The editor's text *is* the markdown. Never rewrite text the person didn't change: opening and saving a file without editing it must leave it byte for byte the same.
- **Every feature earns its place.** Keep the interface minimal. When unsure whether to add a button, option or setting, open an issue first.
- **Native first.** If AppKit or SwiftUI already does it (documents, tabs, find, spell check, printing), use that.
- **Offline, always.** No network access, telemetry or update checks.
- **Dependencies:** swift-markdown is the only one. Copying code is allowed only from MIT, Apache 2.0 or BSD projects (never GPL, LGPL or AGPL), keeping its copyright and license notice at the top of the file and in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- Open an issue before starting a large change, so we can agree on the approach first.

## Development setup

1. macOS 14 Sonoma or later, **Xcode 16+** (free on the Mac App Store), and **XcodeGen** (`brew install xcodegen`).
2. Fork the repo and clone your fork.
3. Generate the project with `cd app && xcodegen`, then open `app/ZephInk.xcodeproj` in Xcode.
   - The Xcode project is **generated from `app/project.yml`** and isn't committed. Change build settings in `project.yml`, never in Xcode's settings screens (those edits get overwritten). New `.swift` files inside `app/ZephInk/` are picked up automatically.
4. Select the **ZephInk** scheme and press **⌘R** to build and run, or **⌘U** to run the tests.
   - Signing is set to "Sign to Run Locally", so no Apple Developer account is needed.

## Project layout

```
app/
├── project.yml        Xcode project spec (XcodeGen), the source of truth for build settings
├── Config/            Info.plist and entitlements (generated from project.yml)
├── ZephInk/           All app source code (synced folder)
│   ├── App/           App entry point and the menu bar
│   ├── Document/      MarkdownDocument (NSDocument)
│   ├── Workspace/     The window: tab bar and editor panes
│   ├── Editor/        The text view, its styling, and the theme
│   └── Resources/     Assets (icon, colors)
└── ZephInkTests/      Unit tests, with markdown files in Fixtures/
docs/                  How the app is put together (architecture.md)
```

## Pull requests

1. Create a branch from `main` (`feature/word-count`, `fix/tab-close`, …).
2. Keep PRs focused, with one feature or fix each.
3. Make sure the app builds with **no warnings** (the project treats them as errors) and the tests pass.
4. Add a line under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
5. Fill out the PR template, and include a screenshot or GIF for UI changes.

## License of contributions

Zeph#Ink is licensed under the [MIT License](LICENSE). By sending a pull request, you agree that your contribution is shared under that license.

## Reporting bugs and suggesting ideas

Use the issue templates: **Bug report** or **Feature request**. For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.
