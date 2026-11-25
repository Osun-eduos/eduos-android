# eduos-mobile

**Osun EduOS teacher app for Android and iOS, built with Flutter.**

Part of [Osun EduOS](https://github.com/Osun-eduos/osun-eduos), the open-source education management and intelligence system for Osun State. The app syncs through [eduos-sync](https://github.com/Osun-eduos/eduos-sync), and teachers sign in with the same account they use on the [EduOS website](https://github.com/Osun-eduos/eduos-web).

## What teachers can do

- **Take the daily register** for their class: one tap per student (present, late, absent, excused), with an optional reason, and "mark everyone present". They can correct the last 7 school days, the same rule as the website.
- **Enter scores** for the subjects they teach, one student per screen with large number fields. The total and grade update as they type, and marks outside the allowed range are flagged at once.
- **Submit scores for approval**, and see the school administrator's note if a sheet is returned.
- **Work without internet.** Everything is saved on the phone first and sent automatically when a connection returns. The home screen always shows what is still waiting to be sent.

If the server refuses a change (for example, results have already been released), the teacher sees a plain message saying what was refused and why.

## How it works offline

1. When online, the app downloads the teacher's **snapshot** from eduos-sync: the current term and score split, their classes and rolls, the last 14 days of registers, their subjects' score sheets, and the grading scales.
2. Every register or score change is saved as a **draft** on the phone and added to an **outbox** with its own ID. Drafts show immediately on screen.
3. The outbox is sent **in order**:
   - when the app opens or comes back to the foreground;
   - when the phone reconnects;
   - every 10 minutes while the app is open;
   - when the teacher pulls down or taps sync.
4. eduos-sync applies each change **exactly once**, through eduos-api, so the school rules are always checked on the server too. A fresh snapshot then replaces the drafts it confirms.

## Security

- **Encrypted storage:** all school data on the phone is in an **SQLCipher-encrypted database**. Its key is generated on the phone the first time the app runs and is kept in the **Android Keystore / iOS Keychain**. It never leaves the device.
- **Sign-in tokens** are kept in the Keystore / Keychain too. The short-lived access token is refreshed automatically, and the app asks the teacher to sign in again only when the refresh token expires or is revoked. Unsent changes are kept until they do.
- **No backups:** Android cloud backup and device-to-device transfer are switched off for the app's data.
- **HTTPS only in release builds.** Development builds may use plain HTTP to reach a local server.
- **Signing out** deletes the school data from the phone, after warning if any changes have not been sent.

## Build and run

You need Flutter 3.47 (stable) and, for Android, Java 17 and the Android SDK.

```sh
flutter pub get
flutter run                     # debug build on a connected phone or emulator
flutter test                    # unit and widget tests
flutter build apk --release --split-per-abi \
  --dart-define=API_URL=https://api.example.ng \
  --dart-define=SYNC_URL=https://sync.example.ng
```

Without `--dart-define`, the app points at a development machine as seen from the Android emulator (`10.0.2.2`). The server addresses can also be changed on the sign-in screen under **Server settings**, which is useful for pilots.

`--split-per-abi` makes one APK per phone type (about 18 to 22 MB each). Most low-cost phones need `armeabi-v7a` or `arm64-v8a`. For the Play Store, build an app bundle instead (`flutter build appbundle`). The release build is currently signed with the debug key; add a release keystore before publishing.

iOS builds need a Mac with Xcode: `flutter build ios`.

## Tests

| Test | Covers |
| --- | --- |
| `test/rules_test.dart` | Register dates and the 7-day window, rolls by admission date, mark limits, totals, grading by level and the term's SSS setting |
| `test/sync_engine_test.dart` | Ordered upload, exactly-once removal from the queue, refused changes and notices, retries, offline, token refresh, sign-in expiry, batching |
| `test/screens_test.dart` | Taking a register offline, entering scores one student at a time with a wrong mark, released results being locked |
| `test/integration/live_test.dart` | The real app code against a running eduos-api and eduos-sync (skipped unless `EDUOS_LIVE=1`) |

The live test signs in a teacher, takes a register, enters and submits scores, sees a refused change, and sees a returned sheet. It needs the walkthrough data from eduos-api.

## Layout

| Path | Holds |
| --- | --- |
| `lib/main.dart` | Start-up, the encrypted database, sync triggers |
| `lib/src/app_state.dart` | What the screens show and the actions teachers take |
| `lib/src/rules.dart` | School rules checked offline (the server checks them again) |
| `lib/src/sync/` | The sync engine |
| `lib/src/store/` | Encrypted local store and secure key storage |
| `lib/src/net/` | Calls to eduos-api and eduos-sync |
| `lib/src/ui/` | Screens |

## Contributing

See the [contributing guide](https://github.com/Osun-eduos/.github/blob/main/CONTRIBUTING.md).

## Licence

[GNU Affero General Public License v3.0](LICENSE).
