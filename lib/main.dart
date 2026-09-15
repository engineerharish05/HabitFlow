import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

const seed = Color(0xFF6750A4);
String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
String clock(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

class Habit {
  Habit({required this.id, required this.name, required this.icon, required this.days, Set<String>? done, this.reminder}) : done = done ?? {};
  final String id;
  String name, icon;
  List<int> days;
  Set<String> done;
  int? reminder;
  bool scheduled(DateTime d) => days.contains(d.weekday);
  bool complete(DateTime d) => done.contains(key(d));

  int current() {
    var d = day(DateTime.now());
    var n = 0;
    while (d.year > 1990) {
      if (scheduled(d)) {
        if (!complete(d)) break;
        n++;
      }
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int best() {
    if (done.isEmpty || days.isEmpty) return 0;
    final dates = done.map(DateTime.parse).map(day).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? last;
    for (final d in dates) {
      if (!scheduled(d)) continue;
      final expected = last == null ? false : _nextScheduled(last!, d);
      run = expected ? run + 1 : 1;
      if (run > best) best = run;
      last = d;
    }
    return best;
  }

  bool _nextScheduled(DateTime previous, DateTime currentDate) {
    var d = previous.add(const Duration(days: 1));
    while (d.isBefore(currentDate)) {
      if (scheduled(d)) return false;
      d = d.add(const Duration(days: 1));
    }
    return d == currentDate;
  }

  Map<String, dynamic> json() => {'id': id, 'name': name, 'icon': icon, 'days': days, 'done': done.toList(), 'reminder': reminder};
  factory Habit.from(Map<String, dynamic> j) => Habit(
    id: '${j['id']}', name: '${j['name']}', icon: j['icon'] ?? '🎯',
    days: List<int>.from(j['days'] ?? [1,2,3,4,5,6,7]),
    done: Set<String>.from(j['done'] ?? []), reminder: j['reminder'] is int ? j['reminder'] : null,
  );
}

class ReminderService {
  static final plugin = FlutterLocalNotificationsPlugin();
  static bool ready = false;

  static Future<void> init() async {
    if (ready) return;
    tz.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.name));
    } catch (_) {}
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(settings);
    final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    ready = true;
  }

  static int _id(String habitId, int weekday) => (habitId.hashCode.abs() % 100000) * 10 + weekday;

  static Future<void> cancelHabit(Habit h) async {
    await init();
    for (final w in h.days) await plugin.cancel(_id(h.id, w));
  }

  static Future<void> scheduleHabit(Habit h) async {
    await init();
    await cancelHabit(h);
    if (h.reminder == null || h.days.isEmpty) return;
    final minute = h.reminder!;
    final hour = minute ~/ 60;
    final min = minute % 60;
    for (final weekday in h.days) {
      var now = tz.TZDateTime.now(tz.local);
      var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, min);
      while (next.weekday != weekday || !next.isAfter(now)) {
        next = next.add(const Duration(days: 1));
      }
      await plugin.zonedSchedule(
        _id(h.id, weekday), 'HabitFlow reminder', '${h.icon} ${h.name}', next,
        const NotificationDetails(android: AndroidNotificationDetails('habit_reminders', 'Habit reminders', channelDescription: 'Reminders for scheduled habits', importance: Importance.high, priority: Priority.high)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }
}

class Store extends ChangeNotifier {
  final habits = <Habit>[];
  ThemeMode theme = ThemeMode.system;
  String name = '';
  String? photo;
  DateTime joined = DateTime.now();
  bool onboard = false;
  SharedPreferences? p;

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    name = p!.getString('name') ?? '';
    photo = p!.getString('photo');
    joined = DateTime.tryParse(p!.getString('joined') ?? '') ?? DateTime.now();
    onboard = p!.getBool('onboard') ?? false;
    final ti = p!.getInt('theme') ?? ThemeMode.system.index;
    theme = ti >= 0 && ti < ThemeMode.values.length ? ThemeMode.values[ti] : ThemeMode.system;
    final raw = p!.getString('habits');
    if (raw != null) { try { habits..clear()..addAll((jsonDecode(raw) as List).map((e) => Habit.from(Map<String,dynamic>.from(e)))); } catch (_) {} }
    await ReminderService.init();
    for (final h in habits) { if (h.reminder != null) await ReminderService.scheduleHabit(h); }
    notifyListeners();
  }

  Future<void> save() async {
    await p?.setString('habits', jsonEncode(habits.map((h) => h.json()).toList()));
    await p?.setString('name', name);
    if (photo == null) { await p?.remove('photo'); } else { await p?.setString('photo', photo!); }
    await p?.setString('joined', joined.toIso8601String());
    await p?.setBool('onboard', onboard);
    await p?.setInt('theme', theme.index);
  }

  Future<void> toggle(Habit h, DateTime d) async {
    final k = key(d);
    if (h.done.contains(k)) { h.done.remove(k); } else { h.done.add(k); HapticFeedback.mediumImpact(); }
    await save();
    notifyListeners();
  }

  Future<void> add(String n, String i, List<int> d, int? r) async {
    final h = Habit(id: DateTime.now().microsecondsSinceEpoch.toString(), name: n.trim(), icon: i, days: [...d]..sort(), reminder: r);
    habits.add(h);
    await save();
    if (r != null) await ReminderService.scheduleHabit(h);
    notifyListeners();
  }

  Future<void> edit(Habit h, String n, String i, List<int> d, int? r) async {
    h.name = n.trim(); h.icon = i; h.days = [...d]..sort(); h.reminder = r;
    await save();
    await ReminderService.scheduleHabit(h);
    notifyListeners();
  }

  Future<void> remove(Habit h) async { await ReminderService.cancelHabit(h); habits.remove(h); await save(); notifyListeners(); }
  Future<void> setTheme(ThemeMode t) async { theme=t; await save(); notifyListeners(); }
  Future<void> setProfile(String n, String? ph) async { name=n.trim(); photo=ph; await save(); notifyListeners(); }
  Map<String,dynamic> backup() => {'app':'HabitFlow','version':3,'profileName':name,'joined':joined.toIso8601String(),'habits':habits.map((h)=>h.json()).toList()};
  Future<void> restore(Map<String,dynamic> d) async {
    if (d['habits'] is! List) throw const FormatException('Invalid HabitFlow backup');
    for (final h in habits) await ReminderService.cancelHabit(h);
    habits..clear()..addAll((d['habits'] as List).map((e)=>Habit.from(Map<String,dynamic>.from(e))));
    name = d['profileName'] ?? name;
    await save();
    for (final h in habits) { if (h.reminder != null) await ReminderService.scheduleHabit(h); }
    notifyListeners();
  }
}

final s = Store();

Future<void> main() async { WidgetsFlutterBinding.ensureInitialized(); runApp(const App()); }

class App extends StatefulWidget { const App({super.key}); @override State<App> createState()=>_App(); }
class _App extends State<App> {
  @override void initState(){super.initState(); s.load();}
  @override Widget build(BuildContext c)=>AnimatedBuilder(animation:s,builder:(_,__)=>MaterialApp(debugShowCheckedModeBanner:false,title:'HabitFlow',themeMode:s.theme,theme:ThemeData(useMaterial3:true,colorSchemeSeed:seed),darkTheme:ThemeData(useMaterial3:true,colorSchemeSeed:seed,brightness:Brightness.dark),home:s.onboard?const Shell():const Intro()));
}

class Intro extends StatelessWidget {
  const Intro({super.key});
  @override Widget build(BuildContext c)=>Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
    Container(width:90,height:90,decoration:BoxDecoration(color:seed.withValues(alpha:.12),shape:BoxShape.circle),child:const Icon(Icons.water_drop_rounded,size:52,color:seed)),
    const SizedBox(height:24), Text('HabitFlow',style:Theme.of(c).textTheme.displaySmall?.copyWith(fontWeight:FontWeight.bold)), const SizedBox(height:8), const Text('Build your future with today’s habit.',textAlign:TextAlign.center), const SizedBox(height:20), const Text('Track habits. Protect streaks. Understand your progress.',textAlign:TextAlign.center), const SizedBox(height:32), SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{s.onboard=true;await s.save();s.notifyListeners();},child:const Text('Get started')))
  ]))));
}

