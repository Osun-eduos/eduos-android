# Changelog

## [0.1.0] - 2026-11-25

### Added
- Flutter teacher app for Android and iOS: sign-in (with first-time password change), offline daily register, offline score entry one student per screen with live totals and grades, submit for approval, returned-sheet notes.
- Encrypted local database (SQLCipher) with a key generated on the phone and kept in the Android Keystore / iOS Keychain; sign-in tokens kept there too. Backups are switched off.
- Ordered offline queue synced through eduos-sync when a connection returns, on app open, every 10 minutes, and on demand; refused changes are shown to the teacher with the reason.
- Unit, widget and live end-to-end tests; CI that builds per-processor release APKs.
