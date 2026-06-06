# DeliMap — Updated App Draft v0.2

**Version:** 0.2 — Decisions Finalized
**App Name:** DeliMap
**Tagline:** *Scan. Route. Deliver.*
**Platform:** Flutter (Android + iOS, cross-platform)
**Audience:** Delivery agents (Instakart, Flipkart, Naaptol, etc.)

---

## Section 1 — Map Provider Decision

### Full Options Compared

| Provider | Free Tier | Paid? | API Key? | Offline? | India Data Quality |
|---|---|---|---|---|---|
| **Google Maps SDK** | $200/month credit (~28,000 map loads free) | Yes, above free tier | Required | No (premium only) | ⭐⭐⭐⭐⭐ Best |
| **Mapbox** | 50,000 map loads/month free | Yes, above free tier | Required | Yes (tile caching) | ⭐⭐⭐⭐ Very Good |
| **OpenStreetMap + flutter_map** | **100% Free. No limits. Ever.** | No | Not required | Yes (with caching) | ⭐⭐⭐ Good (community-maintained) |
| **HERE Maps** | 250,000 transactions/month free | Yes, above free tier | Required | No | ⭐⭐⭐⭐ Good |
| **Apple MapKit** | Free (iOS only) | No | Apple Dev account | No | ⭐⭐⭐⭐ Good |

### ✅ Decision: Google Maps SDK for Flutter

**Why:**
- Google Maps SDK provides exact Google Maps features: high-detail maps in India (essential for delivery agents), street view, satellite view, traffic layers, and extremely accurate Google-level address geocoding.
- **Cost:** Google Cloud Console provides a **$200 monthly free credit**. This covers up to 28,000 dynamic map loads or geocoding queries per month. For 2–3 personal devices, your usage will be way below this cap, making it **100% free** in practice.
- **Geocoding:** We'll use the **Google Geocoding API** to fetch high-precision coordinates for addresses.
- **Setup:** Requires creating a Google Cloud Project, enabling the Android and iOS Maps SDK, Geocoding API, and generating a secure API key.

---

## Section 2 — QR Code / Barcode on Packages

### Current Status: ⏳ Pending Confirmation

**You mentioned providing an image of a package with the QR/barcode — please share that image when ready.**

**Why it matters:**
- Flipkart packages typically have a **1D barcode** encoding just the Order ID (AWB number / shipment tracking number). The full address is NOT encoded — it's printed separately.
- Naaptol / other platforms may vary.
- If only the Order ID is in the barcode/QR, we cannot auto-extract the address from the scan alone. We'd need to either:
  - **Option A:** Scan the barcode for the Order ID, then auto-fill receiver name + address from a manual form (agent types it once).
  - **Option B:** The agent types the address the first time, but it's saved forever — so from the second delivery onward it's instant.

**The app is designed to handle both cases gracefully.** The address intelligence database means manual entry is a one-time cost per receiver.

---

## Section 3 — Database / Sync Strategy

### ✅ Decision: Offline-First → Cloud Sync Later

**Phase 1 (MVP):** Everything stored locally in **SQLite** on the device.
- Works with zero internet.
- Instant read/write.
- No setup or account required.

**Phase 2 (Future Update):** Add **Firebase Firestore** cloud sync.
- Syncs receivers + notes + session history across devices.
- Backup protection if phone is lost.
- Will be added as a separate update — the local DB schema is designed to be sync-compatible from the start.

---

## Section 4 — Authentication

### Options Compared

| Option | Speed for delivery agent | Security | Effort |
|---|---|---|---|
| No auth | Instant | ❌ None | None |
| PIN only | Slow (typing) | ✓ Basic | Low |
| **Biometric (fingerprint/face) + PIN fallback** | ⚡ Instant (1 tap) | ✓ Good | Medium |
| Full login (email/password) | Very slow | ✓ High | High |

### ✅ Decision: Biometric + PIN Fallback

**Why:** A delivery agent is constantly opening and closing the app while on the move. Biometric (fingerprint or face unlock) is the fastest possible auth — one tap/glance, done. PIN is the fallback if biometric fails (wet hands, gloves, etc.).

