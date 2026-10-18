# Daftar

**Your life, in your pocket.** A personal, offline-first Android app: a wallet of
cards for prices, places, menus, calculations and money. Built with Flutter.

[![CI](../../actions/workflows/ci.yml/badge.svg)](../../actions/workflows/ci.yml)

## What's inside

- **Prices**: log what things cost and where, compare, and see the best option and why it won.
- **Places & menus**: stores, cafés and services on a map, with menus read from a photo (on-device OCR).
- **Calculator**: quick maths, baskets, best store, bill splitting, saved lists.
- **Accounts**: cash, cards, wallets, savings and USD accounts with rates, fees and summaries.
- **Bills, debts, nearby alerts, local backup/export.**

Everything works offline and data stays on the phone.

## Getting started

Requirements: Flutter (stable, Dart 3.13+) and the Android SDK.

```bash
flutter pub get
flutter run
```

The map needs a Google Maps key in `android/local.properties`
(`MAPS_API_KEY=...`), see [docs/GOOGLE_MAPS_SETUP.md](docs/GOOGLE_MAPS_SETUP.md).
Without it the app runs, but the map shows grey tiles.

After changing Drift tables, regenerate the database code:

```bash
dart run build_runner build
```

## Checks

```bash
dart format lib test
flutter analyze
flutter test
```

CI runs the same checks plus a debug APK build on every push and pull request.
Pushing a `v*` tag builds and publishes a signed release APK (see [docs/RELEASE.md](docs/RELEASE.md);
needs the `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` and `MAPS_API_KEY` repository secrets).

## Project layout

```
lib/
  app/       router, settings, app shell
  data/      Drift database, repositories, services (OCR, backup, reminders, ...)
  domain/    models and pure logic (money, best-offer scoring, basket, rates, ...)
  ui/        design system (ui/core) and one folder per feature
test/        mirrors lib/
docs/        data model, product notes, design references, release and store docs
```

## Docs

- [Product notes and decisions](docs/PRODUCT.md)
- [Data model](docs/DATA_MODEL.md)
- [Brand assets and license](assets/brand/LICENSE.md)
- [Release](docs/RELEASE.md), [privacy policy](docs/PRIVACY_POLICY.md)

## Credits

Fonts: Plus Jakarta Sans and IBM Plex Sans Arabic (SIL Open Font License, see `assets/fonts/OFL-*.txt`).
Maps by Google Maps. Product data from Open Food Facts.

## License

The source code is released under the [MIT License](LICENSE). The Daftar name, logo and
artwork in `assets/brand/` are **not** open source: all rights reserved, see
[assets/brand/LICENSE.md](assets/brand/LICENSE.md). Fonts keep their own OFL license.
