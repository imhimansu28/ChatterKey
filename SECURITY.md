# Security Policy

## Reporting a vulnerability

Please use GitHub Security Advisories to report vulnerabilities privately. Do not include real API keys, private audio, transcripts, or personal data in public issues.

## Secret handling

- Never commit provider API keys, signing certificates, provisioning profiles, `.env` files, or exported Keychain data.
- API keys must remain in macOS Keychain.
- Use test credentials with minimal permissions when developing provider integrations.
- Revoke a key immediately if it is exposed in a commit, issue, screenshot, log, or release artifact.

## Provider endpoint safety

- Processing requests are pinned to the official OpenRouter API host so a modified preference cannot redirect the API key elsewhere.
- Legacy OpenAI/custom provider configurations are not accepted by the single-model client. Migration never copies their API keys to OpenRouter.
- Provider redirects are rejected.
- The selected model receives audio, prompts, and any selected text used by Magic Voice Edit in one request. Only use models and hosting providers you trust.

## Supported versions

Security fixes are provided for the latest release on the default branch.
