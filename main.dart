import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = HabitStore();
  await store.load();
  runApp(HabitFlowApp(store: store));
}

class Habit {
  final String id;
  String name;
  String emoji;
  List<int> days; // 1=Mon ... 7=Sun
  final Set<String> completions;

  Habit({
    required this.id,
    required this.name,
    required this.emoji,
    required this.days,
    Set<String>? completions,
  }) : completions = completions ?? {};

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'emoji': emoji, 'days': days,
    'completions': completions.toList(),
  };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
    id: j['id'],
    name: j['name'],
    emoji: j['emoji'] ?? '🎯',
    days: List<int>.from(j['days'] ?? [1,2,3,4,5,6,7]),
    completions: Set<String>.from(j['completions'] ?? []),
  );

  bool scheduled(DateTime d) => days.contains(d.weekday);
  String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  bool done(DateTime d) => completions.contains(key(d));

  int currentStreak() {
    var d = DateTime.now();
    if (done(d)) {
      var count = 0;
      while (scheduled(d) && done(d)) {
        count++;
        d = d.subtract(const Duration(days: 1));
      }
      return count;
    }
    d = d.subtract(const Duration(days: 1));
    var count = 0;
    while (scheduled(d) && done(d)) {
      count++;
      d = d.subtract(const Duration(days: 1));
    }
    return count;
  }

  int longestStreak() {
    if (completions.isEmpty) return 0;
    final dates = completions.map((s) => DateTime.parse(s)).toList()..sort();
    int best = 0, run = 0;
    DateTime? previous;
    for (final d in dates) {
      if (previous != null && d.difference(previous!).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      best = best < run ? run : best;
      previous = d;
    }
    return best;
  }

  int totalCompleted() => completions.length;
}

class HabitStore extends ChangeNotifier {
  final List<Habit> habits = [];
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString('habits');
    if (raw != null) {
      habits
        ..clear()
        ..addAll((jsonDecode(raw) as List).map((e) => Habit.fromJson(e)));
    }
    notifyListeners();
  }

  Future<void> save() async {
    await _prefs?.setString('habits', jsonEncode(habits.map((h) => h.toJson()).toList()));
    notifyListeners();
  }

  Future<void> add(String name, String emoji, List<int> days) async {
    habits.add(Habit(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      emoji: emoji,
      days: days,
    ));
    await save();
  }

  Future<void> update(Habit h, String name, String emoji, List<int> days) async {
    h.name = name.trim();
    h.emoji = emoji;
    h.days = days;
    await save();
  }

  Future<void> remove(Habit h) async {
    habits.remove(h);
    await save();
  }

  Future<void> toggle(Habit h, DateTime d) async {
    final k = h.key(d);
    if (h.completions.contains(k)) {
      h.completions.remove(k);
    } else {
      h.completions.add(k);
    }
    await save();
  }
}

class HabitFlowApp extends StatelessWidget {
  final HabitStore store;
  const HabitFlowApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'HabitFlow',
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF635BFF),
          scaffoldBackgroundColor: const Color(0xFFF7F7FA),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
          ),
        ),
        home: HomeScreen(store: store),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final HabitStore store;
  const HomeScreen({super.key, required this.store});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayPage(store: widget.store),
      StatsPage(store: widget.store),
      SettingsPage(store: widget.store),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      floatingActionButton: tab == 0 ? FloatingActionButton.extended(
        onPressed: () => showHabitEditor(context, widget.store),
        icon: const Icon(Icons.add),
        label: const Text('Habit'),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class TodayPage extends StatelessWidget {
  final HabitStore store;
  const TodayPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final active = store.habits.where((h) => h.scheduled(today)).toList();
    final completed = active.where((h) => h.done(today)).length;
    final progress = active.isEmpty ? 0.0 : completed / active.length;
    final hour = today.hour;
    final greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 100),
      children: [
        Text(greeting, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('Your day, one habit at a time.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(DateFormat('EEEE, d MMMM').format(today), style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 22),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              SizedBox(
                width: 78, height: 78,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(value: progress, strokeWidth: 8),
                  Text('$completed/${active.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(width: 18),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(progress == 1 && active.isNotEmpty ? 'Perfect day! 🎉' : 'Today’s progress', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                Text(active.isEmpty ? 'Add your first habit below.' : '${(progress * 100).round()}% complete'),
              ])),
            ]),
          ),
        ),
        const SizedBox(height: 22),
        Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (active.isEmpty)
          Card(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: const [
              Text('🌱', style: TextStyle(fontSize: 42)),
              SizedBox(height: 10),
              Text('No habits yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 5),
              Text('Tap “Habit” to create your first one.', textAlign: TextAlign.center),
            ]),
          ))
        else
          ...active.map((h) => HabitCard(habit: h, date: today, store: store)),
      ],
    );
  }
}

class HabitCard extends StatelessWidget {
  final Habit habit;
  final DateTime date;
  final HabitStore store;
  const HabitCard({super.key, required this.habit, required this.date, required this.store});

