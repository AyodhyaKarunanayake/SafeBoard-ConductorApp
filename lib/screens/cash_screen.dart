import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../widgets/status_message.dart';
import '../widgets/status_pill.dart';
import '../widgets/trip_gate.dart';
import 'cash_collection_screen.dart';

/// Pay-on-board queue: fares passengers chose to pay to the conductor. Tapping
/// one opens its details, where the conductor confirms the cash and gets the
/// passenger's boarding code.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return TripGate(
      noTripDetail: 'Cash payments appear here once you have started a trip.',
      builder: (context, journey) {
        final trip = context.watch<JourneyStreamProvider>();
        if (trip.tripError != null &&
            trip.cashToCollect.isEmpty &&
            trip.cashCollected.isEmpty) {
          return StatusMessage(
            icon: Icons.error_outline,
            message: 'Could not load payments',
            detail: '${trip.tripError}',
          );
        }

        final pending = trip.cashToCollect;
        final collected = trip.cashCollected;
        if (pending.isEmpty && collected.isEmpty) {
          return const StatusMessage(
            icon: Icons.payments_outlined,
            message: 'No pay-on-board fares on this trip',
            detail: 'Passengers who choose to pay the conductor will appear here.',
          );
        }

        final theme = Theme.of(context);
        final toCollect = pending.fold<double>(0, (s, c) => s + c.payment.amountLkr);
        final done = collected.fold<double>(0, (s, c) => s + c.payment.amountLkr);

        return ListView(
          padding: kPagePadding,
          children: [
            // IntrinsicHeight: equal-height cards inside a scrolling list.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _TotalCard(
                      label: 'To collect (${pending.length})',
                      amount: toCollect,
                      color: theme.colorScheme.primary,
                      filled: pending.isNotEmpty,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TotalCard(
                      label: 'Collected (${collected.length})',
                      amount: done,
                      color: kSuccess,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SectionLabel('To collect'),
            if (pending.isEmpty)
              Text('Everything has been collected.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline))
            else
              for (final item in pending) _CashTile(item: item, collectable: true),
            if (collected.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionLabel('Collected'),
              for (final item in collected) _CashTile(item: item, collectable: false),
            ],
          ],
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.color,
    this.filled = true,
  });

  final String label;
  final double amount;
  final Color color;

  /// A tinted card draws the eye to money still owed; a zero balance is quiet.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: filled ? color.withValues(alpha: 0.08) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: filled ? color.withValues(alpha: 0.25) : kHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 6),
            Text(formatLkr(amount),
                style: theme.textTheme.titleLarge?.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

class _CashTile extends StatelessWidget {
  const _CashTile({required this.item, required this.collectable});

  final CashItem item;
  final bool collectable;

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CashCollectionScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = item.allocation;
    final color = collectable ? theme.colorScheme.primary : kSuccess;
    final hasStops = a.boardingStop.isNotEmpty || a.alightingStop.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  collectable ? Icons.payments_rounded : Icons.check_circle_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(formatLkr(item.payment.amountLkr),
                            style: theme.textTheme.titleSmall),
                        StatusPill(label: 'Seat ${a.seatNumber}', color: kMuted),
                      ],
                    ),
                    if (hasStops) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(a.boardingStop, style: theme.textTheme.bodySmall),
                          Icon(Icons.arrow_right_alt_rounded,
                              size: 18, color: theme.colorScheme.outline),
                          Text(a.alightingStop, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${a.referenceCode}  ·  ${formatDateTime(item.payment.timestamp)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            collectable ? 'Tap to collect' : 'Tap to view',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: theme.colorScheme.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
