import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

// ==========================================
// הגדרות גלובליות
// ==========================================
const int currentTermsVersion = 2;

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
// GRADIENT BUTTON
// ==========================================
class GradientButton extends StatelessWidget {
  final String text;
  final List<Color> colors;
  final VoidCallback onTap;
  final double height;
  final double fontSize;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.text,
    required this.colors,
    required this.onTap,
    this.height = 70,
    this.fontSize = 24,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: colors.last.withOpacity(0.5),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 10),
            ],
            Text(
              text,
              style: TextStyle(
                color: Colors.white,
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                shadows: const [
                  Shadow(
                    color: Colors.black26,
                    offset: Offset(1, 1),
                    blurRadius: 3,
                  )
                ],
              ),
            ),
          ],
        ),
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
Color getUnitColor(int unit, bool isDark) {
  if (isDark) {
    switch (unit) {
      case 1: return const Color(0xFF006064);
      case 2: return const Color(0xFF00838F);
      case 3: return const Color(0xFF0097A7);
      case 4: return const Color(0xFF00ACC1);
      case 5: return const Color(0xFF00BCD4);
      case 6: return const Color(0xFFF57F17);
      case 7: return const Color(0xFFE65100);
      case 8: return const Color(0xFFBF360C);
      case 9: return const Color(0xFF3E2723);
      case 10: return const Color(0xFFB71C1C);
      default: return const Color(0xFF424242);
    }
  } else {
    switch (unit) {
      case 1: return const Color(0xFFE0F7FA);
      case 2: return const Color(0xFFB2EBF2);
      case 3: return const Color(0xFF80DEEA);
      case 4: return const Color(0xFF4DD0E1);
      case 5: return const Color(0xFF26C6DA);
      case 6: return const Color(0xFFFFD54F);
      case 7: return const Color(0xFFFFB74D);
      case 8: return const Color(0xFFFF8A65);
      case 9: return const Color(0xFFF4511E);
      case 10: return const Color(0xFFB71C1C);
      default: return Colors.white;
    }
  }
}

Color getTextColorForBackground(int unit, bool isDark) {
  if (isDark) return Colors.white;
  if (unit >= 9) return Colors.white;
  return Colors.black87;
}

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
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
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
    List<String> rawData = _prefs?.getStringList('userprogress') ?? [];
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
              DateTime.fromMillisecondsSinceEpoch(int.parse(parts[4]))
        };
      } else if (parts.length == 3) {
        int lvl = int.parse(parts[1]);
        if (lvl > 0) {
          _cache[id] = {
            'repetitions': lvl,
            'interval': 1,
            'easinessFactor': 2.5,
            'nextReview': DateTime.now()
          };
        }
      }
    }
  }

  Map<String, dynamic>? getWordProgress(String uniqueId) {
    return _cache[uniqueId];
  }

  Future<void> updateWord(String uniqueId, int reps, int interval, double ef,
      DateTime nextReview) async {
    _cache[uniqueId] = {
      'repetitions': reps,
      'interval': interval,
      'easinessFactor': ef,
      'nextReview': nextReview
    };
    await _saveToDisk();
  }

  Future<void> resetWord(String uniqueId) async {
    _cache.remove(uniqueId);
    await _saveToDisk();
  }

  Future<void> _saveToDisk() async {
    List<String> exportList = [];
    _cache.forEach((key, value) {
      int n = value['repetitions'];
      int i = value['interval'];
      double ef = value['easinessFactor'];
      int time = (value['nextReview'] as DateTime).millisecondsSinceEpoch;
      exportList.add("$key:$n:$i:$ef:$time");
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
    );
  }

  String get uniqueId => "${language}_$id";
}