class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState()=>_Shell(); }
class _Shell extends State<Shell> {
  int i=0; final pages=const[Today(),Calendar(),Stats(),Profile()];
  @override Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('HabitFlow')),body:IndexedStack(index:i,children:pages),floatingActionButton:i==0?FloatingActionButton.extended(onPressed:()=>habitDialog(c),icon:const Icon(Icons.add),label:const Text('Habit')):null,bottomNavigationBar:NavigationBar(selectedIndex:i,onDestinationSelected:(x)=>setState(()=>i=x),destinations:const[
    NavigationDestination(icon:Icon(Icons.today_outlined),selectedIcon:Icon(Icons.today),label:'Today'),NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendar'),NavigationDestination(icon:Icon(Icons.insights_outlined),selectedIcon:Icon(Icons.insights),label:'Stats'),NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile')
  ]));
}

class Today extends StatelessWidget {
  const Today({super.key});
  @override Widget build(BuildContext c){
    final d=day(DateTime.now()); final today=s.habits.where((h)=>h.scheduled(d)).toList(); final upcoming=<String>[];
    for(final h in s.habits.where((h)=>!h.scheduled(d))){for(int x=1;x<=7;x++){final n=d.add(Duration(days:x));if(h.scheduled(n)){upcoming.add('${h.icon} ${h.name} • ${DateFormat('EEE, d MMM').format(n)}');break;}}}
    return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[Text(DateFormat('EEEE, d MMMM').format(d)),Text('Today',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),if(today.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(24),child:Center(child:Text('No habits scheduled today')))),...today.map((h)=>HabitCard(h:h,d:d)),if(upcoming.isNotEmpty)...[const SizedBox(height:18),Text('Upcoming',style:Theme.of(c).textTheme.titleLarge),...upcoming.map((x)=>ListTile(leading:const Icon(Icons.event_outlined),title:Text(x)))] ]);
  }
}

