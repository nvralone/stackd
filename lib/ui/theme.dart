import 'package:material_ui/material_ui.dart';

/// Semantic accents used across the app.
class Accents {
  static const savings = Color(0xFF5BE38A); // money green
  static const vacation = Color(0xFFB39DFF); // lavender
  static const vacationBlue = Color(0xFF7FB2FF);
  static const income = Color(0xFFFFD166); // warm yellow
  static const danger = Color(0xFFFF6B6B);
  static const warn = Color(0xFFFFA94D);
  static const purple = Color(0xFF9D7BFF);
}

/// Background / surface tones (dark charcoal + deep purple).
class Tones {
  static const bgDark = Color(0xFF0F0C17);
  static const bgDark2 = Color(0xFF1A1230);
  static const cardDark = Color(0xFF1B1628);
  static const cardDarkHi = Color(0xFF241D36);
  static const outlineDark = Color(0xFF3A2D5E);
  static const bgLight = Color(0xFFF1EDFA);
  static const cardLight = Colors.white;
  static const outlineLight = Color(0xFFD9CFF5);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Accents.purple,
    brightness: b,
    surface: dark ? Tones.cardDark : const Color(0xFFF8F6FD),
    primary: dark ? const Color(0xFFB9A3FF) : const Color(0xFF5B3FD1),
    secondary: Accents.savings,
    tertiary: Accents.income,
    error: Accents.danger,
    outlineVariant: dark ? Tones.outlineDark : Tones.outlineLight,
  );
  final cardColor = dark ? Tones.cardDark : Tones.cardLight;
  final outline = dark ? Tones.outlineDark : Tones.outlineLight;
  return ThemeData(
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: dark ? Tones.bgDark : Tones.bgLight,
    dividerTheme: DividerThemeData(color: outline.withValues(alpha: 0.6)),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: outline.withValues(alpha: 0.7))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? Tones.cardDark : Tones.cardLight,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? Tones.cardDarkHi : Tones.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: outline)),
    ),
    chipTheme: ChipThemeData(
      side: BorderSide(color: outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: dark ? Tones.cardDarkHi : const Color(0xFFF3EFFC),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.55), width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: dark ? const Color(0xFF6D4AE8) : const Color(0xFF5B3FD1),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFB9A3FF), width: 1.5)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: outline),
        selectedBackgroundColor: scheme.primary.withValues(alpha: 0.22),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF231C33) : const Color(0xFFEDE7FA),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF140F20) : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.24),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.primary.withValues(alpha: 0.6))),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Palette offered for categories / accounts / goals.
const pickColors = [
  0xFFFF8A65, 0xFFFFB74D, 0xFFFFD54F, 0xFFAED581, 0xFF81C784, 0xFF4DD0E1, 0xFF4FC3F7, 0xFF7986CB,
  0xFF9575CD, 0xFFBA68C8, 0xFFF06292, 0xFFA1887F, 0xFF90A4AE, 0xFFB0BEC5, 0xFF7BD88F, 0xFFB39DFF,
];

/// Icon choices for categories (index stored in DB).
const categoryIcons = <IconData>[
  Icons.category_rounded, Icons.fastfood_rounded, Icons.restaurant_rounded, Icons.local_grocery_store_rounded,
  Icons.cookie_rounded, Icons.local_drink_rounded, Icons.local_gas_station_rounded, Icons.shield_rounded,
  Icons.home_rounded, Icons.subscriptions_rounded, Icons.shopping_bag_rounded, Icons.sports_esports_rounded,
  Icons.person_rounded, Icons.today_rounded, Icons.pets_rounded, Icons.directions_car_rounded,
  Icons.school_rounded, Icons.favorite_rounded, Icons.medical_services_rounded, Icons.flight_rounded,
];

IconData accountIcon(String kind) => switch (kind) {
      'cash' => Icons.payments_rounded,
      'venmo' => Icons.phone_iphone_rounded,
      'cashapp' => Icons.attach_money_rounded,
      'checking' => Icons.account_balance_rounded,
      'savings' => Icons.savings_rounded,
      _ => Icons.account_balance_wallet_rounded,
    };
