# Google Maps setup

Daftar's maps use the official `google_maps_flutter` plugin (Android only). This replaced flutter_map / OpenStreetMap / CARTO on 2026-10-17. The API key is
**never committed**; it lives in `android/local.properties`, which is git-ignored.

## 1. Create the key

1. Open the [Google Cloud console](https://console.cloud.google.com/) and create (or pick) a project.
2. Link a billing account. Maps SDK for Android has a free monthly allowance for mobile map
   loads, but Google requires billing to be enabled.
3. **APIs & Services > Library**: search for **Maps SDK for Android** and click **Enable**.
4. **APIs & Services > Credentials > Create credentials > API key**.
5. Click the new key to restrict it:
   - **Application restrictions**: Android apps.
   - Add an item: package name `com.amineos.daftar` and the **SHA-1** of the signing key.
     - Debug key (Windows): `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android`
     - Release builds use their own keystore, add its SHA-1 too (Play App Signing has its own SHA-1 in the Play Console).
   - **API restrictions**: restrict to **Maps SDK for Android**.
6. Optional but wise: **Quotas** > set a daily cap so a leaked key cannot run up a bill.

## 2. Paste it

Add one line to `android/local.properties` (create the file if needed; Flutter already writes
`sdk.dir` and `flutter.sdk` there):

```properties
MAPS_API_KEY=AIza...your key...
```

`android/app/build.gradle.kts` reads it and injects it into `AndroidManifest.xml` as
`<meta-data android:name="com.google.android.geo.API_KEY" android:value="${MAPS_API_KEY}"/>`.
If the line is missing the value is an empty string: the app still builds and runs, and the
map shows Google's grey "for development purposes only" tiles. That is expected until a key is set.

Rebuild after changing it (`flutter run` / `flutter build apk --debug`); a hot restart is not enough.

## 3. How the app uses the maps

- Dark theme uses a style JSON (`lib/ui/features/map/views/map_dark_style.dart`).
- Markers (price pins, places, clusters, your position, the drop pin) are Daftar's own pictures
  drawn once into bitmaps and cached. Clustering is Daftar's own (`pin_clustering.dart`).
- Previews in the place form use Android **lite mode** (a static image, cheap in lists).
- Google's logo and copyright stay visible (required by the terms); do not cover them.
- "Directions" still opens the Google Maps app (`directions.dart`).
- Widget tests never create the platform map: they override `mapViewBuilderProvider`
  (see `test/ui/features/map/fake_map_view.dart`).

## 4. Troubleshooting

| Symptom | Cause |
|---|---|
| Grey tiles with "for development purposes only" | No key, wrong package / SHA-1, or Maps SDK for Android not enabled |
| Map is blank white | The key is restricted and the SHA-1 of the build you run is not listed |
| Works on debug, not on release | Add the release (or Play signing) SHA-1 to the key |
