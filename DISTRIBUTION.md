# Distribution checklist

The development script creates an ad-hoc signed app for local testing. Do not present that build as a trusted public macOS release.

## Before publishing source

1. Run `./Scripts/check-public.sh`.
2. Review `git status --short` and every staged diff.
3. Confirm `.build/`, `dist/`, `.env`, certificates, provisioning profiles, local agent files, screenshots, test audio, and API keys are not tracked.
4. Enable GitHub secret scanning, push protection, private vulnerability reporting, and Dependabot alerts.
5. Publish `PRIVACY.md` and `SECURITY.md` with the repository.

## Before distributing binaries

1. Join the Apple Developer Program.
2. Replace ad-hoc signing with a Developer ID Application certificate.
3. Enable the hardened runtime and use the minimum required entitlements.
4. Archive the app, sign every executable, and verify the signature.
5. Submit the build to Apple notarization and staple the notarization ticket.
6. Test the stapled build on a clean Mac user account.
7. Publish checksums for release downloads.
8. Keep provider keys user-supplied; never embed a shared production key in the app.

## Product disclosures

The onboarding and release page should clearly explain that:

- Microphone access records only during push-to-talk.
- Accessibility access is required for the global shortcut and automatic paste.
- Cloud mode sends audio directly to the selected third-party provider.
- Provider retention, training, and regional processing policies apply separately.
- ChatterKey does not operate an analytics or transcription backend in the current architecture.

## App Store considerations

If distributing through the Mac App Store, review sandbox restrictions for global event monitoring, Accessibility-driven paste, and custom provider networking before promising App Store availability. Direct Developer ID distribution may fit the current architecture better.
