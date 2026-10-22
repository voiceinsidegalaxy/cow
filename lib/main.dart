import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

const kSky = Color(0xFFB3E5FC);
const kGrass = Color(0xFF81C784); 
const kWood = Color(0xFF8D6E63);
const kCream = Color(0xFFFFF8E1);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Moscow'));
  await NotificationService.init();
  runApp(const PillFarmApp());
}

class PillFarmApp extends StatelessWidget {
  const PillFarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ферма таблеток',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kSky,
        colorScheme: ColorScheme.fromSeed(seedColor: kGrass),
      ),
      home: const FarmHome(),
    );
  }
}

class Medicine {
  String name;
  int dosesPerDay;
  int health;
  List<Map<String, dynamic>> history;
  Medicine({
    required this.name, 
    required this.dosesPerDay, 
    this.health = 100,
    List<Map<String, dynamic>>? history
  }) : history = history ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'dosesPerDay': dosesPerDay,
        'health': health,
        'history': history,
      };

  factory Medicine.fromJson(Map<String, dynamic> j) => Medicine(
        name: j['name'],
        dosesPerDay: j['dosesPerDay'],
        health: j['health'] ?? 100,
        history: (j['history'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );

  int todayCount() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final rec = history.firstWhere(
      (h) => h['date'] == today,
      orElse: () => {'date': today, 'count': 0, 'times': []},
    );
    return rec['count'] as int;
  }

  bool isDoneToday() => todayCount() >= dosesPerDay;

  void markDose() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final now = DateFormat('HH:mm').format(DateTime.now());
    final idx = history.indexWhere((h) => h['date'] == today);
    if (idx == -1) {
      history.add({'date': today, 'count': 1, 'times': [now]});
    } else {
      history[idx]['count'] = (history[idx]['count'] as int) + 1;
      (history[idx]['times'] as List).add(now);
    }
    if (health < 100) health += 20;
    if (health > 100) health = 100;
  }
}

