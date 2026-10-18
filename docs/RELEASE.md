# Releasing Daftar to Google Play (step by step)

Written for someone who is not a developer. Do the steps in order. Things marked OWNER need your own accounts or secrets.

## 0. One-time setup

1. OWNER: Create a Google Play Developer account at https://play.google.com/console (one-time US$25 fee, identity verification can take days).
2. Install Flutter and Android Studio (already done on your dev machine if you can run the app).
3. Publish the privacy policy (docs/PRIVACY_POLICY.md) at a public web address. Easiest: push the repo to GitHub as a public repo and use the file's web link, or enable GitHub Pages.

## 1. Create your upload key (once, keep it forever)

This key proves updates come from you. If you lose it, Play can reset it, but it is a hassle. Never commit it, never email it.

Open a terminal and run (Windows PowerShell; keytool comes with Android Studio, in `C:\Program Files\Android\Android Studio\jbr\bin`):

```
keytool -genkey -v -keystore C:\Users\Amineos\daftar-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It asks you for a password (choose a strong one) and some name details (anything sensible). Remember the password.

BACK UP the .jks file and password in two places (for example a password manager and a USB stick).

Now create `android/key.properties` by copying `android/key.properties.example` and filling in:

```
storePassword=the password you chose
keyPassword=the same password (or the key password if different)
keyAlias=upload
storeFile=C:/Users/Amineos/daftar-upload-keystore.jks
```

(An absolute path with forward slashes is the least error-prone.) This file is git-ignored; it never gets uploaded.

Without key.properties the build still works but is signed with a debug key, which Play rejects. That fallback is only for local testing.

## 2. Maps key

The map needs a Google Maps API key in `android/local.properties` as `MAPS_API_KEY=...` (see docs/GOOGLE_MAPS_SETUP.md). In Google Cloud, restrict that key to package `com.amineos.daftar` and your signing key's SHA-1. For a Play-distributed app, also add the SHA-1 of the Play App Signing key (Play Console > Setup > App signing).

## 3. Set the version

In `pubspec.yaml`, `version: 0.1.0+1` means name 0.1.0, build number 1. Every upload to Play needs a higher build number than the last one (so 0.1.0+2, 0.1.1+3, ...).

## 4. Build the app bundle

From the project folder:

```
flutter clean
flutter pub get
flutter build appbundle --release
```

Result: `build/app/outputs/bundle/release/app-release.aab`. Optionally test the same build on your phone first with `flutter build apk --release` and install it.

## 5. Create the app in Play Console

1. Play Console > Create app. Name: Daftar. Language: English. App (not game). Free.
2. Complete the "Set up your app" tasks on the dashboard:
   - Privacy policy: paste your public URL.
   - App access, Ads (No), Content rating, Target audience, Data safety: use docs/DATA_SAFETY.md.
   - Store listing: use docs/STORE_LISTING.md, and upload the icon, feature graphic and screenshots.
3. Keep Play App Signing turned on (default). Your key from step 1 is the "upload key".

## 6. Upload to a testing track first

1. Testing > Internal testing > Create new release. Upload the `.aab`.
2. Add release notes ("First test build").
3. Testers tab: create an email list with your own Google account(s) and save.
4. Roll out, then open the opt-in link on your phone and install from Play.
5. Check the map, location, camera and barcode scan on the Play-installed build.

New personal developer accounts must run a Closed test with at least 12 testers for 14 days before they can apply for production. Plan for that: Testing > Closed testing, add testers, keep them opted in for 14 days.

## 7. Go to production

Production > Create new release > upload the same (or a newer) bundle > submit for review. First reviews can take several days.

## Updating later

Raise the build number, run step 4, upload to Internal testing, then promote the release to Production.

## Troubleshooting

- "Upload failed, signed with debug key": key.properties missing or the path in storeFile is wrong.
- Grey map: MAPS_API_KEY missing or not allowed for the signing key's SHA-1.
- "Version code already used": raise the number after `+` in pubspec.yaml.