class HabitCard extends StatefulWidget { final Habit h; final DateTime d; const HabitCard({super.key,required this.h,required this.d}); @override State<HabitCard> createState()=>_HabitCardState(); }
class _HabitCardState extends State<HabitCard> {
  bool anim=false;
  @override Widget build(BuildContext c){final done=widget.h.complete(widget.d);return AnimatedScale(scale:anim?1.035:1,duration:const Duration(milliseconds:160),child:Card(child:ListTile(leading:CircleAvatar(child:Text(widget.h.icon)),title:Text(widget.h.name),subtitle:Text('🔥 ${widget.h.current()} day streak${widget.h.reminder!=null?' • ⏰ ${clock(widget.h.reminder!)}':''}'),trailing:Checkbox(value:done,onChanged:(_){setState(()=>anim=true);Future.delayed(const Duration(milliseconds:180),()=>mounted?setState(()=>anim=false):null);s.toggle(widget.h,widget.d);}),onTap:()=>habitDialog(c,habit:widget.h))));}
}

class Calendar extends StatefulWidget { const Calendar({super.key}); @override State<Calendar> createState()=>_Cal(); }
class _Cal extends State<Calendar>{DateTime d=day(DateTime.now()); Habit? h; @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[Text('Calendar',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:12),DropdownButtonFormField<Habit?>(initialValue:h,decoration:const InputDecoration(labelText:'Habit',border:OutlineInputBorder()),items:[const DropdownMenuItem<Habit?>(value:null,child:Text('All habits')),...s.habits.map((x)=>DropdownMenuItem(value:x,child:Text('${x.icon} ${x.name}')))],onChanged:(v)=>setState(()=>h=v)),const SizedBox(height:12),CalendarDatePicker(initialDate:d,firstDate:DateTime(2020),lastDate:DateTime(2100),onDateChanged:(x)=>setState(()=>d=x)),const SizedBox(height:8),...(h==null?s.habits:[h!]).map((x)=>ListTile(leading:CircleAvatar(child:Text(x.icon)),title:Text(x.name),subtitle:Text(x.scheduled(d)?'Scheduled':'Not scheduled'),trailing:Icon(x.complete(d)?Icons.check_circle:Icons.radio_button_unchecked),onTap:x.scheduled(d)?()=>s.toggle(x,d):null))]);}

