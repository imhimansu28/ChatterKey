# Changelog

All notable changes to ChatterKey are documented here, version by version.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Website

- Simplify the light product site into a direct four-section flow: one illustrative voice-to-text example, three everyday use cases, two centralized platform downloads and three essential questions. Remove duplicate demos, replay/tab controls, repeated slogans and separate technical panels. Keep setup details in the Mac/Android guides, visible provider/distribution caveats and no-JavaScript navigation.
- Add canonical page metadata, a sitemap, platform-specific software descriptions, lightweight local social/icon assets and a custom 404 page. Preserve release links and platform/privacy limitations; add dependency-free website checks and an honest Search Console launch checklist.

## [macOS 5.0.0] - 2026-09-13

### Changed

- Introduce platform-specific `macos-vX.Y.Z` / `android-vX.Y.Z` releases, download links, checksums and documentation from the shared repository. Historical unprefixed tags remain Mac releases.
- Expose shared response finishing for Android's native HTTP adapter without changing the Mac request/response behavior. Mac packaging explicitly builds only the Mac executable, uses build 15, treats compiler warnings as errors, strips debug-symbol build paths, rejects remaining local home paths and bundles the project license/privacy document.
- Preserve existing Mac settings/history/Keychain identities, one-model requests, selected-text review/protected warnings and Fn hold/double-tap controls. These user-facing features were already present in v4.8.0.
- Correct the v4.8.0 release date/changelog link and distinguish Mac-only features from Android functionality. Release scans report filenames rather than printing potential credentials and block tracked private/generated Android artifacts.

### Distribution limits

- Apple Silicon, macOS 14+; ad-hoc signed community-test ZIP, not Developer ID signed or Apple-notarized. No Windows build, automatic cross-device sync or claim of universal editor compatibility.

## [Android 1.0.0] - 2026-09-13

### Added

- First signed Android ARM64 keyboard release with native typing, hold-to-talk and double-tap hands-free recording, Stop/Cancel, and a two-minute in-memory WAV limit.
- A C/JNI adapter cross-compiles the same Swift processing core used by macOS. Android provides its own microphone, editor, encrypted settings and single-request HTTPS transport; no second transcription stage or automatic retry is introduced.
- Selected-text edit preview, protected-value acknowledgement, guarded Apply, Copy and Discard. Session changes invalidate insertion; hiding the keyboard cancels active recording/processing. Voice never submits messages.
- Separate Google/OpenRouter credentials encrypted with Android Keystore, configurable model/mode/prompt/vocabulary/snippets, and a private keyboard test editor.
- Storage-guarded minimal CLI build tooling, mic/WAV unit tests, shared bridge parity/Unicode regressions, and an explicit USB-device validation checklist.
- Android keyboard UI refinement: default English (India) staggered QWERTY, wide spacebar, one-shot Shift/caps lock, two symbol pages with ₹, long-press digits and repeat Backspace. Compact options/cancel controls replace the oversized toolbar.
- Local audio-level animation, recording timer/hands-free feedback and a separate processing state, with fixed mic placement and hidden-view/reduced-motion handling. Native device-rendered UI fixtures cover narrow/large-text, portrait and landscape layouts without touching real editors or recording audio.
- Native Dashboard/Settings/Practice pages, grouped provider/writing controls, collapsible advanced preferences, usage cards and a last-seven-days activity chart.
- Opt-in local aggregate counters distinguish estimated ChatterKey typed-word runs from final dictation output words, successful voice duration, dictations and voice edits. Password/private-mode fields and practice are excluded; no typed text, app identity or per-attempt history is logged. Pause/Clear leave provider settings intact and invalidate stale counting. Counts are not an exact spoken/document word count or billing ledger.

### Changed

- Android release packaging: private persistent signing identity, non-debuggable R8-optimized APK, preserved JNI names, original ChatterKey adaptive icon with themed waveform, bundled privacy/runtime notices and in-app version/documents. Release assembly verifies certificate type, manifest safety, ARM64 runtime inventory and 16 KB ZIP/ELF alignment, and emits a checksum.
- Android microphone denial now offers app-settings recovery. Failed recording startup clears attempt state/releases the device, and audio preparation has a timeout rather than waiting indefinitely before the HTTP deadline begins.
- Release assembly never installs the app. An initially blocked debug-to-release install was traced to a leftover debug copy in a secondary profile; after authorized removal, signed release installation and launch succeeded in the main profile. Document the all-profiles migration check without including private device/profile identifiers.

### Validation and limitations

- Ten release unit tests, lint, shared/bridge regressions, signing and 16 KB ZIP/native alignment checks passed. Earlier debug builds passed native UI/core fixtures and user spot checks; signed release USB installation and launch passed on one Android 15 ARM64 phone. Live release-mode microphone/provider/editor and lifecycle coverage remains incomplete. Advanced predictive typing, language preferences and full Mac feature parity remain planned.
- Android setup stays within the approved 10 GB additional tools/cache/build cap, without an emulator or Android Studio. The separate Mac download is version 5.0.0.

## [4.8.0] - 2026-09-13

### Added

