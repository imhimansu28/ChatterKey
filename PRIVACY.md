# Privacy

ChatterKey is a bring-your-own-key macOS dictation client. It has no ChatterKey account, analytics SDK, advertising SDK, or project-operated transcription server.

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

- **Microphone:** records dictation while the push-to-talk key is held.
- **Accessibility:** detects the global shortcut, reads explicitly selected text for Magic Voice Edit, and pastes replacements into the focused app.
- **Speech Recognition:** optionally creates an on-device rough transcript for the live preview. The selected cloud provider still produces the final text.

ChatterKey does not intentionally read documents, browser history, passwords, or unrelated keystrokes. The global event monitor only uses modifier/key state needed for push-to-talk and cancellation.

## Logging

The app does not intentionally log API keys, recorded audio, or transcript contents.

## Reporting a privacy issue

Please open a private security report through GitHub Security Advisories instead of posting sensitive details in a public issue.
