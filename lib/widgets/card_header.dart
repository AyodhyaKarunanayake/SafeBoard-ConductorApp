import 'package:flutter/material.dart';

/// Title row for a card: a tinted icon tile, the title, and an optional
/// trailing widget. Keeps every card's heading looking the same.
class CardHeader extends StatelessWidget {
  const CardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (trailing != null) trailing!,
      ],
    );
  }
}
