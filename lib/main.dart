import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const HabitFlowApp());

const purple = Color(0xFF6750A4);

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class Habit {
  Habit({required this.id, required this.name, required this.icon, required this.days, Set<String>? done, this.reminder}) : done = done ?? <String>{};
  final String id;
  String name;
  String icon;
  List<int> days; // 1=Mon ... 7=Sun
  Set<String> done;
  int? reminder; // minutes after midnight

  bool scheduled(DateTime d) => days.contains(d.weekday);
  bool completed(DateTime d) => done.contains(dayKey(d));

  int currentStreak() {
    var cursor = dateOnly(DateTime.now());
    var streak = 0;
    while (true) {
      if (scheduled(cursor)) {
        if (!completed(cursor)) break;
        streak++;
      }
      cursor = cursor.subtract(const Duration(days: 1));
      if (cursor.year < 2000) break;
    }
    return streak;
  }

  int bestStreak() {
    if (done.isEmpty) return 0;
    final dates = done.map(DateTime.parse).map(dateOnly).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? previous;
    for (final d in dates) {
      if (previous != null && d.difference(previous!).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      if (scheduled(d)) best = best < run ? run : best;
      previous = d;
    }
    return best;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': icon,
        'days': days,
        'done': done.toList(),
        'reminder': reminder,
      };

  factory Habit.fromJson(Map<String, dynamic> j) => Habit(
        id: j['id'] as String,
        name: j['name'] as String,
        icon: (j['icon'] as String?) ?? '🎯',
        days: (j['days'] as List).map((e) => e as int).toList(),
        done: ((j['done'] as List?) ?? const []).map((e) => e as String).toSet(),
        reminder: j['reminder'] as int?,
      );
}

class HabitStore extends ChangeNotifier {
  final List<Habit> habits = [];
  ThemeMode themeMode = ThemeMode.system;
  String profileName = '';
  String? profileImage;
  DateTime joined = DateTime.now();
  bool onboardingSeen = false;
  SharedPreferences? _prefs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    profileName = _prefs!.getString('profileName') ?? '';
    profileImage = _prefs!.getString('profileImage');
    joined = DateTime.tryParse(_prefs!.getString('joined') ?? '') ?? DateTime.now();
    onboardingSeen = _prefs!.getBool('onboardingSeen') ?? false;
    themeMode = ThemeMode.values[_prefs!.getInt('themeMode') ?? ThemeMode.system.index];
    final raw = _prefs!.getString('habits');
    if (raw != null) {
      try {
        habits
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => Habit.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _prefs?.setString('habits', jsonEncode(habits.map((h) => h.toJson()).toList()));
    await _prefs?.setString('profileName', profileName);
    if (profileImage == null) {
      await _prefs?.remove('profileImage');
    } else {
      await _prefs?.setString('profileImage', profileImage!);
    }
    await _prefs?.setString('joined', joined.toIso8601String());
    await _prefs?.setBool('onboardingSeen', onboardingSeen);
    await _prefs?.setInt('themeMode', themeMode.index);
  }

  Future<void> addHabit(String name, String icon, List<int> days, int? reminder) async {
    habits.add(Habit(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name.trim(), icon: icon, days: days..sort(), reminder: reminder));
    await _save();
    notifyListeners();
  }

  Future<void> editHabit(Habit h, String name, String icon, List<int> days, int? reminder) async {
    h.name = name.trim();
    h.icon = icon;
    h.days = days..sort();
    h.reminder = reminder;
    await _save();
    notifyListeners();
  }

  Future<void> removeHabit(Habit h) async {
    habits.remove(h);
    await _save();
    notifyListeners();
  }

  Future<void> toggle(Habit h, DateTime date) async {
    final key = dayKey(date);
    if (h.done.contains(key)) {
      h.done.remove(key);
    } else {
      h.done.add(key);
      HapticFeedback.mediumImpact();
    }
    await _save();
    notifyListeners();
  }

  Future<void> setProfile(String name, String? image) async {
    profileName = name.trim();
    profileImage = image;
    await _save();
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await _save();
    notifyListeners();
  }

  Map<String, dynamic> backupJson() => {
        'app': 'HabitFlow',
        'version': 2,
        'exportedAt': DateTime.now().toIso8601String(),
        'profileName': profileName,
        'joined': joined.toIso8601String(),
        'habits': habits.map((h) => h.toJson()).toList(),
      };

  Future<void> restore(Map<String, dynamic> data) async {
    final list = data['habits'];
    if (list is! List) throw const FormatException('Invalid HabitFlow backup');
    habits
      ..clear()
      ..addAll(list.map((e) => Habit.fromJson(Map<String, dynamic>.from(e as Map))));
    profileName = (data['profileName'] as String?) ?? profileName;
    joined = DateTime.tryParse((data['joined'] as String?) ?? '') ?? joined;
    await _save();
    notifyListeners();
  }
}

final store = HabitStore();

class HabitFlowApp extends StatefulWidget {
  const HabitFlowApp({super.key});
  @override
  State<HabitFlowApp> createState() => _HabitFlowAppState();
}

class _HabitFlowAppState extends State<HabitFlowApp> {
  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (_, __) => MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'HabitFlow',
          themeMode: store.themeMode,
          theme: ThemeData(useMaterial3: true, colorSchemeSeed: purple, brightness: Brightness.light),
          darkTheme: ThemeData(useMaterial3: true, colorSchemeSeed: purple, brightness: Brightness.dark),
          home: store.onboardingSeen ? const HomeShell() : const OnboardingPage(),
        ),
      );
}

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 92, height: 92, decoration: BoxDecoration(color: purple.withValues(alpha: .12), shape: BoxShape.circle), child: const Icon(Icons.water_drop_rounded, size: 52, color: purple)),
                const SizedBox(height: 28),
                Text('HabitFlow', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                Text('Build your future with today’s habit.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                const Text('Track habits, protect your streaks, understand your progress, and build consistency one day at a time.', textAlign: TextAlign.center),
                const SizedBox(height: 36),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () async { store.onboardingSeen = true; await store._save(); store.notifyListeners(); }, icon: const Icon(Icons.arrow_forward), label: const Text('Get started'))),
              ],
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final pages = const [TodayPage(), CalendarPage(), StatsPage(), ProfilePage()];
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HabitFlow'), centerTitle: false),
        body: IndexedStack(index: index, children: pages),
        floatingActionButton: index == 0 ? FloatingActionButton.extended(onPressed: () => editHabit(context, store), icon: const Icon(Icons.add), label: const Text('Habit')) : null,
        bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Stats'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ]),
      );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});
  @override
  Widget build(BuildContext context) {
    final now = dateOnly(DateTime.now());
    final today = store.habits.where((h) => h.scheduled(now)).toList();
    final upcoming = <Habit, DateTime>{};
    for (final h in store.habits.where((h) => !h.scheduled(now))) {
      for (var i = 1; i <= 7; i++) {
        final d = now.add(Duration(days: i));
        if (h.scheduled(d)) { upcoming[h] = d; break; }
      }
    }
    return RefreshIndicator(
      onRefresh: () async => store.load(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
        Text(DateFormat('EEEE, d MMMM').format(now), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text('Today', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        if (today.isEmpty) EmptyState(onAdd: () => editHabit(context, store)),
        ...today.map((h) => HabitCard(h: h, date: now)),
        if (upcoming.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text('Upcoming', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...upcoming.entries.map((e) => ListTile(leading: CircleAvatar(child: Text(e.key.icon)), title: Text(e.key.name), subtitle: Text('Next: ${DateFormat('EEE, d MMM').format(e.value)}'))),
        ],
      ]),
    );
  }
}

class HabitCard extends StatelessWidget {
  const HabitCard({super.key, required this.h, required this.date});
  final Habit h;
  final DateTime date;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: CircleAvatar(child: Text(h.icon, style: const TextStyle(fontSize: 22))),
          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('🔥 ${h.currentStreak()} day streak${h.reminder != null ? '  •  ${_timeText(h.reminder!)}' : ''}'),
          trailing: Checkbox(value: h.completed(date), onChanged: (_) => store.toggle(h, date)),
          onTap: () => editHabit(context, store, habit: h),
        ),
      );
}

