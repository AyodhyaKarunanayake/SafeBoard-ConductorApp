import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/bus_info.dart';
import '../models/occupancy_summary.dart';
import '../models/route_info.dart';
import '../models/seat_allocation.dart';
import 'field_compat.dart';

typedef DocMap = Map<String, dynamic>;

/// Thrown when starting a trip on a journey id that another conductor is
/// currently running.
class TripConflictException implements Exception {
  const TripConflictException(this.journeyId, this.ownerConductorId);

  final String journeyId;
  final String ownerConductorId;

  @override
  String toString() =>
      'Journey $journeyId is already running under conductor $ownerConductorId. '
      'Choose a different journey ID.';
}

/// Thrown when a standing passenger can't be moved to a seat (the seat was just
/// taken, the passenger has left, or already has a seat). The message is fit to
/// show the conductor.
class SeatAssignException implements Exception {
  const SeatAssignException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Every Firestore read and write the conductor app makes.
///
/// Compatibility rules with the passenger app, which shares these collections:
///  * Field names are snake_case, exactly as the passenger app writes them.
///  * Dates are ISO-8601 STRINGS, never Timestamps: the passenger app parses
///    them with DateTime.parse, which would throw on a Timestamp.
///  * Writes touch only the fields the conductor owns (see each method); the
///    passenger app's fields are never overwritten, and no collection or field
///    the passenger app doesn't already define is created.
///  * Nothing here writes to seat_allocations, buses, routes, passengers or
///    analytics_log.
class ConductorRepository {
  ConductorRepository(this.db);

  final FirebaseFirestore db;

  // --- live queries (single-field equality: no composite index needed) -----

  /// Every conductor, for the pilot login list.
  Query<DocMap> conductors() => db.collection('conductors');

  Query<DocMap> journeysForConductor(String conductorId) => db
      .collection('journey_instances')
      .where('conductor_id', isEqualTo: conductorId);

  Query<DocMap> allocationsForJourney(String journeyId) =>
      db.collection('seat_allocations').where('journey_id', isEqualTo: journeyId);

  Query<DocMap> incidentsForJourney(String journeyId) =>
      db.collection('incident_reports').where('journey_id', isEqualTo: journeyId);

  /// Passengers' "Text the conductor" messages for a journey. The collection is
  /// created by the passenger app on its first message; until then this simply
  /// returns nothing.
  Query<DocMap> messagesForJourney(String journeyId) => db
      .collection('conductor_messages')
      .where('journey_id', isEqualTo: journeyId);

  /// Pay-on-board payments for a journey, both awaiting collection and already
  /// collected (split by status on the client).
  Query<DocMap> conductorPaymentsForJourney(String journeyId) => db
      .collection('payments')
      .where('journey_id', isEqualTo: journeyId)
      .where('method', isEqualTo: 'conductor');

  // --- reference data (read once) -------------------------------------------

  Future<List<BusInfo>> fetchBuses() async {
    final snapshot = await db.collection('buses').get();
    final buses = [
      for (final doc in snapshot.docs) BusInfo.fromMap(doc.data(), doc.id),
    ];
    buses.sort((a, b) => a.busNumber.compareTo(b.busNumber));
    return buses;
  }

  Future<RouteInfo?> fetchRoute(String routeId) async {
    final doc = await db.collection('routes').doc(routeId).get();
    final data = doc.data();
    if (data == null) return null;
    return RouteInfo.fromMap(data, doc.id);
  }

  /// The active allocations for [journeyId] that belong to [busId]. The
  /// passenger app books every trip into one shared journey id, so the bus id
  /// is what tells two buses' passengers apart.
  Future<List<SeatAllocation>> fetchTripAllocations(
      String journeyId, String busId) async {
    final snapshot = await allocationsForJourney(journeyId).get();
    return [
      for (final doc in snapshot.docs)
        SeatAllocation.fromMap(doc.data(), doc.id),
    ].where((a) => a.isActive && (a.busId.isEmpty || a.busId == busId)).toList();
  }

  // --- writes ----------------------------------------------------------------

