import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/receiver_record.dart';
import 'geocoding_service.dart';

class ImportResult {
  final int importedCount;
  final int duplicateCount;
  final int errorCount;

  ImportResult({
    required this.importedCount,
    required this.duplicateCount,
    required this.errorCount,
  });
}

class ImportService {
  /// Opens file picker and returns the parsed CSV rows, or null if cancelled.
  /// Throws Exception if file is invalid or empty.
  static Future<List<List<dynamic>>?> pickAndParseCSV() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (result == null || result.files.single.path == null) {
        return null; // User cancelled
      }

      final file = File(result.files.single.path!);
      String csvString;
      try {
        csvString = await file.readAsString(encoding: utf8);
      } catch (_) {
        // Fallback to Latin-1 if file is not UTF-8 encoded
        csvString = await file.readAsString(encoding: latin1);
      }

      final List<List<dynamic>> rows = const CsvDecoder().convert(csvString);
      if (rows.isEmpty) {
        throw Exception("The selected CSV file is empty.");
      }

      return rows;
    } catch (e) {
      print("CSV File Picker Error: $e");
      rethrow;
    }
  }

  /// Maps the columns of the CSV based on headers.
  /// Returns a Map of column indices.
  static Map<String, int> mapHeaders(List<dynamic> headerRow) {
    final headers = headerRow.map((e) => e.toString().toLowerCase().trim()).toList();

    int nameIdx = headers.indexWhere((h) => h.contains('name') || h == 'receiver' || h == 'buyer' || h == 'customer');
    int addressIdx = headers.indexWhere((h) => h.contains('address') || h == 'location' || h == 'street' || h == 'place');
    int latIdx = headers.indexWhere((h) => h == 'latitude' || h == 'lat');
    int lngIdx = headers.indexWhere((h) => h == 'longitude' || h == 'lng' || h == 'lon');
    int notesIdx = headers.indexWhere((h) => h.contains('note') || h == 'comment' || h == 'info');

    return {
      'name': nameIdx,
      'address': addressIdx,
      'latitude': latIdx,
      'longitude': lngIdx,
      'notes': notesIdx,
    };
  }

  /// Process the rows, geocode if needed, and save to database.
  static Future<ImportResult> processImport({
    required List<List<dynamic>> rows,
    required Map<String, int> columnMapping,
    required Function(String status, double progress) onProgress,
  }) async {
    final nameIdx = columnMapping['name']!;
    final addressIdx = columnMapping['address']!;
    final latIdx = columnMapping['latitude']!;
    final lngIdx = columnMapping['longitude']!;
    final notesIdx = columnMapping['notes']!;

    int imported = 0;
    int duplicates = 0;
    int errors = 0;

    final totalRows = rows.length - 1; // Exclude header row

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= nameIdx || row.length <= addressIdx) {
        errors++;
        continue;
      }

      final name = row[nameIdx]?.toString().trim() ?? '';
      final address = row[addressIdx]?.toString().trim() ?? '';

      if (name.isEmpty || address.isEmpty) {
        errors++;
        continue;
      }

      final currentProgress = i / totalRows;
      onProgress("Checking duplicate: $name", currentProgress);

      // Check for exact duplicate in DB (case-insensitive, trimmed)
      final existing = await DatabaseHelper.instance.getReceiverByNameAndAddress(name, address);
      if (existing != null) {
        duplicates++;
        continue;
      }

      // Parse coordinates if available
      double? lat;
      double? lng;

      if (latIdx != -1 && latIdx < row.length) {
        lat = double.tryParse(row[latIdx]?.toString() ?? '');
      }
      if (lngIdx != -1 && lngIdx < row.length) {
        lng = double.tryParse(row[lngIdx]?.toString() ?? '');
      }

      bool isVerified = true;

      // If coordinates are missing or invalid, resolve via Geocoding Service
      if (lat == null || lng == null) {
        onProgress("Geocoding location: $name", currentProgress);
        final geocodeResult = await GeocodingService.geocodeAddress(address);
        if (geocodeResult != null) {
          lat = geocodeResult.latitude;
          lng = geocodeResult.longitude;
        } else {
          // If geocoding fails, fallback to 0.0, 0.0 and mark as unverified
          lat = 0.0;
          lng = 0.0;
          isVerified = false;
        }
        // Small delay to respect Google Geocoding API rate limits
        await Future.delayed(const Duration(milliseconds: 150));
      }

      final notes = notesIdx != -1 && notesIdx < row.length ? row[notesIdx]?.toString().trim() ?? '' : '';

      final newReceiver = ReceiverRecord(
        id: const Uuid().v4(),
        name: name,
        addressText: address,
        latitude: lat,
        longitude: lng,
        notes: notes,
        isVerified: isVerified,
      );

      // Save to local SQLite and sync with Cloud Firestore
      await DatabaseHelper.instance.insertReceiver(newReceiver);
      imported++;
    }

    return ImportResult(
      importedCount: imported,
      duplicateCount: duplicates,
      errorCount: errors,
    );
  }
}
