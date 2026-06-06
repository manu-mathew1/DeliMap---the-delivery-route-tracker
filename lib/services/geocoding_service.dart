import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_keys.dart';

class GeocodingResult {
  final double latitude;
  final double longitude;
  final String formattedAddress;

  GeocodingResult({
    required this.latitude,
    required this.longitude,
    required this.formattedAddress,
  });
}

class GeocodingService {
  // Geocode address text into latitude/longitude with optional location bias
  static Future<GeocodingResult?> geocodeAddress(
    String address, {
    double? biasLatitude,
    double? biasLongitude,
    double biasRadiusMeters = 2000.0, // Default 2km search radius bias
  }) async {
    final apiKey = ApiKeys.googleMapsKey;
    if (apiKey.isEmpty || apiKey == 'YOUR_GOOGLE_MAPS_API_KEY') {
      print('Google Maps API Key is not configured.');
      return null;
    }

    final encodedAddress = Uri.encodeComponent(address);
    String urlString = 'https://maps.googleapis.com/maps/api/geocode/json?address=$encodedAddress&key=$apiKey';

    // If we have a local similarity coordinate bias, append it to location bias
    if (biasLatitude != null && biasLongitude != null) {
      urlString += '&location=$biasLatitude,$biasLongitude&radius=$biasRadiusMeters';
      print('Applying Geocoding Bias Location: $biasLatitude, $biasLongitude within $biasRadiusMeters meters');
    }

    try {
      final response = await http.get(Uri.parse(urlString));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];

        if (status == 'OK') {
          final results = data['results'] as List;
          if (results.isNotEmpty) {
            final result = results.first;
            final geometry = result['geometry'];
            final location = geometry['location'];
            final lat = location['lat'] as double;
            final lng = location['lng'] as double;
            final formatted = result['formatted_address'] as String;

            return GeocodingResult(
              latitude: lat,
              longitude: lng,
              formattedAddress: formatted,
            );
          }
        } else {
          print('Geocoding API returned status: $status');
        }
      } else {
        print('Geocoding HTTP Request failed with code: ${response.statusCode}');
      }
    } catch (e) {
      print('Geocoding Service Error: $e');
    }

    return null;
  }
}
