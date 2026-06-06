# 📦 DeliMap — The Smart Delivery Route Tracker

DeliMap is a high-performance, premium delivery route tracking and optimization application built with Flutter. Designed specifically for courier and delivery drivers, it leverages local SQLite caching, real-time Firebase Cloud Sync, and OCR machine learning to scan package barcodes, resolve receiver details, group multiple packages, and map out the most efficient delivery route using interactive GPS navigation.

---

## ✨ Key Features

### 🔍 OCR Label Scanning & Fuzzy Matching
- **High-Speed OCR Scanning:** Uses on-device machine learning (Google ML Kit) with a custom fast JPEG parser to immediately capture receiver name and address information from package labels.
- **Fuzzy Levenshtein Matcher:** Automatically resolves OCR-scanned text against your local Receivers Directory using case-insensitive query matches and Levenshtein similarity algorithm ($\ge 80\%$) to find matching receivers.
- **Manual Fallback:** Quick-entry overlay when label scans require editing or manual input.

### 📍 Route Optimization & Navigation
- **Stop Grouping:** Automatically merges multiple package shipments headed to the same recipient/location into a single delivery stop, preventing redundant visits.
- **Dynamic Routing Engine:** Calculates optimized path routing using the Google Directions API with an automatic fallback to the Open Source Routing Machine (OSRM) for offline/no-API scenarios.
- **Live GPS Tracking:** Displays real-time location tracking on an interactive Google Map, dynamically updating the route polyline based on coordinates.
- **Runsheet Queue:** View an active list of package runsheets automatically sorted by geographic proximity to the driver's live GPS coordinates.

### 🔄 Hybrid Database & Sync
- **Local SQLite Cache:** Features a local SQLite database for offline database operations.
- **Cloud Sync:** Synchronizes local tables bidirectionally with Cloud Firestore. Google Sign-In is used to namespaces records `/users/{uid}/receivers/{id}`.
- **Biometric App Lock:** Secure your dashboard with biometrics (Face ID/Fingerprint) using local authentication APIs.

### 📊 Utility, Export & Import
- **CSV Data Export:** Generate and export receiver book lists directly into the device's public Download folder (`delimap_receivers.csv`).
- **CSV Data Import:** Import receiver lists from `.csv` files. Features automatic header mapping, duplicate prevention (based on name/address matches), and geocoding fallbacks with warning alerts.

---

## 🛠️ Technology Stack

- **Framework:** [Flutter](https://flutter.dev) (Dart)
- **Database:** SQLite (local) & Cloud Firestore (sync)
- **Authentication:** Google Sign-In & Firebase Auth
- **AI/ML:** Google ML Kit Text Recognition
- **Mapping:** Google Maps Flutter SDK & OSRM Engine
- **Local Auth:** Biometrics (Face ID / Fingerprint)

---

## 🚀 Getting Started

Since this project is open-source, all sensitive API keys and Firebase credentials have been decoupled into local config files. Follow these setup steps to compile the application locally.

### 📋 Prerequisites
- Flutter SDK (v3.18.0 or newer)
- Android SDK & Build Tools (v34 or newer)
- Cocoapods (for iOS development)
- A Firebase Project (with Firestore and Google Sign-in enabled)

---

## 🔒 Configuration & API Setup

You must create and populate the local configuration files before running the project.

### 1. Dart Layer (Google Maps API Key)
Copy the template file to create the local config:
```bash
cp lib/config/api_keys.dart.template lib/config/api_keys.dart
```
Edit the newly created `lib/config/api_keys.dart` and add your Google Cloud Console API key:
```dart
class ApiKeys {
  static const String googleMapsKey = 'YOUR_GOOGLE_MAPS_API_KEY';
}
```

### 2. Android Layer Setup
#### Firebase configuration
Download your `google-services.json` from the Firebase Console (under Android App settings) and place it in:
```path
android/app/google-services.json
```
For reference on its structure, see the [google-services.json.template](android/app/google-services.json.template) file.

#### Google Maps SDK configuration
Open `android/local.properties` (which is gitignored) and add your Google Maps API key at the bottom:
```properties
googleMapsApiKey=YOUR_GOOGLE_MAPS_API_KEY
```

---

### 3. iOS Layer Setup
#### Google Maps SDK configuration
Copy the template file:
```bash
cp ios/Flutter/Secrets.xcconfig.template ios/Flutter/Secrets.xcconfig
```
Open `ios/Flutter/Secrets.xcconfig` and input your Google Maps API key:
```config
GOOGLE_MAPS_API_KEY = YOUR_GOOGLE_MAPS_API_KEY
```
Xcode will conditionally include this configuration at build time to register the Maps SDK.

---

## 📦 Building the Application

### 📱 Android
To compile and package a release version of the application:
1. Ensure your device or emulator is connected.
2. Run the helper build script:
   ```bash
   ./build_apk.sh
   ```
3. The script will automatically trigger `flutter build apk --release` and save the compiled binary in the `apks/` directory.

### 🍎 iOS
To run on iOS Simulator or Device:
1. Fetch pods:
   ```bash
   cd ios && pod install && cd ..
   ```
2. Run the application:
   ```bash
   flutter run
   ```

---

## 🤝 Contributing
Contributions are welcome! Please feel free to open a Pull Request or report bugs via the Issues page.

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details.