String _timeText(int minutes) {
  final t = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  return t.format(navigatorKey.currentContext!);
}
final navigatorKey = GlobalKey<NavigatorState>();

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.onAdd});
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(children: [const Icon(Icons.checklist_rounded, size: 54), const SizedBox(height: 12), const Text('No habits scheduled today'), const SizedBox(height: 12), OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Create your first habit'))])));
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}
class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = dateOnly(DateTime.now());
  Habit? selectedHabit;
  @override
  Widget build(BuildContext context) {
    final h = selectedHabit;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Calendar', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      DropdownButtonFormField<Habit?>(initialValue: h, decoration: const InputDecoration(labelText: 'View', border: OutlineInputBorder()), items: [const DropdownMenuItem<Habit?>(value: null, child: Text('All habits')), ...store.habits.map((x) => DropdownMenuItem(value: x, child: Text('${x.icon} ${x.name}')))], onChanged: (v) => setState(() => selectedHabit = v)),
      const SizedBox(height: 14),
      Card(child: CalendarDatePicker(initialDate: selected, firstDate: DateTime(2020), lastDate: DateTime(2100), onDateChanged: (d) => setState(() => selected = d))),
      const SizedBox(height: 14),
      Text(DateFormat('EEEE, d MMMM yyyy').format(selected), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...(h == null ? store.habits : [h]).map((x) => ListTile(leading: CircleAvatar(child: Text(x.icon)), title: Text(x.name), trailing: x.completed(selected) ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.radio_button_unchecked), onTap: x.scheduled(selected) ? () => store.toggle(x, selected) : null)),
    ]);
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final total = store.habits.fold<int>(0, (s, h) => s + h.done.length);
    final scheduled = store.habits.fold<int>(0, (s, h) {
      var count = 0;
      final start = store.joined;
      for (var i = 0; i <= DateTime.now().difference(start).inDays; i++) if (h.scheduled(start.add(Duration(days: i)))) count++;
      return s + count;
    });
    final rate = scheduled == 0 ? 0 : ((total / scheduled) * 100).clamp(0, 100).round();
    final best = store.habits.fold<int>(0, (m, h) => h.bestStreak() > m ? h.bestStreak() : m);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Progress', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 18),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.55, crossAxisSpacing: 10, mainAxisSpacing: 10, children: [
        MetricCard(label: 'Habits', value: '${store.habits.length}', icon: Icons.checklist),
        MetricCard(label: 'Check-ins', value: '$total', icon: Icons.done_all),
        MetricCard(label: 'Completion', value: '$rate%', icon: Icons.percent),
        MetricCard(label: 'Best streak', value: '$best', icon: Icons.local_fire_department),
      ]),
      const SizedBox(height: 22),
      Text('Your habits', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      ...store.habits.map((h) => ListTile(leading: CircleAvatar(child: Text(h.icon)), title: Text(h.name), subtitle: Text('${h.done.length} check-ins • best ${h.bestStreak()} days'), trailing: Text('${h.currentStreak()}🔥'))),
    ]);
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, required this.icon});
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 22), const SizedBox(height: 6), Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)), Text(label)])));
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final completions = store.habits.fold<int>(0, (s, h) => s + h.done.length);
    final best = store.habits.fold<int>(0, (m, h) => h.bestStreak() > m ? h.bestStreak() : m);
    final current = store.habits.fold<int>(0, (m, h) => h.currentStreak() > m ? h.currentStreak() : m);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      Center(child: GestureDetector(onTap: () => profileEditor(context), child: CircleAvatar(radius: 42, backgroundImage: store.profileImage != null ? FileImage(File(store.profileImage!)) : null, child: store.profileImage == null ? const Icon(Icons.person, size: 42) : null))),
      const SizedBox(height: 10),
      Center(child: Text(store.profileName.isEmpty ? 'Your profile' : store.profileName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
      TextButton(onPressed: () => profileEditor(context), child: const Text('Edit profile')),
      const SizedBox(height: 10),
      GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, childAspectRatio: 1.7, children: [
        MetricCard(label: 'Total habits', value: '${store.habits.length}', icon: Icons.checklist),
        MetricCard(label: 'Completions', value: '$completions', icon: Icons.done_all),
        MetricCard(label: 'Current streak', value: '$current', icon: Icons.local_fire_department),
        MetricCard(label: 'Best streak', value: '$best', icon: Icons.emoji_events),
      ]),
      const SizedBox(height: 12),
      ListTile(title: const Text('Joined'), subtitle: Text(DateFormat('d MMMM yyyy').format(store.joined))),
      ListTile(title: const Text('Appearance'), subtitle: Text(_themeLabel(store.themeMode)), leading: const Icon(Icons.palette_outlined), onTap: () => themeDialog(context)),
      ListTile(title: const Text('Achievements'), leading: const Icon(Icons.emoji_events_outlined), onTap: () => achievements(context)),
      ListTile(title: const Text('Export CSV'), leading: const Icon(Icons.table_chart_outlined), onTap: () => csvExport(context)),
      ListTile(title: const Text('Backup JSON'), leading: const Icon(Icons.backup_outlined), onTap: () => backup(context)),
      ListTile(title: const Text('Restore JSON'), leading: const Icon(Icons.restore), onTap: () => restore(context)),
    ]);
  }
}

