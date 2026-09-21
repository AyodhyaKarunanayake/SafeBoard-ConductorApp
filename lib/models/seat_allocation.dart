import '../data/field_compat.dart';
import 'zone.dart';

class SeatAllocation {
  const SeatAllocation({
    required this.allocationId,
    required this.bookingId,
    required this.seatId,
    required this.seatNumber,
    required this.busId,
    required this.journeyId,
    required this.allocationDatetime,
    required this.boardingStop,
    required this.alightingStop,
    required this.allocationType,
    required this.riskScore,
    required this.status,
    required this.qrCode,
    required this.priorityReserved,
  });

  final String allocationId;
  final String bookingId;
  final String seatId;
  final String seatNumber;
  final String busId;
  final String journeyId;
  final DateTime? allocationDatetime;
  final String boardingStop;
  final String alightingStop;
  final String allocationType;
  final double riskScore;
  final String status;
  final String qrCode;
  final bool priorityReserved;

  /// Not stored in the schema; derived from [seatNumber].
  Zone get zone => Zone.fromSeatNumber(seatNumber);

  /// Only 'active' allocations occupy a seat ('released' ones are freed). A
  /// document with no status is treated as active.
  bool get isActive {
    final s = status.trim().toLowerCase();
    return s.isEmpty || s == 'active';
  }

  /// The short reference (SB-XXXXXX) the passenger app shows on the ticket, so
  /// a conductor can match a passenger's ticket by eye. It is computed, not
  /// stored, using the passenger app's exact formula. It relies on
  /// String.hashCode, so it only matches when both apps run on the same Dart
  /// runtime (e.g. both Android); a web build may compute a different code.
  String get referenceCode {
    final code = allocationId.hashCode
        .abs()
        .toRadixString(36)
        .toUpperCase()
        .padLeft(6, '0');
    return 'SB-${code.substring(code.length - 6)}';
  }

  factory SeatAllocation.fromMap(Map<String, dynamic> map, String docId) {
    final seatId = asString(pick(map, 'seatId', 'seat_id'));
    return SeatAllocation(
      allocationId: asString(pick(map, 'allocationId', 'allocation_id'), docId),
      bookingId: asString(pick(map, 'bookingId', 'booking_id')),
      seatId: seatId,
      seatNumber: asString(pick(map, 'seatNumber', 'seat_number'), seatId),
      busId: asString(pick(map, 'busId', 'bus_id')),
      journeyId: asString(pick(map, 'journeyId', 'journey_id')),
      allocationDatetime:
          asDateTime(pick(map, 'allocationDatetime', 'allocation_datetime')),
      boardingStop: asString(pick(map, 'boardingStop', 'boarding_stop')),
      alightingStop: asString(pick(map, 'alightingStop', 'alighting_stop')),
      allocationType: asString(pick(map, 'allocationType', 'allocation_type')),
      riskScore: asDouble(pick(map, 'riskScore', 'risk_score')),
      status: asString(map['status']),
      qrCode: asString(pick(map, 'qrCode', 'qr_code')),
      priorityReserved:
          asBool(pick(map, 'priorityReserved', 'priority_reserved')),
    );
  }
}
