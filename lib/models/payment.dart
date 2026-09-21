import '../data/field_compat.dart';

/// A row of the passenger app's `payments` collection.
class Payment {
  const Payment({
    required this.paymentId,
    required this.allocationId,
    required this.journeyId,
    required this.method,
    required this.amountLkr,
    required this.status,
    required this.timestamp,
    required this.reference,
  });

  final String paymentId;
  final String allocationId;
  final String journeyId;

  /// 'card' | 'mobile_wallet' | 'conductor'
  final String method;
  final double amountLkr;

  /// 'completed' | 'pay_on_board'
  final String status;
  final DateTime? timestamp;
  final String reference;

  static const String methodConductor = 'conductor';
  static const String statusPayOnBoard = 'pay_on_board';
  static const String statusCompleted = 'completed';

  bool get isPayOnBoard => status == statusPayOnBoard;
  bool get isPaid => status == statusCompleted;

  factory Payment.fromMap(Map<String, dynamic> map, String docId) {
    return Payment(
      paymentId: asString(pick(map, 'paymentId', 'payment_id'), docId),
      allocationId: asString(pick(map, 'allocationId', 'allocation_id')),
      journeyId: asString(pick(map, 'journeyId', 'journey_id')),
      method: asString(map['method']),
      amountLkr: asDouble(pick(map, 'amountLkr', 'amount_lkr')),
      status: asString(map['status']),
      timestamp: asDateTime(map['timestamp']),
      reference: asString(map['reference']),
    );
  }
}
