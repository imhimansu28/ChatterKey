# ChatterKey Android — signed release build

**Android 1.0.0** is a signed, non-debuggable ARM64 release APK, distributed separately from macOS 5.0.0 under the `android-v1.0.0` tag. See [release notes and migration guidance](../../docs/releases/android-v1.0.0.md). It is not a Play Store submission. Signed release USB installation/launch passed on one physical phone; live release-mode microphone/provider/editor coverage remains incomplete. Build tooling/caches are constrained to **10 GB**, without an emulator, Android Studio or a heavy IDE. Building does not modify an installed Mac or Android app.

## Architecture

```text
Native Android keyboard / settings (Java, Android framework)
  ├─ AudioRecord → bounded 16 kHz mono PCM WAV in memory
  ├─ InputConnection → selected-text capture and guarded insertion
  ├─ Android Keystore → provider-specific encrypted credentials
  └─ UTF-8 JNI / C bridge
       └─ ChatterKeyAndroidBridge (Swift)
            └─ ChatterKeyCore (the same sources used by macOS)
```

The shared core builds the provider request, processes the response, applies writing modes/vocabulary/snippets, and generates edit diffs and protected-value warnings. Android supplies audio, settings, HTTPS transport, and editor/lifecycle adapters. No duplicate transcription pipeline, backend, Mac Keychain access, or automatic settings sync is introduced. The Swift core does not own native recording or UI.

Each attempt makes **one audio-model request**, directly to Google by default, or to OpenRouter when explicitly selected. Retry is manual and can incur another charge. Review, Apply, Copy, and Discard do not call a model. Cancellation cannot undo a request already received by the provider.

## Implemented scope

- Default English (India) four-row QWERTY with staggered letter rows, a wide labeled spacebar, one-letter Shift, double-tap/long-press caps lock, two number/symbol pages including ₹, and the editor's manual action key. Hold top-row letters for digits; hold Backspace to repeat; hold Space to switch keyboards.
- Compact options menu for Settings/Switch instead of permanent full-width buttons. Cancel appears only during an active attempt. Rounded keys, press feedback, and a dedicated microphone keep typing controls uncluttered.
- A recording panel shows locally measured audio level, elapsed time, and hands-free status. Processing has its own animated state. Visual updates stop when hidden/detached and respect the system's disabled-animation setting. The mic stays in place when recording begins, preserving hold-to-talk touch handling.
- Hold the mic and release to process; double-tap to record hands-free, then tap again or use Stop. Short taps have a 350 ms double-tap grace period. Cancel clears the recording lock and pending taps.
- Recordings are limited to two minutes. Hiding/switching the keyboard or changing editor sessions cancels recording or processing; late results cannot insert into a new session.
- Shared eight writing modes, editable model/system prompt, vocabulary, snippets, smart polish, and spoken commands. The preserve-language mode supports instructions for Hindi/Hinglish; live quality has not been evaluated on a phone.
- Selected-text edit review with local highlights, protected-value acknowledgement, Apply, Copy & close, and Discard.
- Apply requires the same connection/session, UTF-16 selection, selected text, and nearby local context. Incomplete editor information means Copy only, not guessed replacement. Ordinary dictation inserts directly only when these checks pass.
- Voice is disabled for declared password and unsupported `TYPE_NULL` fields. Normal typing remains local. No voice action invokes Send or Enter.
- Provider keys are encrypted using Android Keystore and kept separate. A blank key on Save removes only that connection's key. Switching connections discards unsaved form changes.

This is **not full Mac feature parity**: no live transcript, transcript history, a billing/cost dashboard, editable cost-rate UI, app-specific presets, automatic correction learning, swipe typing, suggestions, emoji picker, a dedicated Hindi typing layout, or swipe-cursor editing. Explicit Roman/Devanagari language controls remain a planned milestone. Custom editors may require manual Copy. Earlier native layout/core fixtures and signed-release installation/launch passed on a USB phone; live release-mode microphone/provider/editor and lifecycle coverage remains incomplete.

## Dashboard and local usage

The app opens to native **Dashboard / Settings / Practice** pages. Settings group the provider/key, writing mode and optional advanced instructions/vocabulary/snippets; switching tabs preserves unsaved form values, while switching providers explicitly discards unsaved edits. Saving still makes no network request. Credentials remain encrypted and isolated as before.

Usage is **off by default**. Enable **Local usage counters** on Dashboard to start collecting future aggregate activity; there is no backfill from old dictations, other keyboards or Mac history.

