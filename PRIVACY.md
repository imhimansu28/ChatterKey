# Privacy

ChatterKey is a bring-your-own-key macOS dictation client. It has no ChatterKey account, analytics SDK, advertising SDK, or project-operated transcription server.

## Data that stays on the Mac

- Provider API keys are stored in macOS Keychain.
- Preferences such as provider, model IDs, processing options, vocabulary, snippets, and custom system instructions are stored in `UserDefaults`.
- Dashboard records store local aggregate metadata such as date, provider/model names, word count, audio duration, estimated cost, and generated speaking suggestions. They do not store transcript text or audio.
- The last transcript exists in app memory for recovery and is not written to the repository or a project server.
- ChatterKey temporarily uses the clipboard to paste generated text, then attempts to restore the previous clipboard contents.

## Data sent to providers

When cloud processing is used, recorded audio and processing instructions—including the selected writing mode, custom system prompt, and relevant vocabulary—are sent directly from the Mac to the provider selected by the user, such as OpenAI or OpenRouter. When Magic Voice Edit is active, the selected text is also sent to that provider so it can create the requested replacement. The resulting transcript is returned directly to the app. Provider privacy, retention, regional processing, and training policies apply independently; users should review them before use.

Custom provider URLs receive the same request data. Only configure providers you trust. Custom cloud endpoints must use HTTPS; local development endpoints may use HTTP only on localhost. OpenAI and OpenRouter requests use fixed official API hosts.

## Temporary audio

Audio is recorded to a temporary local WAV file. ChatterKey deletes it after a successful request or cancellation. After a processing failure, it may retain the file temporarily for an explicit retry; it is removed after retry success, cancellation, a new recording, or the next app launch.

## Permissions

- **Microphone:** records dictation while the push-to-talk key is held.
- **Accessibility:** detects the global shortcut, reads explicitly selected text for Magic Voice Edit, and pastes replacements into the focused app.
- **Speech Recognition:** optionally creates an on-device rough transcript for the live preview. The selected cloud provider still produces the final text.

ChatterKey does not intentionally read documents, browser history, passwords, or unrelated keystrokes. The global event monitor only uses modifier/key state needed for push-to-talk and cancellation.

## Logging

The app does not intentionally log API keys, recorded audio, or transcript contents.

## Reporting a privacy issue

Please open a private security report through GitHub Security Advisories instead of posting sensitive details in a public issue.
