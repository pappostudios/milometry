import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// Native TTS — replaces flutter_tts which crashes on iOS 26.
// AVSpeechSynthesizer is called via a method channel to AppDelegate.swift.
// ==========================================
class _NativeTts {
  static const _channel = MethodChannel('com.pappostudios.milometry/tts');
  String _language = 'en-US';
  double _rate = 0.5;

  Future<void> setLanguage(String lang) async {
    _language = lang;
  }

  Future<void> setSpeechRate(double rate) async {
    _rate = rate;
  }

  Future<void> speak(String text) async {
    try {
      await _channel.invokeMethod('speak', {
        'text': text,
        'language': _language,
        'rate': _rate,
      });
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}

// ==========================================
// הגדרות גלובליות
// ==========================================
const int currentTermsVersion = 3;

// Set to true once real iOS AdMob unit IDs are added to _AdIds
const bool kAdsEnabled = false;

// ==========================================
// הגדרות רכישה
// ==========================================
const String kFullVersionProductId = 'milometry_full_version';
const String kAppStoreId = '6762563156';

// ==========================================
// PURCHASE MANAGER
// ==========================================
class PurchaseManager {
  static final PurchaseManager _instance = PurchaseManager._internal();
  factory PurchaseManager() => _instance;
  PurchaseManager._internal();

  final ValueNotifier<bool> isPro = ValueNotifier(false);
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  ProductDetails? _productDetails;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isPro.value = prefs.getBool('is_pro') ?? false;

    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) return;

    // האזנה לעדכוני רכישה
    _subscription = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) => print('Purchase stream error: $error'),
    );

    // טעינת פרטי המוצר מהחנות
    await _loadProductDetails();
  }

  Future<void> _loadProductDetails() async {
    try {
      final ProductDetailsResponse response = await InAppPurchase.instance
          .queryProductDetails({kFullVersionProductId}).timeout(
              const Duration(seconds: 8));
      if (response.productDetails.isNotEmpty) {
        _productDetails = response.productDetails.first;
      }
    } catch (_) {
      // timed out or store unavailable — _productDetails stays null
    }
  }

  ProductDetails? get productDetails => _productDetails;

  Future<void> reloadProductDetails() => _loadProductDetails();

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == kFullVersionProductId) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          await _setPro(true);
        } else if (purchase.status == PurchaseStatus.error) {
          print('Purchase error: ${purchase.error}');
        }
        if (purchase.pendingCompletePurchase) {
          await InAppPurchase.instance.completePurchase(purchase);
        }
      }
    }
  }

  Future<void> _setPro(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro', value);
    isPro.value = value;
  }

  /// מפעיל את תהליך הרכישה
  Future<bool> buyFullVersion(BuildContext context) async {
    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      _showError(context, 'החנות אינה זמינה כרגע. נסה שוב מאוחר יותר.');
      return false;
    }
    if (_productDetails == null) {
      await _loadProductDetails();
    }
    if (_productDetails == null) {
      _showError(context, 'לא הצלחנו לטעון את פרטי הרכישה. נסה שוב.');
      return false;
    }
    final PurchaseParam param = PurchaseParam(productDetails: _productDetails!);
    return await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
  }

  /// שחזור רכישות קודמות
  Future<void> restorePurchases(BuildContext context) async {
    final bool available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      _showError(context, 'החנות אינה זמינה כרגע.');
      return;
    }
    await InAppPurchase.instance.restorePurchases();
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void dispose() {
    _subscription?.cancel();
  }

  /// FOR TESTING ONLY – instantly simulates paid/free state without going
  /// through the store.  Guarded by [kDebugMode] so the tree-shaker removes
  /// it entirely from release builds.
  Future<void> setProDebug(bool value) async {
    if (!kDebugMode) return;
    await _setPro(value);
  }
}

// ==========================================
// AD MANAGER — stubbed out while kAdsEnabled = false.
// To re-enable: uncomment google_mobile_ads in pubspec.yaml,
// uncomment the import above, fill in real iOS ad unit IDs,
// and restore the full AdManager implementation.
// ==========================================

class AdManager {
  static final AdManager _instance = AdManager._internal();
  factory AdManager() => _instance;
  AdManager._internal();

  Future<void> init() async {}
  Widget buildBanner() => const SizedBox.shrink();
  void showInterstitial() {}
  void dispose() {}
}

// ==========================================
// STREAK MANAGER
// ==========================================
class StreakManager {
  static final StreakManager _instance = StreakManager._internal();
  factory StreakManager() => _instance;
  StreakManager._internal();

  final ValueNotifier<int> currentStreak = ValueNotifier(0);
  final ValueNotifier<int> dailyGoalNotifier = ValueNotifier(10);
  final ValueNotifier<int> todayWordsNotifier = ValueNotifier(0);
  int longestStreak = 0;
  int todayWordsStudied = 0;
  int dailyGoal = 10;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    currentStreak.value = prefs.getInt('streak_current') ?? 0;
    longestStreak = prefs.getInt('streak_longest') ?? 0;
    dailyGoal = prefs.getInt('daily_goal') ?? 10;
    dailyGoalNotifier.value = dailyGoal;

    final String today = _dateKey(DateTime.now());
    final String yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final String? lastDate = prefs.getString('streak_last_date');

    // אם עברו יותר מיום — מאפסים את הרצף
    if (lastDate != null && lastDate != today && lastDate != yesterday) {
      currentStreak.value = 0;
      await prefs.setInt('streak_current', 0);
    }

    todayWordsStudied = prefs.getInt('streak_today_$today') ?? 0;
    todayWordsNotifier.value = todayWordsStudied;
  }

  Future<void> setDailyGoal(int goal) async {
    dailyGoal = goal;
    dailyGoalNotifier.value = goal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('daily_goal', goal);
  }

  Future<void> recordStudySession(int wordsStudied) async {
    if (wordsStudied <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final String today = _dateKey(DateTime.now());
    final String yesterday =
        _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final String? lastDate = prefs.getString('streak_last_date');

    // עדכון מספר מילים היום
    final int updatedCount =
        (prefs.getInt('streak_today_$today') ?? 0) + wordsStudied;
    await prefs.setInt('streak_today_$today', updatedCount);
    todayWordsStudied = updatedCount;
    todayWordsNotifier.value = updatedCount;

    // עדכון רצף
    if (lastDate == today) {
      // כבר למד היום — לא משנים את הרצף
    } else if (lastDate == null || lastDate == yesterday) {
      // למד אתמול (או ראשון בכלל) — מגדילים רצף
      final int newStreak = currentStreak.value + 1;
      currentStreak.value = newStreak;
      await prefs.setInt('streak_current', newStreak);
      if (newStreak > longestStreak) {
        longestStreak = newStreak;
        await prefs.setInt('streak_longest', longestStreak);
      }
    } else {
      // פספס יום — מאפסים לרצף של 1
      currentStreak.value = 1;
      await prefs.setInt('streak_current', 1);
    }

    await prefs.setString('streak_last_date', today);
  }

  Future<List<bool>> getLast7DaysActivity() async {
    final prefs = await SharedPreferences.getInstance();
    return List.generate(7, (i) {
      final date = _dateKey(DateTime.now().subtract(Duration(days: 6 - i)));
      return (prefs.getInt('streak_today_$date') ?? 0) > 0;
    });
  }

  String _dateKey(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

// ==========================================
// ANIMATION HELPER: כפתור עם אפקט לחיצה
// ==========================================
class AnimatedButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final double scale;

  const AnimatedButton({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.95,
  });

  @override
  State<AnimatedButton> createState() => _AnimatedButtonState();
}

class _AnimatedButtonState extends State<AnimatedButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: widget.child,
      ),
    );
  }
}

// ==========================================
// PAGE ROUTE עם אנימציה
// ==========================================
Route _slideRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeInOutCubic));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
    transitionDuration: const Duration(milliseconds: 350),
  );
}

// ==========================================
// 1. Theme Manager
// ==========================================
class ThemeManager {
  static final ThemeManager _instance = ThemeManager._internal();
  factory ThemeManager() => _instance;
  ThemeManager._internal();

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedTheme = prefs.getString('theme_mode');
    if (savedTheme == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else if (savedTheme == 'light') {
      themeMode.value = ThemeMode.light;
    }
  }

  Future<void> toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (themeMode.value == ThemeMode.dark) {
      themeMode.value = ThemeMode.light;
      await prefs.setString('theme_mode', 'light');
    } else {
      themeMode.value = ThemeMode.dark;
      await prefs.setString('theme_mode', 'dark');
    }
  }
}

// ==========================================
// 2. Color Palette Helper
// ==========================================
// Unit colors use a categorical (non-sequential) palette so no unit
// reads as "harder" or "easier" than another based on color alone.
// Hue order: Indigo → Teal → Pink → Blue → DeepOrange →
//            Purple → Green → Amber → Cyan → Brown
Color getUnitColor(int unit, bool isDark) {
  if (isDark) {
    switch (unit) {
      case 1:
        return const Color(0xFF303F9F); // Indigo 700
      case 2:
        return const Color(0xFF00796B); // Teal 700
      case 3:
        return const Color(0xFFAD1457); // Pink 800
      case 4:
        return const Color(0xFF1565C0); // Blue 800
      case 5:
        return const Color(0xFFE64A19); // Deep Orange 700
      case 6:
        return const Color(0xFF6A1B9A); // Purple 800
      case 7:
        return const Color(0xFF2E7D32); // Green 800
      case 8:
        return const Color(0xFFF9A825); // Amber 800
      case 9:
        return const Color(0xFF00838F); // Cyan 700
      case 10:
        return const Color(0xFF4E342E); // Brown 800
      default:
        return const Color(0xFF424242);
    }
  } else {
    switch (unit) {
      case 1:
        return const Color(0xFFC5CAE9); // Indigo 100
      case 2:
        return const Color(0xFFB2DFDB); // Teal 100
      case 3:
        return const Color(0xFFF8BBD0); // Pink 100
      case 4:
        return const Color(0xFFBBDEFB); // Blue 100
      case 5:
        return const Color(0xFFFFCCBC); // Deep Orange 100
      case 6:
        return const Color(0xFFE1BEE7); // Purple 100
      case 7:
        return const Color(0xFFC8E6C9); // Green 100
      case 8:
        return const Color(0xFFFFECB3); // Amber 100
      case 9:
        return const Color(0xFFB2EBF2); // Cyan 100
      case 10:
        return const Color(0xFFD7CCC8); // Brown 100
      default:
        return Colors.white;
    }
  }
}

Color getTextColorForBackground(int unit, bool isDark) {
  if (isDark) return Colors.white;
  // All light-theme pastels (100-range) are light enough for black text
  return Colors.black87;
}

// ==========================================
// DESIGN SYSTEM CONSTANTS
// ==========================================
const Color kBgCream = Color(0xFFFAF3EA);
const Color kBluePrimary = Color(0xFF3D8BFD);
const Color kPurplePrimary = Color(0xFF7A3DFD);
const Color kDarkButton = Color(0xFF1A1A2E);
const Color kDarkShadow = Color(0xFF0A0A14);
const Color kGreenButton = Color(0xFF1AA84A);
const Color kGreenShadow = Color(0xFF0C6B29);
const Color kAgainRed = Color(0xFFE14F4F);
const Color kHardOrange = Color(0xFFFF8C3D);
const Color kGoodBlue = Color(0xFF3D8BFD);
const Color kEasyGreen = Color(0xFF1AA84A);

// ==========================================
// 3. NotificationManager
// ==========================================
class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();
  factory NotificationManager() => _instance;
  NotificationManager._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    try {
      final location = tz.getLocation('Asia/Jerusalem');
      tz.setLocalLocation(location);
    } catch (e) {
      print("Could not set Israel timezone: $e");
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print("User clicked on notification");
      },
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleDailyNotification(int hour, int minute) async {
    const String channelId = 'daily_reminders_v10';
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'זמן ללמוד! 🎓',
      'המילים שלך מחכות לך... בוא נתרגל קצת',
      _nextInstanceOfTime(hour, minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'תזכורות יומיות',
          channelDescription: 'תזכורת יומית ללימוד מילים',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleInactivityNotification(int hoursFromNow) async {
    await cancelNotifications();
    const String channelId = 'inactivity_reminder_v1';
    final tz.TZDateTime scheduledDate =
        tz.TZDateTime.now(tz.local).add(Duration(hours: hoursFromNow));
    await flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'המילים מתגעגעות אליך! 🥺',
      'עברו כבר $hoursFromNow שעות... בוא להשלים פערים!',
      scheduledDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'תזכורות נחישות',
          channelDescription: 'תזכורת המבוססת על זמן אי-פעילות',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    print("Notification scheduled for: $scheduledDate");
  }

  Future<void> cancelNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}

// ==========================================
// REVIEW MANAGER
// Shows the native App Store / Play Store rating dialog after the user
// completes 3 study sessions, then no more than once every 30 days.
// ==========================================
class ReviewManager {
  static final ReviewManager _instance = ReviewManager._internal();
  factory ReviewManager() => _instance;
  ReviewManager._internal();

  static const String _keySessionCount = 'review_session_count';
  static const String _keyLastRequested = 'review_last_requested_ms';
  static const int _sessionsBeforeFirstAsk = 3;
  static const int _daysBetweenAsks = 30;

  Future<void> recordSessionAndMaybeAsk() async {
    final prefs = await SharedPreferences.getInstance();

    // Increment session counter
    final int count = (prefs.getInt(_keySessionCount) ?? 0) + 1;
    await prefs.setInt(_keySessionCount, count);

    // Too few sessions? Skip.
    if (count < _sessionsBeforeFirstAsk) return;

    // Asked too recently? Skip.
    final int lastMs = prefs.getInt(_keyLastRequested) ?? 0;
    final DateTime lastDate =
        DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true);
    final int daysSince = DateTime.now().toUtc().difference(lastDate).inDays;
    if (daysSince < _daysBetweenAsks) return;

    // Ask for a review — try/catch because isAvailable() can return false
    // on iOS 26 even when StoreKit is functional.
    try {
      await InAppReview.instance.requestReview();
      if (!kDebugMode) {
        await prefs.setInt(
            _keyLastRequested, DateTime.now().toUtc().millisecondsSinceEpoch);
      }
    } catch (_) {
      // StoreKit not ready — will retry next session
    }
  }
}

// ==========================================
// 4. Progress Manager
// ==========================================
class ProgressManager {
  static final ProgressManager _instance = ProgressManager._internal();
  factory ProgressManager() => _instance;
  ProgressManager._internal();

