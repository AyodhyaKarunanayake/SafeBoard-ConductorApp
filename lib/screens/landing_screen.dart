import 'package:flutter/material.dart';

import '../app_theme.dart';

/// First screen: brand, what the app does, and a single call to action that
/// leads to the pilot login. Purely static; it touches no Firebase.
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const _gradientEnd = Color(0xFF2F5CA8);

  static const _features = [
    _Feature(
      icon: Icons.stacked_bar_chart_rounded,
      title: 'Live occupancy',
      description:
          'Priority, general, limited and standing capacity for your journey at a glance.',
    ),
    _Feature(
      icon: Icons.event_seat_rounded,
      title: 'Seat allocations',
      description:
          'See every allocation and its risk score as passengers are seated.',
    ),
    _Feature(
      icon: Icons.notifications_active_rounded,
      title: 'Instant alerts',
      description:
          'Get notified the moment a passenger is allocated a seat on your bus.',
    ),
    _Feature(
      icon: Icons.shield_outlined,
      title: 'Incident visibility',
      description:
          'Review passenger-reported incidents, colour-coded by severity.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kNavy, _gradientEnd],
          ),
        ),
        child: Stack(
          children: [
            const _BackgroundCircle(top: -80, right: -60, size: 260, alpha: 0.08),
            const _BackgroundCircle(bottom: 120, left: -100, size: 220, alpha: 0.06),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight),
                                child: const _EntranceAnimation(
                                  child: _Content(features: _features),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _GetStartedButton(),
                        const SizedBox(height: 12),
                        Text(
                          'Pilot version  ·  Sign in with your conductor account',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.features});

  final List<_Feature> features;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.directions_bus_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Text('SafeBoard',
                style: textTheme.titleLarge?.copyWith(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Know your bus.\nKeep every passenger safe.',
          style: textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'The conductor companion to the SafeBoard passenger app: live occupancy, seat allocations and incident reports for your journey.',
          style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 28),
        for (final feature in features) _FeatureRow(feature: feature),
      ],
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});

  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(feature.icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title,
                    style: textTheme.titleSmall?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(feature.description,
                    style:
                        textTheme.bodyMedium?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GetStartedButton extends StatelessWidget {
  const _GetStartedButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: kNavy,
          minimumSize: const Size.fromHeight(56),
          shape: const StadiumBorder(),
          // Derived from the theme so the button keeps the app's font family.
          textStyle: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: () => Navigator.of(context).pushNamed('/login'),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Get started'),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class _BackgroundCircle extends StatelessWidget {
  const _BackgroundCircle({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.size,
    required this.alpha,
  });

  final double? top;
  final double? bottom;
  final double? left;
  final double? right;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: alpha),
          ),
        ),
      ),
    );
  }
}

/// One-shot fade and slide-up when the screen first appears.
class _EntranceAnimation extends StatelessWidget {
  const _EntranceAnimation({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
      ),
    );
  }
}
