import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../db/database_helper.dart';
import '../models/receiver_record.dart';
import 'geocoding_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

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

  /// Opens file picker and returns a list of map records parsed from PDF, or null if cancelled.
  static Future<List<Map<String, dynamic>>?> pickAndParsePDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result == null || result.files.single.path == null) {
        return null; // User cancelled
      }

      final file = File(result.files.single.path!);
      final List<int> bytes = await file.readAsBytes();

      // Load PDF using Syncfusion PDF library
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      
      // Extract text from all pages
      final String fullText = PdfTextExtractor(document).extractText();
      
      // Dispose document to avoid leaks
      document.dispose();

      if (fullText.isEmpty) {
        throw Exception("The selected PDF file contains no readable text.");
      }

      // Regex to find all Tracking IDs: 4 uppercase letters followed by 10 digits
      final RegExp trackingRegExp = RegExp(r'[A-Z]{4}\d{10}');
      final Iterable<RegExpMatch> matches = trackingRegExp.allMatches(fullText);

      if (matches.isEmpty) {
        throw Exception("No tracking IDs (e.g. FMPC1234567890) found in the PDF.");
      }

      final List<RegExpMatch> matchList = matches.toList();
      final List<Map<String, dynamic>> records = [];

      for (int i = 0; i < matchList.length; i++) {
        final RegExpMatch currentMatch = matchList[i];
        final String trackingId = currentMatch.group(0)!;
        
        final int startIdx = currentMatch.end;
        final int endIdx = i + 1 < matchList.length ? matchList[i + 1].start : fullText.length;
        
        final String detailsText = fullText.substring(startIdx, endIdx).trim();
        records.add({
          'tracking_id': trackingId,
          'details': detailsText,
        });
      }

      final List<Map<String, dynamic>> parsedRecords = [];

      for (final r in records) {
        final String trackingId = r['tracking_id'] as String;
        final String rawDetails = r['details'] as String;
        
        // Clean up text spacing and replace newlines with spaces
        final String cleanDetails = rawDetails.replaceAll(RegExp(r'\s+'), ' ');

        // Date-time pattern: YYYY-MM-DD followed optionally by time, priority (P0-P4), amount, and address
        final RegExp dtRegExp = RegExp(r'(\d{4}-\d{2}-\d{2}(?:\s?\d{2}:\d{2}:\d{2})?)\s*(P\d)\s*(\d+)\s*(.*)');
        final RegExpMatch? dtMatch = dtRegExp.firstMatch(cleanDetails);

        if (dtMatch != null) {
          final String priority = dtMatch.group(2)!;
          final String amountStr = dtMatch.group(3)!;
          final String remainder = dtMatch.group(4)!;

          // Extract pincode (6-digit number starting with 6) and status
          final RegExp pincodeRegExp = RegExp(r'(6\d{5})\s*(.*)');
          final RegExpMatch? pincodeMatch = pincodeRegExp.firstMatch(remainder);

          String address = remainder;
          String statusText = "";
          String pincode = "";

          if (pincodeMatch != null) {
            pincode = pincodeMatch.group(1)!;
            statusText = pincodeMatch.group(2)!.trim();
            address = remainder.substring(0, pincodeMatch.start).trim();
          }

          // Clean up address
          if (address.endsWith(',')) {
            address = address.substring(0, address.length - 1).trim();
          }

          // Determine name: use first comma-separated segment, or first 2 words if no comma
          String name = "";
          if (address.contains(',')) {
            name = address.split(',')[0].trim();
          } else {
            final List<String> words = address.split(' ');
            name = words.length >= 2 ? "${words[0]} ${words[1]}" : address;
          }

          // Limit status code to raw text
          if (statusText.length > 50) {
            statusText = statusText.substring(0, 50).trim();
          }

          parsedRecords.add({
            'id': trackingId,
            'name': name,
            'addressText': '$address ${pincode.isNotEmpty ? pincode : ""}'.trim(),
            'notes': 'Priority: $priority | COD Amount: $amountStr${statusText.isNotEmpty ? ' | Status: $statusText' : ''}',
          });
        } else {
          // Fallback parsing if structure differs
          parsedRecords.add({
            'id': trackingId,
            'name': 'Customer $trackingId',
            'addressText': cleanDetails.length > 100 ? cleanDetails.substring(0, 100) : cleanDetails,
            'notes': 'Unparsed data: $cleanDetails',
          });
        }
      }

      return parsedRecords;
    } catch (e) {
      print("PDF Parser Error: $e");
      rethrow;
    }
  }

  /// Process the parsed PDF records, geocode if needed, and save to database.
  static Future<ImportResult> processPDFImport({
    required List<Map<String, dynamic>> records,
    required Function(String status, double progress) onProgress,
  }) async {
    int imported = 0;
    int duplicates = 0;
    int errors = 0;

    final totalRecords = records.length;

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      final String trackingId = r['id'] as String;
      final String name = r['name'] as String;
      final String address = r['addressText'] as String;
      final String notes = r['notes'] as String;

      final currentProgress = (i + 1) / totalRecords;
      onProgress("Checking duplicate: $trackingId", currentProgress);

      // Check for exact duplicate in DB (by AWB / tracking ID primary key)
      final existing = await DatabaseHelper.instance.getReceiver(trackingId);
      if (existing != null) {
        duplicates++;
        continue;
      }

      onProgress("Geocoding location: $name", currentProgress);
      
      double? lat;
      double? lng;
      bool isVerified = true;

      // Geocode the address text
      final geocodeResult = await GeocodingService.geocodeAddress(address);
      if (geocodeResult != null) {
        lat = geocodeResult.latitude;
        lng = geocodeResult.longitude;
      } else {
        // Fallback to 0.0, 0.0 and mark as unverified
        lat = 0.0;
        lng = 0.0;
        isVerified = false;
      }

      // Small delay to respect Google Geocoding API limits
      await Future.delayed(const Duration(milliseconds: 150));

      final newReceiver = ReceiverRecord(
        id: trackingId, // Use Tracking ID as primary key
        name: name,
        addressText: address,
        latitude: lat,
        longitude: lng,
        notes: notes,
        isVerified: isVerified,
      );

      try {
        await DatabaseHelper.instance.insertReceiver(newReceiver);
        imported++;
      } catch (e) {
        print("Error inserting receiver $trackingId: $e");
        errors++;
      }
    }

    return ImportResult(
      importedCount: imported,
      duplicateCount: duplicates,
      errorCount: errors,
    );
  }
}
