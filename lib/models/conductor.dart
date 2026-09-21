import '../data/field_compat.dart';

class Conductor {
  const Conductor({
    required this.conductorId,
    required this.name,
    required this.phoneNumber,
    required this.rating,
  });

  final String conductorId;
  final String name;
  final String phoneNumber;
  final double rating;

  factory Conductor.fromMap(Map<String, dynamic> map, String docId) {
    return Conductor(
      conductorId: asString(pick(map, 'conductorId', 'conductor_id'), docId),
      name: asString(map['name']),
      phoneNumber: asString(pick(map, 'phoneNumber', 'phone_number')),
      rating: asDouble(map['rating']),
    );
  }
}
