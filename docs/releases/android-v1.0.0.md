# ChatterKey for Android 1.0.0 — Your keyboard. Your voice.

Released September 13, 2026 · Android 9/API 28+ · ARM64 only · Version code 4

The first signed Android release combines a native keyboard/settings/recording layer with the actual cross-compiled Swift processing core used by ChatterKey for macOS. It is a separate APK and version line, not a Windows build or a wrapper around the Mac app.

## Keyboard and voice

- English (India) staggered QWERTY, wide spacebar, one-shot Shift/caps lock, two number/symbol pages including ₹, long-press top-row digits, repeat Backspace and keyboard switching.
- Hold the mic and release to process, or double-tap for hands-free and tap again/Stop. Cancel clears the attempt; Escape is supported when available. Recordings are limited to two minutes in memory.
- Local audio-level animation, recording timer and processing feedback keep the held mic target stationary. Visual updates stop when hidden and respect disabled animations.
- Each attempt uses one configurable audio-capable model: Google Direct by default, OpenRouter optional. No hidden transcription/polishing pair, automatic retry, repair call, fallback or Send. Manual Retry makes another request and may incur charges.
- Selected-text edits show original/proposed text, local highlights and warnings for detected protected-value changes. Apply requires the original editor, selection and nearby context to remain verifiable; otherwise use Copy or Discard. Warnings are not factual/semantic verification.
- Failed recording startup cleans up state/device resources; audio preparation and HTTP processing have deadlines. Denied microphone permission offers an app-settings recovery path.

## Settings, dashboard and privacy

- Separate Dashboard, Settings and private Practice pages; configurable provider/model/mode/prompt/vocabulary/snippets; branded adaptive/themed launcher icon; version and offline privacy/license documents.
- Provider keys are encrypted with Android Keystore and isolated by connection. Preferences/keys do not migrate from Mac, and ordinary typing needs neither a key nor a network connection.
- Usage counters are **OFF by default**. Opt in for estimated typed-word runs, words in final dictation output, successful voice duration, dictations and separate edits. Today, seven-day and all-time views are local only. These are not exact spoken-word or net document counts.
- Counting stores no characters, audio or per-attempt history, reads no editor document for analytics and adds no API request. Password/unsupported fields, private-marked editors and ChatterKey settings/Practice are excluded. Private detection relies on the host app marking its field correctly.
- Clearing counters or changing consent invalidates pending counts. Android app backup/cloud transfer is disabled. Copy explicitly writes the result to the system clipboard; other permitted system/app features may access copied text.

## Install or update

Download `ChatterKey-Android-v1.0.0-arm64.apk` and its `.sha256` file. This is the release-signed APK, not the development/debug APK. Full native runtime dependencies and license notices are included; the download is approximately 84 MiB.

```bash
shasum -a 256 -c ChatterKey-Android-v1.0.0-arm64.apk.sha256
```

1. For the first debug-to-release switch, safely note your provider key and custom preferences, then uninstall old debug ChatterKey copies from **every profile where installed**, including secondary/secure/work/clone spaces. Only remove ChatterKey, not an entire profile. Different signing identities cannot replace one another; a leftover copy can cause a package-conflict error. Uninstall removes that copy's local settings/counters.
2. Install the APK using Android's installer. Enable installation from the source you intentionally use if Android requests it; do not disable platform security globally.
3. Open ChatterKey → Practice → Enable ChatterKey → Choose keyboard → Allow microphone. Then enter your provider's own API key in Settings and Save. Android shows a standard warning when enabling a third-party keyboard; review the source/privacy information before granting trust.
4. Start with the private Practice editor. Review text before applying and never use sensitive real drafts for diagnostics. Practice intentionally does not count usage.
5. Later release updates use the same release-signing identity and a higher version code; do not replace them with debug/instrumentation APKs. No need to uninstall ordinary same-key future release updates.

Public release certificate SHA-256 fingerprint:

```text
53a465cdc0bdd2345a28e92b71366a342d88f0d4736e3c1fcb57a6af4b5998d6
```

This fingerprint is public; it does not disclose the private key. The private keystore/passwords are not release assets or repository contents.

## Tested scope and known limits

- Ten release unit tests, Android lint, host/shared Swift regressions, R8/JNI-name checks, APK signature and 16 KB ZIP/ELF alignment checks for all 19 native libraries form the release checks.
- Earlier debug builds passed synthetic native keyboard/dashboard/settings/privacy fixtures on a physical Android 15 ARM64 phone, including narrow/large-text and landscape layouts. The user reported their tested baseline functionality working.
- The signed release was installed via USB after removing a conflicting secondary-profile debug copy, launched successfully and stayed running with no app-scoped fatal error observed. This verifies that install/launch path, not every installer UI, device or editor.
- Live release-mode microphone capture, provider calls, Apply/Copy across apps, interruption/network failures and lifecycle edge cases are not exhaustively validated. A compiled APK, preserved JNI symbol or initial launch alone is not proof of full voice/editor compatibility.
- No predictive typing/swipe typing, local live transcript, Android transcript history, billing/cost dashboard, dedicated Hindi layout, automatic sync or full Mac feature parity is included. The selectable writing mode/instructions can preserve Hindi/Hinglish; quality depends on the chosen model and recording.
- ARM64 Android 9+ only: no 32-bit/x86/emulator build, Play Store distribution or Windows application. Users supply their own approved provider credentials; provider fees/retention policies apply independently.

See [Android setup/build documentation](https://github.com/imhimansu28/ChatterKey/blob/android-v1.0.0/apps/android/README.md), [Privacy](https://github.com/imhimansu28/ChatterKey/blob/android-v1.0.0/PRIVACY.md) and [Security](https://github.com/imhimansu28/ChatterKey/blob/android-v1.0.0/SECURITY.md). The separate desktop download is [macOS 5.0.0](https://github.com/imhimansu28/ChatterKey/releases/tag/macos-v5.0.0).
