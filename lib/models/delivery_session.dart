enum SessionStatus { active, completed }

class DeliverySession {
  final String id;
  final DateTime date;
  final SessionStatus status;

  DeliverySession({
    required this.id,
    required this.date,
    required this.status,
  });

  DeliverySession copyWith({
    String? id,
    DateTime? date,
    SessionStatus? status,
  }) {
    return DeliverySession(
      id: id ?? this.id,
      date: date ?? this.date,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'status': status.name,
    };
  }

  factory DeliverySession.fromMap(Map<String, dynamic> map) {
    return DeliverySession(
      id: map['id'] as String,
      date: DateTime.parse(map['date'] as String),
      status: SessionStatus.values.byName(map['status'] as String? ?? 'active'),
    );
  }
}
