# DATA_MODEL.md — Daftar

Local SQLite via **Drift**. Offline-first, single user, **sync-ready**.

## 1. Conventions (every table)

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID v4 (`uuid` package). Never auto-increment. |
| `created_at` | INTEGER | UTC epoch milliseconds. |
| `updated_at` | INTEGER | Set on every write (future sync uses last-write-wins). |
| `deleted_at` | INTEGER NULL | Soft delete. All reads filter `deleted_at IS NULL`. |

- **Money:** integer minor units + currency code (`amount_minor INTEGER`,
  `currency TEXT` = `TND` / `USD`). TND minor = millimes (×1000), USD = cents (×100).
- **Rates:** integer micro-units: `rate_micro` = TND per 1 USD × 1 000 000
  (3.050 → `3050000`).
- **Enums:** stored as TEXT (stable names), e.g. `kind = 'shop' | 'venue'`.
- **Search:** text entities have a `search_key` column = `normalizeForSearch(name …)`,
  indexed. Update it on every write.
- Seeded rows (`is_built_in = 1`) can be renamed or hidden but not hard-deleted.
  Their ids are **UUID v5** of `daftar:<table>:<slug>` (`builtInId`), identical on every
  install, so a future sync never duplicates "Supermarket". Likewise a product saved
  without variants gets one default variant (id = v5 of the product id), and a menu
  item without options gets one single-price option, so prices always have a target.
- Photos are files in the app documents directory (`photos/<uuid>.jpg`); the DB stores the path.
- Schema version starts at **1**. Every change bumps the version with a
  tested migration in `MigrationStrategy.onUpgrade`.

## 2. Core tables

```
settings              key TEXT PK, value TEXT            (theme_mode, stale_days=90, default_unit, lock_enabled …)

place_types           id, name, icon_key, kind('shop'|'venue'), sort_order, is_built_in, +base
places                id, name, type_id → place_types, lat REAL?, lng REAL?, address?, phone?,
                      opening_hours TEXT? (JSON, see §5), wifi_name?, wifi_password?,
                      rating INTEGER? (1–5), notes?, search_key, +base
payment_methods       id, name, icon_key, sort_order, is_built_in, +base
                      (seed: Cash, Card, D17, Flouci, e-Dinar, Bank transfer)
place_payment_methods place_id, payment_method_id                (PK both)
place_tags            place_id, tag TEXT                         (PK both; quick tags)

categories            id, name, icon_key, sort_order, is_built_in, +base
                      (seed: Food, Drinks, Snacks, Dairy, Cleaning, Hygiene, Baby, Electronics,
                       Clothes, Services, Transport, Other)
products              id, name, brand?, category_id?, photo_path?, search_key, +base
variants              id, product_id, name? (NULL = default), barcode? (indexed),
                      size_value REAL?, size_unit? ('g'|'kg'|'ml'|'l'|'pc'),
                      base_quantity INTEGER? (normalised: g, ml or pieces), search_key, +base

menu_sections         id, place_id, name, sort_order, +base
menu_items            id, place_id, section_id?, name, is_usual BOOLEAN, sort_order, search_key, +base
menu_item_options     id, menu_item_id, name? (NULL = single price; 'S','L','+cheese'), sort_order, +base

global_price_types    id, name, is_built_in, sort_order, +base
                      (seed: Reference price, Seen somewhere, Official price)

price_entries         id,
                      variant_id? → variants          ┐ exactly one of these two
                      menu_option_id? → menu_item_options ┘
                      place_id? → places               (NULL ⇒ global price)
                      global_type_id? → global_price_types (required when place_id IS NULL)
                      amount_minor INTEGER, amount_max_minor INTEGER? (range), currency TEXT='TND',
                      seen_at INTEGER, is_promo BOOLEAN, promo_ends_at INTEGER?,
                      note?, transaction_id? ("I bought it"), +base
                      INDEX (variant_id, place_id, seen_at), (menu_option_id, seen_at)

photos                id, owner_type ('place'|'product'|'price'|'menu'), owner_id, file_path,
                      ocr_text?, +base
```

