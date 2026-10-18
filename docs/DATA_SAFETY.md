# Play Console "Data safety" answer sheet

Based on the current app (permissions: internet, coarse/fine location, camera). Re-check if features change. Definitions follow Google's form: "collected" means data leaves the device to us or a third party we use for our own purposes.

## Overview questions
| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | See rows below. Our own servers receive nothing. Conservative answer: declare Approximate and Precise location as collected (see note), everything else No. |
| Is all user data encrypted in transit? | Yes (all outside services are used over HTTPS) |
| Do you provide a way for users to request data deletion? | Not applicable: data exists only on the device; uninstalling deletes it. Choose the option stating no data is collected/stored off-device if offered, otherwise explain this in the free text. |

## Data types
| Data type | Collected | Shared | Notes |
|---|---|---|---|
| Approximate location | Yes (conservative) | No | Read on device for "I'm here" and distance. Not sent to us. Google Maps SDK may process location-related requests. Optional. Purpose: App functionality. |
| Precise location | Yes (conservative) | No | Same as above. Optional, user can deny. |
| Personal info (name, email, address, etc.) | No | No | No accounts. |
| Financial info | No | No | |
| Health and fitness | No | No | |
| Messages | No | No | |
| Photos and videos | No | No | Stay on device; text recognition is on-device. |
| Audio | No | No | |
| Files and docs | No | No | |
| Calendar / Contacts | No | No | |
| App activity (search history in app, interactions) | No | No | Searches typed into address search are sent to Nominatim only to get results; not stored by us. |
| Web browsing | No | No | |
| App info and performance (crashes, diagnostics) | No | No | No crash reporting SDK. |
| Device or other IDs | No | No | No advertising ID used. |

Note on location: Google's form lets you skip "collected" for data processed only on-device. Location here is processed on-device, so "No" is defensible. Declaring it is the cautious choice because the Maps SDK is included; either is acceptable, but be consistent with the privacy policy.

## Third-party services to know about
- Google Maps SDK (map tiles): Google's own data practices apply.
- Nominatim / OpenStreetMap (address search text).
- Open Food Facts (barcode number only).

## Other Play Console declarations
- Ads: No ads.
- App access: all functionality available without login.
- Target audience: 13+ / general audience, not designed for children.
- Content rating: complete the questionnaire; expected "Everyone".
- Permissions declaration: location is foreground-only (no background location). Camera is optional (hardware not required).
- News app / government / financial features: No.
