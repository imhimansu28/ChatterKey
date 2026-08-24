# Security Policy

## Reporting a vulnerability

Please use GitHub Security Advisories to report vulnerabilities privately. Do not include real API keys, private audio, transcripts, or personal data in public issues.

## Secret handling

- Never commit provider API keys, signing certificates, provisioning profiles, `.env` files, or exported Keychain data.
- API keys must remain in macOS Keychain.
- Use test credentials with minimal permissions when developing provider integrations.
- Revoke a key immediately if it is exposed in a commit, issue, screenshot, log, or release artifact.

## Supported versions

Security fixes are provided for the latest release on the default branch.
