enum PackageStatus { pending, delivered, failed }

class PackageItem {
  final String id;
  final String sessionId;
  final String name;
  final String addressText;
  final PackageStatus status;
  final DateTime scannedAt;
  final DateTime? deliveredAt;
  final String? receiverId; // Link to ReceiverRecord if identified
  final double? latitude;    // Temporary or resolved GPS latitude
  final double? longitude;   // Temporary or resolved GPS longitude
  final String notes;

  PackageItem({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.addressText,
    required this.status,
    required this.scannedAt,
    this.deliveredAt,
    this.receiverId,
    this.latitude,
    this.longitude,
    this.notes = '',
  });

  PackageItem copyWith({
    String? id,
    String? sessionId,
    String? name,
    String? addressText,
    PackageStatus? status,
    DateTime? scannedAt,
    DateTime? deliveredAt,
    String? receiverId,
    double? latitude,
    double? longitude,
    String? notes,
  }) {
    return PackageItem(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      name: name ?? this.name,
      addressText: addressText ?? this.addressText,
      status: status ?? this.status,
      scannedAt: scannedAt ?? this.scannedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      receiverId: receiverId ?? this.receiverId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'name': name,
      'address_text': addressText,
      'status': status.name,
      'scanned_at': scannedAt.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'receiver_id': receiverId,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
    };
  }

  factory PackageItem.fromMap(Map<String, dynamic> map) {
    return PackageItem(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      name: map['name'] as String,
      addressText: map['address_text'] as String,
      status: PackageStatus.values.byName(map['status'] as String? ?? 'pending'),
      scannedAt: DateTime.parse(map['scanned_at'] as String),
      deliveredAt: map['delivered_at'] != null
          ? DateTime.tryParse(map['delivered_at'] as String)
          : null,
      receiverId: map['receiver_id'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      notes: map['notes'] as String? ?? '',
    );
  }
}
