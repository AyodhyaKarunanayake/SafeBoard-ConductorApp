import 'package:flutter/material.dart';

import 'models/zone.dart';

/// SafeBoard navy, matching the passenger app's branding. The brand colour;
/// everything below is built around it.
const Color kNavy = Color(0xFF1F3864);

/// Page background: a cool, very light grey-blue so white cards read as
/// raised without needing shadows.
const Color kBackground = Color(0xFFF3F5F9);

/// Hairline used for card and input borders.
const Color kHairline = Color(0xFFDDE3EE);

/// Near-black with a hint of navy, for body text.
const Color kInk = Color(0xFF141B2D);

/// Muted text and icons.
const Color kMuted = Color(0xFF66738A);

/// Semantic status colours (success / warning) used for pills and totals.
const Color kSuccess = Color(0xFF2E7D32);
const Color kWarning = Color(0xFFB26A00);

/// Corner radii and spacing shared by every screen.
const double kRadius = 16;
const double kRadiusSmall = 12;
const double kGap = 16;
const EdgeInsets kPagePadding = EdgeInsets.all(16);

/// Colour used for a seating zone on the seat map, bars and chips.
Color zoneColor(Zone zone) {
  switch (zone) {
    case Zone.priority:
      return Colors.indigo.shade600;
    case Zone.general:
      return Colors.teal.shade600;
    case Zone.limited:
      return Colors.blueGrey.shade600;
    case Zone.standing:
      return Colors.deepOrange.shade600;
    case Zone.unknown:
      return Colors.grey.shade600;
  }
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: kNavy).copyWith(
    primary: kNavy,
    onPrimary: Colors.white,
    primaryContainer: const Color(0xFFDDE6F7),
    onPrimaryContainer: const Color(0xFF14284D),
    secondaryContainer: const Color(0xFFDDE6F7),
    onSecondaryContainer: const Color(0xFF14284D),
    surface: Colors.white,
    onSurface: kInk,
    onSurfaceVariant: kMuted,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: const Color(0xFFF7F9FC),
    surfaceContainer: const Color(0xFFF1F4F9),
    surfaceContainerHigh: const Color(0xFFEBEFF6),
    surfaceContainerHighest: const Color(0xFFE4E9F2),
    outline: kMuted,
    outlineVariant: kHairline,
    error: const Color(0xFFC62828),
    errorContainer: const Color(0xFFFCE8E8),
    onErrorContainer: const Color(0xFF7A1212),
  );

  RoundedRectangleBorder rounded(double radius, {BorderSide side = BorderSide.none}) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: side);

  OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(kRadiusSmall),
        borderSide: BorderSide(color: color, width: width),
      );

  // Every custom text style below is derived from the platform's own text
  // theme. Material replaces (rather than merges) the ambient style for app
  // bars, buttons and snack bars, so a style built from scratch would have no
  // font family and could render in a different font from the rest of the app.
  final base = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;
  TextStyle from(TextStyle? style, {double? size, FontWeight? weight, Color? color}) =>
      (style ?? const TextStyle()).copyWith(fontSize: size, fontWeight: weight, color: color);

  // Only weights and tracking are overridden; sizes stay Material's.
  final textTheme = base.copyWith(
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.1),
    titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600),
  );
  final buttonText = from(textTheme.labelLarge, size: 15, weight: FontWeight.w600);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBackground,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: kNavy,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: from(textTheme.titleLarge, size: 20, weight: FontWeight.w600, color: Colors.white)
          .copyWith(letterSpacing: -0.1),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: rounded(kRadius, side: const BorderSide(color: kHairline)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: inputBorder(kHairline),
      enabledBorder: inputBorder(kHairline),
      disabledBorder: inputBorder(kHairline),
      focusedBorder: inputBorder(kNavy, 1.6),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, 1.6),
      helperMaxLines: 2,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: rounded(kRadiusSmall),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: rounded(kRadiusSmall),
        side: const BorderSide(color: kHairline),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: rounded(kRadiusSmall),
        textStyle: from(textTheme.labelLarge, weight: FontWeight.w600),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: kMuted,
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: const BorderSide(color: kHairline),
        shape: rounded(kRadiusSmall),
        textStyle: from(textTheme.labelLarge, weight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      side: const BorderSide(color: kHairline),
      shape: const StadiumBorder(),
      labelStyle: from(textTheme.labelLarge, size: 13, weight: FontWeight.w600, color: kInk),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => from(
          textTheme.labelMedium,
          size: 12,
          weight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? kNavy : kMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? kNavy : kMuted,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: rounded(20),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1B2540),
      contentTextStyle: from(textTheme.bodyMedium, size: 14, color: Colors.white),
      shape: rounded(kRadiusSmall),
    ),
    dividerTheme: const DividerThemeData(color: kHairline, thickness: 1, space: 1),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: kNavy,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
  );
}