This is a **Settings toggle** — auth can be disabled entirely if the agent prefers no lock.

---

## Section 5 — Route Start Point

### ✅ Decision: Current GPS Location (default) OR User-Set Custom Point

- **Default:** Route starts from wherever the agent currently is (GPS).
- **Custom:** Agent can set a "Home Base" address in Settings (e.g., the Instakart warehouse). The route will then start from that fixed point every day.
- The agent can switch between these two modes in Settings at any time.

---

## Design Language

> **Minimal. Purposeful. Reliable.**
> On-road use: sunlight-readable, one-thumb operable, premium feel.

**Color Palette (Dark Mode — Primary):**
| Token | Value | Use |
|---|---|---|
| Background | `#0D0D0D` | Screen backgrounds |
| Surface | `#1C1C1E` | Cards, sheets |
| Surface Elevated | `#2C2C2E` | Modals, dialogs |
| Primary Accent | `#F5A623` | CTAs, active states, highlights |
| Success | `#30D158` | Delivered, verified |
| Warning | `#FF9F0A` | New/unverified address |
| Danger | `#FF453A` | Failed, delete |
| Text Primary | `#FFFFFF` | Main text |
| Text Secondary | `#8E8E93` | Subtitles, captions |
| Divider | `#2C2C2E` | Section separators |

**Typography:** `Inter` (Google Fonts)
- Heading: Inter Bold 20–24px
- Body: Inter Regular 14–16px
- Caption: Inter Medium 12px

**Icons:** Material Symbols Rounded
**Corner Radius:** 12px (cards), 8px (inputs), 100px (buttons — pill shape)
**Spacing:** 8px base grid

---

## App Structure — Navigation

```
Bottom Navigation Bar (4 tabs):
├── 🏠 Home         → Today's session / Start new day
├── 🗺️  Route        → Live map with delivery stops
├── 📚  Receivers    → Address book / history
└── ⚙️  Settings     → App preferences
```

---

## Screen-by-Screen Design

---

