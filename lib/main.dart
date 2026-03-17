import 'dart:convert';

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

    _logoController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.elasticOut));
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoController, curve: Curves.easeIn));

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
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Stack(
          children: [
            // עיגולים דקורטיביים ברקע
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
                onTap: () =>
                    Navigator.push(context, _slideRoute(const SettingsScreen())),
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

                  FadeTransition(
                    opacity: _logoFade,
                    child: const Text(
                      "מילים לפסיכומטרי",
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // כפתור עברית
                  SlideTransition(
                    position: _hebrewSlide,
                    child: _buildHomeButton(
                      context,
                      "עברית",
                      Icons.translate_rounded,
                      isDark
                          ? [const Color(0xFF37474F), const Color(0xFF263238)]
                          : [const Color(0xFF424242), const Color(0xFF212121)],
                      () => Navigator.push(
                        context,
                        _slideRoute(const UnitSelectorScreen(
                            jsonPath: 'assets/hebrew.json', title: 'עברית')),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // כפתור אנגלית
                  SlideTransition(
                    position: _englishSlide,
                    child: _buildHomeButton(
                      context,
                      "אנגלית",
                      Icons.language_rounded,
                      isDark
                          ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                          : [const Color(0xFF00C853), const Color(0xFF1B5E20)],
                      () => Navigator.push(
                        context,
                        _slideRoute(const UnitSelectorScreen(
                            jsonPath: 'assets/english.json', title: 'אנגלית')),
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

  Widget _buildHomeButton(BuildContext context, String title, IconData icon,
      List<Color> colors, VoidCallback onTap) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        height: 75,
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
              color: colors.last.withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(
                      color: Colors.black26,
                      offset: Offset(1, 1),
                      blurRadius: 2)
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
      print("Error loading data: $e");
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
                      margin: const EdgeInsets.only(
                          bottom: 20, left: 5, right: 5),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.red.shade300,
                            Colors.red.shade700
                          ],
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
                                Text(
                                    "יש לך $totalFailedCount מילים לחיזוק",
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
              title: Text("יחידה $unitNum", textAlign: TextAlign.center),
              children: [
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context,
                        _slideRoute(LearningScreen(
                            jsonPath: widget.jsonPath,
                            unitFilter: unitNum)));
                    loadAndOrganizeData();
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
                        context, _slideRoute(VocabularyListScreen(
                            jsonPath: widget.jsonPath,
                            unitFilter: unitNum)));
                    loadAndOrganizeData();
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

    Map<String, int> levels = {};
    List<Word> relevantWords = [];

    for (var w in allWords) {
      if (widget.unitFilter != null && w.unitNumber != widget.unitFilter) {
        continue;
      }
      relevantWords.add(w);
      var progress = ProgressManager().getWordProgress(w.uniqueId);
      if (progress != null) {
        levels[w.uniqueId] = progress['repetitions'] ?? 0;
      }
    }

    if (!mounted) return;
    setState(() {
      filteredWords = relevantWords;
      wordLevels = levels;
      isLoading = false;
    });
  }

  Future<void> manuallyUpdateStatus(Word word, int newLevel) async {
    if (newLevel == -1) {
      await ProgressManager().resetWord(word.uniqueId);
    } else if (newLevel == 0) {
      await ProgressManager().updateWord(word.uniqueId, 0, 0, 2.5, DateTime.now());
    } else {
      await ProgressManager().updateWord(word.uniqueId, 1, 1, 2.5,
          DateTime.now().add(const Duration(days: 1)));
    }
    loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.unitFilter != null
            ? "רשימה - יחידה ${widget.unitFilter}"
            : "כל המילים"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              itemCount: filteredWords.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final word = filteredWords[index];
                Icon statusIcon;
                if (!wordLevels.containsKey(word.uniqueId)) {
                  statusIcon = const Icon(Icons.remove_circle_outline, color: Colors.grey);
                } else if (wordLevels[word.uniqueId]! > 0) {
                  statusIcon = const Icon(Icons.check_circle, color: Colors.blue);
                } else {
                  statusIcon = const Icon(Icons.cancel, color: Colors.red);
                }

                return ListTile(
                  leading: statusIcon,
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
                              title: Text(word.term, textAlign: TextAlign.center),
                              children: [
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(context,
                                        _slideRoute(SingleCardScreen(word: word)));
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 10),
                                    child: Row(children: [
                                      Icon(Icons.visibility, color: Colors.black),
                                      SizedBox(width: 10),
                                      Text("צפייה בכרטיסייה",
                                          style: TextStyle(fontWeight: FontWeight.bold))
                                    ]),
                                  ),
                                ),
                                const Divider(),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    manuallyUpdateStatus(word, 1);
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.check_circle, color: Colors.blue),
                                    SizedBox(width: 10),
                                    Text("סמן כ'יודע'")
                                  ]),
                                ),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    manuallyUpdateStatus(word, 0);
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.cancel, color: Colors.red),
                                    SizedBox(width: 10),
                                    Text("סמן כ'לא יודע'")
                                  ]),
                                ),
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    manuallyUpdateStatus(word, -1);
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.remove_circle_outline, color: Colors.grey),
                                    SizedBox(width: 10),
                                    Text("אפס (כאילו לא נלמד)")
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

  const LearningScreen({
    super.key,
    required this.jsonPath,
    this.unitFilter,
    this.onlyFailed = false,
  });

  @override
  State<LearningScreen> createState() => _LearningScreenState();
}