- **Typed words:** an estimate of new letter/number runs in successfully accepted ChatterKey key taps. It does not read the document to reconcile cursor moves, corrections or deletions, and does not subtract erased words. Reopening a field or retyping can count a run again. No characters or key sequences are retained by the counter.
- **Voice output:** the shared core's whitespace-based word estimate for final successful dictation output, not an exact count of spoken audio. Translation/polishing can change it. Voice edits are counted separately and do not add the rewritten selection's words to this metric.
- **Voice time / dictations / edits:** successful, non-cancelled processing completions. Pending/failed requests are not counted; a successful explicit retry counts once. Apply/Copy/Discard do not add another count. Completed previews remain counted if later discarded. This is not an API billing ledger.
- **Today / 7 days / All time**, plus a last-seven-days activity chart. Only date buckets, integer aggregates and the tracking preference/revision are saved in a separate private preferences file. Daily buckets older than 30 days are pruned on new counted activity; all-time aggregates remain until cleared.
- Declared password/unsupported fields and editors requesting `IME_FLAG_NO_PERSONALIZED_LEARNING` are excluded. All ChatterKey settings/practice fields request that private mode. Incognito detection depends on the editor providing the flag; the app does not inspect browser/app contents to infer it.
- Turning counters off pauses collection without deleting totals. **Clear local usage** removes totals without touching provider settings or keys, and invalidates counting for in-flight attempts started before the reset/consent change.

No app names, per-attempt timestamps, transcripts, audio, typed content, clipboard contents or screen captures are added to usage storage. This feature makes no model request and does not change the keyboard's one-request architecture.

## Build on an Apple Silicon Mac

The APK targets **ARM64 (`arm64-v8a`), Android 9/API 28 or newer**. It does not contain an x86/emulator or 32-bit build. The Java build targets API 36. Both the cross-compiled core and its transitive Swift/native runtime libraries are packaged in the APK; a successful host-only Swift build is not used as Android proof.

Pinned local tools are under `.build/android-tools`:

| Component | Version / location |
| --- | --- |
| Matching OSS Swift host toolchain | 6.3.3, `swift-toolchain/usr/bin` |
| Swift Android SDK | 6.3.3, `swift-sdks/swift-6.3.3-RELEASE_android.artifactbundle` |
| NDK | r27d, `ndk/android-ndk-r27d` |
| Java | Temurin 17.0.20.1+1, `jdk/*/Contents/Home` |
| Gradle | 8.13, `gradle-8.13` |
| Android Gradle plugin | 8.13.2, pinned in `build.gradle` |
| Android SDK | platform 36 revision 2, build-tools 36.0.0, platform-tools 37.0.1, under `sdk` |

The matching OSS Swift compiler is extracted locally, not installed over Apple's compiler. The NDK retains its sysroot, Clang 18 resources, and LLVM inspection/strip tools; the matching Swift toolchain supplies Clang and the linker. This avoids a duplicate full NDK toolchain. The Swift Android SDK's NDK setup must point to that local r27d directory. Tool archives were verified against official checksums/signatures before extraction and removed afterward.

The build script expects this layout; it is **not an automatic tool installer**. On a new machine, obtain these versions from their official distributions and re-evaluate download/extraction peaks before installing. Never treat the current installed footprint as the peak storage needed for a fresh full toolchain extraction.

```bash
python3 Scripts/build-android.py
```

This builds the shared ARM64 library/JNI bridge, packages transitive runtime dependencies, strips debug data, and runs `assembleDebug`, `testDebugUnitTest`, and `lintDebug`. Gradle may fetch pinned build dependencies. Java heap is capped at 1 GB and builds use at most two workers; that heap cap is not a total-process RAM guarantee.

The storage guard monitors local tools, caches, Android build outputs and source, stopping at 9.6 GB to leave headroom below the approved 10 GB limit. It also requires 2 GB free disk space. SDK auto-download is disabled. Do not run unrelated Android downloads/builds concurrently or bypass the guard.

Output:

```text
apps/android/app/build/outputs/apk/debug/app-debug.apk
```

The default command produces a debug-signed `1.0.0-dev` APK for development. It is approximately 88 MB (84 MiB), mostly the bundled Swift runtime. Do not distribute the debug APK as a release. Local keys, SDK paths, caches and generated packages are ignored by Git.

Mac-only compilation and the shared regression harness remain available:

```bash
swift build --product ChatterKey
bash Scripts/test-models.sh
bash Scripts/check-public.sh
```

## Signed release APK

The local release identity lives in **`apps/android/signing/`**, outside disposable tool/build caches. This entire directory is Git-ignored. Keep the directory owner-only (`700`) and its keystore/properties files owner-readable/writable only (`600`). Back up both files in encrypted storage. **Do not regenerate the key for each version:** future APK updates must use the same signing identity. Never share this directory with the APK.