- Fn double-tap starts hands-free recording; pressing Fn again stops and processes the audio. Holding Fn remains hold-to-talk, and Escape cancels an active recording. A short single Fn tap waits briefly for a possible second tap before processing.
- Hands-free status and stop instructions appear in the recording overlay and menu. Shortcut changes, manual Stop, startup failures, and event-tap interruptions clear pending taps and recording locks.
- Gesture recognition uses physical event timestamps so delayed callback delivery does not misread a double-tap as a hold. Local regression fixtures cover delayed delivery and overdue timers without using the microphone or posting system-wide keys.
- Preview recovery distinguishes missing editable-selection information from moved focus. A temporary focus change no longer permanently disables Apply when the original selection has a verifiable range; the original target/text are still checked before paste.
- Selected-text voice edits pause at a review window with literal before/after highlighting, Apply to Original, Copy & Close, and Discard. Large selections use a bounded changed-passage comparison.
- Local warnings compare detected numbers, email addresses, and HTTP(S)/www URL values and occurrence counts; Apply requires acknowledgement when they differ. These checks are heuristic, not factual or semantic validation.
- Apply rechecks the original target and selection. An unverifiable or changed target retains the proposed text for manual Copy recovery without another model request.
- Pending reviews block new dictation/history insertion, release retry audio after processing, and remain memory-only until Apply or Copy saves to optional history. Discard does not remove usage already incurred by the request.
- An ordered roadmap for language controls, app preferences, approved corrections, attempt details, and Android development gated on explicit approval and a system-resource plan.

### Changed

- Separate the native Mac application and resources into `apps/macos` and extract `ChatterKeyCore` as a real Swift module. Shared processing, prompts, edit checks and usage calculations no longer depend on native app settings/storage or microphone APIs.
- Inject the Mac HTTP transport explicitly and keep completed-audio file reads in the native recorder adapter. Preserve timeout/redirect policy, existing settings/history formats and one model request per attempt.
- Update packaging, public-source checks and the existing regression harness for the split layout. No Android code, tooling or bridge is included.

## [4.6.1] - 2026-09-12

### Fixed

- Read selected text without blocking the hotkey event loop; handle empty Accessibility attributes, valid UTF-16 ranges, oversized selections, and known insertion points explicitly.
- Serialize temporary clipboard operations, finish bounded clipboard cleanup after cancellation, and recheck the original app/field/selection before pasting. Clipboard restoration remains best-effort for unusually delayed external applications.
- Handle Space release after shortcut modifiers are released; avoid duplicate fallback monitoring and stale queued shortcut callbacks.
- Prevent cancelled requests from deleting a newer attempt's retry audio or replacing its state. Guard repeated Retry and diagnostic actions.
- Preserve legitimate quotes, code fences, and edit/verbatim whitespace; reject results that become empty after local formatting.
- Expand snippet cues once without recursively expanding their replacement text.
- Remove expired history from persistent storage when history is loaded or new entries are saved, and preserve unreadable settings for recovery rather than overwriting them.
- Validate model IDs and non-negative, finite cost rates before saving; trim pasted API-key whitespace without moving keys between providers.
- Convert audio in bounded chunks instead of allocating buffers for the entire recording, and clean up temporary recording files on app exit.
- Show actionable errors and an honest “Paste sent” status instead of implying that every target application confirmed insertion.
- Correct single-request cost descriptions, avoid quoting arbitrary speech in new usage suggestions, and disclose legacy suggestion storage.
- Include documentation and Google-key patterns in public-source scans; fix website reveal transitions, invalid font syntax, and overly broad compatibility claims.

### Validation

- Extended the existing regression script with isolated clipboard, hotkey, audio-conversion, retention, settings-recovery, and literal-output checks. No real API keys, model requests, microphone recordings, or system-wide keyboard events are used by these tests.
- Debug/release builds, packaged app signatures, archive checksums, and desktop/mobile website checks are verified for release. These checks do not establish real-provider accuracy or universal cross-application compatibility.

### Distribution

- Version `4.6.1`, build `11`, as an Apple Silicon community-test ZIP with a SHA-256 checksum. Ad-hoc signed and not Apple-notarized.

## [4.6.0] - 2026-09-12

### Added

- Added Google Direct using a Gemini API key and Google's OpenAI-compatible audio endpoint, alongside the existing OpenRouter connection.
- Added a connection picker and provider-specific key labels in Settings and onboarding. New installs default to Google Direct with `gemini-3.5-flash-lite`.
- Preserve each connection's model and cost-rate settings when switching; API keys remain isolated in provider-specific Keychain accounts.

### Changed

- Existing OpenRouter setups stay on OpenRouter during migration. Choosing Google Direct is explicit and never reuses an OpenRouter key.
- Google payloads use `reasoning_effort` and omit OpenRouter routing parameters and headers. Both connections retain one model request per attempt and manual-only Retry.
- Expanded the existing regression harness across both connections, including audio payloads, all writing modes, voice edits, authentication/quota errors, and settings round trips.
- Updated the app to version `4.6.0`, build `10`, and refreshed the README, website, announcement, and download links.

### Distribution

- Published an Apple Silicon community-test ZIP with a SHA-256 checksum. The app is ad-hoc signed and not Apple-notarized.

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

[4.8.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v4.8.0
[4.6.1]: https://github.com/imhimansu28/ChatterKey/releases/tag/v4.6.1
[4.6.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v4.6.0
[4.5.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v4.5.0
[0.4.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.4.0
[0.3.1]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.3.1
[0.3.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.3.0
[0.2.4]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.4
[0.2.1]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.1
[0.2.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.2.0
[0.1.0]: https://github.com/imhimansu28/ChatterKey/releases/tag/v0.1.0
