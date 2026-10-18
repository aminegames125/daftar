# Daftar: product notes

What the app is, the decisions behind it, and the feature spec.

## 1. Product summary

Daftar is a "wallet for life": a home screen made of stacked wallet **cards**,
each a feature. It is offline, private and costs $0 to run.

| Card | One-liner |
|---|---|
| Prices | Log what things cost and where; always know the best option. |
| Places | Stores, cafés, services on a free map, with everything about them. |
| Menus | Menus and price lists of venues; photo + on-device text reading. |
| Calculator | Quick → Basket → Best store → Split bill; saved lists. |
| Accounts | Cash, cards, D17, Flouci, savings, USD accounts, rates, fees, totals. |
| Bills & subscriptions | Due dates and reminders. |
| Debts & loans | Who owes whom, including "I owe myself" (borrowing from savings). |

---

## 2. Decisions

| # | Topic | Decision |
|---|---|---|
| D1 | Name | **Daftar** (دفتر). Tagline "Your life, in your pocket." |
| D2 | Palette | **C**: near-black + electric lime, "modern fintech". |
| D3 | Theme | Light **and** dark; **dark is the default**; switch in settings. |
| D4 | Logo | **B · Dal**: one lime stroke forming the Arabic letter د. |
| D5 | Personality | **Premium & calm.** Lime only for key actions. |
| D6 | Motion | Rich spring-based motion, used per moment, not all at once. |
| D7 | UI style | **2026 floating UI**: floating glass nav pill + attached lime "+", floating action toolbar on detail pages (never both), floating sheets/toasts, glass only on floating surfaces. |
| D8 | UI language | **English only.** User content in any language (Arabic RTL supported). |
| D9 | Currency | Prices in **TND only** (3 decimals). Accounts may be **TND or USD**. |
| D10 | Users | **Just the owner** for now. May go public later. |
| D11 | Storage | **Phone only** for now; cloud sync later → schema is sync-ready. |
| D12 | App lock | **Optional** fingerprint/PIN lock, off by default; hide content in recents when locked. |
| D13 | Unit size | **Optional** size (g, kg, ml, L, pc). If present, compare per unit; else raw price. |
| D14 | Best option | **Smart score**: unit price + freshness + distance, with "why it won" reasons. |
| D15 | Stale price | Older than **3 months** = "old" (faded, trusted less). Configurable. |
| D16 | History | Keep **every** price entry; chart per store; "+12% since March" labels. |
| D17 | Promos | Promo flag + optional **end date**; auto-expires from scoring. No deal types (buy 2 get 1). |
| D18 | Adding products | **Type with autocomplete** + optional **barcode** scan (Open Food Facts autofill). |
| D19 | Categories | **Starter set + editable**, with icons. |
| D20 | Variants | **Product + variants** (Milka → Oreo / Noisette). Size via the size field. |
| D21 | Global prices | Not linked to a store; any kind (reference/fair, seen somewhere, official) via **user-editable type labels**. |
| D22 | Ranges | Single value by default; optional **min–max range** toggle on any price. |
| D23 | Adding a place | **GPS "I'm here" + drop/move pin + address search**; location optional (online shops). |
| D24 | Place info | Phone, opening hours (open-now badge), photos, notes, personal rating + quick tags, Wi-Fi name/password, accepted payment methods. |
| D25 | Place kinds | **Shop** (supermarkets etc.) → **Products** tab (barcode, variants, sizes). **Venue** (cafés, restaurants, services) → **Menu / Price list** tab. The place *type* decides the kind. |
| D26 | Map | Search results as **price pins**; best glows lime; stale faded; List/Map toggle. Pins merge/split when zooming. |
| D27 | Map engine (changed 2026-10-17: Google Maps replaces flutter_map/OSM) | `google_maps_flutter` (Android). Google caches viewed tiles itself; no region downloads. The earlier "no Google Maps" decision is overridden. Key: `docs/GOOGLE_MAPS_SETUP.md`. |
| D28 | Nearby alerts | **Later**, not v1 (background location). |
| D29 | Menu entry | Photo is kept; **OCR auto-read with review** AND manual entry. If OCR is unreliable (low confidence, Arabic, blur) show "Better to type it yourself". |
| D30 | Menu detail | Sections, sizes/options with own prices, ⭐ usual order, cross-place comparison ("capucin" at every café). |
| D31 | Calculator | One screen, mode chips ordered **Quick → Basket → Best store → Split**. Must stay simple: split is **equal by default**, by-item optional. |
| D32 | Saved lists | Baskets can be saved and reused; show current best store + total; check off while shopping. |
| D33 | Accounts | Payment methods with balances; **multi-currency** (TND/USD). Paying a TND price from a USD account asks for **today's rate** (prefilled with the last one) + **fee** → effective rate. Every rate saved → **rate chart**. Each special account type gets its **own calculator**. |
| D34 | Account extras | Fees/commission, average buy rate + gain/loss, reverse calculator, exchange log (who/where, amount, rate, fee, note), pay directly in USD, summaries by day/week/month/year, savings accounts. |
| D35 | Totals | Total TND and Total USD **separately**, plus tap-to-reveal "≈ all in TND" at last rate; toggle to include/hide savings. |
| D36 | Price ↔ expense | Logging a price is a note; optional **"I bought it"** toggle + account picker turns it into an expense. |
| D37 | Future cards | Bills & subscriptions; Debts & loans incl. "I owe myself". |
| D39 | Platform | Android only, minSdk **24**, package `com.amineos.daftar`. |

---

## 3. Feature spec

### 3.1 Places
- Place types (editable list, each with icon + kind `shop|venue`). Starter set:
  Supermarket, Grocery, Bakery, Pharmacy, Butcher, Electronics (shops);
  Café, Restaurant, Fast food, Hairdresser, Car wash, Gym, Service (venues).