### Screen A — Launch / Biometric Lock

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│           [DeliMap logo]            │
│            D E L I M A P           │
│         Scan. Route. Deliver.       │
│                                     │
│                                     │
│         👆 Touch to Unlock          │
│        (or use PIN instead)         │
│                                     │
│                                     │
└─────────────────────────────────────┘
```
- Shown only if auth is enabled in Settings.
- Fingerprint sensor triggers immediately on open.
- "Use PIN instead" → 6-digit PIN pad slides up.

---

### Screen 1 — Home (No Active Session)

```
┌─────────────────────────────────────┐
│  ☀️  Good Morning                   │
│  Thursday, 5 June 2026              │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  📦  No active session       │    │
│  │  Ready to start your day?   │    │
│  └─────────────────────────────┘    │
│                                     │
│  ╔═════════════════════════════╗    │
│  ║   ➕  START NEW DAY         ║    │  ← Large amber pill button
│  ╚═════════════════════════════╝    │
│                                     │
│  ─────  Recent Sessions  ─────      │
│                                     │
│  📋  4 Jun  ·  18 pkgs  ·  ✅ 17 ❌1│
│  📋  3 Jun  ·  22 pkgs  ·  ✅ 22   │
│  📋  2 Jun  ·  15 pkgs  ·  ✅ 15   │
│                                     │
└─────────────────────────────────────┘
```

---

### Screen 2 — Home (Active Session)

```
┌─────────────────────────────────────┐
│  Today · 5 Jun 2026    [End Day]    │
│  🟢 Active Session                  │
│                                     │
│  ┌───────────┬──────────┬────────┐  │
│  │  📦  18   │  ✅  6   │ ⏳  12 │  │
│  │  Total    │  Done    │  Left  │  │
│  └───────────┴──────────┴────────┘  │
│                                     │
│  ╔═════════════════════════════╗    │
│  ║  📷  SCAN PACKAGE LABELS    ║    │  ← Primary amber button
│  ╚═════════════════════════════╝    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  🗺️  VIEW & VERIFY ROUTE     │    │  ← Secondary (outlined)
│  └─────────────────────────────┘    │
│  ┌─────────────────────────────┐    │
│  │  🎒  PACKING ORDER          │    │  ← Secondary (outlined)
│  └─────────────────────────────┘    │
│                                     │
│  ─────  Today's Stops  ─────        │
│                                     │
│  ① Ravi Kumar                       │
│    Sector 14, Noida  ·  ✅ Known    │
│                                     │
│  ② Meena S.                         │
│    MG Road, Bangalore  ·  🆕 New    │
│                                     │
│  ③ Anand Pillai                     │
│    Thrissur, Kerala  ·  ⏳ Geocoding│  ← Background task geocoding
│  ···                                │
└─────────────────────────────────────┘
```

---

### Screen 3 — Package Label Scanner (OCR)

```
┌─────────────────────────────────────┐
│  ←  Scan Package Label              │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │    [ Camera Viewfinder ]    │    │
│  │                             │    │
│  │    ┌───────────────────┐    │    │
│  │    │  ALIGN BUYER      │    │    │
│  │    │  NAME & ADDRESS   │    │    │
│  │    │  INSIDE BOX       │    │    │
│  │    └───────────────────┘    │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  Align text to read...         🔦   │
│                                     │
│  ────────────── or ──────────────   │
│                                     │
│  ✏️  Enter details manually         │
│                                     │
└─────────────────────────────────────┘
```

**Live OCR scan result card (slides up instantly on detection):**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  🔍  Confirm Text Scan

  Name:      Maria ginnu
  Address:   Hilltop road, Kanjirapally
             P.O, Hilltop, Kottayam
             686507 India

  [ ] Looks incorrect? Adjust crop.

  ╔═════════════════════════════╗
  ║  ✅  CONFIRM & SCAN NEXT     ║  ← Tapping this immediately
  ╚═════════════════════════════╝     restarts camera for next scan.
                                      Geocoding happens in background.
  [ ✏️ Edit Text manually ]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Background Queue Status (seen on Active Session list):**
*   **⏳ Processing...** - ML Kit text parsed, querying DB and geocoding.
*   **✅ Known Location** - Name + Address found in SQLite. Exact GPS loaded.
*   **🆕 New (Unverified)** - New address geocoded using Google API.
*   **🆕 New (Locality Bias)** - New address geocoded with coordinates biased from a similar saved address (e.g. `Ravi Kumar, Sector 14` used to bias `Amit Singh, Sector 14`).
*   **⚠️ Geocode Error** - Geocoding failed (no internet or address totally invalid). Agent can tap to resolve manually.
```

---

### Screen 4 — Manual Entry

```
┌─────────────────────────────────────┐
│  ←  Add Package Manually            │
│                                     │
│  Order ID  *                        │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  Receiver Name  *                   │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  Delivery Address  *                │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  ╔═════════════════════════════╗    │
│  ║  ➕  ADD TO ROUTE           ║    │
│  ╚═════════════════════════════╝    │
└─────────────────────────────────────┘
```

---

### Screen 5 — Packing Order

```
┌─────────────────────────────────────┐
│  ←  Packing Order                   │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  🔝  TOP OF BAG  (deliver first)│
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ①  Ravi Kumar              │    │
│  │     Sector 14, Noida        │    │
│  │     FK2026060512345  [ ✓ ]  │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ②  Meena S.    🆕          │    │
│  │     MG Road, Bangalore      │    │
│  │     NK2026060598765  [ ✓ ]  │    │
│  └─────────────────────────────┘    │
│                                     │
│         ···  (more stops)  ···      │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ⑱  Last Receiver           │    │
│  │     Address...              │    │
│  │     FK2026060577890  [ ✓ ]  │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  🔚  BOTTOM OF BAG (last)   │    │
│  └─────────────────────────────┘    │
│                                     │
│  ╔═════════════════════════════╗    │
│  ║  🚀  START DELIVERY         ║    │
│  ╚═════════════════════════════╝    │
└─────────────────────────────────────┘
```

- Each item has a checkbox `[ ✓ ]` — tap to mark as packed (turns green).
- "START DELIVERY" always available — checkbox is a convenience, not a gate.
- 🆕 badge on new/unverified stops as a reminder.

