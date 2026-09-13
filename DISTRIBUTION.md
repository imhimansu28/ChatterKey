# Distribution checklist

The development script creates an ad-hoc signed app for local testing. Do not present that build as a trusted public macOS release.

## macOS 5.0.0 community-test download

- Version `5.0.0`, build `15`; macOS 14 or later.
- The published ZIP is built for Apple Silicon (`arm64`), not a universal Intel/Apple Silicon binary.
- Ad-hoc signed, not Developer ID signed, not hardened/notarized, and not verified on a clean Mac account. Gatekeeper may block it. Do not describe it as a trusted production release or disable system-wide security protections to install it.
- A SHA-256 checksum accompanies the ZIP to verify download integrity; it does not establish Apple approval or publisher identity.
- Release notes distinguish automated/mock validation from real-provider and cross-application testing.

## Platform releases

Keep one repository/core with independent tags: `macos-vX.Y.Z` and `android-vX.Y.Z`. Historical unprefixed tags are Mac releases. Publish platform-specific filenames, notes and checksums; source archives for either tag contain the shared repository, not just that platform. Use explicit download/tag links on the website rather than treating GitHub's single Latest release as a cross-platform update feed. Mark the Mac release Latest for historical compatibility and do not make the Android release replace that selection.

### Android 1.0.0

- Signed, non-debuggable ARM64 APK, Android 9/API 28+; version code 4. It is a direct APK download, not a Play Store submission.
- Run `python3 Scripts/build-android.py assembleRelease testReleaseUnitTest lintRelease` with the storage guard. Retain the existing private signing identity; no key generation or phone installation occurs during the build.
- Upload only the named APK and checksum. The public certificate fingerprint is in the release notes. Never upload `apps/android/signing/`, keystores/password properties, caches, device logs, fixture screenshots or debug/test APKs.
- Verify R8 keeps the JNI entry point and APK/native segments support 16 KB pages. The packaged Swift runtime and its dependencies require the bundled license notices.
- Initial signed-release USB installation/launch passed on one physical phone, but full live release-mode microphone/provider/editor and lifecycle coverage is incomplete. Disclose that scope rather than claiming universal production readiness.
- Document debug-to-release conflicts from other profiles and data loss on uninstall. Future same-key release updates must increase version code and preserve provider settings.

## Before publishing source

1. Run `./Scripts/check-public.sh`.
2. Review `git status --short` and every staged diff.
3. Confirm `.build/`, `dist/`, `.env`, certificates, provisioning profiles, local agent files, screenshots, test audio, and API keys are not tracked.
4. Enable GitHub secret scanning, push protection, private vulnerability reporting, and Dependabot alerts.
5. Publish `PRIVACY.md` and `SECURITY.md` with the repository.

## Before distributing trusted, notarized Mac binaries

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

- On Mac, hold-to-talk and Fn double-tap hands-free recording are both available; hands-free recording continues until stopped or cancelled.
- On Mac, Accessibility access is required for the global shortcut and automatic paste.
- Cloud mode sends audio and instructions to the selected connection: Google Direct or OpenRouter. Selected text is included only for Magic Voice Edit.
- Provider retention, training, and regional processing policies apply separately.
- ChatterKey does not operate an analytics or transcription backend in the current architecture.

## App Store considerations

If distributing through the Mac App Store, review sandbox restrictions for global event monitoring, Accessibility-driven paste, and custom provider networking before promising App Store availability. Direct Developer ID distribution may fit the current architecture better.
