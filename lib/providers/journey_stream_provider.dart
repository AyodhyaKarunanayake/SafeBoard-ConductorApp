import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/conductor_repository.dart';
import '../data/field_compat.dart';
import '../models/bus_info.dart';
import '../models/conductor_message.dart';
import '../models/incident_report.dart';
import '../models/journey_instance.dart';
import '../models/occupancy_summary.dart';
import '../models/payment.dart';
import '../models/seat_allocation.dart';
import '../models/seat_freed_event.dart';
import '../models/zone.dart';
import '../utils/format.dart';
import 'notifications_provider.dart';

/// A pay-on-board payment together with the seat allocation it belongs to.
class CashItem {
  const CashItem(this.payment, this.allocation);

  final Payment payment;
  final SeatAllocation allocation;
}

/// Live data and actions for the logged-in conductor's active trip.
///
/// The active trip is the conductor's most recent journey that isn't
/// completed. For it this holds one listener each on the journey, its seat
/// allocations, incident reports and pay-on-board payments, so every tab shares
/// them. It also turns new bookings, incidents and cash payments into in-app
/// alerts (the passenger app's push function is never invoked).
///
/// Every action returns null on success or a user-readable error message.
class JourneyStreamProvider extends ChangeNotifier {
  JourneyStreamProvider({ConductorRepository? repository})
      : _injected = repository;

  final ConductorRepository? _injected;
  ConductorRepository? _repo;
  ConductorRepository get _repository =>
      _repo ??= _injected ?? ConductorRepository(FirebaseFirestore.instance);

  NotificationsProvider? _notifications;
  String? _conductorId;

  StreamSubscription<QuerySnapshot<DocMap>>? _journeySub;
  StreamSubscription<QuerySnapshot<DocMap>>? _allocationSub;
  StreamSubscription<QuerySnapshot<DocMap>>? _incidentSub;
  StreamSubscription<QuerySnapshot<DocMap>>? _paymentSub;
  StreamSubscription<QuerySnapshot<DocMap>>? _messageSub;

  JourneyInstance? _journey;
  bool _isLoading = false;
  Object? _error;
  Object? _tripError;

  List<SeatAllocation> _allocations = const [];
  Map<String, SeatAllocation> _allocationsById = const {};
  List<IncidentReport> _incidents = const [];
  List<Payment> _payments = const [];
  List<ConductorMessage> _messages = const [];

  // Alert bookkeeping. Nothing is announced until the first server-confirmed
  // snapshot has been recorded, so existing data doesn't fire alerts on load.
  bool _allocationsPrimed = false;
  bool _incidentsPrimed = false;
  bool _paymentsPrimed = false;
  bool _messagesPrimed = false;
  final Set<String> _seenAllocations = {};
  final Set<String> _seenIncidents = {};
  final Set<String> _seenPayments = {};
  final Set<String> _seenMessages = {};

  // SOS alerts the conductor has already been shown this session (acknowledged,
  // opened or dismissed), so each pops up once. Kept across trip changes.
  final Set<String> _sosHandled = {};

  // Messages that arrived while the app was open and still need to pop up
  // (in arrival order), and the ones already shown. Existing messages waiting at
  // load only raise the badge; the pop-up is for what arrives live.
  final List<String> _messagePopupQueue = [];
  final Set<String> _messagePopupHandled = {};

  // Passengers who ended their journey while the app was open, and which of
  // them the conductor has been told about / offered a standing passenger for.
  final List<SeatFreedEvent> _seatFreedEvents = [];
  final Set<String> _freedAnnounced = {};
  final Set<String> _freedPrompted = {};

  bool _disposed = false;

  // --- state ------------------------------------------------------------------

  /// The active (not completed) trip, or null if there is none.
  JourneyInstance? get journey => _journey;
  bool get isLoading => _isLoading;

  /// Failure reading the conductor's journeys.
  Object? get error => _error;

  /// Failure reading the active trip's allocations / incidents / payments.
  Object? get tripError => _tripError;

