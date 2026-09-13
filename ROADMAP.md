# ChatterKey product roadmap

macOS 5.0.0 and Android 1.0.0 are separate platform releases from one shared-core repository. Mac voice review/hands-free controls were already in v4.8.0; Android adds the native keyboard, settings/dashboard and signed APK. Signed Android USB installation/launch and earlier native debug fixtures passed, but neither platform claims exhaustive live provider/editor compatibility. Language/preferences work and larger typing features remain planned. There is no Windows implementation.

## Shared-core preparation — included in v4.8.0 (Mac only)

- Separate `apps/macos` (native application/resources/adapters) from `core/Sources/ChatterKeyCore` (Swift processing module). The root Swift package builds and links both targets.
- Share provider request/response logic, prompts, writing modes, text processing, edit warnings, value models and usage estimates. Inject settings and transport; accept WAV data rather than reading native files in the core.
- Keep native settings serialization/migrations, credential storage, microphone capture, live speech preview, Fn gestures, Accessibility/clipboard verification and recording/review lifecycle in the Mac app.
- Preserve existing settings/history formats and one-request behavior; validate the actual module boundary in the existing regression harness.
- The published v4.8.0 step was preparation, not proof of Android compatibility. Subsequent Android implementation was explicitly approved; it does not imply the planned language/preferences milestone is complete.

## 1. Reviewable voice edits — included in v4.8.0

- Show original/proposed text with local change highlighting before replacing selected text.
- Warn about detected numbers, email addresses, and HTTP(S)/www URLs whose values or occurrence counts differ. Require acknowledgement before Apply.
- Provide Apply to Original, Copy & Close, and Discard. Closing the review discards the pending edit.
- Recheck the original app, Accessibility field/range, and selected text before Apply. If verification fails or the app exposes insufficient information, retain the result for manual copying instead of guessing a destination.
- Keep ordinary dictation direct. Do not allow a new dictation/history insertion to silently replace a pending review.
- Keep review data in memory; save the proposed text to optional history only on Apply or Copy. Discard does not undo the provider request or its usage record.
- Keep comparison work bounded for long selections; display a changed-passage highlight when word-level comparison would be too expensive.

### Validation and remaining manual checks

- Run the existing provider/local regression script and debug/release builds with warnings treated as errors.
- Check the native preview at its minimum window size, long text, protected-value acknowledgement, and recovery states.
- Before claiming production readiness, manually exercise selection → recording → review → Apply/Copy/Discard in a supported native editor and browser editor. Also test changing fields, closing the original app, Escape/window close, repeated Apply, unchanged output, and history on/off.
- Check that Copy remains available after target verification fails and that review actions do not issue another provider request.
- Automated fixtures and off-screen rendering do not establish installed-app cross-application compatibility or live-provider quality.

## 2. Language and personal writing preferences — planned

1. **Hindi/Hinglish output controls:** natural Roman-script Hinglish, Hindi in Devanagari, English, and preserve-spoken-language behavior. Keep language and writing style choices explicit; preserve legacy mode settings when migrating.
2. **App-specific preferences:** opt-in writing/language presets keyed to application identity. No background reading of screens, messages, documents, or typed text.
3. **Approved corrections:** an explicit “Remember this correction” action building on the existing dictionary, with a reviewable list, removal, and app-specific exceptions. Do not silently learn from everything the user types.
4. **Attempt details:** preparation/provider/paste timing, connection/model, clearly labeled estimated cost, and an honest outcome. Keep metadata local and avoid storing original selected text in usage records.

Validate representative Hindi/Hinglish recordings before making accuracy claims. Local profile selection and instructions must still feed the same single model request.

## 3. Android keyboard — first signed release, 1.0.0

Approval on September 13, 2026 permits minimal CLI tools/JDK/SDK and a USB-authorized physical phone within a hard **10 GB total additional tools/cache/build budget**. No emulator, Android Studio or heavy IDE; keep the installed Mac app unchanged.

Implemented locally:

1. Native Java `InputMethodService` with basic typing and hold/double-tap microphone controls.
2. Cross-compiled ARM64 shared Swift core behind a narrow C/JNI bridge, with Android audio, HTTPS, settings and editor adapters.
3. One configurable audio model per attempt; Google Direct by default and separately configured OpenRouter optional. Retry stays explicit.
4. Selected-text review and protected-value warnings, guarded Apply, Copy and Discard, with editor-session cancellation and stale-result protection.
5. Android Keystore-encrypted provider credentials and a private test editor; no Mac settings/key migration or background text collection.

APK build, local unit/shared-core regressions, signing/alignment checks and lint are build-time checks only. Earlier debug APKs passed USB installation and native keyboard/dashboard/settings fixtures on a Motorola Edge 40 (Android 15/ARM64); the user reported their tested functionality working. The signed `1.0.0` APK adds release packaging, launcher branding, Dashboard/Settings/Practice, opt-in counters and bundled privacy/licenses. After a secondary-profile debug conflict was removed with authorization, release USB installation and launch passed. **Live release-mode microphone/provider/editor and lifecycle behavior still need broader validation.** The current scope does not include all Mac features or advanced keyboard behavior.

Next: complete the [physical-device test checklist](apps/android/README.md#validation-checklist), fix observed runtime issues, then evaluate explicit language controls, richer typing layouts and the other planned preferences. Publishing requires separate approval and release-signing/dependency-notice preparation. Do not expand tools beyond the approved storage cap.

## Constraints across milestones

- One configurable audio-capable model; one provider request per user attempt. No automatic retries, repairs, fallback models, or connection switches.
- Preserve settings/history migrations and isolate Google/OpenRouter credentials and model/rate preferences.
- Preview and value warnings are aids, not factual verification. Value counts do not detect semantic swaps; detection can miss unusual formats or flag intentional edits.
- No automatic cloud sync or third-party telemetry. Any future sync or extra data collection requires a separate design and explicit opt-in.
- Commit, push, release, and installed-app replacement remain separate, explicitly authorized operations.
