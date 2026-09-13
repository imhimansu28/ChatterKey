# Privacy

ChatterKey provides a bring-your-own-key macOS dictation client and an Android keyboard, distributed in separate platform releases. The Mac behavior is described below; Android-specific handling is documented separately in this page. It has no ChatterKey account, analytics SDK, advertising SDK, or project-operated transcription server.

## Data that stays on the Mac

- Provider API keys are stored in macOS Keychain.
- Preferences such as provider, model ID, processing options, vocabulary, snippets, and custom system instructions are stored in `UserDefaults`.
- Dashboard records store local aggregate metadata such as date, provider/model names, word count, audio duration, estimated cost, and generated speaking suggestions. New suggestions do not quote arbitrary transcript phrases, and no audio is stored there. Older versions may have saved short repeated phrases inside suggestions; use **Dashboard → Clear Usage** to remove existing records.
- The last transcript exists in app memory for recovery and is not written to the repository or a project server.
- In the edit-review workflow, original/proposed text, highlights, and protected-value warnings are computed locally and held in memory. Apply or Copy can save the proposal to optional transcript history; Discard/window close clears the pending review without adding it to history. Discard does not reverse the provider request or its aggregate usage record.
- ChatterKey temporarily uses the clipboard to paste generated text and, when Accessibility selection attributes are unavailable, to try copying the selection at the start of dictation. It attempts to restore the previous clipboard contents. Selection behavior depends on the focused app.

## Recording controls

Holding the configured shortcut starts recording; releasing it finishes the attempt. With Fn selected, a quick double-tap instead keeps recording hands-free until Fn is pressed again, Stop & Process is used, or Escape cancels. A short first Fn tap includes a 350 ms grace period for double-tap recognition. Changing the shortcut or losing the event tap cancels an active recording. The overlay indicates hands-free recording; it does not automatically stop merely because the key has been released.

Audio processing still uses one model request per completed attempt. Locking/unlocking the recording does not introduce a second model request; cancelling before processing does not send the recording for model processing.

## Data sent to providers

When cloud processing is used, recorded audio and processing instructions—including the selected writing mode, custom system prompt, and relevant vocabulary—are sent from the Mac to the selected connection: directly to Google for Google Direct, or to OpenRouter for routing to its model host. Gemini 3.5 Flash-Lite is the default model. When Magic Voice Edit is active, the selected text and spoken instruction audio are included together in the same model request to create the replacement. The resulting transcript is returned directly to the app. Provider privacy, retention, regional processing, and training policies apply independently; users should review them before use.

The app pins Google Direct to `generativelanguage.googleapis.com` and OpenRouter to `openrouter.ai`, and rejects redirects. Each processing attempt sends one model request, with no automatic transcription fallback, repair request, or retry. Explicitly choosing Retry sends another request. Google, OpenRouter, and legacy provider keys stay in separate Keychain accounts and are never copied between connections. Model and cost-rate preferences are retained per connection; changing connections does not send a model request.

## Temporary audio

Audio is captured in a temporary local CAF file and converted to a 16 kHz mono WAV file in bounded chunks. ChatterKey deletes it after a successful request or cancellation. After a processing failure, it may retain the file temporarily for an explicit retry; it is removed after retry success, cancellation, a new recording, app exit, or the next app launch.

## Permissions

- **Microphone:** records during hold-to-talk or an explicitly started hands-free session until stopped or cancelled.
- **Accessibility:** detects the global shortcut, reads explicitly selected text for Magic Voice Edit, and pastes replacements into the focused app.
- **Speech Recognition:** optionally creates an on-device rough transcript for the live preview. The selected cloud provider still produces the final text.

ChatterKey does not intentionally read documents, browser history, passwords, or unrelated keystrokes. The global event monitor only uses modifier/key state needed for push-to-talk and cancellation.

## Logging

The app does not intentionally log API keys, recorded audio, or transcript contents.

## Android keyboard

- Android requests microphone and internet permissions and must be explicitly enabled as a keyboard. Normal key presses are inserted locally, not sent to a provider or used for silent learning. Voice is disabled in declared password fields and unsupported raw-input fields; correct field classification also depends on the host app.
- Holding the mic or double-tapping for hands-free records up to two minutes of 16 kHz mono WAV in memory. No audio file, transcript history or live-transcription service is implemented. Optional aggregate usage counters are described below. Cancel clears the active attempt; an explicit retry can retain failed audio in memory until cancellation or the editor session ends. Hiding/switching the keyboard cancels active recording/processing.
- A completed recording and configured prompt/vocabulary go to the selected provider using the same single-model request logic as the Mac. An edit also includes the explicitly selected text. Up to 64 nearby characters on either side are captured locally for insertion verification and are not added to the provider request. No screenshot or whole document is collected.
- Provider keys are encrypted with Android Keystore AES-GCM and stored as ciphertext in private preferences. Encryption binds each key to its provider. Google/OpenRouter model/settings and credentials remain separate; no keys are imported from the Mac. Settings such as prompts, vocabulary and snippets are ordinary local preferences, not separately encrypted. App backup is disabled, with explicit Android 12+ cloud/device-transfer exclusions.
- The settings window blocks normal screenshots and credential view-state/autofill storage. This does not protect against a compromised device or independently trusted accessibility services.
- Review data remains in process memory. Completed proposals may remain available for Copy after editor invalidation but cannot be applied into the new session. Apply, Copy and Discard clear the pending result; process death also loses recovery data. Discard or cancellation cannot undo provider processing already started.
- Only an explicit Copy action writes a generated result to the system clipboard, marked sensitive. Other apps/system clipboard features may still access or retain copied text; ChatterKey does not automatically erase or restore that copied result.
- Voice insertion uses the editor connection and never invokes Send/Enter. The keyboard's separately pressed manual action key may send a message when the host editor requests that action.

### Optional Android usage counters

Usage counting is **disabled by default**. The Dashboard opt-in enables local totals for estimated manually typed word runs, final dictation output words, successful dictations/voice edits, and successful-request audio duration. Only ChatterKey's accepted key taps contribute to typing estimates; no surrounding document is read for counting. Word-run state is a transient boolean, not stored text or a key sequence. Deletions/cursor edits are not reconciled against the document, so this is not a net document word count. Voice output is also not the exact spoken-word count.

Declared password fields, unsupported fields, and editors requesting Android's no-personalized-learning/private flag are excluded. ChatterKey's settings and practice editors request that flag too. Incognito recognition relies on the host editor marking the field; ChatterKey does not inspect app/browser contents to infer it.

A separate private preferences file stores numeric totals, local-date daily buckets, the consent toggle and a reset revision. It stores no text, audio, app identity, clipboard contents or per-attempt history. No new network request or telemetry is introduced. Daily buckets older than 30 days are pruned when new activity is counted; all-time totals remain until explicitly cleared. Backup exclusions apply to these preferences as well. Turning counting off retains existing totals; Clear Usage removes them without changing keys/settings and prevents pre-reset in-flight attempts from re-adding counts. There is no import or backfill of previous Android/Mac activity.

Installation and launch of the signed Android release were verified on one physical ARM64 phone. Live provider/editor behavior and lifecycle edge cases are not exhaustively validated. See `apps/android/README.md` for supported scope and the test checklist. Provider retention policies apply independently on both platforms.

## Reporting a privacy issue

Please open a private security report through GitHub Security Advisories instead of posting sensitive details in a public issue.