class _LearningScreenState extends State<LearningScreen> {
  List<Word> fullVocabulary = [];
  List<Word> studySession = [];
  bool isLoading = true;
  bool isReviewMode = false;
  int _currentIndex = 0;
  final FlutterTts flutterTts = FlutterTts();

  @override
  void initState() {
    super.initState();
    loadJsonData();
  }

  Future<void> speak(String text) async {
    final prefs = await SharedPreferences.getInstance();
    double speed = prefs.getDouble('tts_speed') ?? 0.5;
    await flutterTts.setLanguage("en-US");
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

      filteredTotal.add(w);
      if (w.nextReview.isBefore(DateTime.now()) || w.repetitions == 0) {
        sessionWords.add(w);
      }
    }

    if (!mounted) return;
    setState(() {
      fullVocabulary = filteredTotal;
      studySession = sessionWords;
      if (widget.onlyFailed) {
        studySession.shuffle();
      } else {
        studySession.sort((a, b) => a.nextReview.compareTo(b.nextReview));
      }
      isLoading = false;
      isReviewMode = false;
      _currentIndex = 0;
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
    });
  }

  Future<void> updateWordProgress(bool knewIt) async {
    if (studySession.isEmpty) return;
    Word word = studySession[_currentIndex];

    setState(() {
      if (isReviewMode && !widget.onlyFailed) {
        if (knewIt) {
          studySession.removeAt(_currentIndex);
        } else {
          studySession.removeAt(_currentIndex);
          studySession.add(word);
        }
      } else {
        int quality = knewIt ? 4 : 0;
        if (quality < 3) {
          word.repetitions = 0;
          word.interval = 1;
        } else {
          if (word.repetitions == 0) {
            word.interval = 1;
          } else if (word.repetitions == 1) {
            word.interval = 6;
          } else {
            word.interval = (word.interval * word.easinessFactor).round();
          }
          word.repetitions++;
          word.easinessFactor = word.easinessFactor +
              (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
          if (word.easinessFactor < 1.3) word.easinessFactor = 1.3;
        }

        word.nextReview = DateTime.now().add(Duration(days: word.interval));
        ProgressManager().updateWord(word.uniqueId, word.repetitions,
            word.interval, word.easinessFactor, word.nextReview);

        if (knewIt) {
          studySession.removeAt(_currentIndex);
        } else {
          studySession.removeAt(_currentIndex);
          studySession.add(word);
        }
      }

      if (_currentIndex >= studySession.length) {
        _currentIndex = studySession.isNotEmpty ? studySession.length - 1 : 0;
      }
    });
  }

  void _nextCard() {
    if (_currentIndex < studySession.length - 1) {
      setState(() => _currentIndex++);
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    bool isDark = Theme.of(context).brightness == Brightness.dark;
    String titleText = widget.onlyFailed
        ? "חזרה על שגיאות"
        : "אימון - יחידה ${widget.unitFilter ?? 'כללי'}";

    return Scaffold(
      appBar: AppBar(title: Text(titleText), centerTitle: true),
      body: studySession.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 80, color: Colors.green),
                  const SizedBox(height: 20),
                  Text(
                      widget.onlyFailed
                          ? "אין מילים אדומות!\nכל הכבוד!"
                          : "סיימת את המילים להיום!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  if (!widget.onlyFailed)
                    AnimatedButton(
                      onTap: startReviewSession,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            )
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh, color: Colors.white),
                            SizedBox(width: 8),
                            Text("תרגול מילים שלמדתי",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  AnimatedButton(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text("חזור לרשימה",
                          style: TextStyle(
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87)),
                    ),
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: widget.onlyFailed
                                ? 0.0
                                : 1 - (studySession.length / fullVocabulary.length),
                            color: widget.onlyFailed
                                ? Colors.redAccent
                                : Colors.blue,
                            backgroundColor: Colors.grey[200],
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text("${_currentIndex + 1}/${studySession.length}",
                          style: const TextStyle(
                              color: Colors.grey, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    flex: 10,
                    child: Center(
                      child: FlipCard(
                        key: ValueKey(studySession[_currentIndex].id),
                        front: _buildCardFace(studySession[_currentIndex], true),
                        back: _buildCardFace(studySession[_currentIndex], false),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios, size: 36),
                        color: _currentIndex > 0
                            ? Colors.grey[700]
                            : Colors.grey[300],
                        onPressed: _currentIndex > 0 ? _prevCard : null,
                      ),
                      const SizedBox(width: 40),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios, size: 36),
                        color: _currentIndex < studySession.length - 1
                            ? Colors.grey[700]
                            : Colors.grey[300],
                        onPressed: _currentIndex < studySession.length - 1
                            ? _nextCard
                            : null,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                          child: _buildButton("עוד לא", Colors.white,
                              Colors.black, () => updateWordProgress(false))),
                      const SizedBox(width: 15),
                      Expanded(
                          child: _buildButton(
                              "ידעתי!",
                              widget.onlyFailed ? Colors.redAccent : Colors.blue,
                              Colors.white,
                              () => updateWordProgress(true))),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildCardFace(Word word, bool isFront) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    Color unitColor = getUnitColor(word.unitNumber, isDark);
    Color cardColor =
        isFront ? unitColor : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5));
    Color textColor = isFront
        ? getTextColorForBackground(word.unitNumber, isDark)
        : (isDark ? Colors.white : Colors.black87);
    Color iconColor = isFront
        ? (textColor == Colors.white ? Colors.white : Colors.blue)
        : Colors.blue;

    return Container(
      width: double.infinity,
      height: 450,
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
                  : "תרגום",
              style: TextStyle(color: textColor.withOpacity(0.6))),
          const SizedBox(height: 20),
          if (isFront) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
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
            if (word.language == 'english')
              IconButton(
                  icon: Icon(Icons.volume_up, color: iconColor),
                  onPressed: () => speak(word.term)),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Text(word.translation,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue)),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.all(15),
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
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildButton(String text, Color bg, Color txt, VoidCallback onTap) {
    return AnimatedButton(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: bg == Colors.white
                  ? Colors.black.withOpacity(0.07)
                  : bg.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: txt, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
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
  final FlutterTts flutterTts = FlutterTts();

  Future<void> speak(String text) async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.speak(text);
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
            AnimatedButton(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: const Center(
                  child: Text("חזור לרשימה",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
              ),
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
                  : "תרגום",
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
                  onPressed: () => speak(word.term)),
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

class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
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
              Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF4FC3F7), Color(0xFF1565C0)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.school_rounded,
                      size: 60, color: Colors.white)),
              const SizedBox(height: 20),
              const Text("מילומטרי",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text("גרסה 1.0.1", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              const Text(
                  "ברוכים הבאים לאפליקציית מילומטרי!\n\nהאפליקציה נועדה לעזור לכם ללמוד מילים לפסיכומטרי בצורה כיפית וקלה.\nתוכלו לתרגל מילים בעברית ובאנגלית ולעקוב אחרי ההתקדמות שלכם.\n\nפותח על ידי Pappo Studios.\nבהצלחה במבחן!",
                  style: TextStyle(fontSize: 18, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
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
// 15. Settings Screen
// ==========================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double ttsSpeed = 0.5;
  String _currentDetermination = "";
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
    });
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
                leading: const Icon(Icons.camera_alt_outlined, color: Colors.purple),
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
          _buildSectionHeader("כללי"),
          SwitchListTile(
            title: const Text("מצב לילה"),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (val) => ThemeManager().toggleTheme(),
          ),
          const Divider(),
          _buildSectionHeader("נחישות ותזכורות"),
          ListTile(
            leading: const Icon(Icons.psychology, color: Colors.orange),
            title: const Text("הגדרת רמת נחישות"),
            subtitle: Text(_currentDetermination),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => Navigator.push(
                context, _slideRoute(const DeterminationScreen())),
          ),
          const Divider(),
          _buildSectionHeader("קראת מילים (אנגלית)"),
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
          _buildSectionHeader("צור קשר"),
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline, color: Colors.blue),
            title: const Text("דברו איתי"),
            subtitle: const Text("דיווח על תקלות, הצעות או סתם דיבור"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showContactOptions,
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
            onTap: () => Navigator.push(
                context, _slideRoute(const AboutScreen())),
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

עדכון אחרון: 02/01/2026

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

8.	יצירת קשר:

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
    if (!context.mounted) return;
    Navigator.pushReplacement(context, _slideRoute(const HomeScreen()));
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
                child: const Icon(Icons.psychology, size: 60, color: Colors.white),
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
                      style: const TextStyle(
                          fontSize: 14, color: Colors.white70)),
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

class _FailedWordsSelectorScreenState
    extends State<FailedWordsSelectorScreen> {
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
                AnimatedButton(
                  onTap: () {
                    Navigator.pushReplacement(
                        context,
                        _slideRoute(LearningScreen(
                            jsonPath: widget.jsonPath, onlyFailed: true)));
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 25, left: 5, right: 5),
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
                const Text("בחר יחידה ספציפית:",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
