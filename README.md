<div align="center">

# Zeph#Ink

**A calm markdown editor for the Mac.** A free, open-source app by **Zephydian**: Word's familiarity without Word's weight. Beginners never have to learn markdown, and experts never have to leave it.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![Status: in development](https://img.shields.io/badge/status-in%20development-orange)

</div>

---

> Zeph#Ink is in early development. There's no release yet.

## What it will be

- **A page, a style menu and a few buttons.** Pick Title, Heading or Body, press **B** for bold, and Zeph#Ink writes clean, standard markdown for you.
- **The file is the truth.** What you see is a plain `.md` or `.txt` file that opens anywhere. No hidden formatting, no proprietary format, and a file you open and save without editing stays byte for byte the same.
- **Tabs and side by side.** Every document is a tab, and up to three can sit next to each other.
- **Never lose work.** Autosave, Versions and crash recovery come from macOS itself.
- **Learn as you go.** Optional tips show the markdown behind each button, then quietly retire.
- **Private.** Works fully offline. No accounts, no telemetry, no network access at all.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon or Intel Mac

## Building from source

1. Install **Xcode** (16 or later) from the Mac App Store, and [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
2. Clone this repo, then generate the Xcode project: `cd app && xcodegen`.
3. Open `app/ZephInk.xcodeproj` and press **⌘R**.

See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Contributing

Bug reports, ideas and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and our [Code of Conduct](CODE_OF_CONDUCT.md) first.

## License

Zeph#Ink is free software under the [MIT License](LICENSE) © 2026 ahmastan.

It reads markdown with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apache 2.0). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
