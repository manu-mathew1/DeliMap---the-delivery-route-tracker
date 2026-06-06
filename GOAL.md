# DeliMap — Goal, Problem Statement & Technical Overview

> **⚠️ AGENT INSTRUCTION: This file MUST be read in full at the start of every session, every prompt, and before any implementation decision is made. Do NOT drift from this document.**
>
> **Workspace:** `/Users/manumathew/Documents/VS_code/DeliMap - the delivery route tracker`

---

## 1. Problem Statement

Delivery agents working for services like Instakart (which delivers for Flipkart, Naaptol, etc.) face three compounding challenges every working day:

1. **No Automatic Route Optimization:** The existing delivery partner app scans packages and creates runsheets but does NOT generate an optimized route. The agent must manually look through all packages and mentally figure out the delivery sequence.

2. **Vague Addresses:** Addresses on delivery packages are often incomplete or ambiguous. There is no reliable way to pin an exact location from the printed address alone.

3. **Inefficient Bag Packing:** The delivery bag must be packed in reverse delivery order (last delivery at the bottom, first delivery on top). Without a pre-computed route, proper packing is impossible.

---

## 2. Purpose of the App — DeliMap

DeliMap is a cross-platform mobile app for delivery agents. Its single, focused purpose is:

> **Scan delivery packages → Build an optimized delivery route → Guide the agent through deliveries → Build a growing address intelligence database.**

---

## 3. Core Workflow

### Step 1 — Start a New Day
- Agent opens the app and starts a new delivery session.
- All packages for the day are scanned into the session.

### Step 2 — Package Scanning (OCR-First)
- Agent opens the app's camera scanner at the hub.
- Agent aligns the camera over the printed "Buyer's Name And Address" block on the package label.
- On-device **Google ML Kit Text Recognition** extracts the text within seconds.
- App prints the extracted text on a quick-review card. The agent confirms/rescans and immediately proceeds to scan the next package.
- The scanned text is added to an asynchronous background processing queue.

### Step 3 — Background Processing & Address Intelligence
- While the agent continues scanning other packages, the app processes the queue in the background:
  - **Fuzzy Address Search:** The app compares the scanned address text with all previously saved addresses in the local SQLite DB using a string similarity/overlap algorithm.
  - **Known Receiver Match:** If an exact name + address match is found, the stop is tagged as **✅ Known** and uses the exact saved coordinates.
  - **Geocoding with Local Bias:** If no exact match is found:
    - If a highly similar address is found in the database (e.g. same street/locality), the app uses that known coordinates as a `location` bias (hint) when calling the **Google Geocoding API**.
    - If no similar address is found, it queries the Google Geocoding API normally.
    - The stop is tagged as **🆕 New — Unverified**.

### Step 4 — Route Optimization (Travelling Salesman Problem)
- After scanning is complete, the agent views the compiled list of stops.
- App calculates the optimal delivery route using the nearest-neighbor TSP heuristic starting from the agent's GPS position or custom start point.
- The route is displayed on a map.

### Step 5 — Hub Map Verification & Adjustments
- Before leaving the hub, the agent reviews the route map.
- The agent can see all **✅ Known** (green) and **🆕 New** (orange) pins.
- For **🆕 New** pins, the agent can tap them and adjust their location on the map directly (using drag-and-drop or search) to correct any geocoding errors *before* heading out.

### Step 6 — Bag Packing Guidance
- App shows the optimized **packing order** (last stop → first stop) so the agent can pack the bag correctly.

### Step 7 — Delivery Flow
- Agent follows the numbered route on the map.
- On arrival at each stop, agent marks the delivery as complete.
- A post-delivery popup asks:
  - Was this location correct? (Yes / Update Location)
  - If new address: Save this location for future deliveries? (Yes / No)
  - Notes: text input (pre-filled with existing notes)

### Step 8 — Session Summary
- After all packages delivered, session closes with a summary.

---

## 4. Data Model (Core Entities)