  /// Active seat allocations on the trip's bus, newest first.
  List<SeatAllocation> get allocations => _allocations;

  OccupancySummary get occupancy =>
      OccupancySummary.fromAllocations(_allocations);

  /// Incident reports for the trip, newest first.
  List<IncidentReport> get incidents => _incidents;

  /// SOS alerts from passengers that nobody has acknowledged and the conductor
  /// hasn't been shown yet, oldest first. Empty until the incidents have been
  /// confirmed by the server, so a stale cached SOS can't raise a false alarm.
  List<IncidentReport> get pendingSos => !_incidentsPrimed
      ? const []
      : (_incidents
          .where((i) => i.isAwaitingAcknowledgement && !_sosHandled.contains(i.incidentId))
          .toList()
        ..sort((a, b) => _compareTime(a.incidentDatetime, b.incidentDatetime)));

  /// The active allocation on [seat], if this bus has one; used to tell the
  /// conductor about the passenger who raised an alert.
  SeatAllocation? allocationForSeat(String seat) {
    final wanted = seat.trim().toUpperCase();
    if (wanted.isEmpty) return null;
    for (final a in _allocations) {
      if (a.seatNumber.trim().toUpperCase() == wanted) return a;
    }
    return null;
  }

  /// Standing passengers on this bus right now.
  List<SeatAllocation> get standingPassengers =>
      _allocations.where((a) => a.zone == Zone.standing).toList();

  /// Passengers who ended their journey and haven't been announced yet.
  List<SeatFreedEvent> get unannouncedSeatFreed =>
      _seatFreedEvents.where((e) => !_freedAnnounced.contains(e.id)).toList();

  /// Freed real seats not yet offered to a standing passenger.
  List<SeatFreedEvent> get unpromptedSeatFreed => _seatFreedEvents
      .where((e) => e.wasSeated && !_freedPrompted.contains(e.id))
      .toList();

  void markSeatFreedAnnounced(SeatFreedEvent event) {
    if (_freedAnnounced.add(event.id)) notifyListeners();
  }

  void markSeatFreedPrompted(SeatFreedEvent event) {
    if (_freedPrompted.add(event.id)) notifyListeners();
  }

  /// Passenger messages for this trip's bus, newest first.
  List<ConductorMessage> get messages => _messages;

  int get unreadMessageCount => _messages.where((m) => m.isUnread).length;

  /// Unread messages that arrived live and haven't popped up yet, oldest first.
  /// One already read or answered elsewhere drops out.
  List<ConductorMessage> get pendingMessagePopups => [
        for (final id in _messagePopupQueue)
          for (final m in _messages)
            if (m.messageId == id && m.isUnread && !_messagePopupHandled.contains(id)) m,
      ];

  /// Cash payments still to collect (oldest first), for this bus's passengers.
  List<CashItem> get cashToCollect => _cashItems((p) => p.isPayOnBoard)
    ..sort((a, b) => _compareTime(a.payment.timestamp, b.payment.timestamp));

  /// Cash payments already collected (newest first).
  List<CashItem> get cashCollected => _cashItems((p) => p.isPaid)
    ..sort((a, b) => _compareTime(b.payment.timestamp, a.payment.timestamp));

  List<CashItem> _cashItems(bool Function(Payment) test) => [
        for (final payment in _payments)
          if (test(payment) && _allocationsById[payment.allocationId] != null)
            CashItem(payment, _allocationsById[payment.allocationId]!),
      ];

