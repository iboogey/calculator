/// Someone I lend to or borrow from.
class DebtPerson {
  const DebtPerson({this.id, required this.name, required this.createdAt});

  factory DebtPerson.fromMap(Map<String, Object?> map) => DebtPerson(
        id: map['id'] as int?,
        name: map['name'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );

  final int? id;
  final String name;
  final DateTime createdAt;

  DebtPerson withId(int id) =>
      DebtPerson(id: id, name: name, createdAt: createdAt);

  DebtPerson copyWith({String? name}) =>
      DebtPerson(id: id, name: name ?? this.name, createdAt: createdAt);

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  @override
  bool operator ==(Object other) =>
      other is DebtPerson &&
      other.id == id &&
      other.name == name &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, createdAt);
}