class Stats extends StatelessWidget { const Stats({super.key}); @override Widget build(BuildContext c){final done=s.habits.fold<int>(0,(a,h)=>a+h.done.length);final best=s.habits.fold<int>(0,(a,h)=>h.best()>a?h.best():a);final current=s.habits.fold<int>(0,(a,h)=>h.current()>a?h.current():a);final rate=_rate();return ListView(padding:const EdgeInsets.all(16),children:[Text('Progress',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[metric(c,'Habits','${s.habits.length}',Icons.checklist),metric(c,'Check-ins','$done',Icons.done_all),metric(c,'Current streak','$current',Icons.local_fire_department),metric(c,'Best streak','$best',Icons.emoji_events),metric(c,'Completion rate','${(rate*100).round()}%',Icons.percent)]),const SizedBox(height:20),...s.habits.map((h)=>ListTile(leading:CircleAvatar(child:Text(h.icon)),title:Text(h.name),subtitle:Text('${h.done.length} check-ins • best ${h.best()} days'),trailing:Text('${h.current()}🔥')))]);}
  double _rate(){final start=day(s.joined);final end=day(DateTime.now());int scheduled=0,done=0;for(final h in s.habits){for(var d=start;!d.isAfter(end);d=d.add(const Duration(days:1))){if(h.scheduled(d)){scheduled++;if(h.complete(d))done++;}}}return scheduled==0?0:done/scheduled;}
}
Widget metric(BuildContext c,String a,String b,IconData i)=>SizedBox(width:MediaQuery.sizeOf(c).width/2-24,height:105,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(i),Text(b,style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),Text(a)]))));

class Profile extends StatelessWidget { const Profile({super.key}); @override Widget build(BuildContext c){final done=s.habits.fold<int>(0,(a,h)=>a+h.done.length);final best=s.habits.fold<int>(0,(a,h)=>h.best()>a?h.best():a);final current=s.habits.fold<int>(0,(a,h)=>h.current()>a?h.current():a);final rate=_rate();return ListView(padding:const EdgeInsets.all(16),children:[Center(child:CircleAvatar(radius:44,backgroundImage:s.photo!=null?FileImage(File(s.photo!)):null,child:s.photo==null?const Icon(Icons.person,size:42):null)),const SizedBox(height:10),Center(child:Text(s.name.isEmpty?'Your profile':s.name,style:Theme.of(c).textTheme.titleLarge)),Center(child:Text('Joined ${DateFormat('d MMM yyyy').format(s.joined)}')),const SizedBox(height:20),Wrap(spacing:10,runSpacing:10,children:[metric(c,'Total habits','${s.habits.length}',Icons.checklist),metric(c,'Total completions','$done',Icons.done_all),metric(c,'Current streak','$current',Icons.local_fire_department),metric(c,'Best streak','$best',Icons.emoji_events),metric(c,'Completion rate','${(rate*100).round()}%',Icons.percent)]),const SizedBox(height:16),ListTile(leading:const Icon(Icons.edit),title:const Text('Edit profile'),onTap:()=>profileDialog(c)),ListTile(leading:const Icon(Icons.palette_outlined),title:const Text('Theme'),subtitle:Text(s.theme.name),onTap:()=>themeDialog(c)),ListTile(leading:const Icon(Icons.file_download_outlined),title:const Text('Export CSV'),onTap:()=>exportCsv()),ListTile(leading:const Icon(Icons.backup_outlined),title:const Text('Backup JSON'),onTap:()=>backup()),ListTile(leading:const Icon(Icons.restore_outlined),title:const Text('Restore JSON'),onTap:()=>restore()),const SizedBox(height:12),const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('🏆 Achievements\n\n🔥 7-day streak — keep showing up\n💪 30 check-ins — consistency wins\n🌟 100 check-ins — serious momentum')))]);}
  double _rate(){final start=day(s.joined),end=day(DateTime.now());int total=0,done=0;for(final h in s.habits){for(var d=start;!d.isAfter(end);d=d.add(const Duration(days:1))){if(h.scheduled(d)){total++;if(h.complete(d))done++;}}}return total==0?0:done/total;}
}

