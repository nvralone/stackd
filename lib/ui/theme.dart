import 'package:material_ui/material_ui.dart';

/// Semantic accents used across the app.
class Accents {
  static const savings = Color(0xFF7BD88F); // soft green
  static const vacation = Color(0xFFB39DFF); // lavender
  static const vacationBlue = Color(0xFF7FB2FF);
  static const income = Color(0xFFFFD166); // warm yellow
  static const danger = Color(0xFFFF6B6B);
  static const warn = Color(0xFFFFA94D);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8E7CFF),
    brightness: b,
    surface: dark ? const Color(0xFF17141F) : const Color(0xFFF7F5FB),
    primary: dark ? const Color(0xFFB8A9FF) : const Color(0xFF5B47C9),
    secondary: Accents.savings,
    tertiary: Accents.income,
    error: Accents.danger,
  );
  final cardColor = dark ? const Color(0xFF221E2D) : Colors.white;
  return ThemeData(
    colorScheme: scheme,
    brightness: b,
    scaffoldBackgroundColor: dark ? const Color(0xFF131119) : const Color(0xFFF2EFF8),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
      fillColor: dark ? const Color(0xFF2A2536) : const Color(0xFFEDE9F5),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF1B1824) : Colors.white,
      indicatorColor: scheme.primary.withValues(alpha: 0.22),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
