# Flow

Flow is a voice dictation app that captures audio, transcribes speech, and formats it into clean text. It supports shortcuts, learning, and tone that adapts per app.



## Product

- Dictation with app-aware formatting
- Voice shortcuts and learned corrections
- Usage stats and configurable providers

## Tech stack

- Rust core engine in `flowwispr-core/`
- FFI bridge for native app integration (C ABI in `flowwispr-core/src/ffi.rs`)
- Provider abstraction for transcription and completion
- SQLite-backed storage for user data and stats

The rest of the app lives here in the repo root.

## Setup

```sh
git clone https://github.com/JasonLovesDoggo/flow.git
cd flow
cd flowwispr-core
cargo build
cd ..
swift run
```
