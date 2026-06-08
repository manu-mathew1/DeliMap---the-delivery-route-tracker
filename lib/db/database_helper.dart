import 'dart:async';
import 'dart:math';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/receiver_record.dart';
import '../models/delivery_session.dart';
import '../models/package_item.dart';
import '../services/cloud_sync_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('delimap.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Receivers table (Address Intelligence Book)
    await db.execute('''
      CREATE TABLE receivers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        address_text TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        notes TEXT NOT NULL,
        delivery_count INTEGER NOT NULL,
        last_delivered TEXT,
        is_verified INTEGER NOT NULL,
        last_updated INTEGER DEFAULT 0
      )
    ''');

    // Index name + address for fast exact matching
    await db.execute('CREATE INDEX idx_receivers_name_address ON receivers (name, address_text)');

    // 2. Delivery Sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    // 3. Packages table
    await db.execute('''
      CREATE TABLE packages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        name TEXT NOT NULL,
        address_text TEXT NOT NULL,
        status TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        delivered_at TEXT,
        receiver_id TEXT,
        latitude REAL,
        longitude REAL,
        notes TEXT NOT NULL,
        type TEXT DEFAULT 'delivery',
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute('ALTER TABLE receivers ADD COLUMN last_updated INTEGER DEFAULT 0');
      } catch (e) {
        print('Database upgrade error: $e');
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute("ALTER TABLE packages ADD COLUMN type TEXT DEFAULT 'delivery'");
      } catch (e) {
        print('Database upgrade v3 error: $e');
      }
    }
  }

  // ==========================================
  // RECEIVERS (Address Intelligence) CRUD
  // ==========================================

  Future<String> insertReceiver(ReceiverRecord receiver, {bool syncToCloud = true}) async {
    final db = await instance.database;
    await db.insert(
      'receivers',
      receiver.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (syncToCloud) {
      CloudSyncService.saveToCloud(receiver);
    }
    return receiver.id;
  }

  Future<ReceiverRecord?> getReceiver(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'receivers',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return ReceiverRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<ReceiverRecord?> getReceiverByNameAndAddress(String name, String addressText) async {
    final db = await instance.database;
    final maps = await db.query(
      'receivers',
      where: 'LOWER(name) = ? AND LOWER(address_text) = ?',
      whereArgs: [name.trim().toLowerCase(), addressText.trim().toLowerCase()],
    );

    if (maps.isNotEmpty) {
      return ReceiverRecord.fromMap(maps.first);
    }
    return null;
  }

  Future<List<ReceiverRecord>> getReceiversByName(String name) async {
    final db = await instance.database;
    final maps = await db.query(
      'receivers',
      where: 'LOWER(name) = ?',
      whereArgs: [name.trim().toLowerCase()],
    );
    return maps.map((json) => ReceiverRecord.fromMap(json)).toList();
  }

  Future<int> updateReceiver(ReceiverRecord receiver, {bool syncToCloud = true}) async {
    final db = await instance.database;
    final res = await db.update(
      'receivers',
      receiver.toMap(),
      where: 'id = ?',
      whereArgs: [receiver.id],
    );
    if (syncToCloud && res > 0) {
      CloudSyncService.saveToCloud(receiver);
    }
    return res;
  }

  Future<int> deleteReceiver(String id, {bool syncToCloud = true}) async {
    final db = await instance.database;
    final res = await db.delete(
      'receivers',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (syncToCloud && res > 0) {
      CloudSyncService.deleteFromCloud(id);
    }
    return res;
  }

  Future<List<ReceiverRecord>> getAllReceivers() async {
    final db = await instance.database;
    final result = await db.query('receivers', orderBy: 'name ASC');
    return result.map((json) => ReceiverRecord.fromMap(json)).toList();
  }

  // Local Address Similarity Match (Fuzzy Search)
  // Calculates overlap coefficient of words in the address text
  Future<List<MapEntry<ReceiverRecord, double>>> findSimilarReceivers(String queryAddress, {double threshold = 0.5}) async {
    final all = await getAllReceivers();
    final queryTokens = _tokenizeAddress(queryAddress);
    if (queryTokens.isEmpty) return [];

    final List<MapEntry<ReceiverRecord, double>> matched = [];

    for (var receiver in all) {
      final dbTokens = _tokenizeAddress(receiver.addressText);
      if (dbTokens.isEmpty) continue;

      // Calculate intersection
      final intersection = queryTokens.intersection(dbTokens);
      final smallerSize = queryTokens.length < dbTokens.length ? queryTokens.length : dbTokens.length;
      
      // Overlap Coefficient
      final score = intersection.length / smallerSize;

      if (score >= threshold) {
        matched.add(MapEntry(receiver, score));
      }
    }

    // Sort descending by score
    matched.sort((a, b) => b.value.compareTo(a.value));
    return matched;
  }

  Set<String> _tokenizeAddress(String address) {
    // Convert to lowercase, remove common punctuation, split by whitespace and filter short words
    final clean = address.toLowerCase().replaceAll(RegExp(r'[,.\-/]'), ' ');
    return clean.split(RegExp(r'\s+'))
        .map((s) => s.trim())
        .where((s) => s.length > 2 && s != 'india') // ignore noise words
        .toSet();
  }

  // Calculate distance between two coordinates using the Haversine formula
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 - cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
        (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000; // Returns distance in meters
  }

  // Token-based Jaccard similarity for names
  double calculateNameSimilarity(String name1, String name2) {
    final Set<String> tokens1 = tokenizeName(name1);
    final Set<String> tokens2 = tokenizeName(name2);
    if (tokens1.isEmpty || tokens2.isEmpty) return 0.0;

    final intersection = tokens1.intersection(tokens2);
    final union = tokens1.union(tokens2);
    return intersection.length / union.length;
  }

  Set<String> tokenizeName(String name) {
    final clean = name.toLowerCase().replaceAll(RegExp('[,.\\-/()\'"]'), ' ');
    final ignoreList = {
      'mr', 'mrs', 'ms', 'miss', 'dr', 'prof', 'shri', 'smt', 'shree',
      'house', 'villa', 'home', 'h', 'ho', 'co', 'care', 'of'
    };
    return clean.split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.length > 1 && !ignoreList.contains(w))
        .toSet();
  }

  // Find a matching receiver record within maxDistanceMeters that has name similarity >= minNameSimilarity.
  // Returns the best matching receiver, or null if none found.
  Future<ReceiverRecord?> findNearbyReceiverMatch({
    required String name,
    required double latitude,
    required double longitude,
    double maxDistanceMeters = 1000.0,
    double minNameSimilarity = 0.60,
  }) async {
    final all = await getAllReceivers();
    ReceiverRecord? bestMatch;
    double bestNameSim = 0.0;
    double closestDistance = double.maxFinite;

    final double latRange = maxDistanceMeters / 111000.0; // 1 degree lat is ~111km
    final double cosLat = cos(latitude * 0.017453292519943295).abs();
    final double lngRange = cosLat > 0.1 ? (maxDistanceMeters / (111000.0 * cosLat)) : 0.5;

    for (var receiver in all) {
      if (receiver.latitude == null || receiver.longitude == null ||
          receiver.latitude == 0.0 || receiver.longitude == 0.0) {
        continue;
      }

      // Bounding box filter (fast check)
      if ((receiver.latitude! - latitude).abs() > latRange ||
          (receiver.longitude! - longitude).abs() > lngRange) {
        continue;
      }

      final distance = calculateDistance(
        latitude,
        longitude,
        receiver.latitude!,
        receiver.longitude!,
      );

      if (distance <= maxDistanceMeters) {
        final nameSim = calculateNameSimilarity(name, receiver.name);
        if (nameSim >= minNameSimilarity) {
          if (nameSim > bestNameSim) {
            bestNameSim = nameSim;
            bestMatch = receiver;
            closestDistance = distance;
          } else if (nameSim == bestNameSim) {
            if (distance < closestDistance) {
              bestMatch = receiver;
              closestDistance = distance;
            }
          }
        }
      }
    }
    return bestMatch;
  }

  // ==========================================
  // SESSIONS CRUD
  // ==========================================

  Future<String> insertSession(DeliverySession session) async {
    final db = await instance.database;
    await db.insert('sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return session.id;
  }

  Future<DeliverySession?> getSession(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return DeliverySession.fromMap(maps.first);
    }
    return null;
  }

  Future<DeliverySession?> getActiveSession() async {
    final db = await instance.database;
    final maps = await db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.active.name],
    );
    if (maps.isNotEmpty) {
      return DeliverySession.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateSession(DeliverySession session) async {
    final db = await instance.database;
    return db.update(
      'sessions',
      session.toMap(),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<List<DeliverySession>> getAllSessions() async {
    final db = await instance.database;
    final result = await db.query('sessions', orderBy: 'date DESC');
    return result.map((json) => DeliverySession.fromMap(json)).toList();
  }

  Future<void> prunePastSessions(int keepCount) async {
    final db = await instance.database;
    final completedSessions = await db.query(
      'sessions',
      where: 'status = ?',
      whereArgs: [SessionStatus.completed.name],
      orderBy: 'date DESC',
    );

    if (completedSessions.length > keepCount) {
      final sessionsToDelete = completedSessions.sublist(keepCount);
      for (final session in sessionsToDelete) {
        final id = session['id'] as String;
        // Delete packages belonging to this session
        await db.delete(
          'packages',
          where: 'session_id = ?',
          whereArgs: [id],
        );
        // Delete session itself
        await db.delete(
          'sessions',
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  // ==========================================
  // PACKAGES CRUD
  // ==========================================

  Future<String> insertPackage(PackageItem package) async {
    final db = await instance.database;
    await db.insert('packages', package.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    return package.id;
  }

  Future<PackageItem?> getPackage(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'packages',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return PackageItem.fromMap(maps.first);
    }
    return null;
  }

  Future<List<PackageItem>> getPackagesInSession(String sessionId) async {
    final db = await instance.database;
    final result = await db.query(
      'packages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'scanned_at ASC',
    );
    return result.map((json) => PackageItem.fromMap(json)).toList();
  }

  Future<int> updatePackage(PackageItem package) async {
    final db = await instance.database;
    return db.update(
      'packages',
      package.toMap(),
      where: 'id = ?',
      whereArgs: [package.id],
    );
  }

  Future<int> deletePackage(String id) async {
    final db = await instance.database;
    return await db.delete(
      'packages',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
