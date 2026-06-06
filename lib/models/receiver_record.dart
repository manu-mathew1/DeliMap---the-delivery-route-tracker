class ReceiverRecord {
  final String id;
  final String name;
  final String addressText;
  final double latitude;
  final double longitude;
  final String notes;
  final int deliveryCount;
  final DateTime? lastDelivered;
  final bool isVerified;
  final int lastUpdated;

  ReceiverRecord({
    required this.id,
    required this.name,
    required this.addressText,
    required this.latitude,
    required this.longitude,
    this.notes = '',
    this.deliveryCount = 0,
    this.lastDelivered,
    this.isVerified = false,
    int? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now().millisecondsSinceEpoch;

  ReceiverRecord copyWith({
    String? id,
    String? name,
    String? addressText,
    double? latitude,
    double? longitude,
    String? notes,
    int? deliveryCount,
    DateTime? lastDelivered,
    bool? isVerified,
    int? lastUpdated,
  }) {
    return ReceiverRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      addressText: addressText ?? this.addressText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      notes: notes ?? this.notes,
      deliveryCount: deliveryCount ?? this.deliveryCount,
      lastDelivered: lastDelivered ?? this.lastDelivered,
      isVerified: isVerified ?? this.isVerified,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address_text': addressText,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
      'delivery_count': deliveryCount,
      'last_delivered': lastDelivered?.toIso8601String(),
      'is_verified': isVerified ? 1 : 0,
      'last_updated': lastUpdated,
    };
  }

  factory ReceiverRecord.fromMap(Map<String, dynamic> map) {
    return ReceiverRecord(
      id: map['id'] as String,
      name: map['name'] as String,
      addressText: map['address_text'] as String,
      latitude: map['latitude'] as double,
      longitude: map['longitude'] as double,
      notes: map['notes'] as String? ?? '',
      deliveryCount: map['delivery_count'] as int? ?? 0,
      lastDelivered: map['last_delivered'] != null
          ? DateTime.tryParse(map['last_delivered'] as String)
          : null,
      isVerified: (map['is_verified'] as int? ?? 0) == 1,
      lastUpdated: map['last_updated'] as int? ?? 0,
    );
  }
}
