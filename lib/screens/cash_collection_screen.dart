import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../models/payment.dart';
import '../models/seat_allocation.dart';
import '../providers/journey_stream_provider.dart';
import '../utils/format.dart';
import '../widgets/card_header.dart';
import '../widgets/status_pill.dart';
import 'boarding_code_dialog.dart';

/// Full details of one pay-on-board fare, and the action that closes it out:
/// confirming the cash was received, which hands the conductor a boarding code
/// to read out to the passenger. Pushed from the Cash tab.
///
/// There is no passenger name in the schema — seat_allocations and payments
/// carry no passenger_id the conductor app can read — so this screen (like the
/// SOS pop-up) identifies the passenger by seat, not by name.
class CashCollectionScreen extends StatefulWidget {
  const CashCollectionScreen({super.key, required this.item});

  final CashItem item;

  @override
  State<CashCollectionScreen> createState() => _CashCollectionScreenState();
}

class _CashCollectionScreenState extends State<CashCollectionScreen> {
  bool _busy = false;
  String? _error;
  late bool _collected = widget.item.payment.isPaid;

  Future<void> _confirmCollected() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await context
        .read<JourneyStreamProvider>()
        .collectPayment(widget.item.payment);
    if (!mounted) return;

    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }

    setState(() {
      _busy = false;
      _collected = true;
    });
    await showBoardingCodeDialog(context, seat: widget.item.allocation.seatNumber);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = widget.item.allocation;
    final p = widget.item.payment;

    return Scaffold(
      appBar: AppBar(title: const Text('Collect payment')),
      body: ListView(
        padding: kPagePadding,
        children: [
          _AmountHero(amount: p.amountLkr, collected: _collected),
          const SizedBox(height: kGap),
          _PassengerCard(allocation: a),
          const SizedBox(height: kGap),
          _PaymentCard(payment: p),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(kRadiusSmall),
              ),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ],
          const SizedBox(height: 24),
          if (!_collected) ...[
            Text(
              'Once you have the cash in hand, confirm it below. This gives you '
              'the boarding code to tell the passenger.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.4),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _confirmCollected,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.vpn_key_rounded),
              label: const Text('Code to Confirm'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kSuccess.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(kRadius),
                border: Border.all(color: kSuccess.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: kSuccess),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Payment collected',
                        style: theme.textTheme.titleSmall?.copyWith(color: kSuccess)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () =>
                  showBoardingCodeDialog(context, seat: a.seatNumber),
              icon: const Icon(Icons.vpn_key_outlined),
              label: const Text('Show boarding code again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountHero extends StatelessWidget {
  const _AmountHero({required this.amount, required this.collected});

  final double amount;
  final bool collected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = collected ? kSuccess : theme.colorScheme.primary;

    return Card(
      color: color.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadius),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.payments_rounded, color: color, size: 32),
            const SizedBox(height: 8),
            Text(formatLkr(amount),
                style: theme.textTheme.headlineMedium?.copyWith(color: color)),
            const SizedBox(height: 10),
            StatusPill(
              label: collected ? 'Collected' : 'Awaiting payment',
              color: color,
              icon: collected ? Icons.check_circle_rounded : Icons.schedule_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class _PassengerCard extends StatelessWidget {
  const _PassengerCard({required this.allocation});

  final SeatAllocation allocation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final a = allocation;
    final color = zoneColor(a.zone);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(icon: Icons.person_rounded, title: 'Passenger'),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.event_seat_rounded, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.seatNumber.isEmpty ? 'Unknown seat' : 'Seat ${a.seatNumber}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    StatusPill(label: a.zone.label, color: color),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow('Boarding', a.boardingStop.isEmpty ? '—' : a.boardingStop),
            _DetailRow('Alighting', a.alightingStop.isEmpty ? '—' : a.alightingStop),
            _DetailRow('Reference', a.referenceCode),
            _DetailRow('Booked', formatDateTime(a.allocationDatetime)),
          ],
        ),
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final Payment payment;

  String get _methodLabel =>
      payment.method.trim().toLowerCase() == Payment.methodConductor
          ? 'Cash (pay on board)'
          : humanize(payment.method);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CardHeader(icon: Icons.receipt_long_rounded, title: 'Payment'),
            const SizedBox(height: 12),
            _DetailRow('Method', _methodLabel),
            if (payment.reference.isNotEmpty && payment.reference != _methodLabel)
              _DetailRow('Note', payment.reference),
            _DetailRow('Requested', formatDateTime(payment.timestamp)),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