- Add place: name, type, location by **GPS** / **pin** / **search** (Nominatim,
  1 request/second max, descriptive User-Agent), address, phone, weekly opening
  hours, Wi-Fi name + password (copy button), payment methods
  (Cash, Card, D17, Flouci, e-Dinar, Bank transfer — editable), rating 1–5
 , quick tags (Clean, Cheap, Quiet, Good Wi-Fi, Slow service…),
  notes, photos.
- Place page: collapsing header, open-now badge, floating action toolbar
  (Call · Directions · Copy Wi-Fi · **Log price**).
  Tab "Products" (shop) or "Menu"/"Price list" (venue), "History", "Notes".

### 3.2 Products & prices
- Product: name, brand?, category, photo; **variants** (name, barcode?, size value + unit).
- **Log a price** screen (see brand board): product (autocomplete + scan),
  variant chips, size (optional) + unit segmented control, price input (big,
  tabular; calculator button), **range toggle**, where: place picker *or*
  **Global** (with a type label), promo toggle + end date, "I bought it" toggle
  photo, note.
  Shows "= 44.000 TND / kg" live when size is set.
- Price history: every entry kept; per-store chart, change labels
  (coral up / lime down,).
- Stale (> threshold) prices are faded (40% opacity) and labelled "old".
- Expired promos are excluded from scoring automatically.

### 3.3 Menus
- Venue menu: sections → items → options (e.g. S 3.200 / L 4.000). Each option
  price is a price entry (so history works).
- ⭐ "Your usual" items shown at the top of the place page.
- Snap a menu: camera/gallery photo → ML Kit Latin text recognition → parsed
  lines "name … price" → review screen to fix/confirm → saved. Photo is always
  kept. If average confidence is low, text looks Arabic, or the image is blurry,
  show "This one's hard to read. Typing it yourself will be more accurate."
- Cross-place compare: searching "capucin" ranks every venue's capucin.

### 3.4 Search & best option
- One search box (bottom-first, thumb reach) across products, variants, menu
  items, places. Accent/diacritic-insensitive (see DATA_MODEL § Search).
- Result for a product/item: **Best option** card (lime chip) with reasons,
  then other offers. List/Map toggle (map = price pins).
- Algorithm: `docs/DATA_MODEL.md § Best-option score`.

### 3.5 Map
- **Google Maps** (`google_maps_flutter`, Android only; changed 2026-10-17,
  replaces flutter_map + OSM/CARTO). Dark theme = map style JSON
  (`map_dark_style.dart`); light = Google default. Google's logo stays visible.
- API key from `android/local.properties` (`MAPS_API_KEY`), never committed:
  `docs/GOOGLE_MAPS_SETUP.md`. No key = grey "for development" tiles.
- Markers are bitmaps drawn from Daftar visuals and cached; clustering is our own
  (`pin_clustering.dart`). Previews in forms use lite mode.
- Widget tests never create the platform map: `mapViewBuilderProvider` is
  overridden with a placeholder.
- Price pins (best = lime glow, stale faded, promo amber outline), clustering
 , "I'm here" radar while locating, place drop.

### 3.6 Settings & lock
- Theme (System / Dark / Light) with circular reveal, stale threshold,
  default unit, manage categories / place types / payment methods / global types.
- Optional app lock (local_auth: fingerprint/face/PIN). Requires
  `MainActivity` to extend `FlutterFragmentActivity`. When locked, hide content
  in recents (FLAG_SECURE via a tiny platform channel). Lock screen uses
  breathe, PIN entry, fingerprint.

### 3.7 Calculator
- Mode chips in this order: **Quick → Basket → Best store → Split**.
- Quick: normal calculator; result can be inserted into any price field.
- Basket: items × quantity at a chosen place → total.
- Best store: same basket across all places; also "cheapest split" (buy X at A,
  Y at B) as an optional view.
- Split: equal split by default ("42.000 ÷ 4 = 10.500 each"); "by item" optional.
- Saved lists ("Monthly groceries"): reopen to see current best store + total;
  check off while shopping.

### 3.8 Accounts
- Account types: Cash, Card, Wallet (D17/Flouci/…), Bank, **Savings** (quiet,
  low activity), **Foreign currency** (USD). Name, colour, last 4 digits,
  opening balance, include-in-totals toggle.
- Transactions: expense, income, transfer, exchange (USD↔TND), adjustment.
- Pay a TND price from a USD account: ask rate (prefilled last), fee (% or
  fixed) → effective rate → deduct USD. Can also pay directly in USD.
- Every rate saved → rate chart per account; average buy rate; gain/loss vs
  current rate; reverse calculator ("I need 500 TND, how many USD?").
- Exchange log with who/where, amount, rate, fee, note.
- Summaries by day/week/month/year per account.
- Totals: TND and USD separately; tap to reveal "≈ all in TND"; savings toggle;
  hide-amounts eye.

### 3.9 Later
- Bills & subscriptions with reminders — STEG, SONEDE, internet, top-ups, Netflix (USD).
- Debts & loans, incl. "I owe myself" (borrowed from savings, tracked until repaid).
- Nearby alerts (background location, opt-in).
- Cloud sync (Supabase/Firebase free tier), backup/export.
- Play Store release (privacy policy, signing, store listing).

---

## 4. Risks & open questions

- **Google Maps terms/quota**: restrict the key to the package + SHA-1 and set a quota cap (`docs/GOOGLE_MAPS_SETUP.md`).
- **Open Food Facts** wants a User-Agent with a contact → decide before release.
- **ML Kit Arabic**: Latin model only; Arabic menus fall back to manual entry (by design, D29).
- **Glass blur cost** on budget phones → keep the `blur: false` fallback path tested.