For official release updates, the existing private keystore is `chatterkey-release.jks`, alias `chatterkey`; `release.properties` provides `storeFile`, `storePassword`, `keyAlias`, and `keyPassword`. Passwords are not embedded in Gradle source or the APK. Release assembly fails if signing configuration is missing. An ordinary build never creates or replaces a signing key. Official maintainers must restore the existing private signing folder securely on another machine rather than create a new update identity. Other contributors should use the debug build for development; they do not receive the official release key.

```bash
python3 Scripts/build-android.py assembleRelease testReleaseUnitTest lintRelease
```

Output folder:

```text
apps/android/app/build/outputs/apk/release/
  app-release.apk
  app-release.apk.sha256
  app-release.apk.signing.txt
```

Release builds disable Java/native debugging, enable R8 code/resource shrinking, and preserve the JNI entry-point name. The build verifies non-debug signing/manifest flags, 16 KB ZIP and native ELF alignment, the expected ARM64 runtime inventory, and packaged privacy/license documents. It writes an APK checksum and public signing-certificate details beside the APK. These checks do not install or launch the app. Public release assets use the filename `ChatterKey-Android-v1.0.0-arm64.apk` with a matching named checksum; the generated `app-release.apk` is the build output.

The launcher reuses ChatterKey's original icon with adaptive masking and a waveform monochrome layer for themed launchers. Settings includes the Android version, offline Privacy & data, and open-source licenses. The runtime notices include the pinned SDK components plus ICU/Unicode data and C++ attribution; no build tools or test dependencies are bundled.

### Manual clean-install checklist

**Nothing is installed/uninstalled by the release build command.** For the first debug-to-release switch, save your provider key and any custom preferences somewhere safe before uninstalling the debug app. The signing identities differ, so this is not an in-place debug update. Uninstalling removes ChatterKey's local preferences, encrypted credentials and optional counters; there is no automatic restore.

1. Uninstall debug ChatterKey from every profile where it is installed (including secondary/secure/work/clone spaces), then install the signed release APK using Android's package installer. Only remove ChatterKey, not a whole profile. A leftover debug copy can cause a package-conflict error. It supports ARM64 phones on Android 9/API 28 or newer, not 32-bit/x86 devices.
2. Open ChatterKey and confirm the branded launcher icon and version `1.0.0`. In Practice, enable/choose the keyboard and allow the microphone. In Settings, enter your provider key and Save.
3. Check ordinary typing without a key/network; symbols/Shift/delete; Hindi/English voice input; hold/release and double-tap/Stop/Cancel; permission denial and its app-settings recovery; offline/authentication failure and explicit Retry.
4. In the private Practice editor, check selected-text review, protected warnings, Apply/Copy/Discard, and changed-selection recovery. Verify no automatic Send. Practice does not count usage; explicitly enable counters before checking normal non-private typing/dictation elsewhere, using disposable drafts only.
5. Switch editors, rotate, hide the keyboard and lock/unlock during an attempt; verify recording stops and no late result inserts into another session. Verify the optimized release loads JNI successfully, not just a debug build.
6. Subsequent release updates must use this same release certificate and a higher version code. Validate settings/key retention during an in-place release-to-release update separately from the clean-install test.

Broader manual validation remains necessary. This is a direct APK release, not a Play Store submission or a claim of universal keyboard compatibility.

## USB install and setup

1. Connect an unlocked phone with a data-capable USB cable. Enable USB debugging and accept this Mac's authorization prompt on the phone.
2. Check that the authorized device is listed, and verify its ABI and Android version before installing:

   ```bash
   .build/android-tools/sdk/platform-tools/adb devices -l
   .build/android-tools/sdk/platform-tools/adb -s SERIAL shell getprop ro.product.cpu.abilist
   .build/android-tools/sdk/platform-tools/adb -s SERIAL shell getprop ro.build.version.sdk
   .build/android-tools/sdk/platform-tools/adb -s SERIAL install -r apps/android/app/build/outputs/apk/debug/app-debug.apk
   ```

3. Open ChatterKey on the phone. Enable and choose the keyboard, allow microphone access, enter the selected provider's own API key, and Save. Do not paste a real key into chat, source, logs, or shell commands.
4. Start in the app's **Private test editor**. Do not test by modifying or submitting real messages in other apps.

## Validation checklist

Automated checks cover the mic gesture state machine/WAV encoding, shared-core request parity for both providers and all modes, UTF-8/Hindi/emoji/embedded-NUL bridge data, response errors, and protected-value preview behavior. The development APK also passes signature verification and 16 KB ZIP/native segment alignment checks for all 19 packaged native libraries. These tests do **not** exercise the on-phone JNI loader, microphone, or editor lifecycle.

Before calling this device-ready, verify on the USB phone:

- Launch/settings/core catalog load without native-library errors; API key save/reload and provider isolation.
- Typing, shift, delete (including supplementary Unicode), symbols, action labels, portrait/landscape and system-bar insets.
- Mic permission denied/granted, hold/release, double-tap/stop, Cancel, two-minute limit, interruption, keyboard switch and screen lock.
- Hindi/Hinglish dictation, translation and an edit containing numbers/email/URLs, with one provider request per attempt.
- Selection → record → review → Apply changes only the selected text. Moving the cursor, changing text or switching editors leaves Copy-only recovery; no automatic message submission.
- No-network/401/timeout/cancel paths, explicit Retry, and Copy/Discard after an invalidated editor session.

On September 13, 2026, the development APK was installed over authorized USB on a physical ARM64 phone running Android 15/API 35 (ARM64). Settings launched successfully and populated the shared-core provider/mode catalog, confirming the packaged JNI/Swift libraries load on this phone. The IME registered and Android reported its input view shown. No app-scoped fatal error was observed during this initial check.

Automated typing was paused when the phone switched to another app; no real-message/draft test was performed. Gboard was restored as the default keyboard. Microphone permission was not yet granted. The user subsequently reported that the functionality they tested was working. Agent-controlled key insertion, audio capture, provider calls, review/replacement and lifecycle coverage remain incomplete; initial installation/core loading and user spot checks are not exhaustive validation.

### Keyboard UI device fixtures

`KeyboardDeviceChecks` is the single dependency-free Android instrumentation harness for native UI checks. Build it with the same storage guard:

```bash
python3 Scripts/build-android.py assembleDebug testDebugUnitTest lintDebug assembleDebugAndroidTest
```

After installing the matching app and test APKs on an authorized phone, run:

```bash
.build/android-tools/sdk/platform-tools/adb -s SERIAL shell am instrument -w app.chatterkey.android.test/app.chatterkey.android.KeyboardDeviceChecks
```

It renders the real keyboard views into synthetic, app-owned PNG fixtures at portrait, narrow/large-text, and landscape sizes; verifies key bounds, wide spacebar, symbol pages, stable mic position and processing controls; and loads the actual JNI core catalog. It does not open/edit another app, record audio, read credentials, or make provider requests. Instrumentation can restart ChatterKey, so do not run it during dictation or a pending edit. Fixture images are written to ChatterKey's private cache and can be deleted after inspection. These rendered fixtures are not live editor/provider validation.

On September 13, 2026, the `0.1.1-dev` UI build passed this harness on the connected ARM64 phone: 360 dp portrait, 320 dp with 1.3× font scale, and 640 dp landscape; both symbol pages; recording/processing layouts; key-label and text-height bounds; stable held-mic geometry; and native-core catalog loading. Device-rendered PNGs were visually inspected. These checks caught and fixed fractional-density mic movement, utility-key label clipping, and a large-text header overflow. The nine local unit tests and Android lint also passed. Live provider/audio behavior was not rerun by the harness.

On September 13, 2026, `0.1.2-dev` passed the same phone harness, plus Dashboard/Settings/Practice rendering at 360 dp and 320 dp with 1.3× font scale, settings save/tab preservation in isolated preferences, opt-in/private-field exclusions, aggregate/reset/revision checks, and a synthetic Hindi/English response through the actual JNI core word counter. Ten local unit tests, Android lint, APK signature/alignment checks and shared/Mac regression fixtures passed. The update was installed on the connected phone without changing its selected ChatterKey IME or the installed Mac app. Fixture data was isolated from user settings and counters. Live microphone/provider/editor flows were not rerun for this dashboard update.

### Signed 1.0.0 build verification — September 13, 2026

The optimized ARM64 release APK passed ten release unit tests, Android lint with no issues, the shared/Mac regression harness, APK signature and 16 KB ZIP/ELF alignment checks for all 19 native libraries, bundled-document checks, and a comparison with the private release identity's public certificate. The release verifier rejected the previous debug-signed APK. The JNI class/method and C export survived shrinking; the packaged DEX contains no device-fixture harness. The existing device harness compiled but was not installed or run. No phone install/uninstall/launch or live microphone/provider/editor test was performed for this handoff, and the installed Mac binary was unchanged. Manual clean-install and release-mode device validation remain the owner's next step.

### Signed installation follow-up

After explicit installation approval, a package conflict was traced to a leftover `0.1.2-dev` copy in a secondary profile even though the main-profile copy had been removed. Only ChatterKey was uninstalled, then the signed `1.0.0` release was installed in the main profile and launched successfully. No app-scoped fatal error was observed in that launch check. This supersedes the earlier no-install handoff status, but does not establish full live microphone/provider/editor validation. No device identifiers, real credentials or profile names are needed in public diagnostics.
