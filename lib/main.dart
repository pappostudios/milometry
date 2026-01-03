import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

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
      case 1:
        return const Color(0xFF006064);
      case 2:
        return const Color(0xFF00838F);
      case 3:
        return const Color(0xFF0097A7);
      case 4:
        return const Color(0xFF00ACC1);
      case 5:
        return const Color(0xFF00BCD4);
      case 6:
        return const Color(0xFFF57F17);
      case 7:
        return const Color(0xFFE65100);
      case 8:
        return const Color(0xFFBF360C);
      case 9:
        return const Color(0xFF3E2723);
      case 10:
        return const Color(0xFFB71C1C);
      default:
        return const Color(0xFF424242);
    }
  } else {
    switch (unit) {
      case 1:
        return const Color(0xFFE0F7FA);
      case 2:
        return const Color(0xFFB2EBF2);
      case 3:
        return const Color(0xFF80DEEA);
      case 4:
        return const Color(0xFF4DD0E1);
      case 5:
        return const Color(0xFF26C6DA);
      case 6:
        return const Color(0xFFFFD54F);
      case 7:
        return const Color(0xFFFFB74D);
      case 8:
        return const Color(0xFFFF8A65);
      case 9:
        return const Color(0xFFF4511E);
      case 10:
        return const Color(0xFFB71C1C);
      default:
        return Colors.white;
    }
  }
}

Color getTextColorForBackground(int unit, bool isDark) {
  if (isDark) return Colors.white;
  if (unit >= 9) return Colors.white;
  return Colors.black87;
}

