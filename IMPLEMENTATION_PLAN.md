# DeliMap — Implementation Plan & Tracker

> **⚠️ AGENT INSTRUCTION: Read GOAL.md before reading this file. Every implementation step must trace back to a feature listed in GOAL.md. If a step does not map to GOAL.md, it should NOT be implemented without user approval and a GOAL.md update.**
>
> **Workspace:** `/Users/manumathew/Documents/VS_code/DeliMap - the delivery route tracker`

---

## Status Legend
- `[ ]` Not started
- `[/]` In progress
- `[x]` Completed
- `[!]` Blocked / needs decision

---

## Phase 0 — Project Setup & Governance *(Current Phase)*

- [x] Create GOAL.md — project aim, problem statement, data model, scope
- [x] Create IMPLEMENTATION_PLAN.md — this file
- [x] Create INSTRUCTIONS.md — agent rules
- [x] Create App Draft v0.1 (initial wireframe document)
- [x] Finalize tech stack decisions (Map: Google Maps SDK, DB: SQLite, Auth: Biometric+PIN)
- [x] Move all project files to correct workspace
- [x] Create App Draft v0.2 (updated with decisions)
- [x] Analyze package image and decode Data Matrix (revealed no address encoded)
- [ ] Set up Flutter project scaffold in workspace directory
- [ ] Configure project directory as active workspace

---

## Phase 1 — Foundation & Navigation

**Goal:** Basic app shell, navigation structure, and design system in place.

- [ ] `flutter create deliMap .` in workspace
- [ ] Set up folder structure:
  ```
  lib/
    screens/
    widgets/
    models/
    services/
    db/
    utils/
  ```
- [ ] Add dependencies to `pubspec.yaml`:
  - `google_maps_flutter` (Google Maps SDK)
  - `sqflite` (local database)
  - `google_mlkit_text_recognition` (On-device OCR)
  - `camera` (Camera control for OCR)
  - `local_auth` (biometric)
  - `geolocator` (GPS)
  - `google_maps_webservice` (Google Geocoding & Places APIs)
  - `uuid` (unique IDs)
  - `intl` (date formatting)
- [ ] Define color palette, typography, and dark theme
- [ ] Create `AppTheme` class with all design tokens
- [ ] Set up bottom navigation: Home / Route Map / Receivers / Settings
- [ ] Create placeholder screens for all 4 tabs
- [ ] App launches and tabs navigate correctly

**Completion criteria:** App launches, tabs navigate, theme applied.

---

## Phase 2 — Database & Models

**Goal:** Local SQLite database fully operational with all models.

- [ ] Define Dart models: `ReceiverRecord`, `DeliverySession`, `Package`
- [ ] Create `DatabaseService` class (singleton)
- [ ] Schema: create tables on first launch
  - `receivers` table
  - `sessions` table
  - `packages` table
- [ ] CRUD operations for each entity
- [ ] Migration strategy for future schema changes

**Completion criteria:** DB initializes, CRUD operations verified.

---

## Phase 3 — Authentication

**Goal:** App locked behind biometric / PIN on launch.

- [ ] Integrate `local_auth` package
- [ ] On app start: check if auth is enabled (Settings toggle)
- [ ] Biometric prompt (fingerprint/face)
- [ ] PIN fallback if biometric fails
- [ ] Settings screen: enable/disable auth, set/change PIN

**Completion criteria:** App requires biometric or PIN to open.

---

## Phase 4 — OCR Label Scanning & Session Queue

**Goal:** Agent can scan package labels at the hub in a fast, batch-like sequence with background processing.

- [ ] Home screen: "Start New Day" → creates new `DeliverySession`
- [ ] Active session screen: lists scanned packages with processing indicators
- [ ] Integrate `camera` package and configure camera preview overlay for text box
- [ ] Integrate `google_mlkit_text_recognition` for on-device OCR
- [ ] Implement live scan confirmation flow (shows recognized name + address, tap to confirm/rescan)
- [ ] Create background task processor queue (`SessionQueue`) to run geocoding and matching asynchronously
- [ ] Manual entry form fallback
- [ ] Swipe-to-remove package from list

**Completion criteria:** Agent can scan multiple labels in sequence, seeing them added to a background queue.

---

## Phase 5 — Local Fuzzy Matching & Geocoding Bias

**Goal:** Resolve known receivers and geocode new addresses using local database similarity hints.

- [ ] Implement local string overlap/similarity algorithm (e.g. word token matching or Jaro-Winkler)
- [ ] Check DB for exact matching `(name + address)` → tag **✅ Known** and load saved GPS
- [ ] Check DB for similar address text (e.g. same street/landmark):
  - If found: retrieve coordinates to use as `location` bias in Google Geocoding API