  SharedPreferences? _prefs;
  final Map<String, Map<String, dynamic>> _cache = {};

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadFromDisk();
  }

  void _loadFromDisk() {
    List<String>? rawData = _prefs?.getStringList('userprogress');
    // Migrate from old key 'user_progress' if new key has no data
    if (rawData == null || rawData.isEmpty) {
      final legacyData = _prefs?.getStringList('user_progress');
      if (legacyData != null && legacyData.isNotEmpty) {
        rawData = legacyData;
        // Migrate to new key and remove old one
        _prefs?.setStringList('userprogress', rawData);
        _prefs?.remove('user_progress');
      }
    }
    rawData ??= [];
    _cache.clear();
    for (String record in rawData) {
      List<String> parts = record.split(':');
      String id = parts[0];
      if (parts.length >= 5) {
        _cache[id] = {
          'repetitions': int.parse(parts[1]),
          'interval': int.parse(parts[2]),
          'easinessFactor': double.parse(parts[3]),
          'nextReview':
              DateTime.fromMillisecondsSinceEpoch(int.parse(parts[4])),
          'word_status': parts.length >= 6 ? parts[5] : '',
          'muvvan_repeat_done': parts.length >= 7 ? parts[6] == '1' : false,
        };
      } else if (parts.length == 3) {
        int lvl = int.parse(parts[1]);
        if (lvl > 0) {
          _cache[id] = {
            'repetitions': lvl,
            'interval': 1,
            'easinessFactor': 2.5,
            // Fix: use a future date so known words don't immediately
            // reappear in practice after loading from legacy format.
            'nextReview': DateTime.now().add(const Duration(days: 1))
          };
        }
      }
    }
  }

  Map<String, dynamic>? getWordProgress(String uniqueId) {
    return _cache[uniqueId];
  }

  /// מחזיר עותק של כל ההתקדמות השמורה
  Map<String, Map<String, dynamic>> getAllProgress() {
    return Map.unmodifiable(_cache);
  }

  Future<void> updateWord(
      String uniqueId, int reps, int interval, double ef, DateTime nextReview,
      {String wordStatus = ''}) async {
    _cache[uniqueId] = {
      'repetitions': reps,
      'interval': interval,
      'easinessFactor': ef,
      'nextReview': nextReview,
      'word_status': wordStatus,
    };
    await _saveToDisk();
  }

  /// Returns uniqueIds of all words with a given word_status.
  List<String> getAllByStatus(String status) {
    return _cache.entries
        .where((e) => (e.value['word_status'] ?? '') == status)
        .map((e) => e.key)
        .toList();
  }

  int countByStatus(String status) =>
      _cache.values.where((v) => (v['word_status'] ?? '') == status).length;

  Future<void> resetWord(String uniqueId) async {
    _cache.remove(uniqueId);
    await _saveToDisk();
  }

  // ── "מובן — מילים שהבנת" repeat-practice tracking ──────────────
  // Tracks, per word, whether it has already been re-practiced in the
  // current "מובן" review cycle. Independent of word_status/repetitions —
  // never touched by applyWordStatus/updateWord.
  bool isMuvvanRepeatDone(String uniqueId) =>
      _cache[uniqueId]?['muvvan_repeat_done'] ?? false;

  Future<void> markMuvvanRepeatDone(String uniqueId) async {
    final entry = _cache[uniqueId];
    if (entry == null) return;
    entry['muvvan_repeat_done'] = true;
    await _saveToDisk();
  }

  /// Resets the repeat-practice flag. [uniqueIds] null = every word
  /// (global reset); otherwise only the given words (scoped reset).
  Future<void> resetMuvvanRepeatTracking({Set<String>? uniqueIds}) async {
    if (uniqueIds == null) {
      for (final v in _cache.values) {
        v['muvvan_repeat_done'] = false;
      }
    } else {
      for (final id in uniqueIds) {
        _cache[id]?['muvvan_repeat_done'] = false;
      }
    }
    await _saveToDisk();
  }

  List<String> getMuvvanWordsAwaitingRepeat() => _cache.entries
      .where((e) =>
          (e.value['word_status'] ?? '') == 'muvvan' &&
          !(e.value['muvvan_repeat_done'] ?? false))
      .map((e) => e.key)
      .toList();

  bool get allMuvvanRepeatDone {
    final muvvanEntries =
        _cache.values.where((v) => (v['word_status'] ?? '') == 'muvvan');
    if (muvvanEntries.isEmpty) return false;
    return muvvanEntries.every((v) => v['muvvan_repeat_done'] == true);
  }

  Future<void> _saveToDisk() async {
    List<String> exportList = [];
    _cache.forEach((key, value) {
      int n = value['repetitions'];
      int i = value['interval'];
      double ef = value['easinessFactor'];
      int time = (value['nextReview'] as DateTime).millisecondsSinceEpoch;
      String status = value['word_status'] ?? '';
      bool repeatDone = value['muvvan_repeat_done'] ?? false;
      exportList.add("$key:$n:$i:$ef:$time:$status:${repeatDone ? '1' : '0'}");
    });
    await _prefs?.setStringList('userprogress', exportList);
  }

  Future<void> resetAll() async {
    _cache.clear();
    await _prefs?.clear();
  }
}

// ==========================================
// 5. Data Model
// ==========================================
class Word {
  final int id;
  final String language;
  final String term;
  final String translation;
  final String example;
  final int unitNumber;
  final int difficulty; // 1 (easiest) – 10 (hardest)
  DateTime nextReview;
  int repetitions;
  int interval;
  double easinessFactor;

  Word({
    required this.id,
    required this.language,
    required this.term,
    required this.translation,
    required this.example,
    required this.unitNumber,
    this.difficulty = 5,
    DateTime? nextReview,
    this.repetitions = 0,
    this.interval = 0,
    this.easinessFactor = 2.5,
  }) : nextReview = nextReview ?? DateTime.now();

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      id: json['id'],
      language: json['language'],
      term: json['term'],
      translation: json['translation'],
      example: json['example'],
      unitNumber: json['unit'] ?? 0,
      difficulty: json['difficulty'] ?? 5,
    );
  }

  String get uniqueId => "${language}_$id";
}

// ==========================================
// 6. Main Entry Point
// ==========================================
void main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exception}');
    };

    try {
      await ThemeManager().init();
    } catch (e) {
      debugPrint('ThemeManager init error: $e');
    }
    try {
      await ProgressManager().init();
    } catch (e) {
      debugPrint('ProgressManager init error: $e');
    }
    try {
      await NotificationManager().init();
    } catch (e) {
      debugPrint('NotificationManager init error: $e');
    }
    try {
      await PurchaseManager().init();
    } catch (e) {
      debugPrint('PurchaseManager init error: $e');
    }
    try {
      await AdManager().init();
    } catch (e) {
      debugPrint('AdManager init error: $e');
    }
    try {
      await StreakManager().init();
    } catch (e) {
      debugPrint('StreakManager init error: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final int userAcceptedVersion = prefs.getInt('accepted_terms_version') ?? 0;
    final bool hasChosenDetermination =
        prefs.getBool('hasChosenDetermination') ?? false;
    final bool shownInstructions =
        prefs.getBool('shown_practice_instructions') ?? false;

    Widget firstScreen;
    if (userAcceptedVersion != currentTermsVersion) {
      firstScreen = const TermsOfServiceScreen();
    } else if (!hasChosenDetermination) {
      firstScreen = const DeterminationScreen();
    } else if (!shownInstructions) {
      firstScreen = const InstructionsScreen();
    } else {
      firstScreen = const HomeScreen();
    }

    runApp(PsychoApp(startScreen: firstScreen));
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error\n$stack');
  });
}

class PsychoApp extends StatelessWidget {
  final Widget startScreen;
  const PsychoApp({super.key, required this.startScreen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeManager().themeMode,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'מילומטרי',
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('he', 'IL'),
            Locale('en', 'US'),
          ],
          locale: const Locale('he', 'IL'),
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: Colors.blue,
            scaffoldBackgroundColor: const Color(0xFFF0F4FF),
            fontFamily: 'Arial',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.black),
              titleTextStyle: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              elevation: 0,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: Colors.blueAccent,
            scaffoldBackgroundColor: const Color(0xFF121212),
            fontFamily: 'Arial',
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              iconTheme: IconThemeData(color: Colors.white),
              titleTextStyle: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              elevation: 0,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              ),
            ),
          ),
          home: startScreen,
        );
      },
    );
  }
}

// ==========================================
// 7. Splash Screen
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.pushReplacement(context, _slideRoute(const HomeScreen()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/logo.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(color: const Color(0xFFF3F0EB));
            },
          ),
          const Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// NEW DESIGN WIDGETS
// ==========================================

// ── MiliCharacter ──────────────────────────────────────────────────────────
class _MiliPainter extends CustomPainter {
  final double bobOffset;
  _MiliPainter(this.bobOffset);

  @override
  void paint(Canvas canvas, Size size) {
    final double s = size.width / 200.0; // scale from 200×200 viewbox

    canvas.save();
    canvas.translate(0, bobOffset * s);

    // Drop shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(100 * s, 182 * s), width: 112 * s, height: 14 * s),
      Paint()..color = Colors.black.withOpacity(0.10),
    );
    // Body
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(100 * s, 105 * s), width: 144 * s, height: 136 * s),
      Paint()..color = kBluePrimary,
    );
    // Highlight
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(75 * s, 78 * s), width: 44 * s, height: 28 * s),
      Paint()..color = Colors.white.withOpacity(0.22),
    );
    // Left eye
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(78 * s, 100 * s), width: 22 * s, height: 26 * s),
      Paint()..color = const Color(0xFF1A1A2E),
    );
    // Right eye
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(122 * s, 100 * s), width: 22 * s, height: 26 * s),
      Paint()..color = const Color(0xFF1A1A2E),
    );
    // Eye sparkles
    canvas.drawCircle(
        Offset(82 * s, 95 * s), 3.5 * s, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(126 * s, 95 * s), 3.5 * s, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(75 * s, 106 * s), 2 * s, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(119 * s, 106 * s), 2 * s, Paint()..color = Colors.white);
    // Cheeks
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(64 * s, 125 * s), width: 20 * s, height: 14 * s),
      Paint()..color = Colors.pink.withOpacity(0.35),
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(136 * s, 125 * s), width: 20 * s, height: 14 * s),
      Paint()..color = Colors.pink.withOpacity(0.35),
    );
    // Smile
    final smilePath = Path()
      ..moveTo(86 * s, 135 * s)
      ..quadraticBezierTo(100 * s, 150 * s, 114 * s, 135 * s);
    canvas.drawPath(
      smilePath,
      Paint()
        ..color = const Color(0xFF1A1A2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * s
        ..strokeCap = StrokeCap.round,
    );
    // Waving hand (small ellipses off right side)
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(166 * s, 118 * s), width: 24 * s, height: 20 * s),
      Paint()..color = kBluePrimary,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(170 * s, 110 * s), width: 14 * s, height: 12 * s),
      Paint()..color = kBluePrimary,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MiliPainter old) => old.bobOffset != bobOffset;
}

class MiliCharacter extends StatefulWidget {
  final double size;
  const MiliCharacter({super.key, this.size = 104});

  @override
  State<MiliCharacter> createState() => _MiliCharacterState();
}

class _MiliCharacterState extends State<MiliCharacter>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _bob;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _bob = Tween<double>(begin: 0, end: -6).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bob,
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _MiliPainter(_bob.value),
      ),
    );
  }
}

// ── SpeechBubble ──────────────────────────────────────────────────────────
class SpeechBubble extends StatefulWidget {
  const SpeechBubble({super.key});

  @override
  State<SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<SpeechBubble> {
  static const List<String> _messages = [
    'כל מילה חדשה — עוד נקודה בפסיכומטרי 🎯',
    '5 דקות ביום שוות יותר מ-2 שעות בשבוע ⏱️',
    'המוח שלך מתחזק עם כל חזרה 💪',
    'אתה בדרך הנכונה! המשך כך ✨',
    'כל חזרה מחזקת את הזיכרון שלך 🧠',
  ];

  int _index = 0;
  double _opacity = 1.0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() => _opacity = 0.0);
      Future.delayed(const Duration(milliseconds: 350), () {
        if (!mounted) return;
        setState(() {
          _index = (_index + 1) % _messages.length;
          _opacity = 1.0;
        });
        _startTimer();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 300),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFE6EEFB),
          ),
        ),
        child: Text(
          _messages[_index],
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF444444),
            height: 1.4,
          ),
        ),
      ),
    );
  }
}

// ── ProgressSegments ──────────────────────────────────────────────────────
class ProgressSegments extends StatelessWidget {
  final int total;
  final int currentIndex;
  final List<String> outcomes;

  const ProgressSegments({
    super.key,
    required this.total,
    required this.currentIndex,
    required this.outcomes,
  });