  /// Creates journey_instances/[journeyId]. The passenger app only ever
  /// `update()`s this document (to bump current_occupancy), which silently does
  /// nothing until it exists, so this is what makes its occupancy tracking work.
  ///
  /// Refuses (with [TripConflictException]) to take over a journey another
  /// conductor is still running.
  Future<void> createJourney({
    required String journeyId,
    required String busId,
    required String routeId,
    required String conductorId,
    required DateTime departure,
    required DateTime arrival,
    required String currentStop,
    required OccupancySummary occupancy,
  }) async {
    final ref = db.collection('journey_instances').doc(journeyId);

    // The transaction callback must not throw a Dart exception: on Flutter web
    // the Firestore JS SDK boxes it into an opaque "Dart exception thrown from
    // converted Future" error and the real message is lost. It reports a
    // conflict by returning the owner instead, and we throw after it completes.
    final conflictingOwner = await db.runTransaction<String?>((transaction) async {
      final existing = await transaction.get(ref);
      final data = existing.data();
      if (data != null) {
        final owner = asString(data['conductor_id']);
        final status = asString(data['status']).trim().toLowerCase();
        if (owner.isNotEmpty && owner != conductorId && status != 'completed') {
          return owner;
        }
      }
      transaction.set(ref, {
        'journey_id': journeyId,
        'bus_id': busId,
        'route_id': routeId,
        'conductor_id': conductorId,
        'departure_datetime': _iso(departure),
        'arrival_datetime': _iso(arrival),
        'current_occupancy': occupancy.total,
        'current_stop': currentStop,
        'status': 'in_transit',
        ...occupancy.toJourneyCounters(),
      });
      return null;
    });

    if (conflictingOwner != null) {
      throw TripConflictException(journeyId, conflictingOwner);
    }
  }

  /// Updates only the given conductor-owned fields of a journey. Fails if the
  /// journey document does not exist.
  Future<void> updateJourney(String journeyId, Map<String, Object?> fields) =>
      db.collection('journey_instances').doc(journeyId).update(fields);

  /// Sets an incident's status / action_taken and keeps resolution_date in step
  /// with it: an ISO string when resolved, null otherwise.
  Future<void> updateIncident(
    String incidentId, {
    required String status,
    required String actionTaken,
    DateTime? resolvedAt,
  }) =>
      db.collection('incident_reports').doc(incidentId).update({
        'status': status,
        'action_taken': actionTaken,
        'resolution_date': resolvedAt == null ? null : _iso(resolvedAt),
      });

  /// Marks a passenger message as read. Only `status` changes.
  Future<void> markMessageRead(String messageId) => db
      .collection('conductor_messages')
      .doc(messageId)
      .update({'status': 'read'});

  /// Moves a standing passenger to [seat]. Only `seat_number`, `seat_id` and
  /// `allocation_type` (set to 'manual_override', a value the passenger app's
  /// schema already defines) change; the passenger's other fields are untouched.
  ///
  /// Checked first, so nothing is written on a stale screen: the seat must still
  /// be free on this bus, and the booking must still be an active standing one.
  /// Throws [SeatAssignException] otherwise. (The failure is reported by
  /// returning from the transaction, not by throwing inside it, which web boxes
  /// into an unreadable error.)
  Future<void> assignStandingPassengerToSeat({
    required String allocationId,
    required String journeyId,
    required String busId,
    required String seat,
  }) async {
    final wanted = seat.trim().toUpperCase();
    final taken = (await fetchTripAllocations(journeyId, busId))
        .any((a) => a.seatNumber.trim().toUpperCase() == wanted);
    if (taken) throw SeatAssignException('Seat $seat has just been taken.');

    final ref = db.collection('seat_allocations').doc(allocationId);
    final problem = await db.runTransaction<String?>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data == null) return 'That passenger\'s booking no longer exists.';

      final status = asString(data['status']).trim().toLowerCase();
      if (status.isNotEmpty && status != 'active') {
        return 'That passenger has already left the bus.';
      }
      final current = asString(pick(data, 'seatNumber', 'seat_number'));
      if (!current.toLowerCase().startsWith('standing')) {
        return 'That passenger already has a seat ($current).';
      }
      transaction.update(ref, {
        'seat_number': seat,
        'seat_id': seat,
        'allocation_type': 'manual_override',
      });
      return null;
    });
    if (problem != null) throw SeatAssignException(problem);
  }

  /// Adds the conductor's reply to a passenger message and marks it 'replied'.
  /// Only `replies` (appended to, never rewritten) and `status` change, so the
  /// passenger's own fields and any earlier replies are untouched. The date is
  /// an ISO string like every date in the passenger app.
  Future<void> replyToMessage(
    String messageId, {
    required String text,
    required String conductorId,
    required DateTime sentAt,
  }) =>
      db.collection('conductor_messages').doc(messageId).update({
        'replies': FieldValue.arrayUnion([
          {
            'text': text,
            'sent_datetime': _iso(sentAt),
            'conductor_id': conductorId,
          },
        ]),
        'status': 'replied',
      });

  /// Marks a pay-on-board payment as collected. Only `status` changes.
  Future<void> completePayment(String paymentId) => db
      .collection('payments')
      .doc(paymentId)
      .update({'status': 'completed'});

  static String _iso(DateTime value) => value.toUtc().toIso8601String();
}
