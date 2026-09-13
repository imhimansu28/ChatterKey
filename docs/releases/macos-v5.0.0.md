# ChatterKey for macOS 5.0.0 — Separate apps. Shared processing.

Released September 13, 2026 · Apple Silicon · macOS 14+ · Build 15

This release packages the Mac app independently alongside the first Android release. It does not add Windows support or move Mac recording, credentials or editor access into Android.

## Changes since macOS 4.8.0

- Native Android HTTP adapters can finish responses through the same Swift core rules. Mac response validation, one-model request behavior and explicit Retry remain unchanged.
- Mac packaging explicitly selects the Mac executable, treats compiler warnings as errors, removes debug-symbol build paths, rejects remaining local home paths and bundles the project license/privacy notice. No Android SDK, Java runtime, APK or release key is included in the Mac ZIP.
- Separate platform tags (`macos-v5.0.0`, `android-v1.0.0`), release notes, download buttons and checksums prevent mixing desktop and keyboard downloads. Version numbers evolve independently; the source repository and processing core are shared.
- Website, README, privacy/security disclosures and migration guidance now distinguish platform capabilities. The historical v4.8.0 release date and changelog link are corrected.
- Public-source scans report matching filenames instead of echoing possible credentials and reject tracked private/generated Android artifacts.

## Existing functionality retained

Selected-text review, protected-value acknowledgement, verified Apply/Copy recovery and Fn hold/double-tap hands-free recording were already released in v4.8.0. They are retained, not newly introduced in 5.0.0. The Google Direct default, optional OpenRouter connection, provider-isolated credentials/model preferences, settings/history formats and bundle identity remain unchanged. There is no automatic settings/key sync between devices.

## Download and update

Download `ChatterKey-macOS-v5.0.0.zip` and its `.sha256` file from this release. Quit the old app, extract the ZIP, replace `ChatterKey.app` in Applications and reopen it. Existing Keychain accounts and preferences are retained; recheck Microphone/Accessibility permissions if macOS asks. Speech Recognition is optional for the on-device rough preview.

```bash
shasum -a 256 -c ChatterKey-macOS-v5.0.0.zip.sha256
```

**This is an ad-hoc signed community-test build, not Developer ID signed or Apple-notarized.** Gatekeeper may block it. Do not disable system-wide security protections. The checksum verifies file integrity, not Apple approval or publisher identity. The ZIP is ARM64 only, not an Intel/universal build.

## Validation and limits

- Mac debug/release compilation, shared provider/local regressions, bridge host fixtures, package signature and ZIP integrity checks are release gates.
- The regression harness covers one-request behavior, provider isolation/migrations, modes, Unicode, protected-value previews, selection/clipboard recovery, hotkeys, audio handoff, history and usage with synthetic fixtures/mock provider responses.
- No new clean-account Mac, real-provider accuracy/latency or exhaustive installed-app editor compatibility test is claimed. This release process does not reinstall the user's Mac app.
- Incomplete Accessibility information remains Copy-only. A dispatched paste is not confirmation that a destination accepted it. Review detected value changes and the full result; warnings do not verify meaning/facts.
- Audio/instructions and selected text for an explicit edit go to the selected provider under that provider's policies. Supply your own API key. Review [Privacy](https://github.com/imhimansu28/ChatterKey/blob/macos-v5.0.0/PRIVACY.md) and [distribution limits](https://github.com/imhimansu28/ChatterKey/blob/macos-v5.0.0/DISTRIBUTION.md).

Android has its own [1.0.0 release notes](https://github.com/imhimansu28/ChatterKey/releases/tag/android-v1.0.0), requirements and APK; Mac-only live preview, history and cost dashboards are not promised on Android.