- [ ] Call Google Geocoding API (with location bias hint if available) → tag **🆕 New — Unverified**
- [ ] Pre-route hub map verification: UI list of unverified stops with mini-maps to adjust/drag-and-drop pins *before* starting the route
- [ ] Save/Update `ReceiverRecord` with coordinates and notes

**Completion criteria:** Background queue resolves addresses, applies similarity bias, and lets users adjust pins at the hub.

---

## Phase 6 — Route Optimization & Map Display

**Goal:** App computes and displays the optimal delivery route.

- [ ] Implement nearest-neighbor TSP algorithm in `RouteService`
- [ ] Starting point: current GPS location OR user-set point (from Settings)
- [ ] Display route on Google Map with numbered markers (Stop 1, 2, 3...)
- [ ] Draw polyline connecting all stops in order
- [ ] "Recalculate Route" button
- [ ] Edge cases: 0 packages, 1 package, GPS unavailable

**Completion criteria:** Correct numbered route displayed on Google Map.

---

## Phase 7 — Bag Packing Order Screen

**Goal:** Agent sees how to pack the bag in correct order.

- [ ] Packing Order screen — packages listed in reverse route order
- [ ] Visual list: "1 → Bottom of bag" to "Last → Top of bag"
- [ ] "Mark as Packed" checkbox per package
- [ ] "START DELIVERY" button → activates live delivery mode

**Completion criteria:** Correct packing order shown, all items can be checked off.

---

## Phase 8 — Delivery Flow & Post-Delivery Popup

**Goal:** Agent can complete deliveries with data capture.

- [ ] Live map: agent GPS dot, current stop highlighted
- [ ] Bottom card per stop: receiver name, address, note, distance
- [ ] "Navigate" button → opens device maps app (Google Maps / Apple Maps)
- [ ] "Delivered" button → triggers post-delivery popup
- [ ] Post-delivery popup logic:
  - Location correct? Yes / No → if No, pin-drop to correct
  - Save location? (new addresses only)
  - Notes text input (pre-filled)
  - Confirm → marks package delivered, removes from route
- [ ] Route auto-advances to next stop

**Completion criteria:** Full delivery flow works end-to-end.

---

## Phase 9 — Session Summary

**Goal:** Clean end-of-day wrap-up screen.

- [ ] Summary: total, delivered, failed, distance, time
- [ ] List of unverified new addresses
- [ ] Failed deliveries list
- [ ] "End Session" → archives session
- [ ] Session history on Home screen

**Completion criteria:** Session ends cleanly, archived correctly.

---

## Phase 10 — Receiver Address Book

**Goal:** Agent can browse and manage saved receivers.

- [ ] Receivers tab: searchable, filterable list
- [ ] Receiver detail screen: name, address, mini-map, notes, history
- [ ] Edit location (re-pin on map)
- [ ] Edit notes
- [ ] Delete receiver record

**Completion criteria:** Full CRUD on receiver records from Receivers tab.

---

## Phase 11 — Settings Screen

**Goal:** Minimal, functional settings.

- [ ] Set custom start location for routes
- [ ] Toggle biometric/PIN auth
- [ ] Route algorithm preference (nearest-neighbor only for MVP)
- [ ] Export receivers to CSV
- [ ] Clear session history
- [ ] About / version info

**Completion criteria:** All settings persist and affect app behavior.

---

## Phase 12 — Polish & Testing

- [ ] Loading states and error handling throughout
- [ ] No-internet graceful fallback (Nominatim geocoding may fail)
- [ ] Edge case testing: 0 packages, 1 package, GPS off, scan fail
- [ ] Performance: route compute for 50 stops acceptable
- [ ] UI polish: animations, transitions, empty states
- [ ] Android build test (primary)
- [ ] iOS build test

---

## Open Decisions

| # | Decision | Status |
|---|---|---|
| 1 | Map Provider | ✅ **Google Maps SDK for Flutter** ($200/mo free tier covers 2-3 devices for free) |
| 2 | What data does Flipkart/Naaptol QR encode? | ❓ **Pending — user to provide package image** |
| 3 | Cloud sync | ✅ **Offline-first (SQLite). Firebase Firestore sync in future update.** |
| 4 | Authentication | ✅ **Biometric (fingerprint/face) + PIN fallback** |
| 5 | Route start point | ✅ **Current GPS location OR user-set custom point (Settings)** |
| 6 | App name | ✅ **DeliMap** |

---

*Last updated: 2026-06-05 | Current Phase: Phase 0*
