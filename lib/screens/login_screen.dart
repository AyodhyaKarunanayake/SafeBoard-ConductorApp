import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../data/conductor_repository.dart';
import '../models/conductor.dart';
import '../providers/conductor_provider.dart';
import '../widgets/status_message.dart';

/// Pilot/demo login: pick a conductor from the `conductors` collection. There
/// is no password or credential check.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.repository});

  /// Only for tests; defaults to the live Firestore.
  final ConductorRepository? repository;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final Stream<List<Conductor>> _conductors;
  String? _pendingId;

  @override
  void initState() {
    super.initState();
    final repository =
        widget.repository ?? ConductorRepository(FirebaseFirestore.instance);
    _conductors = repository.conductors().snapshots().map(_parse);
  }

  static List<Conductor> _parse(QuerySnapshot<DocMap> snapshot) {
    final items = [
      for (final doc in snapshot.docs) Conductor.fromMap(doc.data(), doc.id),
    ];
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return items;
  }

  Future<void> _select(Conductor conductor) async {
    final provider = context.read<ConductorProvider>();
    if (provider.isLoggingIn) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _pendingId = conductor.conductorId);

    await provider.login(conductor);
    if (!mounted) return;

    if (provider.topicError != null) {
      messenger.showSnackBar(const SnackBar(
        content: Text(
            'Logged in, but push notifications could not be enabled. See the Alerts tab.'),
      ));
    }
    navigator.pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('SafeBoard Conductor')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: StreamBuilder<List<Conductor>>(
              stream: _conductors,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return StatusMessage(
                    icon: Icons.error_outline_rounded,
                    message: 'Could not load conductors',
                    detail: '${snapshot.error}',
                  );
                }
                if (!snapshot.hasData) return const LoadingIndicator();

                final conductors = snapshot.data!;
                if (conductors.isEmpty) {
                  return const StatusMessage(
                    icon: Icons.person_off_outlined,
                    message:
                        'No conductors found — check that the passenger app has been used to seed data.',
                  );
                }

                return ListView(
                  padding: kPagePadding,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Select your conductor profile',
                              style: theme.textTheme.headlineSmall),
                          const SizedBox(height: 4),
                          Text('Pilot login: tap your name to continue.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.colorScheme.outline)),
                        ],
                      ),
                    ),
                    for (final conductor in conductors)
                      _ConductorTile(
                        conductor: conductor,
                        loading: _pendingId == conductor.conductorId,
                        enabled: _pendingId == null,
                        onTap: () => _select(conductor),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ConductorTile extends StatelessWidget {
  const _ConductorTile({
    required this.conductor,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  final Conductor conductor;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;

  String get _initial {
    final name = conductor.name.trim();
    return name.isEmpty ? '?' : name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(_initial,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(conductor.name.isEmpty ? '(unnamed)' : conductor.name,
                        style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(conductor.conductorId,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right_rounded, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}