---

### Screen 6 — Route Map (Live Delivery)

```
┌─────────────────────────────────────┐
│  Route Map  ·  12 left    🔄        │
│                                     │
│  ╔═══════════════════════════════╗  │
│  ║                               ║  │
│  ║  [Full-screen Google Map]     ║  │
│  ║                               ║  │
│  ║    🔵 (agent location)        ║  │
│  ║                               ║  │
│  ║    ①  (amber — current)       ║  │
│  ║    ②  ③  ④  (grey)           ║  │
│  ║    ⑤  (orange border = 🆕)   ║  │
│  ║                               ║  │
│  ║    ──── (route polyline) ──── ║  │
│  ║                               ║  │
│  ╚═══════════════════════════════╝  │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ①  Ravi Kumar  ·  1.2 km  │    │
│  │  Sector 14, Noida          │    │
│  │  ✅ Known  ·  📝 Blue gate  │    │
│  │                             │    │
│  │  [🧭 Navigate]  [✅ Delivered]│   │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

**Map pin styles:**
| Pin | Meaning |
|---|---|
| 🔵 Blue dot | Agent's live GPS location |
| `①` Amber filled | Current (next) stop |
| `②③...` Grey outlined | Upcoming stops |
| `✅` Green filled | Completed stop |
| Orange border on any pin | Unverified/new address |

**"Navigate" button:** Opens the device's default maps app (Google Maps / Apple Maps / Waze) with the stop address for turn-by-turn navigation.

---

### Screen 7 — Post-Delivery Popup

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✅  Package Delivered!

  Ravi Kumar
  H-42, Sector 14, Noida

  ─────────────────────────────────

  Was this the correct location?

  ● Yes, location was correct
  ○ No — let me update the pin

  ─────────────────────────────────

  Notes  (optional)
  ┌───────────────────────────────┐
  │ Blue gate, ring twice         │  ← Pre-filled
  └───────────────────────────────┘

  ╔═════════════════════════════╗
  ║  ✅  CONFIRM & NEXT STOP    ║
  ╚═════════════════════════════╝

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Additional section for New addresses only:**
```
  Save this location for future
  deliveries to Meena S.?

  ● Yes — save location
  ○ No, skip
