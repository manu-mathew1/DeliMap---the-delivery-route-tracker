import 'dart:async';
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
      version: 2,
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