// ==========================================
// 6. Main Entry Point
// ==========================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeManager().init();
  await ProgressManager().init();
  await NotificationManager().init();

  final prefs = await SharedPreferences.getInstance();
  final int userAcceptedVersion = prefs.getInt('accepted_terms_version') ?? 0;
  final bool hasChosenDetermination =
      prefs.getBool('hasChosenDetermination') ?? false;

  Widget firstScreen;
  if (userAcceptedVersion != currentTermsVersion) {
    firstScreen = const TermsOfServiceScreen();
  } else if (!hasChosenDetermination) {
    firstScreen = const DeterminationScreen();
  } else {
    firstScreen = const HomeScreen();
  }

  runApp(PsychoApp(startScreen: firstScreen));
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
      Navigator.pushReplacement(
          context, _slideRoute(const HomeScreen()));
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
// 8. Home Screen
// ==========================================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _buttonsController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _hebrewSlide;
  late Animation<Offset> _englishSlide;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationManager().cancelNotifications();

    // אנימציית לוגו
    _logoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

    // אנימציית כפתורים
    _buttonsController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _hebrewSlide =
        Tween<Offset>(begin: const Offset(-1.5, 0), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _buttonsController, curve: Curves.easeOutCubic));
    _englishSlide =
        Tween<Offset>(begin: const Offset(1.5, 0), end: Offset.zero).animate(
            CurvedAnimation(
                parent: _buttonsController, curve: Curves.easeOutCubic));

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final prefs = await SharedPreferences.getInstance();
    final int hours = prefs.getInt('determination_hours') ?? 24;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await NotificationManager().scheduleInactivityNotification(hours);
    } else if (state == AppLifecycleState.resumed) {
      await NotificationManager().cancelNotifications();
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Stack(
          children: [
            // רקע עם עיגולים דקורטיביים
            Positioned(
              top: -60,
              right: -60,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.blue.withOpacity(isDark ? 0.08 : 0.12),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.purple.withOpacity(isDark ? 0.06 : 0.08),
                ),
              ),
            ),

            // כפתור הגדרות
            Positioned(
              top: 10,
              left: 10,
              child: AnimatedButton(
                onTap: () => Navigator.push(
                    context, _slideRoute(const SettingsScreen())),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.08)
                        : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Icon(Icons.settings_rounded,
                      color: isDark ? Colors.white70 : Colors.grey[700],
                      size: 26),
                ),
              ),
            ),

            // תוכן מרכזי
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 2),

                  // לוגו עם אנימציה
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        height: 140,
                        width: 140,
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
                              blurRadius: 30,
                              offset: const Offset(0, 12),
                            )
                          ],
                        ),
                        child: const Icon(Icons.school_rounded,
                            size: 75, color: Colors.white),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  FadeTransition(
                    opacity: _logoFade,
                    child: ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF7B1FA2)],
                      ).createShader(bounds),
                      child: const Text(
                        "מילומטרי",
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  const Text(
                    "מילים לפסיכומטרי",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),

                  const Spacer(flex: 2),

                  // כפתור עברית עם אנימציית כניסה
                  SlideTransition(
                    position: _hebrewSlide,
                    child: GradientButton(
                      text: "עברית",
                      icon: Icons.translate_rounded,
                      colors: isDark
                          ? [const Color(0xFF37474F), const Color(0xFF263238)]
                          : [const Color(0xFF424242), const Color(0xFF212121)],
                      onTap: () => Navigator.push(
                        context,
                        _slideRoute(const UnitSelectorScreen(
                            jsonPath: 'assets/hebrew.json',
                            title: 'עברית')),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // כפתור אנגלית עם אנימציית כניסה
                  SlideTransition(
                    position: _englishSlide,
                    child: GradientButton(
                      text: "אנגלית",
                      icon: Icons.language_rounded,
                      colors: isDark
                          ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                          : [const Color(0xFF00C853), const Color(0xFF1B5E20)],
                      onTap: () => Navigator.push(
                        context,
                        _slideRoute(const UnitSelectorScreen(
                            jsonPath: 'assets/english.json',
                            title: 'אנגלית')),
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),
                ],
              ),
            ),
          ],
        ),
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
  Map<int, List<Word>> units = {};
  Map<int, int> learnedCounts = {};
  bool isLoading = true;
  int totalFailedCount = 0;

  @override
  void initState() {
    super.initState();
    loadAndOrganizeData();
  }

  Future<void> loadAndOrganizeData() async {
    try {
      final String response = await rootBundle.loadString(widget.jsonPath);
      final data = await json.decode(response);
      var list = data["words"] as List;
      List<Word> allWords = list.map((w) => Word.fromJson(w)).toList();

      Map<int, List<Word>> tempUnits = {};
      Map<int, int> tempCounts = {};
      int failedCounter = 0;

      for (var word in allWords) {
        int u = word.unitNumber;
        if (u == 0) continue;
        if (!tempUnits.containsKey(u)) {
          tempUnits[u] = [];
          tempCounts[u] = 0;
        }
        tempUnits[u]!.add(word);
        var progress = ProgressManager().getWordProgress(word.uniqueId);
        if (progress != null) {
          int reps = progress['repetitions'] ?? 0;
          if (reps > 0) tempCounts[u] = tempCounts[u]! + 1;
          if (reps == 0) failedCounter++;
        }
      }

      if (!mounted) return;
      setState(() {
        units = tempUnits;
        learnedCounts = tempCounts;
        totalFailedCount = failedCounter;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var sortedKeys = units.keys.toList()..sort();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: Text("בחר יחידה - ${widget.title}")),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (totalFailedCount > 0) ...[
                  AnimatedButton(
                    onTap: () async {
                      await Navigator.push(
                          context,
                          _slideRoute(FailedWordsSelectorScreen(
                              jsonPath: widget.jsonPath)));
                      loadAndOrganizeData();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 20, left: 5, right: 5),
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
                            color: Colors.red.withOpacity(0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.refresh_rounded,
                              size: 32, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("חזרה על מילים שלא הכרת",
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                        color: Colors.white)),
                                Text("יש לך $totalFailedCount מילים לחיזוק",
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.white70)),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios,
                              size: 16, color: Colors.white70),
                        ],
                      ),
                    ),
                  ),
                ],
                ...sortedKeys.map((unitNum) {
                  int total = units[unitNum]!.length;
                  int learned = learnedCounts[unitNum]!;
                  double progress = total > 0 ? learned / total : 0.0;
                  Color unitColor = getUnitColor(unitNum, isDark);
                  Color textColor =
                      getTextColorForBackground(unitNum, isDark);

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
                            color: unitColor.withOpacity(0.4),
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
                                  color: textColor.withOpacity(0.8),
                                  fontSize: 13)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor:
                                  Colors.white.withOpacity(0.4),
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
              ],
            ),
    );
  }

  void _showOptionsDialog(BuildContext context, int unitNum) {
    showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text("יחידה $
