# Security Policy

## Reporting a vulnerability

Please use GitHub Security Advisories to report vulnerabilities privately. Do not include real API keys, private audio, transcripts, or personal data in public issues.

## Secret handling

- Never commit provider API keys, signing certificates, provisioning profiles, `.env` files, or exported Keychain data.
- Provider API keys stay in macOS Keychain or Android Keystore-encrypted private preferences; never embed a shared key in a binary.
- Use test credentials with minimal permissions when developing provider integrations.
- Revoke a key immediately if it is exposed in a commit, issue, screenshot, log, or release artifact.

## Android release identity

- Keep the release keystore and password properties in the ignored `apps/android/signing/` directory, outside disposable caches, with owner-only permissions and an encrypted backup. Never commit or attach them to a release.
- Release updates must retain the signing identity. Debug builds are not release updates; a leftover debug installation in any device profile can block a differently signed release APK.
- Public certificate fingerprints and download checksums may be distributed. Neither contains the private signing key; a checksum alone is not publisher authentication.
- Android usage counters are opt-in and aggregate-only. Do not collect typed text, audio, private drafts or real credentials for diagnostics. See [Privacy](PRIVACY.md).

## Provider endpoint safety

- Processing requests are pinned to the selected connection’s official host: `generativelanguage.googleapis.com` for Google Direct and `openrouter.ai` for OpenRouter. A modified base URL preference cannot redirect a provider key elsewhere.
- Legacy OpenAI/custom provider configurations are not accepted by the single-model client. Migration and connection switching never copy API keys between Google, OpenRouter, or legacy provider accounts.
- Provider redirects are rejected.
- The selected model receives audio, prompts, and any selected text used by Magic Voice Edit in one request. Only use models and hosting providers you trust.

## Supported versions

Security fixes target the latest macOS and Android release lines on the default branch. Platform tags use `macos-vX.Y.Z` and `android-vX.Y.Z`; older unprefixed tags are historical Mac releases. There is no Windows build.
