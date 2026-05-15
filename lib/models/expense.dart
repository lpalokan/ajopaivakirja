enum ExpenseType {
  parking('Pysäköinti'),
  toll('Tietulli'),
  meal('Ateria'),
  other('Muu');

  final String displayName;
  const ExpenseType(this.displayName);
}

class Expense {
  final int? id;
  final int? tripLegId;
  final ExpenseType type;
  final double amount;
  final String? description;
  final String createdAt;

  const Expense({
    this.id,
    this.tripLegId,
    required this.type,
    required this.amount,
    this.description,
    required this.createdAt,
  });

  Expense copyWith({
    int? id,
    int? tripLegId,
    ExpenseType? type,
    double? amount,
    String? description,
    String? createdAt,
  }) {
    return Expense(
      id: id ?? this.id,
      tripLegId: tripLegId ?? this.tripLegId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'trip_leg_id': tripLegId,
      'type': type.index,
      'amount': amount,
      'description': description,
      'created_at': createdAt,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    final typeIndex = map['type'] as int? ?? 0;
    return Expense(
      id: map['id'] as int?,
      tripLegId: map['trip_leg_id'] as int?,
      type: ExpenseType.values[typeIndex.clamp(0, ExpenseType.values.length - 1)],
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      description: map['description'] as String?,
      createdAt: map['created_at'] as String,
    );
  }

  @override
  String toString() =>
      'Expense(id: $id, ${type.displayName}, ${amount.toStringAsFixed(2)}€)';
}
