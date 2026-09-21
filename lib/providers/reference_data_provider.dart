import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../data/conductor_repository.dart';
import '../models/bus_info.dart';
import '../models/route_info.dart';

/// Read-only reference data: the buses (trip templates) and Route 87. Loaded
/// once after sign-in. If Firestore can't be read, the route falls back to the
/// built-in Route 87 stop list and the bus list stays empty.
class ReferenceDataProvider extends ChangeNotifier {
  ReferenceDataProvider({ConductorRepository? repository})
      : _injected = repository;

  final ConductorRepository? _injected;
  ConductorRepository? _repo;
  ConductorRepository get _repository =>
      _repo ??= _injected ?? ConductorRepository(FirebaseFirestore.instance);

  List<BusInfo> _buses = const [];
  RouteInfo _route = RouteInfo.route87Fallback;
  bool _isLoading = false;
  bool _started = false;
  bool _disposed = false;
  String? _error;

  List<BusInfo> get buses => _buses;
  RouteInfo get route => _route;
  bool get isLoading => _isLoading;
  String? get error => _error;

  BusInfo? busById(String busId) {
    for (final bus in _buses) {
      if (bus.busId == busId) return bus;
    }
    return null;
  }

  /// The buses assigned to [conductorId] in the `buses` collection.
  List<BusInfo> busesFor(String conductorId) =>
      _buses.where((b) => b.conductorId == conductorId).toList();

  /// Stops in the direction the given bus travels (Colombo -> Jaffna unless
  /// the bus starts in Jaffna).
  List<String> stopsForBus(BusInfo? bus) =>
      _route.stopsFrom(bus?.startPoint ?? '');

  /// Starts loading on first call; later calls do nothing. Safe to call from a
  /// provider `update` (the first notification happens after an await).
  void ensureLoaded() {
    if (_started) return;
    _started = true;
    _isLoading = true;
    unawaited(_load());
  }

  Future<void> reload() {
    _started = true;
    _isLoading = true;
    notifyListeners();
    return _load();
  }

  Future<void> _load() async {
    String? error;
    try {
      _buses = await _repository.fetchBuses();
      if (_buses.isEmpty) error = 'No buses found in the buses collection.';
    } catch (e) {
      error = 'Could not load buses: $e';
    }
    try {
      final route = await _repository.fetchRoute('R_87');
      if (route != null && route.hasStops) _route = route;
    } catch (_) {
      // Keep the built-in stop list.
    }
    _error = error;
    _isLoading = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