// ==========================================
// 3. Notification Manager (מתוקן עם Timezone)
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
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
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
    List<String> rawData = _prefs?.getStringList('user_progress') ?? [];
    _cache.clear();

    for (String record in rawData) {
      List<String> parts = record.split(':');
      String id = parts[0];

      if (parts.length >= 5) {
        _cache[id] = {
          'repetitions': int.parse(parts[1]),
          'interval': int.parse(parts[2]),
          'easinessFactor': double.parse(parts[3]),
          'nextReview': DateTime.fromMillisecondsSinceEpoch(int.parse(parts[4]))
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
    await _prefs?.setStringList('user_progress', exportList);
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
  final bool hasAcceptedTerms = prefs.getBool('hasAcceptedTerms') ?? false;

  runApp(PsychoApp(
      startScreen: hasAcceptedTerms
          ? const SplashScreen()
          : const TermsOfServiceScreen()));
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
            scaffoldBackgroundColor: Colors.white,
            fontFamily: 'Arial',
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              iconTheme: IconThemeData(color: Colors.black),
              titleTextStyle: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
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
          context, MaterialPageRoute(builder: (context) => const HomeScreen()));
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
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
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
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[200],
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 20,
              child: IconButton(
                icon: const Icon(Icons.settings),
                color: isDark ? Colors.white : Colors.grey[800],
                iconSize: 30,
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SettingsScreen()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(30.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  Container(
                    height: 150,
                    width: 150,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        )
                      ],
                    ),
                    child: const Icon(Icons.school_rounded,
                        size: 80, color: Colors.blue),
                  ),
                  const SizedBox(height: 30),
                  Text(
                    "מילומטרי",
                    style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87),
                  ),
                  const Text(
                    "מילים לפסיכומטרי",
                    style: TextStyle(fontSize: 20, color: Colors.grey),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 80,
                    child: _buildHomeButton(
                        context,
                        "עברית",
                        isDark ? Colors.grey[800]! : Colors.black,
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const UnitSelectorScreen(
                                    jsonPath: 'assets/hebrew.json',
                                    title: 'עברית')))),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 80,
                    child: _buildHomeButton(
                        context,
                        "אנגלית",
                        isDark ? Colors.green[900]! : Colors.greenAccent[700]!,
                        () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const UnitSelectorScreen(
                                    jsonPath: 'assets/english.json',
                                    title: 'אנגלית')))),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeButton(
      BuildContext context, String title, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 15,
                offset: const Offset(0, 8))
          ],
        ),
        child: Center(
          child: Text(
            title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(
                      color: Colors.black26,
                      offset: Offset(1, 1),
                      blurRadius: 2)
                ]),
          ),
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

      for (var word in allWords) {
        int u = word.unitNumber;
        if (u == 0) continue;

        if (!tempUnits.containsKey(u)) {
          tempUnits[u] = [];
          tempCounts[u] = 0;
        }
        tempUnits[u]!.add(word);

        var progress = ProgressManager().getWordProgress(word.uniqueId);
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
      setState(() {
        isLoading = false;
      });
      print("Error loading data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    var sortedKeys = units.keys.toList()..sort();
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text("בחר יחידה - ${widget.title}"),
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : sortedKeys.isEmpty
              ? const Center(child: Text("לא נמצאו יחידות"))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, index) {
                    int unitNum = sortedKeys[index];
                    int total = units[unitNum]!.length;
                    int learned = learnedCounts[unitNum]!;
                    double progress = total > 0 ? learned / total : 0.0;

                    Color unitColor = getUnitColor(unitNum, isDark);
                    Color textColor =
                        getTextColorForBackground(unitNum, isDark);

                    return Card(
                      color: unitColor,
                      margin: const EdgeInsets.only(bottom: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      elevation: 3,
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(15),
                        title: Text(
                          "יחידה $unitNum",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: textColor),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text("התקדמות: $learned / $total מילים",
                                style: TextStyle(
                                    color: textColor.withOpacity(0.8))),
                            const SizedBox(height: 5),
                            LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white.withOpacity(0.5),
                              color: textColor == Colors.white
                                  ? Colors.greenAccent
                                  : Colors.blue,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(4),
                            )
                          ],
                        ),
                        trailing: Icon(Icons.arrow_forward_ios,
                            size: 16, color: textColor),
                        onTap: () {
                          _showOptionsDialog(context, unitNum);
                        },
                      ),
                    );
                  },
                ),
    );
  }

  void _showOptionsDialog(BuildContext context, int unitNum) {
    showDialog(
        context: context,
        builder: (ctx) => SimpleDialog(
              title: Text("יחידה $unitNum", textAlign: TextAlign.center),
              children: [
                SimpleDialogOption(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => LearningScreen(
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
                        context,
                        MaterialPageRoute(
                            builder: (context) => VocabularyListScreen(
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
      await ProgressManager()
          .updateWord(word.uniqueId, 0, 0, 2.5, DateTime.now());
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
        elevation: 0,
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
                  statusIcon = const Icon(Icons.remove_circle_outline,
                      color: Colors.grey);
                } else if (wordLevels[word.uniqueId]! > 0) {
                  statusIcon =
                      const Icon(Icons.check_circle, color: Colors.blue);
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
                              title:
                                  Text(word.term, textAlign: TextAlign.center),
                              children: [
                                SimpleDialogOption(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                SingleCardScreen(word: word)));
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
                                    manuallyUpdateStatus(word, 1);
                                  },
                                  child: const Row(children: [
                                    Icon(Icons.check_circle,
                                        color: Colors.blue),
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
                                    Icon(Icons.remove_circle_outline,
                                        color: Colors.grey),
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

  const LearningScreen({super.key, required this.jsonPath, this.unitFilter});

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
      filteredTotal.add(w);

      var progress = ProgressManager().getWordProgress(w.uniqueId);
      if (progress != null) {
        w.repetitions = progress['repetitions'];
        w.interval = progress['interval'];
        w.easinessFactor = progress['easinessFactor'];
        w.nextReview = progress['nextReview'];
      }

      if (w.nextReview.isBefore(DateTime.now()) || w.repetitions == 0) {
        sessionWords.add(w);
      }
    }

    if (!mounted) return;

    setState(() {
      fullVocabulary = filteredTotal;
      studySession = sessionWords;
      studySession.sort((a, b) => a.nextReview.compareTo(b.nextReview));
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

  Future<void> resetAllProgress() async {
    setState(() {
      isLoading = true;
    });
    loadJsonData();
  }

  Future<void> updateWordProgress(bool knewIt) async {
    if (studySession.isEmpty) return;

    Word word = studySession[_currentIndex];

    setState(() {
      if (isReviewMode) {
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
      setState(() {
        _currentIndex++;
      });
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "אימון - יחידה ${widget.unitFilter ?? 'כללי'}",
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: () {
              showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                        title: const Text("איפוס התקדמות"),
                        content:
                            const Text("פעולה זו תאפס את הזיכרון באפליקציה."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text("ביטול")),
                          TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                ProgressManager().resetAll().then((_) {
                                  resetAllProgress();
                                });
                              },
                              child: const Text("אפס הכל",
                                  style: TextStyle(color: Colors.red))),
                        ],
                      ));
            },
          ),
        ],
      ),
      body: studySession.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle, size: 80, color: Colors.green),
                  const SizedBox(height: 20),
                  const Text("סיימת את המילים להיום!",
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: startReviewSession,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text("תרגול מילים שלמדתי",
                        style: TextStyle(color: Colors.white, fontSize: 18)),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.blue),
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
                        child: LinearProgressIndicator(
                          value: 1 -
                              (studySession.length /
                                  (isReviewMode
                                      ? studySession.length + 1
                                      : fullVocabulary.length)),
                          color: isReviewMode ? Colors.orange : Colors.blue,
                          backgroundColor: Colors.grey[200],
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
                        front:
                            _buildCardFace(studySession[_currentIndex], true),
                        back:
                            _buildCardFace(studySession[_currentIndex], false),
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
                              isReviewMode ? Colors.orange : Colors.blue,
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
        isFront ? unitColor : (isDark ? const Color(0xFF1E1E1E) : Colors.white);

    Color textColor;
    if (isFront) {
      textColor = getTextColorForBackground(word.unitNumber, isDark);
    } else {
      textColor = isDark ? Colors.white : Colors.black87;
    }

    Color iconColor = isFront
        ? (textColor == Colors.white ? Colors.white : Colors.blue)
        : Colors.blue;

    if (!isFront && !isDark) {
      cardColor = const Color(0xFFF5F5F5);
    }

    return Container(
      width: double.infinity,
      height: 450,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5))
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
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        padding: const EdgeInsets.symmetric(vertical: 20),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Text(text,
          style:
              TextStyle(color: txt, fontWeight: FontWeight.bold, fontSize: 18)),
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
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20))),
              child: const Text("חזור לרשימה"),
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
    Color cardColor;
    if (isFront) {
      cardColor = unitColor;
    } else {
      cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5);
    }

    Color textColor;
    if (isFront) {
      textColor = getTextColorForBackground(word.unitNumber, isDark);
    } else {
      textColor = isDark ? Colors.white : Colors.black87;
    }

    Color iconColor = isFront
        ? (textColor == Colors.white ? Colors.white : Colors.blue)
        : Colors.blue;

    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? Colors.grey[800]! : Colors.grey.shade300, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
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
// 13. Flip Card Component
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
      appBar: AppBar(title: const Text("אודות"), elevation: 0),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E1E)
                          : Colors.blue.shade50,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.school_rounded,
                      size: 60, color: Colors.blue)),
              const SizedBox(height: 20),
              const Text("מילומטרי",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Text("גרסה 0.3 (Beta)",
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              const Text(
                  "ברוכים הבאים לאפליקציית מילומטרי!\n\nהאפליקציה נועדה לעזור לכם ללמוד מילים לפסיכומטרי בצורה כיפית וקלה.\nתוכלו לתרגל מילים בעברית ובאנגלית ולעקוב אחרי ההתקדמות שלכם.\n\nפותח על ידי Pappo Studios.\nבהצלחה במבחן!",
                  style: TextStyle(fontSize: 18, height: 1.5),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              const Text("© 2025 כל הזכויות שמורות",
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 15. Settings Screen (מסך הגדרות מעודכן)
// ==========================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double ttsSpeed = 0.5;
  // --- משתנים חדשים לתזכורות ---
  bool isReminderOn = false;
  TimeOfDay reminderTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ttsSpeed = prefs.getDouble('tts_speed') ?? 0.5;

      // טעינת הגדרות תזכורת
      isReminderOn = prefs.getBool('reminder_on') ?? false;
      int hour = prefs.getInt('reminder_hour') ?? 18;
      int minute = prefs.getInt('reminder_minute') ?? 0;
      reminderTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _updateSpeed(double newSpeed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('tts_speed', newSpeed);
    setState(() {
      ttsSpeed = newSpeed;
    });
  }

  // --- פונקציות לתפעול התזכורות ---
  Future<void> _toggleReminder(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isReminderOn = value;
    });
    await prefs.setBool('reminder_on', value);

    if (value) {
      await NotificationManager()
          .scheduleDailyNotification(reminderTime.hour, reminderTime.minute);
      await NotificationManager()
          .flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else {
      await NotificationManager().cancelNotifications();
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: reminderTime,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (newTime != null) {
      setState(() {
        reminderTime = newTime;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reminder_hour', newTime.hour);
      await prefs.setInt('reminder_minute', newTime.minute);

      if (isReminderOn) {
        await NotificationManager()
            .scheduleDailyNotification(newTime.hour, newTime.minute);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text("הגדרות"), elevation: 0),
      body: ListView(
        children: [
          const SizedBox(height: 20),

          // --- מדור כללי ---
          _buildSectionHeader("כללי"),
          SwitchListTile(
            title: const Text("מצב לילה"),
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode),
            value: isDark,
            onChanged: (val) {
              ThemeManager().toggleTheme();
            },
          ),
          const Divider(),

          // --- מדור תזכורות (חדש) ---
          _buildSectionHeader("תזכורות"),
          SwitchListTile(
            title: const Text("תזכורת יומית"),
            subtitle: Text(isReminderOn
                ? "תזכורת בשעה ${reminderTime.format(context)}"
                : "כבוי"),
            secondary: const Icon(Icons.alarm),
            value: isReminderOn,
            onChanged: (val) => _toggleReminder(val),
          ),

          if (isReminderOn)
            ListTile(
              leading: const Icon(Icons.edit_calendar),
              title: const Text("שנה שעת תזכורת"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: _pickTime,
            ),

          const Divider(),

          // --- מדור דיבור (TTS) ---
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

          // --- מדור ניהול נתונים ---
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

          // --- מדור אודות ---
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text("אודות האפליקציה"),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) => const AboutScreen()));
            },
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

// --- מסך תנאי השימוש ---
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
    await prefs.setBool('hasAcceptedTerms', true);

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const HomeScreen()),
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
ברוכים הבאים לאפליקציית הלימוד לפסיכומטרי של Pappo Studios.

1. שימוש באפליקציה:
השימוש באפליקציה הוא באחריות המשתמש בלבד. האפליקציה נועדה לתרגול ושיפור אוצר מילים לפסיכומטרי, אך אינה מבטיחה ציון מסוים במבחן.

2. קניין רוחני:
כל התכנים באפליקציה, לרבות מאגרי המילים, העיצובים והקוד, הם קניינו הבלעדי של המפתח ואין להעתיקם או לעשות בהם שימוש מסחרי ללא אישור.

3. פרטיות:
אנו מכבדים את פרטיותך. האפליקציה שומרת נתונים מקומיים על גבי המכשיר שלך לצורך מעקב התקדמות.

4. היוצר אינו אחראי לכל נזק ישיר או עקיף שייגרם כתוצאה משימוש באפליקציה.
                      ''',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.right,
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
                setState(() {
                  _isChecked = value ?? false;
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isChecked ? _acceptTerms : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isChecked ? Colors.blue : Colors.grey,
                ),
                child: const Text(
                  'המשך לאפליקציה',
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
