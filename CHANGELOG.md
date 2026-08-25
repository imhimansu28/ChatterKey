# Changelog

All notable changes to ChatterKey are documented here, version by version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added privacy-safe starter vocabulary for common technology names and three editable general-purpose voice snippets for new and existing users.

### Fixed

- Prevented provider requests from hanging on stale connections by using isolated sessions, one transient-network retry, and bounded processing timeouts.
- Restored compact 16 kHz mono PCM audio uploads while keeping the on-device live transcription preview, reducing payload size and provider latency.
- Added an automatic dedicated speech-to-text fallback when OpenRouter single-pass audio processing times out or loses its connection.
- Automatically dismisses the failure overlay after showing the error while keeping the recorded audio available for Retry.

## [0.3.0] - 2026-08-25

### Added

- Optional on-device live transcription preview in the floating dictation overlay while recording.
- Magic Voice Edit: select text in any accessible app, hold the shortcut, and speak an instruction to replace the selection.
- Speech Recognition permission status, diagnostics, and Settings controls for live preview.

### Fixed

- Prevented the real-time audio callback from violating MainActor isolation and terminating the app when push-to-talk started.
- Fixed Speech Recognition authorization and partial-result callbacks so permission requests and live previews no longer terminate the app.

### Changed

- Updated the packaged application version to `0.3.0` with build number `5`.

## [0.2.4] - 2026-08-24

### Added

- Redesigned Settings with a modern macOS sidebar, focused detail pages, reusable cards, empty states, and a persistent action footer.
- Voice snippets that expand short spoken cues into exact reusable text after transcription.
- Optional spoken formatting commands for new lines, paragraphs, bullets, and punctuation, including common Hinglish variants.

### Fixed

- Removed the stale keyboard-focus border from previously selected Settings sidebar items and disabled unnecessary section transition animation.
- Clipboard restoration now preserves multiple pasteboard item types and avoids overwriting content copied by the user immediately after dictation.

### Changed

- Updated the packaged application version to `0.2.4` with build number `4`.

## [0.2.1] - 2026-08-24

### Changed

- Replaced the large dictation status pill with a compact animation-only indicator for listening, processing, completion, and failure states.
- Kept failed-dictation retry available from the menu-bar popover while removing controls from the compact overlay.
- Updated the packaged application version to `0.2.1` with build number `3`.

### Fixed

- Removed the rectangular window shadow and clipped gray border around the compact dictation indicator.

## [0.2.0] - 2026-08-24

### Added

- Guided first-run onboarding for provider, output mode, shortcut, and permissions setup.
- System diagnostics for microphone, Accessibility, global shortcut, Keychain, and provider connectivity.
- Eight output modes: clean same language, translate to English, professional, casual, concise, bullet points, technical, and verbatim.
- Personal dictionary for preferred names, products, acronyms, and technical spellings.
- Optional local transcript history with 1-day, 7-day, and 30-day retention controls.
- Copy and reinsert actions for recent transcripts.
- Retry for failed dictation without recording the audio again.
- Configurable push-to-talk shortcuts: Fn, Right Option, Option-Space, and Command-Shift-Space.
- Quick output-mode selection in the menu-bar popover.
- Focused model and settings migration test script.

### Changed

- Redesigned the menu-bar popover and Settings window for clearer setup and faster access.
- Improved AI processing prompts for output modes and personal vocabulary.
- Updated the packaged application version to `0.2.0` with build number `2`.

### Fixed

- Prevented unexpected repeated macOS Keychain password prompts from older local-build credentials.
- Changed Keychain saving from delete-and-recreate to update-or-create for more reliable persistence.
- Retained temporary audio after a processing failure so the request can be retried safely.

### Security

- API keys remain stored in macOS Keychain.
- Transcript history remains disabled by default and stores text locally only when enabled.
- Temporary audio is never included in transcript history.

## [0.1.0] - 2026-08-24

### Added

- Initial public release of the native SwiftUI macOS menu-bar application.
- Hold-to-talk Fn shortcut with microphone, waveform, processing, success, and error overlays.
- Automatic insertion of generated text into the focused macOS application.
- OpenAI, OpenRouter, and custom OpenAI-compatible provider configuration.
- Editable transcription and polishing model IDs.
- Fast single-pass audio processing for supported OpenRouter models.
- Hindi and Hinglish transcription cleanup with optional English translation.
- macOS Microphone and Accessibility permission setup.
- API key storage in macOS Keychain.
- Temporary audio cleanup and public-source safety checks.
- Privacy, security, distribution, and MIT license documentation.