class Store {
  static const _key = 'medicines';
  static Future<List<Medicine>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Medicine.fromJson(e)).toList();
  }

  static Future<void> save(List<Medicine> meds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(meds.map((m) => m.toJson()).toList()));
  }
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  static Future<void> rescheduleAll(List<Medicine> meds) async {
    await _plugin.cancelAll();
    final hours = [8, 11, 14, 17, 20, 23];
    int id = 0;
    for (final m in meds) {
      if (m.isDoneToday()) continue;
      for (final h in hours) {
        String title;
        String body;
        
        if (h < 12) {
          title = '🐄 Доброе утро!';
          body = 'Коровы проснулись и ждут вкусномс. Выпей таблетку «${m.name}»! 🥕';
        } else if (h < 18) {
          title = '🐄 Му-у! Может пару тефтель?';
          body = 'Не забудь выпить «${m.name}». 🌿';
        } else {
          title = '🐄 50 бубликов, где?';
          body = 'Выпей таблетку «${m.name}», корова ждёт! 🥨';
        }

        await _scheduleDaily(id++, title, body, h);
      }
    }
  }

  static Future<void> _scheduleDaily(int id, String title, String body, int hour) async {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
    if (when.isBefore(now)) when = when.add(const Duration(days: 1));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'farm_channel',
          'Напоминания фермы',
          channelDescription: 'Пора выпить таблетку',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

class FarmHome extends StatefulWidget {
  const FarmHome({super.key});
  @override
  State<FarmHome> createState() => _FarmHomeState();
}

class _FarmHomeState extends State<FarmHome> {
  List<Medicine> meds = [];
  bool loading = true;
  
  bool isEating = false;
  
  int idleFrame = 1;
  Timer? _idleTimer;

  int eatFrame = 1;
  Timer? _eatTimer;

  final List<String> hungryPhrases = [
    'Я голодная', 'Нужен вкусномс', 'Я же не умею', 'Ну полный му',
    'Тефтели', 'И как теперь жить', 'Муууууу',
  ];
  final List<String> eatingPhrases = [
    'Вкусноооомс', 'Блэм му-му-му', 'Тефтельки', 'День свежей травки',
  ];
  final List<String> sleepingPhrases = [
    'Эх родной коровник', 'Кавмук устала', 'А мои нанотельняшки...',
  ];
  
  String currentHungryPhrase = 'Я голодная';
  String currentEatingPhrase = 'Вкусноооомс';
  String currentSleepingPhrase = 'Эх родной коровник';

  @override
  void initState() {
    super.initState();
    _load();
    _startIdleAnimation();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _eatTimer?.cancel();
    super.dispose();
  }

  void _startIdleAnimation() {
    _idleTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (mounted && !isEating && !allDone) {
        setState(() {
          idleFrame = idleFrame >= 3 ? 1 : idleFrame + 1;
        });
      }
    });
  }

  void _startEatingAnimation() {
    eatFrame = 1;
    _eatTimer = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (mounted && isEating) {
        setState(() {
          eatFrame = eatFrame >= 4 ? 1 : eatFrame + 1;
        });
      }
    });
  }

  Future<void> _load() async {
    meds = await Store.load();
    _randomizePhrases();
    setState(() => loading = false);
    await NotificationService.rescheduleAll(meds);
  }

  Future<void> _persist() async {
    await Store.save(meds);
    await NotificationService.rescheduleAll(meds);
  }

  bool get allDone => meds.isNotEmpty && meds.every((m) => m.isDoneToday());

  void _randomizePhrases() {
    currentHungryPhrase = hungryPhrases[Random().nextInt(hungryPhrases.length)];
    currentEatingPhrase = eatingPhrases[Random().nextInt(eatingPhrases.length)];
    currentSleepingPhrase = sleepingPhrases[Random().nextInt(sleepingPhrases.length)];
  }

  Future<void> _takeDose(Medicine m) async {
    setState(() {
      m.markDose();
      isEating = true;
      currentEatingPhrase = eatingPhrases[Random().nextInt(eatingPhrases.length)];
      _startEatingAnimation();
    });
    await _persist();

    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      _eatTimer?.cancel();
      setState(() {
        isEating = false;
      });
    }
    
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() {
        _randomizePhrases(); 
      });
    }

    if (m.isDoneToday()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Нанотельняшки наелись 🐄🧦'),
          backgroundColor: kGrass,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addMedicine() async {
    final nameCtrl = TextEditingController();
    int doses = 1;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: kCream,
          title: Row(
            children: [
              Image.asset(
                'icon_cow.png', 
                width: 32, height: 32,
                errorBuilder: (c, e, s) => const Text('🐄', style: TextStyle(fontSize: 24)),
              ),
              const SizedBox(width: 8),
              const Text('Новая корова'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Название таблетки'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Приёмов в день: '),
                  DropdownButton<int>(
                    value: doses,
                    items: [1, 2, 3, 4]
                        .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                        .toList(),
                    onChanged: (v) => setSt(() => doses = v!),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kGrass),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                setState(() {
                  meds.add(Medicine(name: nameCtrl.text.trim(), dosesPerDay: doses));
                });
                Navigator.pop(ctx);
                _persist();
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(Medicine m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCream,
        title: Text('Удалить «${m.name}»?'),
        content: const Text('История тоже удалится.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => meds.remove(m));
      _persist();
    }
  }

  void _openHistory(Medicine m) {
    final sorted = [...m.history]..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: kCream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 50, height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('📖 ', style: TextStyle(fontSize: 22)),
                Expanded(
                  child: Text('Дневник «${m.name}»',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kWood)),
                ),
              ],
            ),
            const Divider(color: kWood),
            const SizedBox(height: 8),
            Expanded(
              child: sorted.isEmpty 
                ? const Center(child: Text('Пока пусто', style: TextStyle(color: kWood)))
                : ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (_, i) {
                      final h = sorted[i];
                      return Card(
                        color: Colors.white,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.event, color: kGrass),
                          title: Text(h['date'], style: const TextStyle(fontWeight: FontWeight.bold, color: kWood)),
                          subtitle: Text('Выпито: ${h['count']}/${m.dosesPerDay} (${(h['times'] as List).join(', ')})', style: const TextStyle(color: kWood)),
                        ),
                      );
                    },
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCow() {
    String currentPhrase;
    String currentImage;

    if (allDone) {
      currentPhrase = currentSleepingPhrase;
      currentImage = 'cow_sleep.png';
    } else if (isEating) {
      currentPhrase = currentEatingPhrase;
      currentImage = 'cow_eat_$eatFrame.png';
    } else {
      currentPhrase = currentHungryPhrase;
      currentImage = 'cow_idle_$idleFrame.png';
    }

    return Container(
      height: 220,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: kWood.withOpacity(0.2), width: 2),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: kGrass,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
              ),
            ),
          ),
          
          Positioned(
            bottom: allDone ? 10 : 20, 
            child: Image.asset(
              currentImage,
              height: 130,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Text('🐄', style: TextStyle(fontSize: 90)),
            ),
          ),
          
          Positioned(
            top: 10, 
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  currentPhrase, 
                  key: ValueKey(currentPhrase),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kWood),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMedicine,
        backgroundColor: kWood,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Корова', style: TextStyle(color: Colors.white)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [kSky, kGrass], 
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('🌿 Моя ферма 🌿', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kWood)),
              ),
              if (meds.isNotEmpty) _buildCow(),
              Expanded(
                child: meds.isEmpty
                    ? const Center(child: Text('Пока пусто. Добавь первую корову 🐄', style: TextStyle(fontSize: 16, color: kWood)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: meds.length,
                        itemBuilder: (_, i) {
                          final m = meds[i];
                          final done = m.isDoneToday();
                          return Card(
                            color: kCream,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Image.asset(
                                        'icon_cow.png', 
                                        width: 40, height: 40,
                                        errorBuilder: (c, e, s) => Text(done ? '🐄😋' : '🐄', style: const TextStyle(fontSize: 32)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(m.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kWood)),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Text('❤️ Здоровье: ', style: TextStyle(fontSize: 12, color: kWood)),
                                                Expanded(
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(10),
                                                    child: LinearProgressIndicator(
                                                      value: m.health / 100,
                                                      backgroundColor: Colors.grey.shade300,
                                                      color: m.health > 50 ? Colors.green : Colors.redAccent,
                                                      minHeight: 8,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text('${m.health}%', style: const TextStyle(fontSize: 12, color: kWood)),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _openHistory(m),
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Image.asset(
                                            'book_icon.png', width: 28, height: 28,
                                            errorBuilder: (c, e, s) => const Icon(Icons.menu_book, color: kWood, size: 28),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: kWood),
                                        onPressed: () => _delete(m),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text('${m.todayCount()}/${m.dosesPerDay} приёмов сегодня', style: const TextStyle(color: kWood, fontSize: 14)),
                                  const SizedBox(height: 8),
                                  if (done)
                                    Container(
                                      width: double.infinity, padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(color: kGrass.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                                      child: const Text('Нанотельняшки наелись 🐄🧦', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kWood)),
                                    )
                                  else
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: kGrass, foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        onPressed: () => _takeDose(m),
                                        icon: const Text('🥕', style: TextStyle(fontSize: 20)),
                                        label: const Text('Выпил', style: TextStyle(fontSize: 16)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}