```

**If "No — update location" is selected:**
- A small map opens with a draggable pin.
- Agent moves pin to the exact house/building.
- Tap "Set Location" → location saved, popup continues.

---

### Screen 8 — Session Summary

```
┌─────────────────────────────────────┐
│                                     │
│  🎉  Day Complete!                  │
│  Thursday, 5 June 2026             │
│                                     │
│  ┌───────────┬──────────┬────────┐  │
│  │  📦  18   │  ✅  17  │  ❌ 1  │  │
│  │  Total    │Delivered │ Failed │  │
│  └───────────┴──────────┴────────┘  │
│                                     │
│  ┌───────────────┬─────────────┐    │
│  │  🛣️  24.3 km  │  ⏱️ 4h 12m │    │
│  │  Distance     │  Time       │    │
│  └───────────────┴─────────────┘    │
│                                     │
│  ─────  Needs Attention  ─────      │
│                                     │
│  🆕  2 new locations not verified  │
│       Tap to review and pin them    │
│                                     │
│  ❌  Sunita Devi — No answer       │
│       12, Church St, Bangalore      │
│                                     │
│  ╔═════════════════════════════╗    │
│  ║  📋  END SESSION            ║    │
│  ╚═════════════════════════════╝    │
└─────────────────────────────────────┘
```

---

### Screen 9 — Receivers (Address Book)

```
┌─────────────────────────────────────┐
│  Receivers                    🔍    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 🔍  Search name or address  │    │
│  └─────────────────────────────┘    │
│                                     │
│  Filter: [ All ▾ ]                  │
│                                     │
│  ─────  A  ─────                    │
│                                     │
│  👤  Anand Pillai                   │
│      Thrissur, Kerala               │
│      ✅ Verified · 5 deliveries     │
│                                     │
│  ─────  M  ─────                    │
│                                     │
│  👤  Meena S.                       │
│      MG Road, Bangalore             │
│      🆕 Unverified · 1 delivery     │
│                                     │
│  ─────  R  ─────                    │
│                                     │
│  👤  Ravi Kumar                     │
│      Sector 14, Noida              │
│      ✅ Verified · 3 deliveries     │
│                                     │
└─────────────────────────────────────┘
```

---

### Screen 10 — Receiver Detail

```
┌─────────────────────────────────────┐
│  ←  Ravi Kumar                 ✏️   │
│                                     │
│  📋  Delivery Address               │
│  H-42, Sector 14, Noida,           │
│  Uttar Pradesh - 201301             │
│                                     │
│  📍  Saved Location                 │
│  ╔═══════════════════════════════╗  │
│  ║  [Mini Google Map with pin]   ║  │
│  ╚═══════════════════════════════╝  │
│  ✅ Verified  ·  28.5400°N 77.3200°E│
│  [ 📍 Update Location ]            │
│                                     │
│  📝  Notes                          │
│  ┌─────────────────────────────┐    │
│  │ Blue gate, ring bell twice. │    │
│  │ 2nd floor, right apartment. │    │
│  └─────────────────────────────┘    │
│  [ ✏️ Edit Notes ]                  │
│                                     │
│  📊  Delivery History               │
│  3 deliveries · Last: 28 May 2026  │
│  First: 10 Apr 2026                │
│                                     │
│  [ 🗑️ Delete Record ]               │  ← Red text, confirmation required
└─────────────────────────────────────┘
```

---

### Screen 11 — Settings

```
┌─────────────────────────────────────┐
│  Settings                           │
│                                     │
│  ─────  Route  ─────                │
│                                     │
│  Starting Point                     │
│  ● Current GPS location (default)   │
│  ○ Custom address                   │
│    [ Set custom address... ]        │
│                                     │
│  ─────  Security  ─────             │
│                                     │
│  App Lock              [ Toggle ]   │
│  Biometric / PIN lock               │
│  [ Change PIN ]                     │
│                                     │
│  ─────  Data  ─────                 │
│                                     │
│  Export Receivers as CSV            │
│  Clear Session History              │
│                                     │
│  ─────  About  ─────                │
│                                     │
│  DeliMap  v1.0.0                    │
│  Built for delivery agents          │
│                                     │
└─────────────────────────────────────┘
```

---

## Key User Flows

```
MORNING FLOW:
Open App (biometric unlock)
  → Home: START NEW DAY
  → Scanner: scan all packages one by one
  → Each scan: Known (auto-adds) / New (geocodes, flags)
  → View Packing Order → pack bag top-to-bottom
  → START DELIVERY → Route Map goes live

DELIVERY FLOW (per stop):
Route Map: bottom card shows next stop
  → [Navigate] → device maps app for directions
  → [✅ Delivered] → Post-Delivery Popup
  → Confirm/update location + notes → CONFIRM
  → Route advances to next stop

EVENING FLOW:
Last stop delivered
  → Session Summary shown automatically
  → Review unverified new addresses (optional, pin them)
  → END SESSION → archived

FUTURE (when cloud sync added):
Same flow, but data silently syncs to Firebase in background
```

---

## Suggested Additions (For User Review — Not In MVP)

| # | Feature | Value | Decision |
|---|---|---|---|
| 1 | Failed delivery reason logging | Track "No answer", "Wrong address", etc. | ❓ Pending |
| 2 | Photo proof of delivery | Protect agent if dispute arises | ❓ Pending |
| 3 | Offline tile caching | Full offline map — no internet at all | ❓ Pending |
| 4 | Multi-language (Hindi, Tamil, etc.) | Better UX for Indian delivery agents | ❓ Pending |

---

## One Remaining Open Question

> [!IMPORTANT]
> **QR / Barcode Content on Packages**
> Please share an image of a Flipkart or Naaptol delivery package showing the QR code and/or barcode. We need to know what data is actually encoded so we can correctly build the scanning + auto-fill feature. This is the last unresolved technical question before we can start coding.

---

*Document version: 0.2 | Updated: 2026-06-05*
