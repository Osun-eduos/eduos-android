# Changelog

## [0.4.0] - 2026-11-26

### Added
- Inspector mode for school inspectors and LGA education officers: their schools, the inspection checklist with photos and notes, drafts that survive the app closing, and offline queuing with uploads that are safe to retry. Background sync sends waiting inspections too.
- Camera and photo library permission texts for iOS.

### Changed
- The local database is upgraded to version 2 (new inspection tables); existing data is kept.

## [0.3.0] - 2026-11-25

### Added
- Holidays from the snapshot: the register skips them and the home screen names today's holiday.

## [0.2.0] - 2026-11-25

### Added
- Background sync while the app is closed: Android WorkManager and iOS BGTaskScheduler, about every 30 minutes when online.
- Release signing from a private upload key (`scripts/create-upload-key.sh`, `android/key.properties`), also in CI through repository secrets.
- CI builds the APKs for the live servers when the `EDUOS_API_URL` and `EDUOS_SYNC_URL` repository variables are set.
- iOS project ready for building: background task registration, local networking for development, and `scripts/check-ios.sh`.

## [0.1.0] - 2026-11-25

### Added
- Flutter teacher app for Android and iOS: sign-in (with first-time password change), offline daily register, offline score entry one student per screen with live totals and grades, submit for approval, returned-sheet notes.
- Encrypted local database (SQLCipher) with a key generated on the phone and kept in the Android Keystore / iOS Keychain; sign-in tokens kept there too. Backups are switched off.
- Ordered offline queue synced through eduos-sync when a connection returns, on app open, every 10 minutes, and on demand; refused changes are shown to the teacher with the reason.
- Unit, widget and live end-to-end tests; CI that builds per-processor release APKs.