Future<void> habitDialog(BuildContext c,{Habit? habit}) async {final name=TextEditingController(text:habit?.name??'');final icon=TextEditingController(text:habit?.icon??'🎯');var days=[...(habit?.days??[1,2,3,4,5,6,7])];int? reminder=habit?.reminder;final picked=await showDialog<bool>(context:c,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>AlertDialog(title:Text(habit==null?'New habit':'Edit habit'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:name,decoration:const InputDecoration(labelText:'Habit name')),TextField(controller:icon,decoration:const InputDecoration(labelText:'Icon / emoji')),const SizedBox(height:12),const Align(alignment:Alignment.centerLeft,child:Text('Repeat')),Wrap(spacing:4,children:[for(int i=1;i<=7;i++)FilterChip(label:Text(DateFormat('EE').format(DateTime(2024,1,i))),selected:days.contains(i),onSelected:(v){set(()=>v?days.add(i):days.remove(i));})]),const SizedBox(height:12),ListTile(contentPadding:EdgeInsets.zero,leading:const Icon(Icons.alarm_outlined),title:Text(reminder==null?'Add reminder':'Reminder ${clock(reminder!)}'),onTap:()async{final t=await showTimePicker(context:ctx,initialTime:reminder==null?const TimeOfDay(hour:20,minute:0):TimeOfDay(hour:reminder!~/60,minute:reminder!%60));if(t!=null)set(()=>reminder=t.hour*60+t.minute);}),if(habit!=null)TextButton.icon(onPressed:(){Navigator.pop(ctx,false);showDialog(context:c,builder:(_)=>AlertDialog(title:const Text('Delete habit?'),content:const Text('This removes its history and reminders.'),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:()async{await s.remove(habit);if(c.mounted)Navigator.pop(c);},child:const Text('Delete'))]));},icon:const Icon(Icons.delete_outline),label:const Text('Delete'))])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:(){if(name.text.trim().isEmpty||days.isEmpty)return;Navigator.pop(ctx,true);},child:const Text('Save'))])));if(picked==true){if(habit==null)await s.add(name.text,icon.text.trim().isEmpty?'🎯':icon.text.trim(),days,reminder);else await s.edit(habit,name.text,icon.text.trim().isEmpty?'🎯':icon.text.trim(),days,reminder);}}

Future<void> profileDialog(BuildContext c)async{final n=TextEditingController(text:s.name);String? photo=s.photo;await showDialog(context:c,builder:(ctx)=>AlertDialog(title:const Text('Edit profile'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Name')),const SizedBox(height:12),OutlinedButton.icon(onPressed:()async{final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:80);if(x!=null){photo=x.path;}},icon:const Icon(Icons.photo_library_outlined),label:const Text('Choose photo'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){s.setProfile(n.text,photo);Navigator.pop(ctx);},child:const Text('Save'))]));}

Future<void> themeDialog(BuildContext c)async{final t=await showDialog<ThemeMode>(context:c,builder:(ctx)=>SimpleDialog(title:const Text('Theme'),children:[for(final x in ThemeMode.values)RadioListTile<ThemeMode>(value:x,groupValue:s.theme,onChanged:(v)=>Navigator.pop(ctx,v),title:Text(x.name))]));if(t!=null)await s.setTheme(t);}

Future<void> exportCsv()async{final rows=[['Habit','Date','Completed','Streak']];for(final h in s.habits){for(final d in h.done.map(DateTime.parse)){rows.add([h.name,key(d),'Yes','${h.current()}']);}}final dir=await getTemporaryDirectory();final f=File('${dir.path}/habitflow_export.csv');await f.writeAsString(const ListToCsvConverter().convert(rows));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow CSV export');}
Future<void> backup()async{final dir=await getTemporaryDirectory();final f=File('${dir.path}/habitflow_backup.json');await f.writeAsString(const JsonEncoder.withIndent('  ').convert(s.backup()));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow backup');}
Future<void> restore()async{final result=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json'],withData:true);if(result==null)return;try{final bytes=result.files.single.bytes;if(bytes==null)throw const FormatException();final data=jsonDecode(utf8.decode(bytes));await s.restore(Map<String,dynamic>.from(data));}catch(e){if(navigatorKey.currentContext!=null)ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(const SnackBar(content:Text('Invalid HabitFlow backup')));}}
final navigatorKey=GlobalKey<NavigatorState>();
