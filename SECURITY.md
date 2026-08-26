# Security Policy

## Reporting a vulnerability

Please use GitHub Security Advisories to report vulnerabilities privately. Do not include real API keys, private audio, transcripts, or personal data in public issues.

## Secret handling

- Never commit provider API keys, signing certificates, provisioning profiles, `.env` files, or exported Keychain data.
- API keys must remain in macOS Keychain.
- Use test credentials with minimal permissions when developing provider integrations.
- Revoke a key immediately if it is exposed in a commit, issue, screenshot, log, or release artifact.

## Provider endpoint safety

- OpenAI and OpenRouter requests are pinned to their official API hosts so a modified preference cannot redirect a provider key elsewhere.
- Custom providers must use HTTPS. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, and `::1` development endpoints.
- Provider redirects are rejected. Configure the final API base URL directly.
- A custom provider receives the configured API key, audio, prompts, and any selected text used by Magic Voice Edit. Only use endpoints you trust.

## Supported versions

Security fixes are provided for the latest release on the default branch.