  static int _compareTime(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  // --- binding ---------------------------------------------------------------

  /// Called (via ChangeNotifierProxyProvider) whenever the logged-in conductor
  /// changes. Safe to call repeatedly with the same id.
  void bind(String? conductorId, {NotificationsProvider? notifications}) {
    _notifications = notifications;
    if (conductorId == _conductorId) return;
    _conductorId = conductorId;

    _journeySub?.cancel();
    _journeySub = null;
    _journey = null;
    _error = null;
    _clearTripData();
    _sosHandled.clear();
    _isLoading = conductorId != null;

    if (conductorId != null) {
      _journeySub = _repository
          .journeysForConductor(conductorId)
          .snapshots()
          .listen(_onJourneys, onError: _onJourneyError);
    }

    // Called during a build (proxy update); defer to avoid notifying mid-build.
    scheduleMicrotask(_notifyIfAlive);
  }

  void _onJourneys(QuerySnapshot<DocMap> snapshot) {
    final active = [
      for (final doc in snapshot.docs) JourneyInstance.fromMap(doc.data(), doc.id),
    ].where((j) => !j.isCompleted).toList();
    sortNewestFirst(active, (j) => j.departureDatetime);
    final latest = active.isEmpty ? null : active.first;

    final tripChanged = _tripKey(latest) != _tripKey(_journey);
    _journey = latest;
    _isLoading = false;
    _error = null;
    if (tripChanged) _subscribeToTrip(latest);
    notifyListeners();
  }

  void _onJourneyError(Object error) {
    _error = error;
    _isLoading = false;
    notifyListeners();
  }

  // Journey id + bus id: the seat filter depends on both.
  static String? _tripKey(JourneyInstance? j) =>
      j == null ? null : '${j.journeyId}|${j.busId}';

  void _subscribeToTrip(JourneyInstance? journey) {
    _cancelTripStreams();
    _clearTripData();
    if (journey == null) return;

    _allocationSub = _repository
        .allocationsForJourney(journey.journeyId)
        .snapshots()
        .listen((s) => _onAllocations(s, journey), onError: _onTripError);
    _incidentSub = _repository
        .incidentsForJourney(journey.journeyId)
        .snapshots()
        .listen(_onIncidents, onError: _onTripError);
    _paymentSub = _repository
        .conductorPaymentsForJourney(journey.journeyId)
        .snapshots()
        .listen(_onPayments, onError: _onTripError);
    _messageSub = _repository
        .messagesForJourney(journey.journeyId)
        .snapshots()
        .listen((s) => _onMessages(s, journey), onError: _onTripError);
  }

  void _cancelTripStreams() {
    _allocationSub?.cancel();
    _incidentSub?.cancel();
    _paymentSub?.cancel();
    _messageSub?.cancel();
    _allocationSub = _incidentSub = _paymentSub = _messageSub = null;
  }

  void _clearTripData() {
    _tripError = null;
    _allocations = const [];
    _allocationsById = const {};
    _incidents = const [];
    _payments = const [];
    _messages = const [];
    _allocationsPrimed = _incidentsPrimed = _paymentsPrimed = _messagesPrimed = false;
    _seenAllocations.clear();
    _seenIncidents.clear();
    _seenPayments.clear();
    _seenMessages.clear();
    _messagePopupQueue.clear();
    _seatFreedEvents.clear();
    _freedAnnounced.clear();
    _freedPrompted.clear();
  }

  void _onTripError(Object error) {
    _tripError = error;
    notifyListeners();
  }

  // --- snapshots -> state + alerts ---------------------------------------------

  void _onAllocations(QuerySnapshot<DocMap> snapshot, JourneyInstance journey) {
    final items = [
      for (final doc in snapshot.docs) SeatAllocation.fromMap(doc.data(), doc.id),
    ].where((a) => _belongsToTrip(a, journey)).toList();
    sortNewestFirst(items, (a) => a.allocationDatetime);

    final previousById = _allocationsById;
    _allocations = items;
    _allocationsById = {for (final a in items) a.allocationId: a};
    _tripError = null;

    if (_allocationsPrimed) {
      for (final a in items) {
        if (_seenAllocations.add(a.allocationId)) {
          _alert(
            'New passenger allocated',
            'Seat ${a.seatNumber} (${a.zone.label}) at ${a.boardingStop}',
          );
        }
      }
      _detectPassengersWhoLeft(previousById);
    } else if (!snapshot.metadata.isFromCache) {
      _seenAllocations.addAll(items.map((a) => a.allocationId));
      _allocationsPrimed = true;
    }

    _alertNewCash();
    notifyListeners();
  }

  // A booking that was on the bus in the previous snapshot and isn't active now
  // means that passenger ended their journey (the passenger app marks the
  // booking 'released'). A standing passenger being given a seat keeps the same
  // booking id, so it doesn't count.
  void _detectPassengersWhoLeft(Map<String, SeatAllocation> previousById) {
    for (final entry in previousById.entries) {
      if (_allocationsById.containsKey(entry.key)) continue;
      final gone = entry.value;
      final now = DateTime.now();
      final event = SeatFreedEvent(
        id: '${entry.key}@${now.microsecondsSinceEpoch}',
        allocation: gone,
        at: now,
      );
      _seatFreedEvents.add(event);
      _alert(
        'Passenger left',
        event.wasSeated
            ? 'Seat ${gone.seatNumber} is empty again.'
            : 'A standing passenger ended their journey.',
      );
    }
  }

  void _onIncidents(QuerySnapshot<DocMap> snapshot) {
    final items = [
      for (final doc in snapshot.docs) IncidentReport.fromMap(doc.data(), doc.id),
    ];
    sortNewestFirst(items, (i) => i.incidentDatetime);
    _incidents = items;
    _tripError = null;

    if (_incidentsPrimed) {
      for (final i in items) {
        if (_seenIncidents.add(i.incidentId)) {
          if (i.isSos) {
            _alert(
              'SOS alert',
              i.seatLocation.isEmpty
                  ? 'A passenger pressed the SOS button.'
                  : 'Seat ${i.seatLocation}: a passenger pressed the SOS button.',
            );
          } else {
            final seat = i.seatLocation.isEmpty ? '' : ' at seat ${i.seatLocation}';
            _alert(
              'New incident reported',
              '${humanize(i.incidentType)}$seat (${humanize(i.severityLevel)} severity)',
            );
          }
        }
      }
    } else if (!snapshot.metadata.isFromCache) {
      _seenIncidents.addAll(items.map((i) => i.incidentId));
      _incidentsPrimed = true;
    }
    notifyListeners();
  }

  void _onMessages(QuerySnapshot<DocMap> snapshot, JourneyInstance journey) {
    // The journey id is shared by every bus, so keep this bus's messages (or
    // ones that don't say which bus).
    final items = [
      for (final doc in snapshot.docs) ConductorMessage.fromMap(doc.data(), doc.id),
    ].where((m) => m.busId.isEmpty || m.busId == journey.busId).toList();
    sortNewestFirst(items, (m) => m.sentDatetime);
    _messages = items;
    _tripError = null;

    if (_messagesPrimed) {
      for (final m in items) {
        if (_seenMessages.add(m.messageId) && m.isUnread) {
          final seat = m.seatNumber.isEmpty ? 'A passenger' : 'Seat ${m.seatNumber}';
          _alert('New message', '$seat: "${m.text}"');
          _messagePopupQueue.add(m.messageId);
        }
      }
    } else if (!snapshot.metadata.isFromCache) {
      _seenMessages.addAll(items.map((m) => m.messageId));
      _messagesPrimed = true;
    }
    notifyListeners();
  }

  void _onPayments(QuerySnapshot<DocMap> snapshot) {
    _payments = [
      for (final doc in snapshot.docs) Payment.fromMap(doc.data(), doc.id),
    ];
    _tripError = null;

    if (!_paymentsPrimed && !snapshot.metadata.isFromCache) {
      _seenPayments.addAll(_payments.map((p) => p.paymentId));
      _paymentsPrimed = true;
    }
    _alertNewCash();
    notifyListeners();
  }

  // A payment is announced once its allocation is known, because the shared
  // journey id means a payment may belong to another bus's passenger.
  void _alertNewCash() {
    if (!_paymentsPrimed) return;
    for (final payment in _payments) {
      final allocation = _allocationsById[payment.allocationId];
      if (allocation == null || !payment.isPayOnBoard) continue;
      if (_seenPayments.add(payment.paymentId)) {
        _alert(
          'Cash to collect',
          'LKR ${payment.amountLkr.toStringAsFixed(0)} from seat ${allocation.seatNumber}',
        );
      }
    }
  }

  void _alert(String title, String body) =>
      _notifications?.addLocal(title: title, body: body);

  static bool _belongsToTrip(SeatAllocation a, JourneyInstance journey) =>
      a.isActive && (a.busId.isEmpty || a.busId == journey.busId);

  // --- actions -----------------------------------------------------------------

  /// Starts a trip: creates journey_instances/[journeyId] for [bus]. Occupancy
  /// starts from any allocations already booked on that bus.
  Future<String?> startTrip({
    required BusInfo bus,
    required String journeyId,
    required List<String> stops,
  }) async {
    final conductorId = _conductorId;
    final id = journeyId.trim();
    if (conductorId == null) return 'You are not signed in.';
    if (id.isEmpty) return 'Enter a journey ID.';

    debugPrint('[startTrip] journey=$id bus=${bus.busId} conductor=$conductorId');
    try {
      var occupancy = OccupancySummary.empty;
      try {
        occupancy = OccupancySummary.fromAllocations(
          await _repository.fetchTripAllocations(id, bus.busId),
        );
      } catch (e) {
        // Couldn't count existing bookings; start from zero rather than fail.
        debugPrint('[startTrip] could not count existing bookings: ${e.runtimeType}: $e');
      }

      final now = DateTime.now();
      await _repository.createJourney(
        journeyId: id,
        busId: bus.busId,
        routeId: bus.routeId.isEmpty ? 'R_87' : bus.routeId,
        conductorId: conductorId,
        departure: now,
        arrival: now.add(Duration(minutes: bus.durationMinutes)),
        currentStop: stops.isEmpty ? bus.startPoint : stops.first,
        occupancy: occupancy,
      );
      return null;
    } catch (e, stack) {
      return _fail('startTrip', e, stack);
    }
  }

  /// Records the bus's current stop, and brings the zone counters and crowding
  /// level up to date with the live allocations in the same write.
  Future<String?> setCurrentStop(String stop) => _updateTrip({
        'current_stop': stop,
        ...occupancy.toJourneyCounters(),
      });

  /// Sets the trip status (scheduled / in_transit / completed), also syncing
  /// counters. Completing a trip removes it from the active list.
  Future<String?> setStatus(String status) => _updateTrip({
        'status': status,
        ...occupancy.toJourneyCounters(),
      });

  Future<String?> _updateTrip(Map<String, Object?> fields) async {
    final journey = _journey;
    if (journey == null) return 'There is no active trip.';
    try {
      await _repository.updateJourney(journey.journeyId, fields);
      return null;
    } catch (e, stack) {
      return _fail('updateJourney', e, stack);
    }
  }

  /// Updates an incident's status and action taken. Resolving stamps
  /// resolution_date; any other status clears it.
  Future<String?> updateIncident(
    IncidentReport incident, {
    required String status,
    required String actionTaken,
  }) async {
    try {
      await _repository.updateIncident(
        incident.incidentId,
        status: status,
        actionTaken: actionTaken.trim(),
        resolvedAt: status == IncidentStatus.resolved ? DateTime.now() : null,
      );
      return null;
    } catch (e, stack) {
      return _fail('updateIncident', e, stack);
    }
  }

  /// Gives a standing passenger a free seat: their booking moves to [seat] and
  /// is marked a manual override. Returns null on success or a message to show
  /// (for example when the seat was taken in the meantime).
  Future<String?> assignStandingToSeat(SeatAllocation standing, String seat) async {
    final journey = _journey;
    if (journey == null) return 'There is no active trip.';
    try {
      await _repository.assignStandingPassengerToSeat(
        allocationId: standing.allocationId,
        journeyId: journey.journeyId,
        busId: journey.busId,
        seat: seat,
      );
      return null;
    } catch (e, stack) {
      return _fail('assignStandingToSeat', e, stack);
    }
  }

  /// Records that the conductor has seen this SOS (whatever they chose to do),
  /// so it doesn't pop up again this session. The incident itself stays in the
  /// Incidents tab until it is acknowledged or resolved.
  void markSosHandled(IncidentReport incident) {
    if (_sosHandled.add(incident.incidentId)) notifyListeners();
  }

  /// Acknowledges an SOS: sets its status to 'acknowledged' and records the
  /// action taken, which the passenger sees in their "My reports".
  Future<String?> acknowledgeSos(IncidentReport incident) {
    markSosHandled(incident);
    return updateIncident(
      incident,
      status: IncidentStatus.acknowledged,
      actionTaken: 'Conductor acknowledged the SOS alert',
    );
  }

  /// Records that the conductor has seen this message's pop-up (whether they
  /// replied or chose Later), so it doesn't pop up again. The message itself
  /// stays on the Messages page.
  void markMessagePopupHandled(ConductorMessage message) {
    if (_messagePopupHandled.add(message.messageId)) notifyListeners();
  }

  /// Sends [text] as the conductor's reply to [message] (which is then marked
  /// 'replied'). Returns null on success or a message to show.
  Future<String?> replyToMessage(ConductorMessage message, String text) async {
    final reply = text.trim();
    final conductorId = _conductorId;
    if (conductorId == null) return 'You are not signed in.';
    if (reply.isEmpty) return 'Type a reply first.';
    try {
      await _repository.replyToMessage(
        message.messageId,
        text: reply,
        conductorId: conductorId,
        sentAt: DateTime.now(),
      );
      markMessagePopupHandled(message);
      return null;
    } catch (e, stack) {
      return _fail('replyToMessage', e, stack);
    }
  }

  /// Marks a passenger message as read. A message that has already been read or
  /// answered is left alone (this never downgrades 'replied' to 'read').
  Future<String?> markMessageRead(ConductorMessage message) async {
    if (!message.isUnread) return null;
    try {
      await _repository.markMessageRead(message.messageId);
      return null;
    } catch (e, stack) {
      return _fail('markMessageRead', e, stack);
    }
  }

  /// Marks every unread message on this trip as read.
  Future<String?> markAllMessagesRead() async {
    String? firstError;
    for (final message in _messages.where((m) => m.isUnread)) {
      final error = await markMessageRead(message);
      firstError ??= error;
    }
    return firstError;
  }

  /// Marks a pay-on-board payment as collected.
  Future<String?> collectPayment(Payment payment) async {
    try {
      await _repository.completePayment(payment.paymentId);
      return null;
    } catch (e, stack) {
      return _fail('collectPayment', e, stack);
    }
  }

  /// Logs the real underlying error and stack trace to the console, then
  /// returns the message to show the user. Errors reaching the UI are
  /// summarised, so the console is where the full detail lives.
  static String _fail(String action, Object error, StackTrace stack) {
    debugPrint('[$action] failed: ${error.runtimeType}: $error\n$stack');
    return _describe(error);
  }

  static String _describe(Object error) {
    if (error is TripConflictException) return error.toString();
    if (error is SeatAssignException) return error.message;
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Firestore refused this change (permission denied). Check the security rules.';
      }
      if (error.code == 'not-found') {
        return 'That record no longer exists.';
      }
      if (error.code == 'unavailable') {
        return 'No connection to Firestore. Check your internet and try again.';
      }
      return 'Firestore error (${error.code}): ${error.message ?? ''}'.trim();
    }
    return 'Something went wrong (${error.runtimeType}): $error';
  }

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _journeySub?.cancel();
    _cancelTripStreams();
    super.dispose();
  }
}
