# Changelog

All notable changes to ChatterKey are documented here, version by version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Nothing yet.

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
