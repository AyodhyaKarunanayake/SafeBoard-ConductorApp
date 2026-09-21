import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/journey_instance.dart';
import '../providers/journey_stream_provider.dart';
import '../providers/reference_data_provider.dart';

/// Read-only list of the route's stops in the bus's direction of travel, drawn
/// as a timeline: stops already passed are filled, the current stop is marked
/// with the bus, and the rest are hollow.
class RouteScreen extends StatelessWidget {
  const RouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reference = context.watch<ReferenceDataProvider>();
    final journey =
        context.select<JourneyStreamProvider, JourneyInstance?>((p) => p.journey);
    final bus = journey == null ? null : reference.busById(journey.busId);
    final stops = reference.stopsForBus(bus);
    final route = reference.route;
    final forward = stops.isEmpty || stops.first == route.stops.first;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final current = journey == null
        ? -1
        : stops.indexWhere(
            (s) => s.toLowerCase() == journey.currentStop.trim().toLowerCase());

    return Scaffold(
      appBar: AppBar(title: Text('${route.routeName}: ${stops.length} stops')),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        itemCount: stops.length,
        itemBuilder: (context, i) {
          final passed = current != -1 && i < current;
          final isCurrent = i == current;
          final km = route.kmAt(stops[i]);
          final shownKm = km == null ? null : (forward ? km : route.distanceKm - km);
          final lineColor = (current != -1 && i <= current)
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant;
          final prevLineColor = (current != -1 && i - 1 < current)
              ? scheme.primary.withValues(alpha: 0.45)
              : scheme.outlineVariant;

          return SizedBox(
            height: isCurrent ? 64 : 48,
            child: Row(
              children: [
                // Timeline rail: a line above and below the stop's marker.
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 3,
                            color: i > 0 ? prevLineColor : Colors.transparent,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.directions_bus_rounded,
                              size: 18, color: Colors.white),
                        )
                      else
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: passed ? scheme.primary : Colors.white,
                            border: Border.all(
                              color: passed ? scheme.primary : scheme.outline,
                              width: 2,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 3,
                            color: i < stops.length - 1
                                ? lineColor
                                : Colors.transparent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    stops[i],
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: passed ? scheme.outline : scheme.onSurface,
                    ),
                  ),
                ),
                if (shownKm != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text('${shownKm.round()} km',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.outline)),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
