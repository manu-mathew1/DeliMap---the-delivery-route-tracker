import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:delimap/models/package_item.dart';

class DeliveryStop {
  final String id;
  final String name;
  final String addressText;
  final double? latitude;
  final double? longitude;
  final List<PackageItem> packages;

  DeliveryStop({
    required this.id,
    required this.name,
    required this.addressText,
    this.latitude,
    this.longitude,
    required this.packages,
  });

  LatLng? get latLng {
    if (latitude != null && longitude != null) {
      return LatLng(latitude!, longitude!);
    }
    return null;
  }

  // A stop is pending if any of its packages are pending
  bool get isPending => packages.any((p) => p.status == PackageStatus.pending);

  // A stop is delivered if all its packages are marked delivered
  bool get isDelivered => packages.every((p) => p.status == PackageStatus.delivered);

  // A stop is failed if all its packages failed
  bool get isFailed => packages.every((p) => p.status == PackageStatus.failed);

  // Check if this stop has notes
  String get combinedNotes {
    final notesList = packages.map((p) => p.notes).where((n) => n.trim().isNotEmpty).toList();
    if (notesList.isEmpty) return '';
    return notesList.toSet().join(' | '); // unique combined notes
  }

  DeliveryStop copyWith({
    String? id,
    String? name,
    String? addressText,
    double? latitude,
    double? longitude,
    List<PackageItem>? packages,
  }) {
    return DeliveryStop(
      id: id ?? this.id,
      name: name ?? this.name,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      packages: packages ?? this.packages,
    );
  }
}