  Color _color(String state) {
    switch (state) {
      // new 3-button outcomes
      case 'lo_hevanti':
        return kAgainRed;
      case 'kacha_kacha':
        return const Color(0xFFFFB800);
      case 'muvvan':
        return kEasyGreen;
      // legacy (review mode fallback)
      case 'again':
        return kAgainRed;
      case 'hard':
        return kHardOrange;
      case 'good':
        return kGoodBlue;
      case 'easy':
        return kEasyGreen;
      case 'current':
        return kPurplePrimary;
      default:
        return const Color(0xFFE4E7EE);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        String state;
        if (i < outcomes.length) {
          state = outcomes[i];
        } else if (i == currentIndex) {
          state = 'current';
        } else {
          state = 'todo';
        }
        return Expanded(
          child: Container(
            height: 6,
            margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
            decoration: BoxDecoration(
              color: _color(state),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }
}

// ── SRSButton ──────────────────────────────────────────────────────────────
class SRSButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final Color color;
  final VoidCallback onTap;

  const SRSButton({
    super.key,
    required this.label,
    required this.sublabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.6),
          boxShadow: [
            BoxShadow(color: color, offset: const Offset(0, 3), blurRadius: 0),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }
}

// ── ResponseButton (3-button system) ──────────────────────────────────────
class _ResponseButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ResponseButton(
      {required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.40),
                offset: const Offset(0, 3),
                blurRadius: 0),
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}

// ── MascotCheer ────────────────────────────────────────────────────────────
class MascotCheer extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const MascotCheer({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<MascotCheer> createState() => _MascotCheerState();
}

class _MascotCheerState extends State<MascotCheer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _scale = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      bottom: 100,
      left: 16,
      right: 16,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: kBluePrimary.withOpacity(0.18),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE6EEFB),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              const MiliCharacter(size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Confetti ───────────────────────────────────────────────────────────────
class _ConfettiParticle {
  final double x;
  final double size;
  final double speed;
  final double delay;
  final Color color;
  final double rotation;

  const _ConfettiParticle({
    required this.x,
    required this.size,
    required this.speed,
    required this.delay,
    required this.color,
    required this.rotation,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiPainter(this.progress, this.particles);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (final p in particles) {
      final t = ((progress + p.delay) % 1.0);
      final x = p.x * size.width;
      final y = t * (size.height + 60) - 20;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + progress * 6.28 * p.speed);
      paint.color = p.color;
      canvas.drawRect(
        Rect.fromCenter(
            center: Offset.zero, width: p.size, height: p.size * 0.45),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class Confetti extends StatefulWidget {
  const Confetti({super.key});

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late List<_ConfettiParticle> _particles;

  static const _colors = [
    kBluePrimary,
    kPurplePrimary,
    kAgainRed,
    kEasyGreen,
    Colors.amber,
    Colors.pink,
  ];

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _particles = List.generate(
        50,
        (i) => _ConfettiParticle(
              x: rng.nextDouble(),
              size: 7 + rng.nextDouble() * 6,
              speed: 0.8 + rng.nextDouble() * 0.6,
              delay: rng.nextDouble(),
              color: _colors[i % _colors.length],
              rotation: rng.nextDouble() * 6.28,
            ));
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_ctrl.value, _particles),
        ),
      ),
    );
  }
}

// ==========================================
// 8. Home Screen
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Logo + button entry animations (kept from original)
  late AnimationController _logoController;
  late AnimationController _buttonsController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _hebrewSlide;
  late Animation<Offset> _englishSlide;

  // Animated background blobs
  late AnimationController _blob1Ctrl;
  late AnimationController _blob2Ctrl;
  late AnimationController _blob3Ctrl;
  late Animation<Offset> _blob1Anim;
  late Animation<Offset> _blob2Anim;
  late Animation<Offset> _blob3Anim;

  // Streak chip pulse
  late AnimationController _streakPulseCtrl;
  late Animation<double> _streakPulseAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationManager().cancelNotifications();

    // Logo
    _logoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

    // Buttons
    _buttonsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _hebrewSlide = Tween<Offset>(begin: const Offset(-1.5, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _buttonsController, curve: Curves.easeOutCubic));
    _englishSlide = Tween<Offset>(begin: const Offset(1.5, 0), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _buttonsController, curve: Curves.easeOutCubic));

    // Background blobs — gentle floating
    _blob1Ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 7))
          ..repeat(reverse: true);
    _blob1Anim = Tween<Offset>(
            begin: Offset.zero, end: const Offset(0.04, -0.05))
        .animate(CurvedAnimation(parent: _blob1Ctrl, curve: Curves.easeInOut));

    _blob2Ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 9))
          ..repeat(reverse: true);
    _blob2Anim = Tween<Offset>(
            begin: Offset.zero, end: const Offset(-0.05, 0.04))
        .animate(CurvedAnimation(parent: _blob2Ctrl, curve: Curves.easeInOut));

    _blob3Ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat(reverse: true);
    _blob3Anim = Tween<Offset>(
            begin: Offset.zero, end: const Offset(0.03, 0.04))
        .animate(CurvedAnimation(parent: _blob3Ctrl, curve: Curves.easeInOut));

    // Streak pulse
    _streakPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _streakPulseAnim = Tween<double>(begin: 1.0, end: 1.08).animate(
        CurvedAnimation(parent: _streakPulseCtrl, curve: Curves.easeInOut));

    _logoController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _buttonsController.forward();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _logoController.dispose();
    _buttonsController.dispose();
    _blob1Ctrl.dispose();
    _blob2Ctrl.dispose();
    _blob3Ctrl.dispose();
    _streakPulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final prefs = await SharedPreferences.getInstance();
    final bool notificationsEnabled =
        prefs.getBool('notifications_enabled') ?? true;
    final int hours = prefs.getInt('determination_hours') ?? 24;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (notificationsEnabled) {
        await NotificationManager().scheduleInactivityNotification(hours);
      }
    } else if (state == AppLifecycleState.resumed) {
      await NotificationManager().cancelNotifications();
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return 'בוקר טוב, המילים מחכות לך';
    if (h >= 12 && h < 17) return 'צהריים טובים, המילים מחכות לך';
    if (h >= 17 && h < 21) return 'ערב טוב, המילים מחכות לך';
    return 'לילה טוב, אתגר היום מחכה';
  }

  Widget _buildPillButton(
      String label, Color bg, Color shadow, VoidCallback onTap) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        height: 64,
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(color: shadow, offset: const Offset(0, 4), blurRadius: 0),
          ],
        ),
        child: Center(
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : kBgCream,
      body: Stack(
        children: [
          // ── Animated background blobs ──
          SlideTransition(
            position: _blob1Anim,
            child: Positioned(
              top: -70,
              right: -70,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBluePrimary.withValues(alpha: isDark ? 0.10 : 0.22),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: _blob2Anim,
            child: Positioned(
              top: 200,
              left: -90,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kPurplePrimary.withValues(alpha: isDark ? 0.07 : 0.15),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: _blob3Anim,
            child: Positioned(
              bottom: -90,
              right: -50,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kBluePrimary.withValues(alpha: isDark ? 0.07 : 0.13),
                ),
              ),
            ),
          ),

          // ── Main content ──
          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Settings chip
                      AnimatedButton(
                        onTap: () => Navigator.push(
                            context, _slideRoute(const SettingsScreen())),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Icon(Icons.settings_rounded,
                              color: isDark ? Colors.white70 : Colors.grey[700],
                              size: 22),
                        ),
                      ),

                      // Streak chip with pulse
                      ValueListenableBuilder<int>(
                        valueListenable: StreakManager().currentStreak,
                        builder: (ctx, streak, _) => AnimatedBuilder(
                          animation: _streakPulseAnim,
                          builder: (ctx, child) => Transform.scale(
                            scale: streak > 0 ? _streakPulseAnim.value : 1.0,
                            child: child,
                          ),
                          child: AnimatedButton(
                            onTap: () {
                              Navigator.push(
                                  ctx, _slideRoute(const StreakScreen()));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '$streak',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: streak > 0
                                          ? Colors.orange
                                          : (isDark
                                              ? Colors.white54
                                              : Colors.grey[500]),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text('🔥',
                                      style: TextStyle(fontSize: 18)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Center area: greeting + icon + app name ──
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Time-of-day greeting
                      Text(
                        _greeting(),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white38 : Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Real app icon
                      FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: Container(
                            width: 128,
                            height: 128,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                )
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Image.asset(
                                'assets/icon.png',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: kBluePrimary,
                                  child: const Icon(Icons.school_rounded,
                                      size: 64, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // App name gradient
                      FadeTransition(
                        opacity: _logoFade,
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [kBluePrimary, kPurplePrimary],
                          ).createShader(bounds),
                          child: const Text(
                            'מילומטרי',
                            style: TextStyle(
                              fontSize: 46,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                      ),

                      // Subtitle
                      FadeTransition(
                        opacity: _logoFade,
                        child: Text(
                          'מילים לפסיכומטרי',
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white38 : Colors.grey[500],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Mascot + speech bubble ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const MiliCharacter(size: 96),
                      const SizedBox(width: 10),
                      const Expanded(child: SpeechBubble()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Language buttons ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      SlideTransition(
                        position: _hebrewSlide,
                        child: _buildPillButton(
                          'עברית',
                          kDarkButton,
                          kDarkShadow,
                          () => Navigator.push(
                            context,
                            _slideRoute(const UnitSelectorScreen(
                                jsonPath: 'assets/hebrew_with_difficulty.json',
                                title: 'עברית')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SlideTransition(
                        position: _englishSlide,
                        child: _buildPillButton(
                          'אנגלית',
                          kGreenButton,
                          kGreenShadow,
                          () => Navigator.push(
                            context,
                            _slideRoute(const UnitSelectorScreen(
                                jsonPath: 'assets/english_with_difficulty.json',
                                title: 'אנגלית')),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => Navigator.push(
                            context, _slideRoute(const InstructionsScreen())),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.flip(
                              flipX: true,
                              child: Icon(Icons.help_outline_rounded,
                                  size: 16,
                                  color:
                                      isDark ? Colors.white38 : Colors.black38),
                            ),
                            const SizedBox(width: 5),
                            Text('איך זה עובד?',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: PurchaseManager().isPro,
        builder: (context, isPro, _) =>
            isPro ? const SizedBox.shrink() : AdManager().buildBanner(),
      ),
    );
  }
}

// ==========================================
// 9. Unit Selector
// ==========================================
class UnitSelectorScreen extends StatefulWidget {
  final String jsonPath;
  final String title;
  const UnitSelectorScreen(
      {super.key, required this.jsonPath, required this.title});

  @override
  State<UnitSelectorScreen> createState() => _UnitSelectorScreenState();
}

class _UnitSelectorScreenState extends State<UnitSelectorScreen> {
  bool isLoading = true;
  int totalFailedCount = 0;
  int kachaKachaCount = 0;
  int muvvanCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final String response = await rootBundle.loadString(widget.jsonPath);
      final data = json.decode(response);
      final list = data['words'] as List;
      final allWords = list.map((w) => Word.fromJson(w)).toList();

      int failedCounter = 0;
      int kachaCounter = 0;
      int muvvanCounter = 0;
      for (var word in allWords) {
        final progress = ProgressManager().getWordProgress(word.uniqueId);
        if (progress != null) {
          final reps = progress['repetitions'] ?? 0;
          final status = progress['word_status'] ?? '';
          if (reps == 0) failedCounter++;
          if (status == 'kacha_kacha') kachaCounter++;
          if (status == 'muvvan') muvvanCounter++;
        }
      }

      if (!mounted) return;
      setState(() {
        totalFailedCount = failedCounter;
        kachaKachaCount = kachaCounter;
        muvvanCount = muvvanCounter;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Widget _modeButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 30, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: Colors.white)),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 13, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 4),

                // ── מובן — browse + practice (conditional) ────────────
                if (muvvanCount > 0)
                  _modeButton(
                    title: 'מובן — מילים שהבנת',
                    subtitle: '$muvvanCount מילים שסיימת',
                    icon: Icons.check_circle_rounded,
                    colors: [kEasyGreen, const Color(0xFF0C6B29)],
                    onTap: () async {
                      await Navigator.push(
                          context,
                          _slideRoute(
                              MuvvanSelectorScreen(jsonPath: widget.jsonPath)));
                      _loadCounts();
                    },
                  ),

                // ── ככה ככה — practice (conditional) ─────────────────
                if (kachaKachaCount > 0)
                  _modeButton(
                    title: 'תרגול — ככה ככה',
                    subtitle: '$kachaKachaCount מילים לתרגול נוסף',
                    icon: Icons.replay_rounded,
                    colors: const [Color(0xFFFFB800), Color(0xFFE57300)],
                    onTap: () async {
                      await Navigator.push(
                          context,
                          _slideRoute(KachaKachaSelectorScreen(
                              jsonPath: widget.jsonPath)));
                      _loadCounts();
                    },
                  ),

                // ── לא הבנתי (conditional) ────────────────────────────
                if (totalFailedCount > 0)
                  _modeButton(
                    title: 'חזרה על מילים שלא הכרת',
                    subtitle: '$totalFailedCount מילים לחיזוק',
                    icon: Icons.refresh_rounded,
                    colors: [Colors.red.shade400, Colors.red.shade800],
                    onTap: () async {
                      await Navigator.push(
                          context,
                          _slideRoute(FailedWordsSelectorScreen(
                              jsonPath: widget.jsonPath)));
                      _loadCounts();
                    },
                  ),

                // ── תרגול לפי יחידה ──────────────────────────────────
                _modeButton(
                  title: 'תרגול לפי יחידה',
                  subtitle: 'יחידות 1–10',
                  icon: Icons.layers_rounded,
                  colors: const [Color(0xFF1A1A2E), Color(0xFF3D4070)],
                  onTap: () async {
                    await Navigator.push(
                        context,
                        _slideRoute(UnitListScreen(
                            jsonPath: widget.jsonPath, title: widget.title)));
                    _loadCounts();
                  },
                ),

                // ── תרגול לפי רמת קושי ────────────────────────────────
                _modeButton(
                  title: 'תרגול לפי רמת קושי',
                  subtitle: '5 רמות — מבסיסי עד קיצוני',
                  icon: Icons.bar_chart_rounded,
                  colors: const [Color(0xFF7A3DFD), Color(0xFF3D8BFD)],
                  onTap: () async {
                    final prefix =
                        widget.jsonPath.contains('hebrew') ? 'heb' : 'eng';
                    await Navigator.push(
                        context,
                        _slideRoute(LevelSelectorScreen(
                            langPrefix: prefix, title: widget.title)));
                    _loadCounts();
                  },
                ),
              ],
            ),
    );
  }
}

// ==========================================
// 9b. Unit List Screen (unit cards 1-N)
// ==========================================
class UnitListScreen extends StatefulWidget {
  final String jsonPath;
  final String title;
  const UnitListScreen(
      {super.key, required this.jsonPath, required this.title});

  @override
  State<UnitListScreen> createState() => _UnitListScreenState();
}

class _UnitListScreenState extends State<UnitListScreen> {
  Map<int, List<Word>> units = {};
  Map<int, int> learnedCounts = {};
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final String response = await rootBundle.loadString(widget.jsonPath);
      final data = json.decode(response);
      final list = data['words'] as List;
      final allWords = list.map((w) => Word.fromJson(w)).toList();

      Map<int, List<Word>> tempUnits = {};
      Map<int, int> tempCounts = {};

      for (var word in allWords) {
        final u = word.unitNumber;
        if (u == 0) continue;
        tempUnits.putIfAbsent(u, () => []).add(word);
        tempCounts.putIfAbsent(u, () => 0);
        final progress = ProgressManager().getWordProgress(word.uniqueId);
        if (progress != null && (progress['repetitions'] ?? 0) > 0) {
          tempCounts[u] = tempCounts[u]! + 1;
        }
      }

      if (!mounted) return;
      setState(() {
        units = tempUnits;
        learnedCounts = tempCounts;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  void _showOptionsDialog(BuildContext context, int unitNum) {
    showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("יחידה $unitNum", textAlign: TextAlign.center),
              children: [
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context,
                        _slideRoute(LearningScreen(
                            jsonPath: widget.jsonPath, unitFilter: unitNum)));
                    _loadData();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(Icons.play_circle_fill,
                          color: Colors.blue, size: 30),
                      SizedBox(width: 15),
                      Text("התחל תרגול", style: TextStyle(fontSize: 18))
                    ]),
                  ),
                ),
                const Divider(),
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context,
                        _slideRoute(VocabularyListScreen(
                            jsonPath: widget.jsonPath, unitFilter: unitNum)));
                    _loadData();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(Icons.list, color: Colors.black87, size: 30),
                      SizedBox(width: 15),
                      Text("רשימת מילים", style: TextStyle(fontSize: 18))
                    ]),
                  ),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    final sortedKeys = units.keys.toList()..sort();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text("יחידות — ${widget.title}")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: sortedKeys.map((unitNum) {
                final total = units[unitNum]!.length;
                final learned = learnedCounts[unitNum]!;
                final progress = total > 0 ? learned / total : 0.0;
                final unitColor = getUnitColor(unitNum, isDark);
                final textColor = getTextColorForBackground(unitNum, isDark);

                return AnimatedButton(
                  onTap: () => _showOptionsDialog(context, unitNum),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: unitColor,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: unitColor.withValues(alpha: 0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text("יחידה $unitNum",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: textColor)),
                            const Spacer(),
                            Icon(Icons.arrow_forward_ios,
                                size: 16, color: textColor),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text("התקדמות: $learned / $total מילים",
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.8),
                                fontSize: 13)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.4),
                            color: textColor == Colors.white
                                ? Colors.greenAccent
                                : Colors.blue,
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ==========================================
// 9c. Level Selector Screen
// ==========================================
class _LevelMeta {
  final String label;
  final String sublabel;
  final Color color;
  final Color shadow;
  const _LevelMeta(this.label, this.sublabel, this.color, this.shadow);
}

const _kLevelMeta = [
  _LevelMeta(
      'בסיסי', 'מילים יומיומיות ושכיחות', Color(0xFF3D8BFD), Color(0xFF1A5FC4)),
  _LevelMeta('בינוני', 'עיתונות', Color(0xFF1AA84A), Color(0xFF0C6B29)),
  _LevelMeta(
      'גבוה', 'אקדמי, ספרותי ומשנה', Color(0xFFFF8C3D), Color(0xFFB85C10)),
  _LevelMeta('מתקדם', 'ארכאי, מלכודות פסיכומטרי', Color(0xFFE14F4F),
      Color(0xFFA02020)),
  _LevelMeta(
      'קיצוני', 'תנ"כי ועתיק מאוד', Color(0xFF7A3DFD), Color(0xFF4A1AC0)),
];

class LevelSelectorScreen extends StatefulWidget {
  final String langPrefix; // 'heb' or 'eng'
  final String title;
  const LevelSelectorScreen(
      {super.key, required this.langPrefix, required this.title});

  @override
  State<LevelSelectorScreen> createState() => _LevelSelectorScreenState();
}

class _LevelSelectorScreenState extends State<LevelSelectorScreen> {
  List<int> _totalCounts = List.filled(5, 0);
  List<int> _learnedCounts = List.filled(5, 0);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final totals = List.filled(5, 0);
    final learned = List.filled(5, 0);

    for (int lvl = 1; lvl <= 5; lvl++) {
      try {
        final path = 'assets/levels/${widget.langPrefix}_level_$lvl.json';
        final String response = await rootBundle.loadString(path);
        final data = json.decode(response);
        final list = data['words'] as List;
        totals[lvl - 1] = list.length;

        int learnedCount = 0;
        for (final w in list) {
          final word = Word.fromJson(w);
          final progress = ProgressManager().getWordProgress(word.uniqueId);
          if (progress != null && (progress['repetitions'] ?? 0) > 0) {
            learnedCount++;
          }
        }
        learned[lvl - 1] = learnedCount;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _totalCounts = totals;
      _learnedCounts = learned;
      _isLoading = false;
    });
  }

  void _showOptionsDialog(
      BuildContext context, int levelNum, String path, String label) {
    showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title:
                  Text('רמה $levelNum — $label', textAlign: TextAlign.center),
              children: [
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context, _slideRoute(LearningScreen(jsonPath: path)));
                    _loadCounts();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(Icons.play_circle_fill,
                          color: Colors.blue, size: 30),
                      SizedBox(width: 15),
                      Text('התחל תרגול', style: TextStyle(fontSize: 18))
                    ]),
                  ),
                ),
                const Divider(),
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(context,
                        _slideRoute(VocabularyListScreen(jsonPath: path)));
                    _loadCounts();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(Icons.list, color: Colors.black87, size: 30),
                      SizedBox(width: 15),
                      Text('רשימת מילים', style: TextStyle(fontSize: 18))
                    ]),
                  ),
                ),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('רמות קושי — ${widget.title}')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 5,
              itemBuilder: (context, i) {
                final meta = _kLevelMeta[i];
                final total = _totalCounts[i];
                final lrnd = _learnedCounts[i];
                final progress = total > 0 ? lrnd / total : 0.0;
                final levelNum = i + 1;
                final path =
                    'assets/levels/${widget.langPrefix}_level_$levelNum.json';

                return AnimatedButton(
                  onTap: () =>
                      _showOptionsDialog(context, levelNum, path, meta.label),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: meta.color,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: meta.shadow.withValues(alpha: 0.45),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('רמה $levelNum',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 10),
                            Text(meta.label,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            const Icon(Icons.arrow_forward_ios,
                                size: 16, color: Colors.white70),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(meta.sublabel,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 10),
                        Text('התקדמות: $lrnd / $total מילים',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.30),
                            color: Colors.greenAccent,
                            minHeight: 8,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
// Shared helper: apply a 3-button status to a word
// (mirrors LearningScreen.updateWordProgress mapping)
// ==========================================
Future<void> applyWordStatus(String uniqueId, String action) async {
  int reps, interval;
  double ef;
  switch (action) {
    case 'lo_hevanti':
      reps = 0;
      interval = 1;
      ef = 1.3;
      break;
    case 'kacha_kacha':
      reps = 1;
      interval = 1;
      ef = 2.5;
      break;
    case 'muvvan':
      reps = 3;
      interval = 3;
      ef = 2.5;
      break;
    default:
      reps = 0;
      interval = 1;
      ef = 2.5;
  }
  await ProgressManager().updateWord(
    uniqueId,
    reps,
    interval,
    ef,
    DateTime.now().add(Duration(days: interval)),
    wordStatus: action,
  );
}

// ==========================================
// 10. Vocabulary List Screen
// ==========================================
class VocabularyListScreen extends StatefulWidget {
  final String jsonPath;
  final int? unitFilter;
  const VocabularyListScreen(
      {super.key, required this.jsonPath, this.unitFilter});

  @override
  State<VocabularyListScreen> createState() => _VocabularyListScreenState();
}

class _VocabularyListScreenState extends State<VocabularyListScreen> {
  List<Word> filteredWords = [];
  Map<String, int> wordLevels = {};
  Map<String, String> wordStatuses = {};
  bool isLoading = true;
  // 'default' = לפי סדר (no reordering). Otherwise one of the word_status
  // values ('muvvan'/'kacha_kacha'/'lo_hevanti') or 'not_studied' for לא נלמד.
  String _sortMode = 'default';

  static const Map<String, String> _sortLabels = {
    'default': 'לפי סדר',
    'muvvan': 'מובן',
    'kacha_kacha': 'ככה ככה',
    'lo_hevanti': 'לא הבנתי',
    'not_studied': 'לא נלמד',
  };

  // Stable "sort to top": words matching _sortMode float to the top,
  // preserving relative order within each group. Nothing is hidden.
  List<Word> get _displayWords {
    if (_sortMode == 'default') return filteredWords;
    final matching = <Word>[];
    final rest = <Word>[];
    for (final w in filteredWords) {
      final status = wordStatuses[w.uniqueId] ?? '';
      final isMatch = _sortMode == 'not_studied' ? status.isEmpty : status == _sortMode;
      (isMatch ? matching : rest).add(w);
    }
    return [...matching, ...rest];
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = await json.decode(response);
    var list = data["words"] as List;
    List<Word> allWords = list.map((w) => Word.fromJson(w)).toList();

    Map<String, int> levels = {};
    Map<String, String> statuses = {};
    List<Word> relevantWords = [];

    for (var w in allWords) {
      if (widget.unitFilter != null && w.unitNumber != widget.unitFilter) {
        continue;
      }
      relevantWords.add(w);
      var progress = ProgressManager().getWordProgress(w.uniqueId);
      if (progress != null) {
        levels[w.uniqueId] = progress['repetitions'] ?? 0;
        statuses[w.uniqueId] = progress['word_status'] ?? '';
      }
    }

    if (!mounted) return;
    setState(() {
      filteredWords = relevantWords;
      wordLevels = levels;
      wordStatuses = statuses;
      isLoading = false;
    });
  }

  Future<void> setWordStatus(Word word, String action) async {
    await applyWordStatus(word.uniqueId, action);
    loadData();
  }

  // Returns the leading status icon based on the new 3-button system,
  // falling back to legacy repetition data for words marked before the change.
  Icon _statusIcon(Word word) {
    final status = wordStatuses[word.uniqueId] ?? '';
    switch (status) {
      case 'muvvan':
        return const Icon(Icons.check_circle, color: kEasyGreen);
      case 'kacha_kacha':
        return const Icon(Icons.adjust, color: Color(0xFFFFB800));
      case 'lo_hevanti':
        return const Icon(Icons.cancel, color: kAgainRed);
    }
    // Legacy fallback
    if (!wordLevels.containsKey(word.uniqueId)) {
      return const Icon(Icons.remove_circle_outline, color: Colors.grey);
    } else if (wordLevels[word.uniqueId]! > 0) {
      return const Icon(Icons.check_circle, color: Colors.blue);
    }
    return const Icon(Icons.cancel, color: kAgainRed);
  }

  @override
  Widget build(BuildContext context) {
    final displayWords = _displayWords;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.unitFilter != null
            ? "רשימה - יחידה ${widget.unitFilter}"
            : "כל המילים"),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'מיין לפי',
            initialValue: _sortMode,
            onSelected: (mode) => setState(() => _sortMode = mode),
            itemBuilder: (context) => _sortLabels.entries
                .map((e) => PopupMenuItem<String>(
                      value: e.key,
                      child: Row(
                        children: [
                          if (e.key == _sortMode)
                            const Icon(Icons.check, size: 18)
                          else
                            const SizedBox(width: 18),
                          const SizedBox(width: 8),
                          Text(e.value),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: displayWords.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final word = displayWords[index];

                return ListTile(
                  leading: _statusIcon(word),
                  title: Hero(
                    tag: word.uniqueId,
                    child: Material(
                      color: Colors.transparent,
                      child: Directionality(
                        textDirection: word.language == 'english'
                            ? TextDirection.ltr
                            : TextDirection.rtl,
                        child: Text(
                          word.term,
                          textAlign: word.language == 'english'
                              ? TextAlign.left
                              : TextAlign.right,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                  ),
                  subtitle: Text(word.translation),
                  onTap: () {
                    showDialog(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20)),
                              title:
                                  Text(word.term, textAlign: TextAlign.center),
                              children: [
                                SimpleDialogOption(
                                  onPressed: () async {
                                    Navigator.pop(ctx);
                                    await Navigator.push(
                                        context,
                                        _slideRoute(
                                            SingleCardScreen(word: word)));
                                    loadData();
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Row(children: [
                                      Icon(Icons.visibility,
                                          color: Colors.black),
                                      SizedBox(width: 10),
                                      Text("צפייה בכרטיסייה",
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold))
                                    ]),
                                  ),
                                ),
                                const Divider(),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setWordStatus(word, 'muvvan');
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.check_circle, color: kEasyGreen),
                                    SizedBox(width: 10),
                                    Text("מובן")
                                  ]),
                                ),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setWordStatus(word, 'kacha_kacha');
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.adjust,
                                        color: Color(0xFFFFB800)),
                                    SizedBox(width: 10),
                                    Text("ככה ככה")
                                  ]),
                                ),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    setWordStatus(word, 'lo_hevanti');
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.cancel, color: kAgainRed),
                                    SizedBox(width: 10),
                                    Text("לא הבנתי")
                                  ]),
                                ),
                              ],
                            ));
                  },
                );
              },
            ),
    );
  }
}

