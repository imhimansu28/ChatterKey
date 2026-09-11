# Changelog

All notable changes to ChatterKey are documented here, version by version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Added Google Direct using a Gemini API key and Google's OpenAI-compatible audio endpoint, alongside the existing OpenRouter connection.
- Added a connection picker and provider-specific key labels in Settings and onboarding. New installs default to Google Direct with `gemini-3.5-flash-lite`.
- Preserve each connection's model and cost-rate settings when switching; API keys remain isolated in provider-specific Keychain accounts.

### Changed

- Existing OpenRouter setups stay on OpenRouter during migration. Choosing Google Direct is explicit and never reuses an OpenRouter key.
- Google payloads use `reasoning_effort` and omit OpenRouter routing parameters and headers. Both connections retain one model request per attempt and manual-only Retry.
- Expanded the existing regression harness across both connections, including audio payloads, all writing modes, voice edits, authentication/quota errors, and settings round trips.
- Incremented the local development build to `9`; the published v4.5.0 release remains build `8`.

## [4.5.0] - 2026-09-08

### Changed

- Redesigned the README as a visual product guide with a generated hero, animated workflow demo, feature comparison, quick-start guide, transparency table, and compact developer sections.
- Strengthened Translate to English instructions so mixed Hindi-English fragments are converted consistently while names, brands, code, URLs, and filenames stay intact.
- Unified all writing modes and Magic Voice Edit on one configurable audio-capable model, defaulting to Gemini 3.5 Flash-Lite through OpenRouter.
- Removed separate transcription/polishing controls, automatic fallback, English-repair calls, and automatic retries. Retry is now always explicit.
- Migrated legacy settings and usage metadata to one model while retaining local history and keeping provider keys isolated.

### Fixed

- Translate to English and all other writing modes use the same audio request even when optional smart cleanup is disabled.
- Added a clipboard-copy selection fallback for apps that do not expose selected text through standard Accessibility attributes, improving Magic Voice Edit compatibility with browsers, Electron apps, PDFs, Apple Notes, and editors. Compatibility still depends on the target app.
- Tagged synthetic copy events so they do not interfere with push-to-talk shortcut handling.
- Magic Voice Edit now sends selected text and instruction audio together through chat-completions `input_audio`, without transcribing the instruction separately.
- Reject empty, blocked, and truncated model responses rather than inserting incomplete results.
- Preserve literal formatting-command and snippet phrases in Verbatim mode.
- Cost estimates use audio-token pricing plus instructions, selected text, and output tokens instead of charging a separate transcription stage.

### Distribution

- Updated the app to version `4.5.0`, build `8`, with matching README, website, announcement, and release download links.
- Published an Apple Silicon community-test ZIP with a SHA-256 checksum. This build is ad-hoc signed and not Apple-notarized.

### Security

- Pin active processing to the official OpenRouter host, reject legacy-provider requests and redirects, and never migrate API keys between provider accounts.

## [0.4.0] - 2026-08-25

### Added

- Added a local usage dashboard with words spoken, speaking time, estimated provider costs, provider breakdowns, activity charts, and speaking suggestions.
- Added editable cost-estimation rates for transcription and input/output tokens.
- Added Dashboard and History pages inside the unified Settings window while keeping only the latest dictation in the compact menu-bar popover.
- Added editable system instructions with a restore-default action and an exact provider-prompt preview in Settings.
- Added a public architecture diagram and transparent processing overview to the README.

### Changed

- Documented how custom prompts, vocabulary, temporary audio, provider requests, and local preferences are handled.
- Updated the packaged application version to `0.4.0` with build number `7`.

## [0.3.1] - 2026-08-25

### Added

- Added a dedicated ChatterKey macOS application icon across Finder and system surfaces.
- Added privacy-safe starter vocabulary for common technology names and three editable general-purpose voice snippets for new and existing users.

### Fixed

- Prevented provider requests from hanging on stale connections by using isolated sessions, one transient-network retry, and bounded processing timeouts.
- Restored compact 16 kHz mono PCM audio uploads while keeping the on-device live transcription preview, reducing payload size and provider latency.
- Added an automatic dedicated speech-to-text fallback when OpenRouter single-pass audio processing times out or loses its connection.
- Automatically dismisses the failure overlay after showing the error while keeping the recorded audio available for Retry.

### Changed

- Updated the packaged application version to `0.3.1` with build number `6`.

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

[Unreleased]: https://github.com/imhimansu28/ChatterKey/compare/v4.5.0...HEAD
[4.5.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v4.5.0
[0.4.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.4.0
[0.3.1]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.3.1
[0.3.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.3.0
[0.2.4]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.4
[0.2.1]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.1
[0.2.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.0
[0.1.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.1.0
