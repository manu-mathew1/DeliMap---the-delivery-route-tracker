import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../db/database_helper.dart';
import '../models/receiver_record.dart';

class CloudSyncService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // Perform a full bidirectional synchronization
  static Future<void> syncReceivers() async {
    final User? user = _auth.currentUser;
    if (user == null) {
      print('CloudSyncService: No authenticated user. Sync skipped.');
      return;
    }

    final String uid = user.uid;
    final CollectionReference receiversRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('receivers');

    try {
      // 1. Fetch local records from SQLite
      final List<ReceiverRecord> localRecords = await DatabaseHelper.instance.getAllReceivers();
      final Map<String, ReceiverRecord> localMap = {
        for (var r in localRecords) r.id: r
      };

      // 2. Fetch cloud records from Firestore
      final QuerySnapshot cloudSnapshot = await receiversRef.get();
      final Map<String, DocumentSnapshot> cloudMap = {
        for (var doc in cloudSnapshot.docs) doc.id: doc
      };

      final WriteBatch batch = _firestore.batch();
      int batchCount = 0;

      // 3. Compare local records with cloud
      for (final local in localRecords) {
        final cloudDoc = cloudMap[local.id];
        if (cloudDoc == null) {
          // Local record is missing in cloud -> upload it
          batch.set(receiversRef.doc(local.id), local.toMap());
          batchCount++;
        } else {
          // Record exists in both -> compare timestamps
          final Map<String, dynamic> cloudData = cloudDoc.data() as Map<String, dynamic>;
          final int cloudLastUpdated = cloudData['last_updated'] as int? ?? 0;

          if (local.lastUpdated > cloudLastUpdated) {
            // Local record is newer -> upload it
            batch.set(receiversRef.doc(local.id), local.toMap());
            batchCount++;
          } else if (cloudLastUpdated > local.lastUpdated) {
            // Cloud record is newer -> download it to local SQLite (preserving updated timestamp)
            final updatedLocal = ReceiverRecord.fromMap(cloudData);
            await DatabaseHelper.instance.insertReceiver(updatedLocal);
          }
        }
      }

      // 4. Compare cloud records with local
      for (final cloudDoc in cloudSnapshot.docs) {
        final Map<String, dynamic> cloudData = cloudDoc.data() as Map<String, dynamic>;
        final String cloudId = cloudDoc.id;

        if (!localMap.containsKey(cloudId)) {
          // Cloud record is missing locally -> download it
          final newLocal = ReceiverRecord.fromMap(cloudData);
          await DatabaseHelper.instance.insertReceiver(newLocal);
        }
      }

      // Commit batch uploads if any
      if (batchCount > 0) {
        await batch.commit();
        print('CloudSyncService: Uploaded $batchCount records to Cloud Firestore.');
      }

      print('CloudSyncService: Bidirectional sync completed successfully.');
    } catch (e) {
      print('CloudSyncService: Error during sync: $e');
      rethrow;
    }
  }

  // Delete a receiver from the cloud when deleted locally
  static Future<void> deleteFromCloud(String id) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('receivers')
          .doc(id)
          .delete();
      print('CloudSyncService: Deleted receiver $id from Cloud Firestore.');
    } catch (e) {
      print('CloudSyncService: Error deleting from Cloud Firestore: $e');
    }
  }

  // Upload or update a single receiver record immediately
  static Future<void> saveToCloud(ReceiverRecord receiver) async {
    final User? user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('receivers')
          .doc(receiver.id)
          .set(receiver.toMap());
      print('CloudSyncService: Saved receiver ${receiver.id} to Cloud Firestore.');
    } catch (e) {
      print('CloudSyncService: Error saving single receiver to Cloud Firestore: $e');
    }
  }

  // Check if we can reach the cloud Firestore database
  static Future<bool> checkConnection() async {
    final User? user = _auth.currentUser;
    if (user == null) return false;

    try {
      // Force fetching from server with a short timeout to verify online connection
      await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      print('CloudSyncService: Connection check failed: $e');
      return false;
    }
  }
}