// ==========================================
// 11. Learning Screen
// ==========================================
class LearningScreen extends StatefulWidget {
  final String jsonPath;
  final int? unitFilter;
  final bool onlyFailed;
  final bool onlyKachaKacha;

  const LearningScreen({
    super.key,
    required this.jsonPath,
    this.unitFilter,
    this.onlyFailed = false,
    this.onlyKachaKacha = false,
  });

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen>
    with TickerProviderStateMixin {
  List<Word> fullVocabulary = [];
  List<Word> studySession = [];
  bool isLoading = true;
  bool isReviewMode = false;
  int _currentIndex = 0;
  int _wordsStudiedThisSession = 0;
  bool _sessionRecorded = false;
  final _NativeTts flutterTts = _NativeTts();

  // New design state
  bool _isFlipped = false;
  bool _lastExitLeft = false;
  int _sessionStreak = 0;
  final List<String> _outcomes = [];
  final Map<String, int> _stats = {
    'lo_hevanti': 0,
    'kacha_kacha': 0,
    'muvvan': 0,
  };
  String? _cheerMessage;
  // Tracks how many times each word was re-queued this session.
  // After 1 retry, the word is dropped from the session (avoids infinite loops).
  final Map<String, int> _sessionRetries = {};
  int _deckSize = 0;

  @override
  void initState() {
    super.initState();
    loadJsonData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> speak(String text, String language) async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('tts_speed') ?? 0.5;
    await flutterTts.setLanguage(language == 'hebrew' ? 'he-IL' : 'en-US');
    await flutterTts.setSpeechRate(speed);
    await flutterTts.speak(text);
  }

  Future<void> loadJsonData() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = await json.decode(response);
    var list = data["words"] as List;
    List<Word> rawWords = list.map((w) => Word.fromJson(w)).toList();

    List<Word> sessionWords = [];
    List<Word> filteredTotal = [];

    for (var w in rawWords) {
      if (widget.unitFilter != null && w.unitNumber != widget.unitFilter) {
        continue;
      }

      var progress = ProgressManager().getWordProgress(w.uniqueId);
      if (progress != null) {
        w.repetitions = progress['repetitions'];
        w.interval = progress['interval'];
        w.easinessFactor = progress['easinessFactor'];
        w.nextReview = progress['nextReview'];
      }

      if (widget.onlyFailed) {
        if (progress != null && w.repetitions == 0) {
          sessionWords.add(w);
          filteredTotal.add(w);
        }
        continue;
      }

      if (widget.onlyKachaKacha) {
        final status = progress != null ? (progress['word_status'] ?? '') : '';
        if (status == 'kacha_kacha') {
          sessionWords.add(w);
          filteredTotal.add(w);
        }
        continue;
      }

      filteredTotal.add(w);
      if (w.nextReview.isBefore(DateTime.now()) || w.repetitions == 0) {
        sessionWords.add(w);
      }
    }

    if (widget.onlyFailed || widget.onlyKachaKacha) {
      sessionWords.shuffle();
    } else {
      sessionWords.sort((a, b) => a.nextReview.compareTo(b.nextReview));
    }

    int startIndex = 0;
    if (!widget.onlyFailed && !widget.onlyKachaKacha) {
      final prefs = await SharedPreferences.getInstance();
      final String? lastWordId = prefs.getString('last_session_word_id');
      if (lastWordId != null && sessionWords.isNotEmpty) {
        final exactIdx =
            sessionWords.indexWhere((w) => w.uniqueId == lastWordId);
        if (exactIdx >= 0) {
          startIndex = exactIdx;
        } else {
          final lastVocabPos =
              filteredTotal.indexWhere((w) => w.uniqueId == lastWordId);
          if (lastVocabPos >= 0) {
            final vocabPosMap = {
              for (int i = 0; i < filteredTotal.length; i++)
                filteredTotal[i].uniqueId: i
            };
            for (int i = 0; i < sessionWords.length; i++) {
              final vp = vocabPosMap[sessionWords[i].uniqueId] ?? -1;
              if (sessionWords[i].repetitions == 0 && vp > lastVocabPos) {
                startIndex = i;
                break;
              }
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      fullVocabulary = filteredTotal;
      studySession = sessionWords;
      isLoading = false;
      isReviewMode = false;
      _currentIndex = startIndex;
      _deckSize = sessionWords.length;
    });
  }

  void startReviewSession() {
    List<Word> learnedWords =
        fullVocabulary.where((w) => w.repetitions > 0).toList();
    learnedWords.shuffle();
    setState(() {
      studySession = learnedWords;
      isReviewMode = true;
      _currentIndex = 0;
      _isFlipped = false;
      _outcomes.clear();
      _stats.updateAll((_, __) => 0);
      _sessionStreak = 0;
      _deckSize = learnedWords.length;
      _sessionRetries.clear();
    });
  }

  /// 3-button response. action ∈ {'lo_hevanti','kacha_kacha','muvvan'}
  Future<void> updateWordProgress(String action) async {
    if (studySession.isEmpty) return;
    Word word = studySession[_currentIndex];

    SharedPreferences.getInstance()
        .then((p) => p.setString('last_session_word_id', word.uniqueId));

    final bool isPositive = action != 'lo_hevanti';
    _lastExitLeft = action == 'lo_hevanti';

    if (isPositive) {
      _sessionStreak++;
      _checkCheer();
    } else {
      _sessionStreak = 0;
    }

    _outcomes.add(action);
    _stats[action] = (_stats[action] ?? 0) + 1;

    switch (action) {
      case 'lo_hevanti':
        word.repetitions = 0;
        word.interval = 1;
        word.easinessFactor = 1.3;
        break;
      case 'kacha_kacha':
        word.repetitions = 1;
        word.interval = 1;
        word.easinessFactor = 2.5;
        break;
      case 'muvvan':
        word.repetitions = 3;
        word.interval = 3;
        word.easinessFactor = 2.5;
        break;
    }

    word.nextReview = DateTime.now().add(Duration(days: word.interval));
    await ProgressManager().updateWord(
      word.uniqueId,
      word.repetitions,
      word.interval,
      word.easinessFactor,
      word.nextReview,
      wordStatus: action,
    );

    _wordsStudiedThisSession++;
    if (isPositive) StreakManager().recordStudySession(1);

    setState(() {
      studySession.removeAt(_currentIndex);
      if (_currentIndex >= studySession.length) {
        _currentIndex = studySession.isNotEmpty ? studySession.length - 1 : 0;
      }
      _isFlipped = false;
    });

    if (studySession.isEmpty && !isReviewMode && !_sessionRecorded) {
      _sessionRecorded = true;
      AdManager().showInterstitial();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          _slideRoute(SessionDoneScreen(
            sessionWordCount: _wordsStudiedThisSession,
            stats: Map.from(_stats),
            jsonPath: widget.jsonPath,
            unitFilter: widget.unitFilter,
          )),
        );
      }
    }
  }

  void _checkCheer() {
    const msgs = {
      3: '3 ברצף! 🔥 ממשיכים?',
      6: '6 ברצף! המוח שלך באש',
      10: '10 ברצף! יוצא מן הכלל ⭐',
    };
    if (msgs.containsKey(_sessionStreak)) {
      setState(() => _cheerMessage = msgs[_sessionStreak]);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _cheerMessage = null);
      });
    }
  }

  // ── Difficulty badge ─────────────────────────────────────────────────────

  Color _difficultyColor(int d) {
    if (d <= 3) return const Color(0xFF1AA84A); // green — easy
    if (d <= 6) return const Color(0xFFFF8C3D); // orange — medium
    return const Color(0xFFE14F4F); // red — hard
  }

  String _difficultyLabel(int d) {
    if (d <= 3) return 'קל';
    if (d <= 6) return 'בינוני';
    return 'קשה';
  }

  Widget _buildDifficultyBadge(int difficulty) {
    final color = _difficultyColor(difficulty);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            _difficultyLabel(difficulty),
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  // ── Card face builders ───────────────────────────────────────────────────

  Widget _audioButton(Word word, {double size = 50}) {
    return GestureDetector(
      onTap: () => speak(word.term, word.language),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kBluePrimary.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.volume_up_rounded,
            color: kBluePrimary, size: size * 0.52),
      ),
    );
  }

  Widget _buildFrontFace(Word word) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langLabel = word.language == 'english' ? '🇬🇧 אנגלית' : '🇮🇱 עברית';
    return Container(
      key: ValueKey('front_${word.uniqueId}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2232) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFEFF1F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Language chip + difficulty badge + audio button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kBluePrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(langLabel,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kBluePrimary)),
              ),
              _buildDifficultyBadge(word.difficulty),
            ],
          ),
          // Word — centered, big
          Expanded(
            child: Center(
              child: Directionality(
                textDirection: word.language == 'english'
                    ? TextDirection.ltr
                    : TextDirection.rtl,
                child: Text(
                  word.term,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
          // Audio button under the word
          _audioButton(word),
          const SizedBox(height: 16),
          // Flip hint pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A3A) : const Color(0xFFF0F0F5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'הקש כדי להפוך',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace(Word word) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: ValueKey('back_${word.uniqueId}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2232) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: isDark ? Colors.white12 : const Color(0xFFEFF1F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Word chip
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: kBluePrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(word.term,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: kBluePrimary)),
            ),
          ),
          const SizedBox(height: 10),
          // translation label
          Text(word.language == 'hebrew' ? 'פירוש' : 'תרגום',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.grey[500],
                  letterSpacing: 0.06)),
          const SizedBox(height: 6),
          // Translation
          Text(
            word.translation,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: kBluePrimary,
                height: 1.25),
          ),
          const SizedBox(height: 12),
          Center(child: _audioButton(word)),
          const SizedBox(height: 16),
          // Example sentence box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2510) : const Color(0xFFFFF8E8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color:
                    isDark ? const Color(0xFF3A3010) : const Color(0xFFFCE9C0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('דוגמה במשפט',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.amber.shade200
                            : const Color(0xFF8B6914),
                        letterSpacing: 0.06)),
                const SizedBox(height: 6),
                Directionality(
                  textDirection: word.language == 'english'
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  child: _buildExampleText(word, isDark),
                ),
              ],
            ),
          ),
          const Spacer(),
          // "seen N times" footer
          Center(
            child: Text(
              '🔁 נראית ${word.repetitions} פעמים',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.grey[500]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExampleText(Word word, bool isDark) {
    final example = word.example;
    final term = word.term.toLowerCase();
    final lower = example.toLowerCase();
    final idx = lower.indexOf(term);
    if (idx < 0) {
      return Text(example,
          style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: isDark ? Colors.white70 : const Color(0xFF1A1A2E)));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(
            fontSize: 14,
            height: 1.55,
            color: isDark ? Colors.white70 : const Color(0xFF1A1A2E)),
        children: [
          TextSpan(text: example.substring(0, idx)),
          TextSpan(
            text: example.substring(idx, idx + word.term.length),
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: kBluePrimary),
          ),
          TextSpan(text: example.substring(idx + word.term.length)),
        ],
      ),
    );
  }

  Widget _buildFlipButton() {
    return AnimatedButton(
      onTap: () => setState(() => _isFlipped = true),
      child: Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          color: kDarkButton,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(color: kDarkShadow, offset: Offset(0, 4), blurRadius: 0),
          ],
        ),
        child: const Center(
          child: Text('הפוך כרטיס',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildResponseRow() {
    return Row(
      children: [
        Expanded(
            child: _ResponseButton(
                label: 'לא הבנתי',
                color: kAgainRed,
                onTap: () => updateWordProgress('lo_hevanti'))),
        const SizedBox(width: 8),
        Expanded(
            child: _ResponseButton(
                label: 'ככה ככה',
                color: const Color(0xFFFFB800),
                onTap: () => updateWordProgress('kacha_kacha'))),
        const SizedBox(width: 8),
        Expanded(
            child: _ResponseButton(
                label: 'מובן',
                color: kEasyGreen,
                onTap: () => updateWordProgress('muvvan'))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleText = widget.onlyFailed
        ? 'חזרה על שגיאות'
        : widget.onlyKachaKacha
            ? 'תרגול ככה ככה'
            : 'יחידה ${widget.unitFilter ?? 'כללי'}';
    final displayTotal = _deckSize > 0 ? _deckSize : studySession.length;
    final displayCurrent = _outcomes.length + 1;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(titleText,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: studySession.isEmpty && !_sessionRecorded
          // Only shown while loading the session-done navigation
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SafeArea(
                  child: Column(
                    children: [
                      // ── Header strip ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Session streak
                                Row(
                                  children: [
                                    Icon(Icons.bolt_rounded,
                                        size: 16,
                                        color: _sessionStreak > 0
                                            ? Colors.orange
                                            : Colors.grey[400]),
                                    const SizedBox(width: 3),
                                    Text(
                                      'סשן: $_sessionStreak ברצף',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: _sessionStreak > 0
                                            ? Colors.orange
                                            : Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                                // Counter
                                Text(
                                  '$displayCurrent / $displayTotal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ProgressSegments(
                              total: displayTotal,
                              currentIndex: _outcomes.length,
                              outcomes: _outcomes,
                            ),
                          ],
                        ),
                      ),

                      // ── Card area ──
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          child: studySession.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    setState(() => _isFlipped = !_isFlipped);
                                  },
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, anim) {
                                      // Slide direction based on last answer
                                      final isEntering = child.key ==
                                              ValueKey(
                                                  'front_${studySession[_currentIndex].uniqueId}') ||
                                          child.key ==
                                              ValueKey(
                                                  'back_${studySession[_currentIndex].uniqueId}');
                                      final offset = isEntering
                                          ? Tween<Offset>(
                                              begin: const Offset(1.0, 0),
                                              end: Offset.zero)
                                          : Tween<Offset>(
                                              begin: Offset.zero,
                                              end: Offset(
                                                  _lastExitLeft ? -1.0 : 1.0,
                                                  0));
                                      return SlideTransition(
                                          position: offset.animate(anim),
                                          child: child);
                                    },
                                    child: _isFlipped
                                        ? _buildBackFace(
                                            studySession[_currentIndex])
                                        : _buildFrontFace(
                                            studySession[_currentIndex]),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),

                      // ── Action row ──
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: _isFlipped
                            ? _buildResponseRow()
                            : _buildFlipButton(),
                      ),
                    ],
                  ),
                ),

                // Mascot cheer overlay
                if (_cheerMessage != null)
                  MascotCheer(
                    message: _cheerMessage!,
                    onDismiss: () => setState(() => _cheerMessage = null),
                  ),
              ],
            ),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: PurchaseManager().isPro,
        builder: (ctx, isPro, _) =>
            isPro ? const SizedBox.shrink() : AdManager().buildBanner(),
      ),
    );
  }
}

