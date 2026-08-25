# ChatterKey — AI Voice Typing for macOS

Hold **Fn**, speak naturally, and release. ChatterKey converts speech into polished text and inserts it into the focused macOS app.

> Bring your own API key. Audio is sent directly to the provider selected by the user; this project does not operate a transcription proxy or collect analytics.

## Website

Visit the ChatterKey product page: **https://imhimansu28.github.io/ChatterKey/**

## Features

### v0.3

- Optional on-device live transcript preview in the floating pill while speaking
- Magic Voice Edit for rewriting selected text with spoken instructions
- Speech Recognition permission controls and diagnostics
- Expanded live overlay that transitions back to the compact completion state

### v0.2

- Guided onboarding and permission setup
- System and provider diagnostics
- Eight output modes, including English translation, professional, concise, technical, bullets, and verbatim
- Personal dictionary for names and exact spellings
- Optional local transcript history with retention controls
- Retry failed dictation without recording again
- Configurable push-to-talk shortcuts
- Local voice snippets for reusable text expansion
- Spoken formatting commands with English and Hinglish phrases
- Clipboard preservation after automatic insertion
- Native SwiftUI menu-bar app
- Hold-to-talk `Fn` shortcut
- Floating microphone, waveform, processing, success, and error states
- Automatic insertion into the focused app
- OpenAI, OpenRouter, and custom compatible provider configuration
- Fast single-pass audio-to-English processing on supported OpenRouter models
- Optional Hindi/Hinglish-to-English cleanup
- API keys stored in macOS Keychain
- Temporary audio cleanup
- No account, telemetry, advertising, or hard-coded credentials

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version-by-version release notes.

## Requirements

- macOS 14 or later
- Microphone permission
- Accessibility permission for the global shortcut, selected-text editing, and automatic paste
- Speech Recognition permission for the optional on-device live preview
- An API key for the selected cloud provider

## Build

```bash
swift build
./Scripts/package-app.sh
open dist/ChatterKey.app
```

## Install locally

```bash
rm -rf /Applications/ChatterKey.app
ditto dist/ChatterKey.app /Applications/ChatterKey.app
open /Applications/ChatterKey.app
```

On first launch, allow Microphone, Accessibility, and optional Speech Recognition access in **System Settings → Privacy & Security**.

## Default provider configuration

Model availability changes over time, so every model ID remains editable in Settings.

- OpenAI transcription: `gpt-4o-mini-transcribe`
- OpenAI cleanup: `gpt-4.1-mini`
- OpenRouter transcription fallback: `openai/whisper-large-v3`
- OpenRouter fast audio processing: `google/gemini-3.5-flash-lite`

## Privacy

Read [PRIVACY.md](PRIVACY.md) before publishing or distributing the app. Cloud mode sends audio directly to the selected third-party provider. ChatterKey itself has no analytics or project-operated backend.

## Repository safety

Build output, packaged apps, local agent files, environment files, certificates, provisioning profiles, and common secret files are excluded by `.gitignore`.

Before every public push, run:

```bash
./Scripts/check-public.sh
git status --short
```

## Contributing

Issues and pull requests are welcome. Never include real API keys, private audio, or transcripts in bug reports.

## License

MIT — see [LICENSE](LICENSE).
