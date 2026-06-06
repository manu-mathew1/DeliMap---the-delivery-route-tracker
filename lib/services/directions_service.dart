import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../config/api_keys.dart';

class DirectionsService {
  // Fetch road routing points between start location and optimized stops
  static Future<List<LatLng>?> fetchRoutePoints({
    required double startLat,
    required double startLng,
    required List<LatLng> stops,
  }) async {
    if (stops.isEmpty) return [];

    // 1. Try Google Directions API first if API key is configured
    final apiKey = ApiKeys.googleMapsKey;
    if (apiKey.isNotEmpty && apiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
      final googlePoints = await _fetchGoogleDirections(startLat, startLng, stops, apiKey);
      if (googlePoints != null && googlePoints.isNotEmpty) {
        return googlePoints;
      }
    }

    // 2. Fallback to Open Source Routing Machine (OSRM) if Google fails/restricted
    print('Directions Service: Falling back to Open Source Routing Machine (OSRM) for exact road route.');
    return await _fetchOsrmDirections(startLat, startLng, stops);
  }

  // Fetches road routing from Google Directions API
  static Future<List<LatLng>?> _fetchGoogleDirections(
    double startLat,
    double startLng,
    List<LatLng> stops,
    String apiKey,
  ) async {
    final String originStr = '$startLat,$startLng';
    final String destStr = '${stops.last.latitude},${stops.last.longitude}';

    // Intermediate stops form waypoints
    final List<String> waypointCoords = [];
    for (int i = 0; i < stops.length - 1; i++) {
      waypointCoords.add('${stops[i].latitude},${stops[i].longitude}');
    }

    String urlString = 'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destStr&key=$apiKey';
    if (waypointCoords.isNotEmpty) {
      urlString += '&waypoints=${waypointCoords.join('|')}';
    }

    try {
      final response = await http.get(Uri.parse(urlString)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final status = data['status'];

        if (status == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes.first;
            final overviewPolyline = route['overview_polyline'];
            if (overviewPolyline != null) {
              final pointsStr = overviewPolyline['points'] as String;
              return _decodePolyline(pointsStr);
            }
          }
        } else {
          print('Directions API returned status: $status - ${data['error_message'] ?? 'No message'}');
        }
      } else {
        print('Directions HTTP Request failed with code: ${response.statusCode}');
      }
    } catch (e) {
      print('Directions Service Google Error: $e');
    }
    return null;
  }

  // Fetches road routing from OSRM (Open Source Routing Machine) API
  static Future<List<LatLng>?> _fetchOsrmDirections(
    double startLat,
    double startLng,
    List<LatLng> stops,
  ) async {
    final List<String> coordsList = [];
    coordsList.add('$startLng,$startLat');
    for (final stop in stops) {
      coordsList.add('${stop.longitude},${stop.latitude}');
    }

    final String urlString = 'https://router.project-osrm.org/route/v1/driving/${coordsList.join(';')}?overview=full&geometries=geojson';

    try {
      final response = await http.get(Uri.parse(urlString)).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['code'] == 'Ok') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final route = routes.first;
            final geometry = route['geometry'];
            if (geometry != null) {
              final coordinates = geometry['coordinates'] as List;
              final List<LatLng> points = [];
              for (final coord in coordinates) {
                if (coord is List && coord.length >= 2) {
                  final double lng = (coord[0] as num).toDouble();
                  final double lat = (coord[1] as num).toDouble();
                  points.add(LatLng(lat, lng));
                }
              }
              return points;
            }
          }
        } else {
          print('OSRM API returned code: ${data['code']}');
        }
      } else {
        print('OSRM HTTP Request failed with code: ${response.statusCode}');
      }
    } catch (e) {
      print('Directions Service OSRM Error: $e');
    }
    return null;
  }

  // Decodes Google Maps encoded polyline string into LatLng list
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }
}