// ==========================================
// 11b. Session Done Screen
// ==========================================
class SessionDoneScreen extends StatefulWidget {
  final int sessionWordCount;
  final Map<String, int> stats;
  final String jsonPath;
  final int? unitFilter;

  const SessionDoneScreen({
    super.key,
    required this.sessionWordCount,
    required this.stats,
    required this.jsonPath,
    this.unitFilter,
  });

  @override
  State<SessionDoneScreen> createState() => _SessionDoneScreenState();
}

class _SessionDoneScreenState extends State<SessionDoneScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.sessionWordCount >= 5) {
      ReviewManager().recordSessionAndMaybeAsk();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muvvan = widget.stats['muvvan'] ?? 0;
    final kachaKacha = widget.stats['kacha_kacha'] ?? 0;
    final loHevanti = widget.stats['lo_hevanti'] ?? 0;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'כל הכבוד!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          const Confetti(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Mascot
                  const MiliCharacter(size: 140),
                  const SizedBox(height: 24),
                  // Gradient "סשן הושלם!" title
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [kBluePrimary, kPurplePrimary],
                    ).createShader(bounds),
                    child: const Text(
                      'סשן הושלם!',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'סיימת ${widget.sessionWordCount} מילים בסבב הזה.\nהזיכרון שלך תמיד מתחזק קצת יותר.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.55,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Stats row
                  Row(
                    children: [
                      _StatBlock(
                          value: muvvan,
                          label: 'מובן',
                          color: kEasyGreen,
                          isDark: isDark),
                      const SizedBox(width: 10),
                      _StatBlock(
                          value: kachaKacha,
                          label: 'ככה ככה',
                          color: const Color(0xFFFFB800),
                          isDark: isDark),
                      const SizedBox(width: 10),
                      _StatBlock(
                          value: loHevanti,
                          label: 'לא הבנתי',
                          color: kAgainRed,
                          isDark: isDark),
                    ],
                  ),
                  const SizedBox(height: 40),
                  // "סבב נוסף" button
                  AnimatedButton(
                    onTap: () => Navigator.pushReplacement(
                      context,
                      _slideRoute(LearningScreen(
                        jsonPath: widget.jsonPath,
                        unitFilter: widget.unitFilter,
                      )),
                    ),
                    child: Container(
                      height: 58,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: kDarkButton,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: const [
                          BoxShadow(
                              color: kDarkShadow,
                              offset: Offset(0, 4),
                              blurRadius: 0),
                        ],
                      ),
                      child: const Center(
                        child: Text('סבב נוסף',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // "חזרה לבית" button
                  AnimatedButton(
                    onTap: () => Navigator.popUntil(context, (r) => r.isFirst),
                    child: Container(
                      height: 52,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A3E) : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color:
                              isDark ? Colors.white24 : const Color(0xFFCDD0D8),
                        ),
                      ),
                      child: Center(
                        child: Text('חזרה לבית',
                            style: TextStyle(
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF1A1A2E),
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  final int value;
  final String label;
  final Color color;
  final bool isDark;

  const _StatBlock({
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text('$value',
                style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 11c. Kacha Kacha Screen — browse "ככה ככה" words
// ==========================================
class KachaKachaScreen extends StatefulWidget {
  final String jsonPath;
  const KachaKachaScreen({super.key, required this.jsonPath});

  @override
  State<KachaKachaScreen> createState() => _KachaKachaScreenState();
}

class _KachaKachaScreenState extends State<KachaKachaScreen> {
  List<Word> _words = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = json.decode(response);
    final list = data['words'] as List;
    final allWords = list.map((w) => Word.fromJson(w)).toList();

    final muvvanIds = ProgressManager().getAllByStatus('muvvan').toSet();
    final filtered =
        allWords.where((w) => muvvanIds.contains(w.uniqueId)).toList();

    if (!mounted) return;
    setState(() {
      _words = filtered;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('מובן — מילים שהבנת')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _words.isEmpty
              ? const Center(
                  child: Text('אין מילים ברשימה כרגע',
                      style: TextStyle(fontSize: 16, color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _words.length,
                  itemBuilder: (context, i) {
                    final w = _words[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E2232) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: kEasyGreen.withValues(alpha: 0.45),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(w.term,
                                    style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1A1A2E))),
                                const SizedBox(height: 4),
                                Text(w.translation,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: kBluePrimary,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: kEasyGreen.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text('מובן',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: kEasyGreen)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ==========================================
// 11d. Muvvan Selector Screen — list / by-unit / by-level / reset
// ==========================================
class MuvvanSelectorScreen extends StatefulWidget {
  final String jsonPath;
  const MuvvanSelectorScreen({super.key, required this.jsonPath});

  @override
  State<MuvvanSelectorScreen> createState() => _MuvvanSelectorScreenState();
}

class _MuvvanSelectorScreenState extends State<MuvvanSelectorScreen> {
  Widget _optionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 5, right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: colors.last.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefix = widget.jsonPath.contains('hebrew') ? 'heb' : 'eng';
    return Scaffold(
      appBar: AppBar(title: const Text('מובן — מילים שהבנת')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _optionButton(
            icon: Icons.list_alt_rounded,
            title: 'רשימת מילים שהבנת',
            subtitle: 'צפייה בכל המילים שסימנת כמובנות',
            colors: [kEasyGreen, const Color(0xFF0C6B29)],
            onTap: () => Navigator.push(context,
                _slideRoute(KachaKachaScreen(jsonPath: widget.jsonPath))),
          ),
          _optionButton(
            icon: Icons.layers_rounded,
            title: 'תרגול לפי יחידה',
            subtitle: 'תרגול חוזר על מילים שהבנת, יחידה אחר יחידה',
            colors: const [Color(0xFF1A1A2E), Color(0xFF3D4070)],
            onTap: () => Navigator.push(context,
                _slideRoute(MuvvanByUnitScreen(jsonPath: widget.jsonPath))),
          ),
          _optionButton(
            icon: Icons.bar_chart_rounded,
            title: 'תרגול לפי רמת קושי',
            subtitle: '5 רמות — רק המילים שהבנת',
            colors: const [Color(0xFF7A3DFD), Color(0xFF3D8BFD)],
            onTap: () => Navigator.push(context,
                _slideRoute(MuvvanByLevelScreen(langPrefix: prefix))),
          ),
          const SizedBox(height: 10),
          _optionButton(
            icon: Icons.restart_alt_rounded,
            title: 'אפס תרגול חוזר',
            subtitle: 'פעולה זאת מאפסת רק את התרגול החוזר ולא את ההתקדמות שלך במילון',
            colors: [Colors.grey.shade600, Colors.grey.shade800],
            onTap: () => Navigator.push(
                context,
                _slideRoute(MuvvanResetScopeScreen(
                    jsonPath: widget.jsonPath, langPrefix: prefix))),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 11e. Muvvan By Unit Screen
// ==========================================
class MuvvanByUnitScreen extends StatefulWidget {
  final String jsonPath;
  const MuvvanByUnitScreen({super.key, required this.jsonPath});

  @override
  State<MuvvanByUnitScreen> createState() => _MuvvanByUnitScreenState();
}

class _MuvvanByUnitScreenState extends State<MuvvanByUnitScreen> {
  Map<int, int> _countsPerUnit = {};
  int _totalCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = json.decode(response);
    final list = data['words'] as List;
    final allWords = list.map((w) => Word.fromJson(w)).toList();

    Map<int, int> tempCounts = {};
    int tempTotal = 0;

    for (var w in allWords) {
      final progress = ProgressManager().getWordProgress(w.uniqueId);
      final status = progress != null ? (progress['word_status'] ?? '') : '';
      final repeatDone = ProgressManager().isMuvvanRepeatDone(w.uniqueId);
      if (status == 'muvvan' && !repeatDone) {
        tempCounts[w.unitNumber] = (tempCounts[w.unitNumber] ?? 0) + 1;
        tempTotal++;
      }
    }

    if (!mounted) return;
    setState(() {
      _countsPerUnit = tempCounts;
      _totalCount = tempTotal;
      _isLoading = false;
    });
  }

  Widget _modeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 5, right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kEasyGreen, Color(0xFF0C6B29)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: kEasyGreen.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedUnits = _countsPerUnit.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('תרגול לפי יחידה — מובן')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _totalCount == 0
              ? const Center(
                  child: Text('אין מילים לתרגול חוזר כרגע',
                      style: TextStyle(fontSize: 16, color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _modeButton(
                      icon: Icons.shuffle,
                      title: 'תרגל הכל (ערבוב)',
                      subtitle: 'כל $_totalCount המילים שהבנת מכל היחידות',
                      onTap: () async {
                        await Navigator.push(
                            context,
                            _slideRoute(MuvvanReviewScreen(
                                jsonPath: widget.jsonPath)));
                        _loadData();
                      },
                    ),
                    const Text('בחר יחידה ספציפית:',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    ...sortedUnits.map((unitNum) {
                      final count = _countsPerUnit[unitNum]!;
                      final unitColor = getUnitColor(unitNum, isDark);
                      final textColor =
                          getTextColorForBackground(unitNum, isDark);

                      return AnimatedButton(
                        onTap: () async {
                          await Navigator.push(
                              context,
                              _slideRoute(MuvvanReviewScreen(
                                  jsonPath: widget.jsonPath,
                                  unitFilter: unitNum)));
                          _loadData();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: unitColor,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: unitColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('יחידה $unitNum',
                                        style: TextStyle(
                                            color: textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 17)),
                                    Text('יש לך $count מילים שהבנת ביחידה זו',
                                        style: TextStyle(
                                            color: textColor.withValues(
                                                alpha: 0.8),
                                            fontSize: 13)),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios,
                                  color: textColor, size: 16),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }
}

// ==========================================
// 11f. Muvvan By Level Screen
// ==========================================
class MuvvanByLevelScreen extends StatefulWidget {
  final String langPrefix; // 'heb' or 'eng'
  const MuvvanByLevelScreen({super.key, required this.langPrefix});

  @override
  State<MuvvanByLevelScreen> createState() => _MuvvanByLevelScreenState();
}

class _MuvvanByLevelScreenState extends State<MuvvanByLevelScreen> {
  final List<int> _counts = List.filled(5, 0);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    for (int lvl = 1; lvl <= 5; lvl++) {
      try {
        final path = 'assets/levels/${widget.langPrefix}_level_$lvl.json';
        final String response = await rootBundle.loadString(path);
        final data = json.decode(response);
        final list = data['words'] as List;
        int count = 0;
        for (final w in list) {
          final word = Word.fromJson(w);
          final progress = ProgressManager().getWordProgress(word.uniqueId);
          final status =
              progress != null ? (progress['word_status'] ?? '') : '';
          final repeatDone = ProgressManager().isMuvvanRepeatDone(word.uniqueId);
          if (status == 'muvvan' && !repeatDone) count++;
        }
        _counts[lvl - 1] = count;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('תרגול לפי רמת קושי — מובן')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 5,
              itemBuilder: (context, index) {
                final lvl = index + 1;
                final meta = _kLevelMeta[index];
                final count = _counts[index];
                final path =
                    'assets/levels/${widget.langPrefix}_level_$lvl.json';

                return AnimatedButton(
                  onTap: count == 0
                      ? () {}
                      : () async {
                          await Navigator.push(
                              context,
                              _slideRoute(
                                  MuvvanReviewScreen(jsonPath: path)));
                          _loadCounts();
                        },
                  child: Opacity(
                    opacity: count == 0 ? 0.45 : 1.0,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [meta.color, meta.shadow],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: meta.shadow.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('$lvl',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(meta.label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text(
                                    count == 0
                                        ? 'אין מילים לתרגול חוזר ✓'
                                        : '$count מילים שהבנת',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
// 11g. Muvvan Review Screen — single "הבנתי" button practice
// ==========================================
class MuvvanReviewScreen extends StatefulWidget {
  final String jsonPath;
  final int? unitFilter;
  const MuvvanReviewScreen({super.key, required this.jsonPath, this.unitFilter});

  @override
  State<MuvvanReviewScreen> createState() => _MuvvanReviewScreenState();
}

class _MuvvanReviewScreenState extends State<MuvvanReviewScreen> {
  List<Word> _session = [];
  bool _isLoading = true;
  int _totalCount = 0;
  final _NativeTts flutterTts = _NativeTts();

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> speak(String text, String language) async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('tts_speed') ?? 0.5;
    await flutterTts.setLanguage(language == 'hebrew' ? 'he-IL' : 'en-US');
    await flutterTts.setSpeechRate(speed);
    await flutterTts.speak(text);
  }

  Future<void> _loadWords() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = json.decode(response);
    final list = data['words'] as List;
    final allWords = list.map((w) => Word.fromJson(w)).toList();

    final filtered = allWords.where((w) {
      if (widget.unitFilter != null && w.unitNumber != widget.unitFilter) {
        return false;
      }
      final progress = ProgressManager().getWordProgress(w.uniqueId);
      final status = progress != null ? (progress['word_status'] ?? '') : '';
      return status == 'muvvan' && !ProgressManager().isMuvvanRepeatDone(w.uniqueId);
    }).toList();
    filtered.shuffle();

    if (!mounted) return;
    setState(() {
      _session = filtered;
      _totalCount = filtered.length;
      _isLoading = false;
    });
  }

  Future<void> _markUnderstood() async {
    if (_session.isEmpty) return;
    final word = _session.first;
    await ProgressManager().markMuvvanRepeatDone(word.uniqueId);

    final justCompletedFullCycle = ProgressManager().allMuvvanRepeatDone;
    // When the whole cycle finishes, report the TOTAL number of green words
    // in the cycle (which may have been practiced across several sessions
    // over several days) — not just the small remaining batch from this
    // final session.
    final wordCountForDisplay = justCompletedFullCycle
        ? ProgressManager().countByStatus('muvvan')
        : _totalCount;
    if (justCompletedFullCycle) {
      await ProgressManager().resetMuvvanRepeatTracking();
    }

    if (!mounted) return;
    setState(() => _session.removeAt(0));

    if (_session.isEmpty) {
      AdManager().showInterstitial();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        _slideRoute(MuvvanReviewDoneScreen(
          wordCount: wordCountForDisplay,
          fullCycleCompleted: justCompletedFullCycle,
        )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_session.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('תרגול חוזר — מובן')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'השלמת את כל המילים שהבנת! אפשר לאפס תרגול חוזר במסך הקודם כדי להתחיל סבב חדש.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }

    final word = _session.first;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressDone = _totalCount - _session.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('תרגול חוזר — ${progressDone + 1} / $_totalCount'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2232) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: kEasyGreen.withValues(alpha: 0.45), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(word.term,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1A1A2E))),
                            ),
                            if (word.language == 'english') ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.volume_up_rounded,
                                    color: kBluePrimary),
                                onPressed: () =>
                                    speak(word.term, word.language),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(word.translation,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 18,
                                color: kBluePrimary,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: AnimatedButton(
                  onTap: _markUnderstood,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kEasyGreen, Color(0xFF0C6B29)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: Text('הבנתי',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 11h. Muvvan Review Done Screen
// ==========================================
class MuvvanReviewDoneScreen extends StatelessWidget {
  final int wordCount;
  final bool fullCycleCompleted;
  const MuvvanReviewDoneScreen(
      {super.key, required this.wordCount, required this.fullCycleCompleted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.celebration_rounded,
                    color: kEasyGreen, size: 64),
                const SizedBox(height: 20),
                Text('סיימת תרגול חוזר של $wordCount מילים 🎉',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                if (fullCycleCompleted) ...[
                  const SizedBox(height: 12),
                  Text(
                      'תרגלת מחדש את כל המילים שהבנת! הרשימה התאפסה כדי שתוכל להתחיל סבב חדש.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: Colors.grey.shade600)),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('חזרה למסך הבית'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 11i. Muvvan Reset Scope Screen — reset all / unit / level
// ==========================================
class MuvvanResetScopeScreen extends StatefulWidget {
  final String jsonPath;
  final String langPrefix;
  const MuvvanResetScopeScreen(
      {super.key, required this.jsonPath, required this.langPrefix});

  @override
  State<MuvvanResetScopeScreen> createState() =>
      _MuvvanResetScopeScreenState();
}

class _MuvvanResetScopeScreenState extends State<MuvvanResetScopeScreen> {
  bool _isLoading = true;
  int _totalMuvvan = 0;
  // unitNumber -> set of uniqueIds with word_status == 'muvvan'
  final Map<int, Set<String>> _unitGreenIds = {};
  // level (1-5) -> set of uniqueIds with word_status == 'muvvan'
  final Map<int, Set<String>> _levelGreenIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    _unitGreenIds.clear();
    _levelGreenIds.clear();

    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = json.decode(response);
    final list = data['words'] as List;
    final allWords = list.map((w) => Word.fromJson(w)).toList();

    final greenIds = ProgressManager().getAllByStatus('muvvan').toSet();
    _totalMuvvan = greenIds.length;

    for (final w in allWords) {
      if (!greenIds.contains(w.uniqueId)) continue;
      _unitGreenIds
          .putIfAbsent(w.unitNumber, () => {})
          .add(w.uniqueId);
    }

    for (int lvl = 1; lvl <= 5; lvl++) {
      try {
        final path = 'assets/levels/${widget.langPrefix}_level_$lvl.json';
        final String levelResponse = await rootBundle.loadString(path);
        final levelData = json.decode(levelResponse);
        final levelList = levelData['words'] as List;
        for (final w in levelList) {
          final word = Word.fromJson(w);
          if (greenIds.contains(word.uniqueId)) {
            _levelGreenIds.putIfAbsent(lvl, () => {}).add(word.uniqueId);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _confirmAndReset({
    required String title,
    required String message,
    Set<String>? uniqueIds,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
            '$message\n\nפעולה זאת מאפסת רק את התרגול החוזר ולא את ההתקדמות שלך במילון.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('אפס')),
        ],
      ),
    );
    if (confirmed != true) return;

    await ProgressManager().resetMuvvanRepeatTracking(uniqueIds: uniqueIds);
    // Refresh in place (instead of leaving the screen) so the counts update
    // immediately — lets the user reset another unit/level right away too.
    if (mounted) setState(() => _isLoading = true);
    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('תרגול חוזר אופס בהצלחה')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sortedUnits = _unitGreenIds.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('אפס תרגול חוזר')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _totalMuvvan == 0
              ? const Center(
                  child: Text('אין עדיין מילים שסימנת כמובנות',
                      style: TextStyle(fontSize: 16, color: Colors.grey)))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    ListTile(
                      tileColor: kEasyGreen.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      leading: const Icon(Icons.restart_alt_rounded,
                          color: kEasyGreen),
                      title: const Text('אפס את כל המילים שהבנת',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('$_totalMuvvan מילים'),
                      onTap: () => _confirmAndReset(
                        title: 'איפוס כל המילים שהבנת',
                        message: 'לאפס את התרגול החוזר לכל $_totalMuvvan המילים שהבנת?',
                      ),
                    ),
                    if (_unitGreenIds.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('אפס יחידה ספציפית:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ...sortedUnits.map((unit) {
                        final ids = _unitGreenIds[unit]!;
                        return ListTile(
                          leading: const Icon(Icons.layers_rounded,
                              color: Colors.grey),
                          title: Text('יחידה $unit'),
                          subtitle: Text('${ids.length} מילים שהבנת'),
                          onTap: () => _confirmAndReset(
                            title: 'איפוס יחידה $unit',
                            message:
                                'לאפס את התרגול החוזר ל-${ids.length} המילים שהבנת ביחידה $unit?',
                            uniqueIds: ids,
                          ),
                        );
                      }),
                    ],
                    if (_levelGreenIds.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text('אפס רמת קושי ספציפית:',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      ...(_levelGreenIds.keys.toList()..sort()).map((lvl) {
                        final ids = _levelGreenIds[lvl]!;
                        final meta = _kLevelMeta[lvl - 1];
                        return ListTile(
                          leading:
                              Icon(Icons.bar_chart_rounded, color: meta.color),
                          title: Text('רמה $lvl — ${meta.label}'),
                          subtitle: Text('${ids.length} מילים שהבנת'),
                          onTap: () => _confirmAndReset(
                            title: 'איפוס רמה $lvl',
                            message:
                                'לאפס את התרגול החוזר ל-${ids.length} המילים שהבנת ברמה $lvl?',
                            uniqueIds: ids,
                          ),
                        );
                      }),
                    ],
                  ],
                ),
    );
  }
}

// ==========================================
// 12. Single Card Screen
// ==========================================
class SingleCardScreen extends StatefulWidget {
  final Word word;
  const SingleCardScreen({super.key, required this.word});

  @override
  State<SingleCardScreen> createState() => _SingleCardScreenState();
}

class _SingleCardScreenState extends State<SingleCardScreen> {
  final _NativeTts flutterTts = _NativeTts();

  Future<void> speak(String text, String language) async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('tts_speed') ?? 0.5;
    await flutterTts.setLanguage(language == 'hebrew' ? 'he-IL' : 'en-US');
    await flutterTts.setSpeechRate(speed);
    await flutterTts.speak(text);
  }

  Future<void> _markAndExit(String action) async {
    await applyWordStatus(widget.word.uniqueId, action);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Spacer(),
            Expanded(
              flex: 4,
              child: Center(
                child: FlipCard(
                  key: ValueKey(widget.word.id),
                  front: _buildSingleCardFace(widget.word, true),
                  back: _buildSingleCardFace(widget.word, false),
                ),
              ),
            ),
            const Spacer(),
            Text("איך הכרת את המילה?",
                style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white60
                        : Colors.black54)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ResponseButton(
                      label: 'לא הבנתי',
                      color: kAgainRed,
                      onTap: () => _markAndExit('lo_hevanti')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResponseButton(
                      label: 'ככה ככה',
                      color: const Color(0xFFFFB800),
                      onTap: () => _markAndExit('kacha_kacha')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ResponseButton(
                      label: 'מובן',
                      color: kEasyGreen,
                      onTap: () => _markAndExit('muvvan')),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleCardFace(Word word, bool isFront) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color unitColor = getUnitColor(word.unitNumber, isDark);
    Color cardColor = isFront
        ? unitColor
        : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5));
    Color textColor = isFront
        ? getTextColorForBackground(word.unitNumber, isDark)
        : (isDark ? Colors.white : Colors.black87);
    Color iconColor = isFront
        ? (textColor == Colors.white ? Colors.white : Colors.blue)
        : Colors.blue;

    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
              isFront
                  ? (word.language == 'english' ? "🇬🇧 אנגלית" : "🇮🇱 עברית")
                  : (word.language == 'hebrew' ? "פירוש" : "תרגום"),
              style: TextStyle(color: textColor.withOpacity(0.6))),
          const SizedBox(height: 20),
          if (isFront) ...[
            Hero(
              tag: word.uniqueId,
              child: Material(
                color: Colors.transparent,
                child: Directionality(
                  textDirection: word.language == 'english'
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  child: Text(word.term,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: textColor)),
                ),
              ),
            ),
            if (word.language == 'english')
              IconButton(
                  icon: Icon(Icons.volume_up, color: iconColor, size: 30),
                  onPressed: () => speak(word.term, word.language)),
          ] else ...[
            Text(word.translation,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue)),
            Padding(
                padding: const EdgeInsets.all(20),
                child: Directionality(
                  textDirection: word.language == 'english'
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  child: Text(word.example,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontStyle: FontStyle.italic,
                          fontSize: 18,
                          color: textColor)),
                )),
          ]
        ],
      ),
    );
  }
}

// ==========================================
// 13. Flip Card
// ==========================================
class FlipCard extends StatefulWidget {
  final Widget front;
  final Widget back;
  const FlipCard({super.key, required this.front, required this.back});

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _animation = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    isFront = !isFront;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * 3.14159;
          final isShowingFront = angle < 3.14159 / 2;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(angle),
            child: isShowingFront
                ? widget.front
                : Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(3.14159),
                    child: widget.back),
          );
        },
      ),
    );
  }
}

// ==========================================
// 14. About Screen
// ==========================================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text("אודות")),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/icon.png',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  )),
              const SizedBox(height: 20),
              const Text("מילומטרי",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text("גרסה 1.1.0", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              const Text(
                  "ברוכים הבאים לאפליקציית מילומטרי!\n\nהאפליקציה נועדה לעזור לכם ללמוד מילים לפסיכומטרי בצורה כיפית וקלה.\nתוכלו לתרגל מילים בעברית ובאנגלית ולעקוב אחרי ההתקדמות שלכם.\n\nפותח על ידי Pappo Studios.\nבהצלחה במבחן!",
                  style: TextStyle(fontSize: 18, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () async {
                  final InAppReview inAppReview = InAppReview.instance;
                  await inAppReview.openStoreListing(appStoreId: kAppStoreId);
                },
                icon: const Icon(Icons.star_rounded, color: Colors.amber),
                label: const Text(
                  "דרגו אותנו ⭐",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
              ),
              const SizedBox(height: 36),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 180,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              const Text("Pappo Studios",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
              const SizedBox(height: 16),
              const Text("© 2026 כל הזכויות שמורות",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 15. Stats Screen
// ==========================================
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isLoading = true;

  // סיכום כללי
  int _totalWords = 0;
  int _studiedWords = 0; // repetitions > 0
  int _masteredWords = 0; // repetitions >= 3
  int _weakWords = 0; // easinessFactor < 2.0 OR (progress!=null && reps==0)

  // לפי שפה
  int _hebrewTotal = 0, _hebrewStudied = 0;
  int _englishTotal = 0, _englishStudied = 0;

  // 7 ימים אחרונים
  List<int> _last7DaysCounts = List.filled(7, 0);

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final allProgress = ProgressManager().getAllProgress();

    // טעינת שתי שפות
    final hebrewData =
        await _loadJson('assets/hebrew_with_difficulty.json', 'hebrew');
    final englishData =
        await _loadJson('assets/english_with_difficulty.json', 'english');
    final allWords = [...hebrewData, ...englishData];

    int total = 0, studied = 0, mastered = 0, weak = 0;
    int hTotal = 0, hStudied = 0, eTotal = 0, eStudied = 0;

    for (final w in allWords) {
      total++;
      final bool isHebrew = w['lang'] == 'hebrew';
      if (isHebrew)
        hTotal++;
      else
        eTotal++;

      final progress = allProgress[w['uniqueId']];
      if (progress == null) continue;

      final int reps = progress['repetitions'] as int;
      final double ef = progress['easinessFactor'] as double;

      if (reps > 0) {
        studied++;
        if (isHebrew)
          hStudied++;
        else
          eStudied++;
      }
      if (reps >= 3) mastered++;

      if ((reps == 0) || (ef < 2.0)) weak++;
    }

    // 7 ימים אחרונים מ-SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final last7 = List.generate(7, (i) {
      final d = DateTime.now().subtract(Duration(days: 6 - i));
      final key =
          'streak_today_${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
      return prefs.getInt(key) ?? 0;
    });

    if (!mounted) return;
    setState(() {
      _totalWords = total;
      _studiedWords = studied;
      _masteredWords = mastered;
      _weakWords = weak;
      _hebrewTotal = hTotal;
      _hebrewStudied = hStudied;
      _englishTotal = eTotal;
      _englishStudied = eStudied;
      _last7DaysCounts = last7;
      _isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _loadJson(String path, String lang) async {
    try {
      final raw = await rootBundle.loadString(path);
      final data = json.decode(raw);
      final list = data['words'] as List;
      return list
          .map((w) => {
                'uniqueId': '${lang}_${w['id']}',
                'term': w['term'] ?? '',
                'translation': w['translation'] ?? '',
                'lang': lang,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int maxDay = _last7DaysCounts.isEmpty
        ? 1
        : (_last7DaysCounts.reduce((a, b) => a > b ? a : b)).clamp(1, 999);
    final List<String> dayLabels = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];

    return Scaffold(
      appBar: AppBar(title: const Text('סטטיסטיקות'), centerTitle: true),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── כרטיסי סיכום ──────────────────────────
                Row(children: [
                  _statCard(
                      isDark, '📖', '$_studiedWords', 'נלמדו', Colors.blue),
                  const SizedBox(width: 10),
                  _statCard(
                      isDark, '⭐', '$_masteredWords', 'הושלמו', Colors.green),
                  const SizedBox(width: 10),
                  _statCard(
                      isDark, '⚠️', '$_weakWords', 'חלשות', Colors.orange),
                ]),

                const SizedBox(height: 20),

                // ── התקדמות לפי שפה ──────────────────────
                _sectionTitle('התקדמות לפי שפה', isDark),
                const SizedBox(height: 10),
                _languageBar(isDark, 'עברית', _hebrewStudied, _hebrewTotal,
                    const Color(0xFF424242)),
                const SizedBox(height: 10),
                _languageBar(isDark, 'אנגלית', _englishStudied, _englishTotal,
                    const Color(0xFF1B5E20)),

                const SizedBox(height: 24),

                // ── 7 ימים אחרונים ────────────────────────
                _sectionTitle('מילים שלמדת — 7 ימים אחרונים', isDark),
                const SizedBox(height: 12),
                _card(
                  isDark,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final count = _last7DaysCounts[i];
                      final heightFrac = count / maxDay;
                      final dayIdx = (DateTime.now()
                              .subtract(Duration(days: 6 - i))
                              .weekday) %
                          7;
                      final isToday = i == 6;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                count > 0 ? '$count' : '',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45),
                              ),
                              const SizedBox(height: 2),
                              Container(
                                height: (60 * heightFrac).clamp(4.0, 60.0),
                                decoration: BoxDecoration(
                                  color: isToday
                                      ? Colors.orange
                                      : (count > 0
                                          ? Colors.blue
                                          : (isDark
                                              ? Colors.white12
                                              : Colors.grey.shade200)),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                dayLabels[dayIdx],
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isToday
                                        ? Colors.orange
                                        : (isDark
                                            ? Colors.white54
                                            : Colors.grey)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
    );
  }

  Widget _statCard(
      bool isDark, String emoji, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45)),
        ]),
      ),
    );
  }

  Widget _languageBar(
      bool isDark, String label, int studied, int total, Color color) {
    final double frac = total > 0 ? studied / total : 0.0;
    return _card(
      isDark,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Text('$studied / $total',
              style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
            color: color,
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 4),
        Text('${(frac * 100).toStringAsFixed(1)}% הושלמו',
            style: TextStyle(
                fontSize: 12, color: isDark ? Colors.white38 : Colors.black38)),
      ]),
    );
  }

  Widget _sectionTitle(String title, bool isDark) => Text(
        title,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white70 : Colors.black87),
      );

  Widget _card(bool isDark, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 3))
                ],
        ),
        child: child,
      );
}

// ==========================================
// 16. Streak Screen
// ==========================================
class StreakScreen extends StatefulWidget {
  const StreakScreen({super.key});
  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  List<bool> _activity = List.filled(7, false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activity = await StreakManager().getLast7DaysActivity();
    if (mounted) setState(() => _activity = activity);
  }

  void _showGoalPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return ValueListenableBuilder<int>(
          valueListenable: StreakManager().dailyGoalNotifier,
          builder: (_, currentGoal, __) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'יעד יומי',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'כמה מילים תרצה ללמוד כל יום?',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [5, 10, 20, 30].map((goal) {
                      final selected = goal == currentGoal;
                      return GestureDetector(
                        onTap: () async {
                          await StreakManager().setDailyGoal(goal);
                          if (mounted) setState(() {});
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 14),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.orange
                                : Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? Colors.orange
                                  : Colors.orange.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '$goal',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: selected
                                      ? Colors.white
                                      : Colors.orange.shade700,
                                ),
                              ),
                              Text(
                                'מילים',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected
                                      ? Colors.white70
                                      : Colors.orange.shade400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final streak = StreakManager().currentStreak.value;
    final longest = StreakManager().longestStreak;

    final List<String> dayLabels = ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳'];
    final today = DateTime.now().weekday % 7; // 0=Sun

    return Scaffold(
      appBar: AppBar(title: const Text('הרצף שלי'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // כרטיס רצף ראשי
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6F00), Color(0xFFFF8F00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: Column(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 8),
                Text(
                  '$streak',
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'ימי רצף',
                  style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // שורת סטטיסטיקות
          Row(
            children: [
              Expanded(
                  child: _statCard(
                isDark: isDark,
                icon: Icons.emoji_events_rounded,
                iconColor: Colors.amber,
                label: 'שיא אישי',
                value: '$longest ימים',
              )),
              const SizedBox(width: 14),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: StreakManager().todayWordsNotifier,
                  builder: (_, todayWords, __) =>
                      _goalCard(isDark: isDark, todayWords: todayWords),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 7 ימים אחרונים
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '7 הימים האחרונים',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    final active = _activity[i];
                    final dayIndex = (DateTime.now()
                            .subtract(Duration(days: 6 - i))
                            .weekday) %
                        7;
                    final isToday = i == 6;
                    return Column(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active
                                ? Colors.orange
                                : (isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200),
                            border: isToday
                                ? Border.all(color: Colors.orange, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: active
                                ? const Text('🔥',
                                    style: TextStyle(fontSize: 16))
                                : Icon(Icons.circle,
                                    size: 8,
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey.shade400),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dayLabels[dayIndex],
                          style: TextStyle(
                              fontSize: 12,
                              color: isToday
                                  ? Colors.orange
                                  : (isDark ? Colors.white54 : Colors.grey)),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // הודעת עידוד
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.06)
                  : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Text('💪', style: TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    streak == 0
                        ? 'התחל ללמוד היום כדי לפתוח רצף!'
                        : streak < 3
                            ? 'כל מסע מתחיל בצעד אחד. המשך כך!'
                            : streak < 7
                                ? 'רצף של $streak ימים — אתה בדרך הנכונה!'
                                : 'מדהים! $streak ימים ברצף — אתה מכור ללמידה!',
                    style: TextStyle(
                        fontSize: 14,
                        color:
                            isDark ? Colors.white70 : Colors.orange.shade800),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // כפתור סטטיסטיקות מלאות
          AnimatedButton(
            onTap: () =>
                Navigator.push(context, _slideRoute(const StatsScreen())),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: Colors.blue.withOpacity(0.3), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart_rounded,
                      color: Colors.blue.shade400, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'ראה סטטיסטיקות מלאות',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade400),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(height: 8),
          Text(value,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: isDark ? Colors.white54 : Colors.grey)),
        ],
      ),
    );
  }

  Widget _goalCard({required bool isDark, required int todayWords}) {
    return ValueListenableBuilder<int>(
      valueListenable: StreakManager().dailyGoalNotifier,
      builder: (_, goal, __) {
        final progress = (todayWords / goal).clamp(0.0, 1.0);
        final done = todayWords >= goal;
        return GestureDetector(
          onTap: () => _showGoalPicker(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            backgroundColor: isDark
                                ? Colors.white12
                                : Colors.orange.shade100,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                done ? Colors.green : Colors.orange),
                          ),
                          if (done)
                            const Center(
                              child: Icon(Icons.check,
                                  size: 14, color: Colors.green),
                            ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.edit_rounded,
                        size: 14,
                        color: isDark ? Colors.white38 : Colors.grey.shade400),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '$todayWords/$goal',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
                Text(
                  'יעד יומי',
                  style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// 16. Settings Screen
// ==========================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double ttsSpeed = 0.5;
  String _currentDetermination = "";
  bool _notificationsEnabled = true;
  final String _email = "pappostudios@gmail.com";

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int hours = prefs.getInt('determination_hours') ?? 24;
    String determinationText;
    switch (hours) {
      case 8:
        determinationText = "🏆 רואה את הניצחון (כל 8 שעות)";
        break;
      case 12:
        determinationText = "🔥 מתקדם (כל 12 שעות)";
        break;
      default:
        determinationText = "😎 ברגוע (כל 24 שעות)";
    }
    setState(() {
      ttsSpeed = prefs.getDouble('tts_speed') ?? 0.5;
      _currentDetermination = determinationText;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
    if (!enabled) {
      await NotificationManager().cancelNotifications();
    }
    setState(() => _notificationsEnabled = enabled);
  }

  Future<void> _updateSpeed(double newSpeed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_speed', newSpeed);
    setState(() => ttsSpeed = newSpeed);
  }

  void _showContactOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.email_outlined, color: Colors.blue),
                title: const Text("שלח אימייל"),
                onTap: () {
                  Navigator.pop(context);
                  _launchEmail();
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.camera_alt_outlined, color: Colors.purple),
                title: const Text("הודעה באינסטגרם"),
                onTap: () {
                  Navigator.pop(context);
                  _launchInstagram();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _launchEmail() async {
    final Uri emailLaunchUri = Uri(
      scheme: 'mailto',
      path: _email,
      query: 'subject=פניה בנושא אפליקציית מילומטרי',
    );
    if (!await launchUrl(emailLaunchUri)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("לא הצלחנו לפתוח את אפליקציית המייל")),
      );
    }
  }

  Future<void> _launchInstagram() async {
    const String username = "pappo_studios";
    final Uri nativeUrl = Uri.parse("instagram://user?username=$username");
    final Uri webUrl = Uri.parse("https://www.instagram.com/$username");
    try {
      if (!await launchUrl(nativeUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch native app');
      }
    } catch (e) {
      if (!await launchUrl(webUrl, mode: LaunchMode.externalApplication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("לא הצלחנו לפתוח את האינסטגרם")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text("הגדרות")),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader("מעקב והתקדמות"),
          ListTile(
            leading: const Icon(Icons.bar_chart_rounded, color: Colors.blue),
            title: const Text("סטטיסטיקות"),
            subtitle: const Text("מילים נלמדו, חלשות, התקדמות"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () =>
                Navigator.push(context, _slideRoute(const StatsScreen())),
          ),
          ListTile(
            leading:
                const Icon(Icons.local_fire_department, color: Colors.orange),
            title: const Text("רצף"),
            subtitle: const Text("הרצף היומי והשיא שלך"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () =>
                Navigator.push(context, _slideRoute(const StreakScreen())),
          ),
          const Divider(),
          _buildSectionHeader("כללי"),
          SwitchListTile(
            title: const Text("מצב לילה"),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (val) => ThemeManager().toggleTheme(),
          ),
          const Divider(),
          _buildSectionHeader("הגדרות התראה"),
          SwitchListTile(
            secondary: Icon(
              _notificationsEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              color: _notificationsEnabled ? Colors.orange : Colors.grey,
            ),
            title: const Text("ללא התראות"),
            subtitle: const Text("השבתת תזכורות הלימוד"),
            value: !_notificationsEnabled,
            onChanged: (val) => _setNotificationsEnabled(!val),
          ),
          ListTile(
            enabled: _notificationsEnabled,
            leading: const Icon(Icons.psychology, color: Colors.orange),
            title: const Text("הגדרת רמת נחישות"),
            subtitle: Text(_currentDetermination),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              await Navigator.push(
                  context, _slideRoute(const DeterminationScreen()));
              _loadSettings();
            },
          ),
          const Divider(),
          _buildSectionHeader("הקראת מילים (אנגלית)"),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text("מהירות דיבור"),
            subtitle: Slider(
              value: ttsSpeed,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: ttsSpeed.toString(),
              onChanged: (val) => _updateSpeed(val),
            ),
            trailing: Text("${(ttsSpeed * 100).toInt()}%"),
          ),
          const Divider(),
          _buildSectionHeader("צרו קשר"),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
            title: const Text("דברו איתי"),
            subtitle: const Text("דיווח על תקלות, הצעות או סתם דיבור"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showContactOptions,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined, color: Colors.grey),
            title: const Text("תנאי שימוש ופרטיות"),
            subtitle: const Text("קראו את התנאים המלאים"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => launchUrl(
              Uri.parse(
                  'https://docs.google.com/document/d/1DLOkIcNFniOLqtGhn-IgsLBikPmWuRKIB7f-ClBuWhw/edit?usp=sharing'),
              mode: LaunchMode.externalApplication,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.coffee_rounded, color: Color(0xFFFFDD00)),
            title: const Text("קנה לי קפה ☕"),
            subtitle: const Text("תומכ/ת בפיתוח האפליקציה"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => launchUrl(
                Uri.parse('https://buymeacoffee.com/pappostudios'),
                mode: LaunchMode.externalApplication),
          ),
          const Divider(),
          _buildSectionHeader("ניהול נתונים"),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text("איפוס התקדמות מלא",
                style: TextStyle(color: Colors.red)),
            subtitle: const Text("מוחק את כל המילים שלמדת"),
            onTap: () {
              showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        title: const Text("בטוח שרוצים לאפס?"),
                        content: const Text(
                            "פעולה זו תמחק את כל הזיכרון ולא ניתן לשחזר אותה."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("ביטול")),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                ProgressManager().resetAll();
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text("הנתונים אופסו בהצלחה")));
                              },
                              child: const Text("אפס הכל",
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("אודות האפליקציה"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () =>
                Navigator.push(context, _slideRoute(const AboutScreen())),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
      child: Text(title,
          style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ==========================================
// 16. Terms Of Service Screen
// ==========================================
class TermsOfServiceScreen extends StatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  State<TermsOfServiceScreen> createState() => _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends State<TermsOfServiceScreen> {
  bool _isChecked = false;
  final ScrollController _scrollController = ScrollController();

  Future<void> _acceptTerms() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accepted_terms_version', currentTermsVersion);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      _slideRoute(const DeterminationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('תנאי שימוש ופרטיות'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: const Text(
                      '''
מדיניות פרטיות ותנאי שימוש – אפליקציית מילומטרי

עדכון אחרון: 19/06/2026

1.	כללי:

a.	ברוכים הבאים לאפליקציית "מילומטרי", אשר פותחה על ידי Pappo" Studios"" הורדה ושימוש באפליקציה מהווים הסכמה מלאה ומחייבת לתנאים המפורטים במסמך זה.

2.	מהות השירות:

a.	האפליקציה נועדה לשמש ככלי עזר לתרגול, לימוד ושיפור אוצר המילים לקראת הבחינה הפסיכומטרית.

b.	השימוש באפליקציה הוא באחריות המשתמש בלבד.

c.	המפתח מבהיר כי השימוש באפליקציה אינו מבטיח קבלת ציון מסוים בבחינה ואינו מהווה תחליף לקורס פסיכומטרי מלא או לחומרים הרשמיים של המרכז הארצי לבחינות והערכה.

3.	קניין רוחני:

a.	כל זכויות הקניין הרוחני באפליקציה, לרבות העיצוב הגרפי, קוד המקור, הלוגו, בסיסי הנתונים והתכנים, הינם קניינו הבלעדי של המפתח (Pappo Studios).

b.	אין להעתיק, לשכפל, להפיץ, לשווק או לעשות כל שימוש מסחרי בחלקים מהאפליקציה או בעיצובה ללא קבלת אישור מפורש ובכתב מהמפתח.

4.	מדיניות פרטיות ואיסוף נתונים:

אנו ב-Pappo Studios  מכבדים את פרטיותך.

a.	איסוף נתונים אישיים: האפליקציה אינה אוספת מידע אישי מזהה (כגון שם, טלפון או מייל) באופן יזום ואינה מעבירה נתונים כאלו לשרתים שלנו.

b.	אחסון מידע: נתוני ההתקדמות של המשתמש נשמרים באופן מקומי (Locally) על גבי מכשיר המשתמש. מחיקת האפליקציה תוביל למחיקת נתוני ההתקדמות.

5.	פרסומות:

a.	האפליקציה נכון להיום(תאריך עדכון המסמך) לא מציגה פרסומות. בקריאה ואישור של מסמך זה - הינך(המשתמש) מסכים לכך שבעתיד ייתכן וכי בזמן שימושך באפליקציה יופיעו פרסומות המוגשות ע"י צד שלישי.

b.	ספקים אלו עשויים להשתמש במידע אנונימי, מזהי מכשיר (Device ID) או טכנולוגיות מעקב כגון "Cookies" על מנת להציג פרסומות המותאמות לתחומי העניין של המשתמש ולשפר את חווית השימוש. השימוש במידע זה כפוף למדיניות הפרטיות של אותם ספקי פרסום.

6.	תמחור ושינויים עתידיים:

a.	שינוי מודל התמחור: המפתח שומר לעצמו את הזכות הבלעדית לשנות את מודל התמחור של האפליקציה בכל עת.(המשתמש לא יחויב בהוצאות כאלה ואחרות ללא הסכמתו האישית).

b.	העדר התחייבות למחיר: המשתמש מאשר כי ידוע לו שהאפליקציה עשויה להפוך לבת-תשלום בעתיד, או כי פיצ'רים מסוימים שכרגע ניתנים בחינם עשויים לדרוש תשלום בגרסאות הבאות. אין בהורדת האפליקציה שום התחייבות של המפתח למחיר קבוע או לחינמיות השירות לצמיתות.

7.	הגבלת אחריות:

a.	היוצר ו/או המפתח אינו אחראי לכל נזק, ישיר או עקיף, שייגרם למשתמש או לצד שלישי כלשהו כתוצאה משימוש באפליקציה, חוסר יכולת להשתמש בה, תקלות טכניות, או הסתמכות על התכנים המופיעים בה. השירות מסופק במתכונת "As Is".

8.	רמות קושי:

a.	רמות הקושי המוצגות באפליקציה (בסיסי, בינוני, גבוה, מתקדם, קיצוני) מהוות הערכה כללית בלבד, המבוססת על תדירות שימוש, מורכבות לשונית ואופי הבחינה הפסיכומטרית.

b.	הסיווג הוא ממוצעי ומתאים לרוב האוכלוסייה, אולם אינו אבסולוטי: מילה המסווגת כ"קשה" עשויה להיות מוכרת היטב לחלק מהמשתמשים, ומילה המסווגת כ"קלה" עשויה להיות לא מוכרת לאחרים.

c.	המפתח אינו אחראי לאי-התאמה בין רמת הקושי המוצגת באפליקציה לבין רמת הקושי הסובייקטיבית של המשתמש.

9.	יצירת קשר:

a.	בכל שאלה, בקשה או דיווח על תקלה בנוגע לאפליקציה או למדיניות הפרטיות, ניתן לפנות אלינו בכתובת המייל [pappostudios@gmail.com].
                      ''',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.right,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            CheckboxListTile(
              title: const Text("קראתי ואני מסכים לתנאי השימוש"),
              value: _isChecked,
              onChanged: (bool? value) {
                setState(() => _isChecked = value ?? false);
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 10),
            AnimatedButton(
              onTap: _isChecked ? _acceptTerms : () {},
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: _isChecked
                      ? const LinearGradient(
                          colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                        )
                      : null,
                  color: _isChecked ? null : Colors.grey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Text(
                    'המשך לאפליקציה',
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
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

// ==========================================
// 17. Determination Screen
// ==========================================
class DeterminationScreen extends StatelessWidget {
  const DeterminationScreen({super.key});

  Future<void> _setDetermination(BuildContext context, int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('determination_hours', hours);
    await prefs.setBool('hasChosenDetermination', true);
    // Choosing a determination level implies the user wants reminders.
    await prefs.setBool('notifications_enabled', true);
    if (!context.mounted) return;
    Navigator.pushReplacement(context, _slideRoute(const InstructionsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child:
                    const Icon(Icons.psychology, size: 60, color: Colors.white),
              ),
              const SizedBox(height: 30),
              const Text(
                "כמה אתה נחוש?",
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "בחר באיזו תדירות נזכיר לך ללמוד\nאם לא נכנסת לאפליקציה",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 50),
              _buildOption(context, "🏆 רואה את הניצחון", "כל 8 שעות", 8,
                  [Colors.redAccent, Colors.red.shade800]),
              const SizedBox(height: 16),
              _buildOption(context, "🔥 מתקדם", "כל 12 שעות", 12,
                  [Colors.orange, Colors.deepOrange]),
              const SizedBox(height: 16),
              _buildOption(context, "😎 ברגוע", "כל 24 שעות", 24,
                  [Colors.green, Colors.green.shade800]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOption(BuildContext context, String title, String subtitle,
      int hours, List<Color> colors) {
    return AnimatedButton(
      onTap: () => _setDetermination(context, hours),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colors.last.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.25),
              child: Text("$hours",
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(fontSize: 14, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 18. Failed Words Selector Screen
// ==========================================
class FailedWordsSelectorScreen extends StatefulWidget {
  final String jsonPath;
  const FailedWordsSelectorScreen({super.key, required this.jsonPath});

  @override
  State<FailedWordsSelectorScreen> createState() =>
      _FailedWordsSelectorScreenState();
}

class _FailedWordsSelectorScreenState extends State<FailedWordsSelectorScreen> {
  Map<int, int> failedCountsPerUnit = {};
  int totalFailed = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = await json.decode(response);
    var list = data["words"] as List;
    List<Word> allWords = list.map((w) => Word.fromJson(w)).toList();

    Map<int, int> tempCounts = {};
    int tempTotal = 0;

    for (var w in allWords) {
      var progress = ProgressManager().getWordProgress(w.uniqueId);
      if (progress != null && progress['repetitions'] == 0) {
        tempCounts[w.unitNumber] = (tempCounts[w.unitNumber] ?? 0) + 1;
        tempTotal++;
      }
    }

    if (!mounted) return;
    setState(() {
      failedCountsPerUnit = tempCounts;
      totalFailed = tempTotal;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    var sortedUnits = failedCountsPerUnit.keys.toList()..sort();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("בחירת תרגול")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // ── Shuffle all ───────────────────────────────────────
                AnimatedButton(
                  onTap: () {
                    Navigator.pushReplacement(
                        context,
                        _slideRoute(LearningScreen(
                            jsonPath: widget.jsonPath, onlyFailed: true)));
                  },
                  child: Container(
                    margin:
                        const EdgeInsets.only(bottom: 14, left: 5, right: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade300, Colors.red.shade700],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shuffle,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("תרגל הכל (ערבוב)",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                              Text("כל $totalFailed המילים מכל היחידות",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios,
                            size: 16, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                // ── By difficulty ─────────────────────────────────────
                AnimatedButton(
                  onTap: () {
                    final prefix =
                        widget.jsonPath.contains('hebrew') ? 'heb' : 'eng';
                    Navigator.push(
                        context,
                        _slideRoute(
                            FailedLevelSelectorScreen(langPrefix: prefix)));
                  },
                  child: Container(
                    margin:
                        const EdgeInsets.only(bottom: 25, left: 5, right: 5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF7A3DFD), Color(0xFF3D8BFD)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF7A3DFD).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        )
                      ],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bar_chart_rounded,
                            color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("תרגל לפי רמת קושי",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                              Text("5 רמות — רק המילים שלא הכרת",
                                  style: TextStyle(
                                      color: Colors.white70, fontSize: 13)),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            size: 16, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
                const Text("בחר יחידה ספציפית:",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                ...sortedUnits.map((unitNum) {
                  int count = failedCountsPerUnit[unitNum]!;
                  Color unitColor = getUnitColor(unitNum, isDark);
                  Color textColor = getTextColorForBackground(unitNum, isDark);

                  return AnimatedButton(
                    onTap: () {
                      Navigator.pushReplacement(
                          context,
                          _slideRoute(LearningScreen(
                              jsonPath: widget.jsonPath,
                              onlyFailed: true,
                              unitFilter: unitNum)));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: unitColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: unitColor.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("יחידה $unitNum",
                                    style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text("יש לך $count מילים לשנן ביחידה זו",
                                    style: TextStyle(
                                        color: textColor.withOpacity(0.8),
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              color: textColor, size: 16),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ],
            ),
    );
  }
}

// ==========================================
// 18b. Failed Level Selector Screen
// ==========================================
class FailedLevelSelectorScreen extends StatefulWidget {
  final String langPrefix; // 'heb' or 'eng'
  const FailedLevelSelectorScreen({super.key, required this.langPrefix});

  @override
  State<FailedLevelSelectorScreen> createState() =>
      _FailedLevelSelectorScreenState();
}

class _FailedLevelSelectorScreenState extends State<FailedLevelSelectorScreen> {
  final List<int> _failedCounts = List.filled(5, 0);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    for (int lvl = 1; lvl <= 5; lvl++) {
      try {
        final path = 'assets/levels/${widget.langPrefix}_level_$lvl.json';
        final String response = await rootBundle.loadString(path);
        final data = json.decode(response);
        final list = data['words'] as List;
        int count = 0;
        for (final w in list) {
          final word = Word.fromJson(w);
          final progress = ProgressManager().getWordProgress(word.uniqueId);
          if (progress != null && (progress['repetitions'] ?? 0) == 0) {
            count++;
          }
        }
        _failedCounts[lvl - 1] = count;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('תרגול לפי רמת קושי — לא הכרתי')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: 5,
              itemBuilder: (context, index) {
                final lvl = index + 1;
                final meta = _kLevelMeta[index];
                final failedCount = _failedCounts[index];
                final path =
                    'assets/levels/${widget.langPrefix}_level_$lvl.json';

                return AnimatedButton(
                  onTap: failedCount == 0
                      ? () {}
                      : () {
                          Navigator.push(
                              context,
                              _slideRoute(LearningScreen(
                                  jsonPath: path, onlyFailed: true)));
                        },
                  child: Opacity(
                    opacity: failedCount == 0 ? 0.45 : 1.0,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [meta.color, meta.shadow],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: meta.shadow.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text('$lvl',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18)),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(meta.label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text(
                                    failedCount == 0
                                        ? 'אין מילים לחזרה ✓'
                                        : '$failedCount מילים לחיזוק',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ==========================================
// 18c. Kacha Kacha Practice Selector Screen
// ==========================================
class KachaKachaSelectorScreen extends StatefulWidget {
  final String jsonPath;
  const KachaKachaSelectorScreen({super.key, required this.jsonPath});

  @override
  State<KachaKachaSelectorScreen> createState() =>
      _KachaKachaSelectorScreenState();
}

class _KachaKachaSelectorScreenState extends State<KachaKachaSelectorScreen> {
  Map<int, int> _countsPerUnit = {};
  int _totalCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final String response = await rootBundle.loadString(widget.jsonPath);
    final data = json.decode(response);
    final list = data['words'] as List;
    final allWords = list.map((w) => Word.fromJson(w)).toList();

    Map<int, int> tempCounts = {};
    int tempTotal = 0;

    for (var w in allWords) {
      final progress = ProgressManager().getWordProgress(w.uniqueId);
      final status = progress != null ? (progress['word_status'] ?? '') : '';
      if (status == 'kacha_kacha') {
        tempCounts[w.unitNumber] = (tempCounts[w.unitNumber] ?? 0) + 1;
        tempTotal++;
      }
    }

    if (!mounted) return;
    setState(() {
      _countsPerUnit = tempCounts;
      _totalCount = tempTotal;
      _isLoading = false;
    });
  }

  Widget _modeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14, left: 5, right: 5),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB800), Color(0xFFE57300)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB800).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 6),
            )
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 16, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedUnits = _countsPerUnit.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(title: const Text('תרגול — ככה ככה')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _modeButton(
                  icon: Icons.shuffle,
                  title: 'תרגל הכל (ערבוב)',
                  subtitle: 'כל $_totalCount המילים שהיו ככה ככה',
                  onTap: () => Navigator.pushReplacement(
                      context,
                      _slideRoute(LearningScreen(
                          jsonPath: widget.jsonPath, onlyKachaKacha: true))),
                ),
                const Text('בחר יחידה ספציפית:',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                ...sortedUnits.map((unitNum) {
                  final count = _countsPerUnit[unitNum]!;
                  final unitColor = getUnitColor(unitNum, isDark);
                  final textColor = getTextColorForBackground(unitNum, isDark);

                  return AnimatedButton(
                    onTap: () => Navigator.pushReplacement(
                        context,
                        _slideRoute(LearningScreen(
                            jsonPath: widget.jsonPath,
                            onlyKachaKacha: true,
                            unitFilter: unitNum))),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: unitColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: unitColor.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('יחידה $unitNum',
                                    style: TextStyle(
                                        color: textColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text('יש לך $count מילים ככה ככה ביחידה זו',
                                    style: TextStyle(
                                        color: textColor.withValues(alpha: 0.8),
                                        fontSize: 13)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios,
                              color: textColor, size: 16),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

// ==========================================
// Instructions Screen
// ==========================================
class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  Future<void> _markSeen(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shown_practice_instructions', true);
    if (!context.mounted) return;
    Navigator.pushReplacement(context, _slideRoute(const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF4F6FB);
    final cardBg = isDark ? const Color(0xFF1E2232) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('איך משתמשים?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      Text(
                        'בזמן תרגול מילים תראה שלושה כפתורים.\nהנה מה שכל אחד עושה:',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15,
                            color: isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(height: 28),
                      _instructionCard(
                        cardBg: cardBg,
                        borderColor: kAgainRed,
                        label: 'לא הבנתי',
                        labelColor: kAgainRed,
                        icon: Icons.close_rounded,
                        iconColor: kAgainRed,
                        description:
                            'לא הכרת את המילה. היא תעבור לרשימת "חזרה על מילים שלא הכרת" כדי שתתרגל אותה שוב.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 14),
                      _instructionCard(
                        cardBg: cardBg,
                        borderColor: const Color(0xFFFFB800),
                        label: 'ככה ככה',
                        labelColor: const Color(0xFFB87800),
                        icon: Icons.thumbs_up_down_rounded,
                        iconColor: const Color(0xFFFFB800),
                        description:
                            'הכרת את המילה בערך. היא תישמר ברשימת "תרגול ככה ככה" לחזרה קצרה.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 14),
                      _instructionCard(
                        cardBg: cardBg,
                        borderColor: kEasyGreen,
                        label: 'מובן',
                        labelColor: kEasyGreen,
                        icon: Icons.check_rounded,
                        iconColor: kEasyGreen,
                        description:
                            'ידעת את המילה היטב. היא תסומן כ"הושלמה" ותופיע ברשימת מילים שהבנת.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 28),
                      const Divider(),
                      const SizedBox(height: 16),
                      Text(
                        'תרגול לפי יחידה מול תרגול לפי רמת קושי',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : kDarkButton),
                      ),
                      const SizedBox(height: 12),
                      _instructionCard(
                        cardBg: cardBg,
                        borderColor: kBluePrimary,
                        label: 'מה ההבדל?',
                        labelColor: kBluePrimary,
                        icon: Icons.compare_arrows_rounded,
                        iconColor: kBluePrimary,
                        description:
                            'בשני התרגולים מופיעות אותן המילים — ההבדל הוא רק בדרך התרגול: לפי רמת קושי, או תרגול חופשי בלי להתייחס לרמה. שימו לב שהיחידות אינן מסודרות לפי רמת קושי, והסדר שלהן שרירותי וחסר משמעות.',
                        isDark: isDark,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedButton(
                onTap: () => _markSeen(context),
                child: Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    color: kDarkButton,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                          color: kDarkShadow,
                          offset: Offset(0, 4),
                          blurRadius: 0)
                    ],
                  ),
                  child: const Center(
                    child: Text('הבנתי, בואו נתחיל!',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _instructionCard({
    required Color cardBg,
    required Color borderColor,
    required String label,
    required Color labelColor,
    required IconData icon,
    required Color iconColor,
    required String description,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: borderColor.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: labelColor)),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