String _themeLabel(ThemeMode m) => switch (m) { ThemeMode.system => 'System', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark' };

Future<void> profileEditor(BuildContext context) async {
  final controller = TextEditingController(text: store.profileName);
  String? image = store.profileImage;
  await showDialog<void>(context: context, builder: (d) => StatefulBuilder(builder: (d, set) => AlertDialog(title: const Text('Edit profile'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name')), const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async { final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85); if (x != null) set(() => image = x.path); }, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose photo'))]), actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () async { await store.setProfile(controller.text, image); if (d.mounted) Navigator.pop(d); }, child: const Text('Save'))])));
}

Future<void> editHabit(BuildContext context, HabitStore s, {Habit? habit}) async {
  final name = TextEditingController(text: habit?.name ?? '');
  var icon = habit?.icon ?? '🎯';
  var days = List<int>.from(habit?.days ?? [1, 2, 3, 4, 5, 6, 7]);
  int? reminder = habit?.reminder;
  await showDialog<void>(context: context, builder: (d) => StatefulBuilder(builder: (d, set) => AlertDialog(title: Text(habit == null ? 'Create habit' : 'Edit habit'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Habit name')), const SizedBox(height: 12), DropdownButtonFormField<String>(initialValue: icon, decoration: const InputDecoration(labelText: 'Icon'), items: const ['🎯', '📚', '💧', '🏃', '🧘', '💻', '🛌', '🥗', '🎸', '🧠'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (v) { if (v != null) set(() => icon = v); }), const SizedBox(height: 12), const Align(alignment: Alignment.centerLeft, child: Text('Repeat on')), Wrap(spacing: 4, children: List.generate(7, (i) { final day = i + 1; return FilterChip(label: Text(['M', 'T', 'W', 'T', 'F', 'S', 'S'][i]), selected: days.contains(day), onSelected: (v) => set(() { if (v) { if (!days.contains(day)) days.add(day); } else { days.remove(day); } })); })), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('One reminder'), subtitle: Text(reminder == null ? 'Off' : _dialogTime(reminder!)), value: reminder != null, onChanged: (v) async { if (!v) { set(() => reminder = null); return; } final t = await showTimePicker(context: d, initialTime: const TimeOfDay(hour: 20, minute: 0)); if (t != null) set(() => reminder = t.hour * 60 + t.minute); })])), actions: [if (habit != null) TextButton(onPressed: () async { await s.removeHabit(habit); if (d.mounted) Navigator.pop(d); }, child: const Text('Delete')), TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: name.text.trim().isEmpty || days.isEmpty ? null : () async { if (habit == null) { await s.addHabit(name.text, icon, days, reminder); } else { await s.editHabit(habit, name.text, icon, days, reminder); } if (d.mounted) Navigator.pop(d); }, child: Text(habit == null ? 'Create' : 'Save'))])));
}

String _dialogTime(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

void themeDialog(BuildContext context) => showDialog<void>(context: context, builder: (d) => SimpleDialog(title: const Text('Appearance'), children: ThemeMode.values.map((m) => RadioListTile<ThemeMode>(value: m, groupValue: store.themeMode, title: Text(_themeLabel(m)), onChanged: (v) { if (v != null) { store.setTheme(v); Navigator.pop(d); } })).toList()));

void achievements(BuildContext context) {
  final done = store.habits.fold<int>(0, (s, h) => s + h.done.length);
  final best = store.habits.fold<int>(0, (m, h) => h.bestStreak() > m ? h.bestStreak() : m);
  showModalBottomSheet<void>(context: context, builder: (_) => ListView(padding: const EdgeInsets.all(20), children: [Text('Achievements', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 10), Achievement('🌱', 'First Habit', store.habits.isNotEmpty), Achievement('🔥', '7-day Streak', best >= 7), Achievement('🚀', '30-day Streak', best >= 30), Achievement('💯', '100 Check-ins', done >= 100)]));
}

class Achievement extends StatelessWidget {
  const Achievement(this.icon, this.title, this.unlocked, {super.key});
  final String icon, title;
  final bool unlocked;
  @override
  Widget build(BuildContext context) => ListTile(leading: CircleAvatar(child: Text(icon)), title: Text(title), trailing: Icon(unlocked ? Icons.check_circle : Icons.lock_outline));
}

Future<void> csvExport(BuildContext context) async {
  final rows = <List<dynamic>>[['Habit', 'Date', 'Day', 'Scheduled']];
  for (final h in store.habits) for (final date in h.done.map(DateTime.parse)) rows.add([h.name, dayKey(date), DateFormat('EEEE').format(date), h.scheduled(date) ? 'Yes' : 'No']);
  final csv = const ListToCsvConverter().convert(rows);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/habitflow_export.csv')..writeAsStringSync(csv);
  if (context.mounted) await Share.shareXFiles([XFile(file.path)], text: 'HabitFlow CSV export');
}

Future<void> backup(BuildContext context) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/habitflow_backup.json')..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(store.backupJson()));
  if (context.mounted) await Share.shareXFiles([XFile(file.path)], text: 'HabitFlow backup');
}

Future<void> restore(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
  if (result?.files.single.path == null) return;
  try {
    final data = jsonDecode(await File(result!.files.single.path!).readAsString()) as Map<String, dynamic>;
    await store.restore(data);
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored successfully')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not restore that backup')));
  }
}
