# eduos-android

**Offline-first Android app for Osun EduOS teachers and inspectors.**

Part of [Osun EduOS](https://github.com/Osun-eduos/osun-eduos), the open-source education management and intelligence system for Osun State. The iOS app lives in [eduos-ios](https://github.com/Osun-eduos/eduos-ios); both apps follow the same behaviour and talk to the same [eduos-api](https://github.com/Osun-eduos/eduos-api) sync service.

> **Status: planned.** No code yet. The intended behaviour is shown in the **Score entry (mobile app)** screen of the [web prototype](https://osun-eduos.pages.dev/#mobile).

## Why a mobile app

Many schools have unreliable internet. Teachers need to enter scores and take attendance wherever they are, and inspectors need to record findings on site. The app works fully offline and syncs when a connection returns. Android is the priority platform because most teachers in the state use Android phones.

## Scope

- **Score entry**: one student per screen, large number fields, live totals and grades, validation against the assessment setup.
- **Attendance**: daily register by class.
- **Inspections**: facilities checklist, findings and GPS location of the school.
- **Offline queue**: every change is stored as an event in an encrypted local database and sent in order when online.
- **Sync**: talks to the sync endpoints in [eduos-api](https://github.com/Osun-eduos/eduos-api); shows clearly what is waiting to sync and any conflicts.
- **Security**: device-generated encryption key that never leaves the phone; data cleared on sign-out.

## Device targets

- Android 8.0 (API 26) and newer, including low-cost phones with 2 GB of RAM.
- Small download size and low data use.
- Works on 2G/3G and with intermittent connections.

## Proposed stack

| Concern | Proposal |
| --- | --- |
| Language and UI | Kotlin with Jetpack Compose |
| Local storage | Room on SQLite with SQLCipher encryption |
| Background sync | WorkManager with retry and back-off |
| Networking | Retrofit or Ktor client against the eduos-api OpenAPI spec |
| Auth | OpenID Connect (AppAuth) with tokens protected by the Android Keystore |
| Distribution | Google Play, plus a signed APK for schools that install directly |

## Contributing

See the organisation-wide [contributing guide](https://github.com/Osun-eduos/.github/blob/main/CONTRIBUTING.md). Test only with fictional data. Behaviour changes that affect both mobile apps start as an issue in [osun-eduos](https://github.com/Osun-eduos/osun-eduos).

## Licence

[GNU Affero General Public License v3.0](LICENSE).
