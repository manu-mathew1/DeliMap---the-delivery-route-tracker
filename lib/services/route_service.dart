import 'dart:math';
import '../models/package_item.dart';
import '../models/delivery_stop.dart';

class RouteService {
  // Groups packages by receiver or unique name/address combo
  static List<DeliveryStop> groupPackagesIntoStops(List<PackageItem> packages) {
    if (packages.isEmpty) return [];

    final Map<String, List<PackageItem>> grouped = {};
    for (final pkg in packages) {
      final String key = pkg.receiverId != null && pkg.receiverId!.isNotEmpty
          ? pkg.receiverId!
          : '${pkg.name.trim().toLowerCase()}_${pkg.addressText.trim().toLowerCase()}';
      grouped.putIfAbsent(key, () => []).add(pkg);
    }

    final List<DeliveryStop> stops = [];
    for (final entry in grouped.entries) {
      final pkgs = entry.value;
      // Get the first package that has valid coordinates
      final validPkg = pkgs.firstWhere(
        (p) => p.latitude != null && p.longitude != null,
        orElse: () => pkgs.first,
      );

      stops.add(
        DeliveryStop(
          id: entry.key,
          name: pkgs.first.name,
          addressText: pkgs.first.addressText,
          latitude: validPkg.latitude,
          longitude: validPkg.longitude,
          packages: pkgs,
        ),
      );
    }

    return stops;
  }

  // Calculates optimized route using nearest-neighbor heuristic
  static List<DeliveryStop> optimizeRoute({
    required double startLatitude,
    required double startLongitude,
    required List<DeliveryStop> stops,
  }) {
    if (stops.isEmpty) return [];

    // Filter stops that have valid coordinates
    final List<DeliveryStop> validStops = stops
        .where((s) => s.latitude != null && s.longitude != null)
        .toList();

    final List<DeliveryStop> invalidStops = stops
        .where((s) => s.latitude == null || s.longitude == null)
        .toList();

    final List<DeliveryStop> optimized = [];
    final List<DeliveryStop> remaining = List.from(validStops);

    double currentLat = startLatitude;
    double currentLng = startLongitude;

    while (remaining.isNotEmpty) {
      int nearestIndex = -1;
      double minDistance = double.maxFinite;

      for (int i = 0; i < remaining.length; i++) {
        final stop = remaining[i];
        final dist = _calculateHaversineDistance(
          currentLat,
          currentLng,
          stop.latitude!,
          stop.longitude!,
        );

        if (dist < minDistance) {
          minDistance = dist;
          nearestIndex = i;
        }
      }

      if (nearestIndex != -1) {
        final nextStop = remaining.removeAt(nearestIndex);
        optimized.add(nextStop);
        currentLat = nextStop.latitude!;
        currentLng = nextStop.longitude!;
      } else {
        break;
      }
    }

    // Append any un-geocoded stops at the very end
    optimized.addAll(invalidStops);

    return optimized;
  }

  // Calculate distance between two coordinates in kilometers using Haversine formula
  static double _calculateHaversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double r = 6371; // Earth's radius in kilometers
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRadians(double degree) {
    return degree * (pi / 180);
  }
}