  @override
  Widget build(BuildContext context) {
    final done = habit.done(date);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => store.toggle(habit, date),
        onLongPress: () => showHabitEditor(context, store, habit: habit),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              child: Text(habit.emoji, style: const TextStyle(fontSize: 23)),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(habit.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null)),
              const SizedBox(height: 4),
              Text('🔥 ${habit.currentStreak()} day streak · 🏆 ${habit.longestStreak()} best', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                done ? Icons.check_circle : Icons.circle_outlined,
                key: ValueKey(done),
                size: 31,
                color: done ? Theme.of(context).colorScheme.primary : Colors.grey.shade400,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  final HabitStore store;
  const StatsPage({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final total = store.habits.fold<int>(0, (a, h) => a + h.totalCompleted());
    final best = store.habits.fold<int>(0, (a, h) => a > h.longestStreak() ? a : h.longestStreak());
    final today = DateTime.now();
    final week = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final scheduled = store.habits.expand((h) => week.where(h.scheduled)).length;
    final completed = store.habits.expand((h) => week.where(h.scheduled)).where((d) {
      final h = store.habits.firstWhere((x) => x.scheduled(d) && x.done(d), orElse: () => Habit(id:'',name:'',emoji:'',days:[]));
      return h.id.isNotEmpty;
    }).length;
    final rate = scheduled == 0 ? 0 : (completed / scheduled * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        Text('Statistics', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text('A simple look at your consistency.', style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 22),
        Row(children: [
          StatBox(value: '$rate%', label: '7-day rate', icon: '📈'),
          const SizedBox(width: 10),
          StatBox(value: '$best', label: 'Best streak', icon: '🏆'),
          const SizedBox(width: 10),
          StatBox(value: '$total', label: 'Completed', icon: '✓'),
        ]),
        const SizedBox(height: 26),
        Text('Your habits', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (store.habits.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('Create habits to see your statistics.')))
        else
          ...store.habits.map((h) => Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Text(h.emoji, style: const TextStyle(fontSize: 25)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${h.totalCompleted()} completed · ${h.longestStreak()} best streak'),
                ])),
                Text('🔥 ${h.currentStreak()}'),
              ]),
            ),
          )),
      ],
    );
  }
}

class StatBox extends StatelessWidget {
  final String value, label, icon;
  const StatBox({super.key, required this.value, required this.label, required this.icon});
  @override
  Widget build(BuildContext context) => Expanded(child: Card(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 8),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 20)),
      const SizedBox(height: 5),
      Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]),
  )));
}

class SettingsPage extends StatelessWidget {
  final HabitStore store;
  const SettingsPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('Settings', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 20),
      const Card(child: ListTile(
        leading: Icon(Icons.offline_bolt_outlined),
        title: Text('Offline-first'),
        subtitle: Text('Your habits are stored locally on this device.'),
      )),
      const SizedBox(height: 10),
      Card(child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: const Text('About HabitFlow'),
        subtitle: const Text('Simple habits. Better consistency.'),
        onTap: () => showAboutDialog(context: context, applicationName: 'HabitFlow', applicationVersion: '1.0.0'),
      )),
    ],
  );
}

Future<void> showHabitEditor(BuildContext context, HabitStore store, {Habit? habit}) async {
  final name = TextEditingController(text: habit?.name ?? '');
  String emoji = habit?.emoji ?? '🎯';
  List<int> days = List<int>.from(habit?.days ?? [1,2,3,4,5,6,7]);
  final emojis = ['🎯','📚','💧','🏃','🧘','💻','🛌','🥗','🧹','🎸','✍️','🧠'];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(habit == null ? 'Create habit' : 'Edit habit', style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        TextField(controller: name, autofocus: habit == null, decoration: const InputDecoration(labelText: 'Habit name', hintText: 'e.g. Read 20 minutes', border: OutlineInputBorder())),
        const SizedBox(height: 18),
        const Text('Choose an icon', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: emojis.map((e) => ChoiceChip(label: Text(e, style: const TextStyle(fontSize: 20)), selected: emoji == e, onSelected: (_) => setModal(() => emoji = e))).toList()),
        const SizedBox(height: 18),
        const Text('Repeat on', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 7, children: List.generate(7, (i) {
          final d = i + 1;
          final labels = ['M','T','W','T','F','S','S'];
          return FilterChip(label: Text(labels[i]), selected: days.contains(d), onSelected: (v) => setModal(() {
            if (v) days.add(d); else days.remove(d);
          }));
        })),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: name.text.trim().isEmpty || days.isEmpty ? null : () async {
            if (habit == null) {
              await store.add(name.text, emoji, days);
            } else {
              await store.update(habit, name.text, emoji, days);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(habit == null ? 'Create habit' : 'Save changes'),
        )),
        if (habit != null) ...[
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete habit'),
            onPressed: () async {
              await store.remove(habit);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          )),
        ],
      ])),
    )),
  );
}