Notes
- A **global** item that is not a shop product (e.g. "Haircut", "Taxi to the
  centre") is still a `products` row (category Services/Transport) so search and
  history work the same way.
- "Latest price at a place" = newest non-deleted `price_entries` row for
  `(variant_id|menu_option_id, place_id)`. If it is an **expired promo**, use the
  newest non-promo entry before it instead.
- Range prices score on `amount_minor` (the minimum) and display "6.000–8.000".

## 3. Calculator tables (Calculator)

```
lists                 id, name, +base
list_items            id, list_id, variant_id? | menu_option_id? | free_text?, quantity INTEGER,
                      is_checked BOOLEAN, sort_order, +base
```

## 4. Schema v2 tables (Accounts, saved lists, bills, debts)

Schema version **2** (migration `if (from < 2)` in `AppDatabase.onUpgrade`; purely additive,
covered by `test/data/migration_v2_test.dart`). All nine tables carry the base columns.
Enums are stored **by Dart name** (`textEnum`), e.g. `'transferOut'`, `'tnd'`; never rename
enum members. Dates are UTC epoch ms. Money is integer minor units (millimes / cents).

```
accounts              name, kind('cash'|'bank'|'card'|'savings'|'wallet'), currency('tnd'|'usd'),
                      opening_balance_minor, include_in_totals (default true),
                      hide_amount (default false), sort_order, icon_key, search_key
transactions          account_id→accounts, kind('expense'|'income'|'transferOut'|'transferIn'|'exchange'),
                      amount_minor, currency, category_id?→categories, note?, occurred_at,
                      price_entry_id?→price_entries ("I bought it"), pair_id? (shared by the two
                      legs of a transfer/exchange), fee_minor?, rate_ten_thousandths?
                      INDEX (account_id, occurred_at), (pair_id)
rate_entries          date, tnd_per_usd_ten_thousandths (3.1250 → 31250), source_note?
saved_lists           name, sort_order, search_key
saved_list_items      list_id→saved_lists, variant_id?→variants | free_text? (exactly one, CHECK),
                      quantity (>0), is_checked, sort_order
bills                 name, amount_minor, currency, cycle('monthly'|'yearly'|'weekly'|'customDays'),
                      custom_days?, next_due_at, reminder_days_before (default 3), is_active,
                      icon_key, category_id?→categories, search_key
bill_payments         bill_id→bills, amount_minor, paid_at
debts                 name (person), direction('owedToMe'|'iOwe'|'iOweMyself'), amount_minor,
                      currency, note?, due_at?, source_account_id?→accounts, search_key
debt_payments         debt_id→debts, amount_minor, paid_at
```

Transaction sign rules (`AccountTransaction`): `amount_minor` is a magnitude (>= 0) for
`expense`/`income`/`transferOut`/`transferIn`; for `exchange` it is **signed** (negative = the leg
leaving this account, positive = the leg arriving). Transfers and exchanges are two rows, one per
account, sharing `pair_id`; deleting one leg soft-deletes both. `fee_minor` is in the row's currency
and is always deducted from that account on top of the amount.

Balance = opening balance + Σ `balanceEffectMinor` (signed amount − fee) of that account's live
transactions (computed, never stored; `domain/use_cases/account_balance.dart`). Totals are per
currency over accounts with `include_in_totals`. Rate: TND per 1 USD ×10 000; effective rate =
rate adjusted for fee.

Bills: `recordPayment` inserts a `bill_payments` row and moves `next_due_at` one cycle on
(`domain/use_cases/bill_schedule.dart`: month-end clamping, weekly, custom days, yearly).
Debts: remaining = amount − Σ payments, floored at 0 (`domain/use_cases/debt_math.dart`).
"I owe myself" is `direction = 'iOweMyself'` (e.g. borrowed from a savings `source_account_id`).

Soft-deleting an account hides its transactions from `TransactionsRepository.watchAll`;
soft-deleting a list/bill/debt soft-deletes its items/payments.

## 5. JSON shapes

`places.opening_hours`:
```json
{"mon":[["08:00","13:00"],["15:00","22:00"]],"tue":[["08:00","22:00"]],"sun":[]}
```
Missing day = unknown; empty list = closed. "Open now" uses device local time.

## 6. Search normalisation — `normalizeForSearch(String)`

Applied to stored `search_key` and to the query:
1. Lowercase (invariant).
2. Strip Latin diacritics: é è ê ë → e, à â → a, ç → c, î ï → i, ô → o, ù û ü → u, œ → oe.
3. Arabic: remove tashkeel `U+064B–U+0652`, `U+0670`, tatweel `U+0640`;
   unify alef `أ إ آ ٱ → ا`; `ى → ي`; `ة → ه`; `ؤ → و`; `ئ → ي`.
4. Arabic-Indic digits `٠–٩` and `۰–۹` → `0–9`; Arabic decimal `٫` → `.`.
5. Collapse whitespace, trim.

Matching: every query token must be a prefix of some token in `search_key`
(so "mil oreo" finds "Milka Oreo"). Rank exact > prefix > contains.

## 7. Best-option score — `BestOfferScorer` (domain/use_cases)

Input: all current offers for one variant (or same-named menu items across
venues), user location (optional), now, `staleDays` (default 90).

1. **Candidates:** latest price per place (see §2) + global prices. Drop expired promos.
2. **Basis:** if *every* candidate has `base_quantity` in the same dimension,
   compare **unit price** = amount ÷ base_quantity × (100 for g/ml, 1 for pc),
   shown as "per 100 g" / "per 100 ml" / "per piece". Otherwise compare raw amount.
3. **Distance factor:** `d` km (haversine) when both locations are known:
   `distMult = 1 + min(0.25, 0.02 × d)` (+2% per km, max +25%).
   Place without location: `1.05`. Global price (no place): `1.10`.
4. **Freshness factor:** age `a` days. `a ≤ staleDays` → `1.0`; otherwise
   `1 + min(0.30, 0.10 × (a − staleDays) / 30)` (+10% per extra month, max +30%).
5. **Score** = basis × distMult × freshMult. Lowest wins. Ties → nearer, then newer.
6. **Reasons** for the winner (max 3, in this order): "Cheapest per 100 g" /
   "Cheapest" (if it has the lowest basis), "1.2 km" (if distance known),
   "Seen 3 days ago" (or "Promo until 20 Oct"). Stale offers get "old".

All constants live at the top of `best_offer_scorer.dart`; cover each rule with
unit tests (unit vs raw basis, distance cap, stale penalty, expired promo,
global price, ties).

## 8. Menu OCR parsing

ML Kit returns blocks → lines. A line is a menu item when it ends with a price
pattern `(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:dt|tnd|d)?$` (case-insensitive). The
name is the text before it (trim dots/dashes). Lines without a price that come
right before priced lines are section headers. Confidence is "low" when < 60%
of lines parse, when Arabic characters are detected, or when ML Kit
confidence is low → show the "Better to type it yourself" hint. Always let the
user review and edit before saving.

## 9. Basket optimizer and bill splitter

Pure Dart, `lib/domain/use_cases/basket_optimizer.dart` and `bill_splitter.dart`.
Inputs are plain objects; the caller reads latest prices from repositories.

**Basket.** Quantities are integer thousandths (`quantityMilli`, 1500 = 1.5), never
doubles. Line total = unit x quantity, rounded half up to the millime; a store total
is the sum of its rounded line totals (so the displayed lines always add up).
Duplicate line keys are merged.
1. Rank stores: more lines priced first, then lower total, then fresher oldest price,
   then place id. So a store pricing everything beats a cheaper partial one; if none
   prices everything, the widest coverage wins and the missing lines are flagged.
   Stores that price no line are dropped.
2. `savingVersusNext` is only set between stores with equal coverage.
3. A price is stale when `ageDays > staleDays` (default 90, same as the scorer).
4. Reasons are sealed `BasketReason` objects (CheapestTotal, CoversAll, CoversPartial,
   MissingItems, SavesVersusNext, Tied, PricesAge, StalePrices, OnlyStore,
   SplitSaves, NotWorthSecondTrip); the UI renders the text.
5. Cheapest split: each line goes to its cheapest store (ties prefer the best single
   store, then place id). `savingVersusBest` = best store's cost of the lines it
   prices minus the split's cost of those same lines. `isWorthIt` needs 2+ stores
   and saving >= threshold (default 1.000 TND, configurable).

**Bill split.** Shares always sum exactly to the total.
- Equal: `total ~/ n` each, leftover millimes one each to the first people in order.
- By item: an item is shared equally by its distinct owners (leftover to the earlier
  participant); tax and tip are allocated in proportion to item subtotals with the
  largest-remainder method (ties to the earlier participant). With no items, extras
  split equally. Use `BillSplitter.percentOf(base, basisPoints)` for percentages.
- `RoundingPolicy.cash050`: everyone except the named remainder person (default first)
  is rounded to the nearest 0.050; the remainder person pays total minus the others.
  If that would go negative, others are rounded down instead.
