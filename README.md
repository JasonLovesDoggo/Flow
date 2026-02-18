<div align="center">
  <img src="https://raw.githubusercontent.com/JasonLovesDoggo/Flow/main/Sources/FlowApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png" width="96" />
  <h1>Flow</h1>
  <p>Voice dictation that actually learns. Free and open source.</p>
  <a href="https://github.com/JasonLovesDoggo/Flow/releases/latest/download/Flow-macOS-universal.dmg"><b>Download for Mac →</b></a>
</div>

---

Hold `Fn`. Talk. Let go. Text appears wherever your cursor is.

That's it. No subscription. No server. Your audio goes to your API key, not ours.

## What makes it different

Most dictation tools transcribe. Flow gets smarter the longer you use it.

- **Learns your corrections** - fix a word once, it remembers forever
- **Local Whisper** - fully offline, no API needed (Metal-accelerated)
- **App-aware tone** - formal in Mail, casual in iMessage, code-friendly in VS Code
- **Contact-aware tone** - knows you text your dad differently than your friends; add a contact and it adjusts automatically
- **Voice shortcuts** - say "my email", get `flow@jasoncameron.dev`

## Setup

Grab the [DMG](https://github.com/JasonLovesDoggo/Flow/releases/latest/download/Flow-macOS-universal.dmg) or build from source:

```sh
git clone https://github.com/JasonLovesDoggo/Flow
cd Flow
cd flow-core && cargo build --release && cd ..
swift run Flow
```

Needs: macOS 14+, Rust toolchain, an OpenAI key (or go local, no key needed).

## Stack

Rust core ([`flow-core/`](flow-core/)) handles audio, transcription, learning, shortcuts, and storage. Swift wraps it for the native Mac experience. C FFI bridges the two.

## Contributing

```sh
cd flow-core && cargo fmt && cargo clippy --all --tests --all-features
cargo test
```

MIT licensed.