### Receiver Record (Address Intelligence Database)
| Field | Type | Description |
|---|---|---|
| receiver_id | UUID | Unique identifier |
| name | String | Name as printed on package |
| address_text | String | Address as printed on package |
| latitude | Double | Saved GPS latitude |
| longitude | Double | Saved GPS longitude |
| notes | String | Agent's personal notes |
| delivery_count | Int | Number of times delivered here |
| last_delivered | DateTime | Last delivery timestamp |
| is_verified | Bool | Has GPS location been manually confirmed? |

### Delivery Session
| Field | Type | Description |
|---|---|---|
| session_id | UUID | Unique session ID |
| date | Date | Delivery date |
| packages | List\<Package\> | All packages in this session |
| route_order | List\<UUID\> | Ordered list of receiver_ids for delivery |
| status | Enum | active / completed |

### Package
| Field | Type | Description |
|---|---|---|
| package_id | UUID | Unique ID (from scan or manual) |
| order_id | String | Order ID from package barcode/QR |
| receiver_id | UUID | FK → Receiver Record |
| status | Enum | pending / delivered / failed |
| scanned_at | DateTime | When it was scanned |
| delivered_at | DateTime | When it was marked delivered |

---

## 5. Finalized Technical Decisions

| # | Decision | Choice | Reason |
|---|---|---|---|
| 1 | **Platform** | Flutter (cross-platform) | Single codebase, Android + iOS, excellent map support |
| 2 | **Map Provider** | **Google Maps SDK for Flutter** | Authentic Google Maps visuals, satellite view, traffic overlay, and high-detail India maps. Free tier ($200/mo) covers 28,000 loads, which easily covers 2–3 device personal use for free. |
| 3 | **Geocoding** | **Google Geocoding API** | Highly accurate geocoding matching Google's dataset, using Google Cloud console setup. |
| 4 | **Routing Algorithm** | Nearest-neighbor TSP heuristic | Simple, fast, good enough for 10–50 stops |
| 5 | **Database** | SQLite (local, via `sqflite`) + future cloud sync | Offline-first. Cloud sync (Firebase Firestore) to be added in a future update |
| 6 | **Label Scanning (OCR)** | **Google ML Kit Text Recognition** | On-device, 100% free, fast and runs offline. Parses name + address. |
| 7 | **Route Start Point** | Current GPS location OR user-set custom point | Configurable in Settings |
| 8 | **Authentication** | **Biometric (fingerprint/face) + PIN fallback** | Fastest for a delivery agent (one tap), protects customer addresses |
| 9 | **Fuzzy String Match** | Levenshtein / Overlap Similarity | Used to find similar known addresses and inject a geocoding coordinate bias. |

---

## 6. Key Features (MVP Scope — Do NOT Expand Beyond This)

- [ ] On-device camera label scanning (Google ML Kit Text Recognition OCR)
- [ ] Asynchronous background scanning queue (geocodes and processes in background)
- [ ] Address intelligence database (SQLite, offline-first)
- [ ] Local address similarity matcher (Fuzzy search to bias geocoding coordinate hints)
- [ ] Pre-route hub map verification (edit/adjust pins on map before packing)
- [ ] TSP nearest-neighbor route optimization
- [ ] Bag packing order screen
- [ ] Interactive map with numbered stops (Google Maps SDK for Flutter)
- [ ] Known vs New address flagging
- [ ] Manual location pinning on map
- [ ] Post-delivery popup (confirm location, add notes)
- [ ] Delivery session summary
- [ ] Notes per receiver (editable, persistent)
- [ ] Receiver address book / history screen
- [ ] Biometric + PIN lock
- [ ] Configurable start point (GPS or custom)

---

## 7. Planned Future Features (NOT in MVP)

- [ ] Cloud sync (Firebase Firestore) — next major update after MVP
- [ ] Failed delivery reason logging
- [ ] Photo proof of delivery
- [ ] Offline tile caching (full offline map — no internet needed at all)
- [ ] Multi-language support (Hindi, Tamil, etc.)

---

## 8. What This App is NOT

- It is NOT a customer-facing delivery tracking app.
- It is NOT a replacement for the existing Instakart runsheet/scanning app.
- It does NOT contact receivers or send notifications.
- It does NOT manage payments or returns (out of scope for MVP).

---

*Last updated: 2026-06-05 | Version: 0.2 — Decisions Finalized*
