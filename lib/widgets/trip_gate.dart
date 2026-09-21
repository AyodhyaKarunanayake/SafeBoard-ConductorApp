import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journey_instance.dart';
import '../providers/journey_stream_provider.dart';
import 'status_message.dart';

/// Shows [builder] once there is an active trip, and otherwise the right
/// loading / error / "no trip" state, so every tab handles those the same way.
class TripGate extends StatelessWidget {
  const TripGate({
    super.key,
    required this.builder,
    this.noTripBuilder,
    this.noTripDetail = 'Start a trip on the Trip tab to see this.',
  });

  final Widget Function(BuildContext context, JourneyInstance journey) builder;

  /// Replaces the default "no active trip" message (the Trip tab uses this to
  /// show its start-a-trip form).
  final WidgetBuilder? noTripBuilder;
  final String noTripDetail;

  @override
  Widget build(BuildContext context) {
    final journeys = context.watch<JourneyStreamProvider>();

    if (journeys.error != null) {
      return StatusMessage(
        icon: Icons.error_outline,
        message: 'Could not load your trip',
        detail: '${journeys.error}',
      );
    }
    if (journeys.isLoading) return const LoadingIndicator();

    final journey = journeys.journey;
    if (journey == null) {
      return noTripBuilder?.call(context) ??
          StatusMessage(
            icon: Icons.directions_bus_outlined,
            message: 'No active trip',
            detail: noTripDetail,
          );
    }
    return builder(context, journey);
  }
}
