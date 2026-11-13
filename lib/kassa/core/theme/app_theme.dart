import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// Yandex Eda brend rangi. Yandexdan kelgan cheklar va Yandexga chiqariladigan
/// mahsulotlar SHU rang bilan belgilanadi — kassir bir qarashda ajratsin
/// (pul Yandexda to'langan, kuryerni ham Yandex yuboradi).
const kYandexColor = Color(0xFFFC3F1D);

class AppColors {
  // Brand
  static const primary = Color(0xFF4F46E5);
  static const primaryDark = Color(0xFF3730A3);
  static const primarySoft = Color(0xFFEEF2FF);
  static const primaryTint = Color(0xFFE0E7FF);

  static const accent = Color(0xFFF59E0B);
  static const accentSoft = Color(0xFFFEF3C7);

  // Semantic
  static const success = Color(0xFF10B981);
  static const successSoft = Color(0xFFD1FAE5);
  static const successTint = Color(0xFFECFDF5);

  static const danger = Color(0xFFEF4444);
  static const dangerSoft = Color(0xFFFEE2E2);
  static const dangerTint = Color(0xFFFEF2F2);

  static const warning = Color(0xFFF97316);
  static const warningSoft = Color(0xFFFFEDD5);
  static const warningTint = Color(0xFFFFF7ED);

  static const info = Color(0xFF0EA5E9);
  static const infoSoft = Color(0xFFE0F2FE);
  static const infoTint = Color(0xFFF0F9FF);

  // Surfaces
  static const bg = Color(0xFFF7F8FB);
  static const bgAlt = Color(0xFFF1F3F8);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFF1F5F9);
  static const surfaceHover = Color(0xFFFAFBFD);

  // Text
  static const text = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);
  static const textFaint = Color(0xFF94A3B8);
  static const textGhost = Color(0xFFCBD5E1);

  // Borders
  static const border = Color(0xFFE2E8F0);
  static const borderSoft = Color(0xFFF1F5F9);
  static const borderStrong = Color(0xFFCBD5E1);
}

class AppRadius {
  static const xs = 6.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const pill = 999.0;
}

/// Ekran o'lchamlari — telefon / planshet / desktop chegaralari
class AppBreakpoints {
  /// Bundan tor bo'lsa telefon layout: pastki navigatsiya, ixcham sarlavha
  static const phone = 720.0;

  /// Kichik telefon (iPhone SE, mini) — matn va bo'shliqlar yanada ixcham
  static const smallPhone = 380.0;

  /// Bundan keng — desktop/katta planshet: yon panel kengroq, ustun ko'proq
  static const desktop = 1280.0;

  static bool isPhone(double width) => width < phone;
  static bool isSmallPhone(double width) => width < smallPhone;
  static bool isTablet(double width) => width >= phone && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
}

/// Ekran kengligiga qarab UI kattaligini moslash.
///
/// NEGA KERAK: butun ilova telefon o'lchamida yozilgan edi — planshetda
/// (iPad 1024pt) hamma narsa mayda bo'lib ekranning uchdan biriga siqilib
/// qolardi, qolgan joy bo'sh turardi. Endi har ekran shu yordamchidan
/// kelib chiqib o'lchamini oshiradi.
enum UiSize { smallPhone, phone, tablet, desktop }

extension AppResponsive on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  UiSize get uiSize {
    final w = screenWidth;
    if (w >= AppBreakpoints.desktop) return UiSize.desktop;
    if (w >= AppBreakpoints.phone) return UiSize.tablet;
    if (w < AppBreakpoints.smallPhone) return UiSize.smallPhone;
    return UiSize.phone;
  }

  bool get isPhoneUi => screenWidth < AppBreakpoints.phone;
  bool get isTabletUi => screenWidth >= AppBreakpoints.phone;

  /// Barcha o'lchamlar shunga ko'paytiriladi: planshetda 1.25×, desktopda 1.3×
  double get uiScale => switch (uiSize) {
        UiSize.smallPhone => 0.94,
        UiSize.phone => 1.0,
        UiSize.tablet => 1.25,
        UiSize.desktop => 1.3,
      };

  /// Shrift/ikonka/o'lcham — telefon qiymatidan planshet qiymatiga
  double s(double base) => base * uiScale;

  /// Ekran chetidagi bo'shliq
  double get gutter => switch (uiSize) {
        UiSize.smallPhone => 12.0,
        UiSize.phone => 14.0,
        UiSize.tablet => 24.0,
        UiSize.desktop => 32.0,
      };

  /// O'qishga qulay maksimal kenglik — planshetda ro'yxat butun ekranga
  /// cho'zilib ketmasin (bir qatorda 1000pt matn o'qishga noqulay)
  double get readableWidth => switch (uiSize) {
        UiSize.desktop => 1100.0,
        UiSize.tablet => 860.0,
        _ => double.infinity,
      };
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 28.0;
  static const xxxl = 40.0;
}

class AppShadows {
  static List<BoxShadow> get xs => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> coloredGlow(Color color, {double opacity = 0.28}) => [
        BoxShadow(
          color: color.withValues(alpha: opacity),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}

class AppDuration {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
}

class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.surface,
      surfaceTint: AppColors.primary,
    );

    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.bg,
      textTheme: textTheme,
      fontFamily: GoogleFonts.inter().fontFamily,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.text, size: 22),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderSoft,
        thickness: 1,
        space: 1,
      ),
      // `ListTile` ning zavod sozlamasi ilova uchun juda bo'sh:
      // yon tomonda 16pt, ikonka bilan matn orasida 16pt (ustiga
      // `minLeadingWidth: 40` — kichik ikonka ham 40pt joy egallaydi)
      // va 72pt minimal balandlik. Natijada oddiy «ikonka + nom +
      // qiymat» qatori butun ekranning oltidan birini olardi va bir
      // ekranga 7-8 ta element sig'ardi. Bu yerda bir marta
      // ixchamlashtirilsa — ListTile ishlatadigan HAMMA ro'yxat
      // (printerlar, mijozlar, zonalar, ta'minot, xodimlar...) zichroq
      // bo'ladi.
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 12),
        horizontalTitleGap: 10,
        minLeadingWidth: 0,
        minVerticalPadding: 8,
      ),
      iconTheme: const IconThemeData(color: AppColors.text, size: 22),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          side: const BorderSide(color: AppColors.border, width: 1),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        selectedColor: AppColors.primary,
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.text,
        ),
        secondaryLabelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.textFaint),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.text,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textMuted,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.text,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        selectedIconTheme: const IconThemeData(
          color: AppColors.primary,
          size: 24,
        ),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textMuted,
          size: 24,
        ),
        selectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textMuted,
        ),
        useIndicator: true,
        indicatorColor: AppColors.primarySoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.text,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
