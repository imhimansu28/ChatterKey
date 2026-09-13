# ChatterKey product roadmap

The v4.8.0 community-test release includes the Mac/core separation and reviewable voice edits below. Language/preferences and Android remain future milestones, in that order. Published test builds do not establish universal cross-application compatibility.

## Shared-core preparation — included in v4.8.0 (Mac only)

- Separate `apps/macos` (native application/resources/adapters) from `core/Sources/ChatterKeyCore` (Swift processing module). The root Swift package builds and links both targets.
- Share provider request/response logic, prompts, writing modes, text processing, edit warnings, value models and usage estimates. Inject settings and transport; accept WAV data rather than reading native files in the core.
- Keep native settings serialization/migrations, credential storage, microphone capture, live speech preview, Fn gestures, Accessibility/clipboard verification and recording/review lifecycle in the Mac app.
- Preserve existing settings/history formats and one-request behavior; validate the actual module boundary in the existing regression harness.
- This step is preparation, not Android implementation or proof of Android compatibility. Do not create an Android app, install Kotlin/Android tools, or introduce a mobile bridge without renewed approval. Other roadmap milestones retain their order.

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

## 3. Android keyboard — approval required before starting

Do not install Android SDKs, Android Studio, Gradle distributions, emulator images, or start Android implementation until the user approves the plan and resource budget.

Before asking for approval:

1. Read this Mac's available storage, RAM, CPU architecture, and any existing Java/Android tools without installing anything.
2. Ask about the phone's Android version, USB availability, desired language/layout, and whether a physical phone can be used for testing.
3. Present a short staged plan: basic typing keyboard → hold-to-dictate with one audio-model request → language/style and edit preview → explicit correction storage.
4. Give a current storage/RAM estimate broken down into required downloads, installed tools, dependency/build caches, and free-space headroom. Distinguish official requirements from estimates; check current official documentation before quoting numbers.
5. Prefer a minimal command-line build and a USB-connected physical phone if supported by the available system resources. Treat an emulator as optional, not a prerequisite.
6. Wait for explicit permission before setup or implementation. USB installation/testing also requires the user's authorized device connection.

## Constraints across milestones

- One configurable audio-capable model; one provider request per user attempt. No automatic retries, repairs, fallback models, or connection switches.
- Preserve settings/history migrations and isolate Google/OpenRouter credentials and model/rate preferences.
- Preview and value warnings are aids, not factual verification. Value counts do not detect semantic swaps; detection can miss unusual formats or flag intentional edits.
- No automatic cloud sync or third-party telemetry. Any future sync or extra data collection requires a separate design and explicit opt-in.
- Commit, push, release, and installed-app replacement remain separate, explicitly authorized operations.
