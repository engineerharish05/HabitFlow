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
    var d = day(DateTime.now()); var n = 0;
    while (d.year > 1990) { if (scheduled(d)) { if (!complete(d)) break; n++; } d = d.subtract(const Duration(days: 1)); }
    return n;
  }
  int best() {
    if (done.isEmpty) return 0;
    final dates = done.map(DateTime.parse).map(day).toList()..sort(); var best = 0; var run = 0; DateTime? last;
    for (final d in dates) { run = last != null && d.difference(last!).inDays == 1 ? run + 1 : 1; if (scheduled(d) && run > best) best = run; last = d; }
    return best;
  }
  Map<String,dynamic> json() => {'id':id,'name':name,'icon':icon,'days':days,'done':done.toList(),'reminder':reminder};
  factory Habit.from(Map<String,dynamic> j) => Habit(id:j['id'],name:j['name'],icon:j['icon'] ?? '🎯',days:List<int>.from(j['days'] ?? [1,2,3,4,5,6,7]),done:Set<String>.from(j['done'] ?? []),reminder:j['reminder']);
}

class Store extends ChangeNotifier {
  final habits=<Habit>[]; ThemeMode theme=ThemeMode.system; String name=''; String? photo; DateTime joined=DateTime.now(); bool onboard=false; SharedPreferences? p;
  Future<void> load() async { p=await SharedPreferences.getInstance(); name=p!.getString('name')??''; photo=p!.getString('photo'); joined=DateTime.tryParse(p!.getString('joined')??'')??DateTime.now(); onboard=p!.getBool('onboard')??false; theme=ThemeMode.values[p!.getInt('theme')??2]; final s=p!.getString('habits'); if(s!=null){try{habits..clear()..addAll((jsonDecode(s) as List).map((e)=>Habit.from(e)));}catch(_){}} notifyListeners(); }
  Future<void> save() async { await p?.setString('habits',jsonEncode(habits.map((h)=>h.json()).toList())); await p?.setString('name',name); if(photo==null) await p?.remove('photo'); else await p?.setString('photo',photo!); await p?.setString('joined',joined.toIso8601String()); await p?.setBool('onboard',onboard); await p?.setInt('theme',theme.index); }
  Future<void> toggle(Habit h,DateTime d) async { final k=key(d); h.done.contains(k)?h.done.remove(k):(h.done.add(k),HapticFeedback.mediumImpact()); await save();notifyListeners(); }
  Future<void> add(String n,String i,List<int>d,int?r)async{habits.add(Habit(id:DateTime.now().microsecondsSinceEpoch.toString(),name:n.trim(),icon:i,days:d..sort(),reminder:r));await save();notifyListeners();}
  Future<void> edit(Habit h,String n,String i,List<int>d,int?r)async{h.name=n.trim();h.icon=i;h.days=d..sort();h.reminder=r;await save();notifyListeners();}
  Future<void> remove(Habit h)async{habits.remove(h);await save();notifyListeners();}
  Future<void> setTheme(ThemeMode t)async{theme=t;await save();notifyListeners();}
  Future<void> setProfile(String n,String?ph)async{name=n.trim();photo=ph;await save();notifyListeners();}
  Map<String,dynamic> backup()=>{'app':'HabitFlow','version':2,'profileName':name,'joined':joined.toIso8601String(),'habits':habits.map((h)=>h.json()).toList()};
  Future<void> restore(Map<String,dynamic>d)async{if(d['habits'] is! List)throw const FormatException();habits..clear()..addAll((d['habits'] as List).map((e)=>Habit.from(Map<String,dynamic>.from(e))));name=d['profileName']??name;await save();notifyListeners();}
}
final s=Store();

void main()=>runApp(const App());
class App extends StatefulWidget{const App({super.key});State<App>createState()=>_App();}
class _App extends State<App>{void initState(){super.initState();s.load();}Widget build(BuildContext c)=>AnimatedBuilder(animation:s,builder:(_,__)=>MaterialApp(debugShowCheckedModeBanner:false,title:'HabitFlow',themeMode:s.theme,theme:ThemeData(useMaterial3:true,colorSchemeSeed:seed),darkTheme:ThemeData(useMaterial3:true,colorSchemeSeed:seed,brightness:Brightness.dark),home:s.onboard?const Shell():const Intro()));}

class Intro extends StatelessWidget{const Intro({super.key});Widget build(BuildContext c)=>Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Container(width:90,height:90,decoration:BoxDecoration(color:seed.withValues(alpha:.12),shape:BoxShape.circle),child:const Icon(Icons.water_drop_rounded,size:52,color:seed)),const SizedBox(height:24),Text('HabitFlow',style:Theme.of(c).textTheme.displaySmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),const Text('Build your future with today’s habit.',textAlign:TextAlign.center),const SizedBox(height:20),const Text('Track habits. Protect streaks. Understand your progress.',textAlign:TextAlign.center),const SizedBox(height:32),SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{s.onboard=true;await s.save();s.notifyListeners();},child:const Text('Get started')))]))));}

class Shell extends StatefulWidget{const Shell({super.key});State<Shell>createState()=>_Shell();}
class _Shell extends State<Shell>{int i=0;final pages=const[Today(),Calendar(),Stats(),Profile()];Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('HabitFlow')),body:IndexedStack(index:i,children:pages),floatingActionButton:i==0?FloatingActionButton.extended(onPressed:()=>habitDialog(c),icon:const Icon(Icons.add),label:const Text('Habit')):null,bottomNavigationBar:NavigationBar(selectedIndex:i,onDestinationSelected:(x)=>setState(()=>i=x),destinations:const[NavigationDestination(icon:Icon(Icons.today_outlined),selectedIcon:Icon(Icons.today),label:'Today'),NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendar'),NavigationDestination(icon:Icon(Icons.insights_outlined),selectedIcon:Icon(Icons.insights),label:'Stats'),NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile')]));}

class Today extends StatelessWidget{const Today({super.key});Widget build(BuildContext c){final d=day(DateTime.now());final today=s.habits.where((h)=>h.scheduled(d)).toList();final upcoming=<String>[];for(final h in s.habits){if(!h.scheduled(d)){for(int x=1;x<=7;x++){final n=d.add(Duration(days:x));if(h.scheduled(n)){upcoming.add('${h.icon} ${h.name}  •  ${DateFormat('EEE, d MMM').format(n)}');break;}}}}return ListView(padding:const EdgeInsets.fromLTRB(16,8,16,100),children:[Text(DateFormat('EEEE, d MMMM').format(d)),Text('Today',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),if(today.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[const Icon(Icons.checklist,size:48),const SizedBox(height:8),const Text('No habits scheduled today')]))) else ...today.map((h)=>Card(child:ListTile(leading:CircleAvatar(child:Text(h.icon)),title:Text(h.name),subtitle:Text('🔥 ${h.current()} day streak${h.reminder==null?'':'  •  '+clock(h.reminder!)}'),trailing:Checkbox(value:h.complete(d),onChanged:(_)=>s.toggle(h,d)),onTap:()=>habitDialog(c,habit:h)))),if(upcoming.isNotEmpty)...[const SizedBox(height:18),Text('Upcoming',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),...upcoming.map((x)=>ListTile(leading:const Icon(Icons.event_outlined),title:Text(x)))]);}}

class Calendar extends StatefulWidget{const Calendar({super.key});State<Calendar>createState()=>_Cal();}
class _Cal extends State<Calendar>{DateTime d=day(DateTime.now());Habit? h;Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(16),children:[Text('Calendar',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:12),DropdownButtonFormField<Habit?>(initialValue:h,decoration:const InputDecoration(labelText:'Habit',border:OutlineInputBorder()),items:[const DropdownMenuItem<Habit?>(value:null,child:Text('All habits')), ...s.habits.map((x)=>DropdownMenuItem(value:x,child:Text('${x.icon} ${x.name}')))],onChanged:(v)=>setState(()=>h=v)),const SizedBox(height:12),CalendarDatePicker(initialDate:d,firstDate:DateTime(2020),lastDate:DateTime(2100),onDateChanged:(x)=>setState(()=>d=x)),const SizedBox(height:8),...(h==null?s.habits:[h!]).map((x)=>ListTile(leading:CircleAvatar(child:Text(x.icon)),title:Text(x.name),trailing:Icon(x.complete(d)?Icons.check_circle:Icons.radio_button_unchecked),onTap:x.scheduled(d)?()=>s.toggle(x,d):null))]);}

class Stats extends StatelessWidget{const Stats({super.key});Widget build(BuildContext c){final done=s.habits.fold(0,(a,h)=>a+h.done.length);final best=s.habits.fold(0,(a,h)=>h.best()>a?h.best():a);final current=s.habits.fold(0,(a,h)=>h.current()>a?h.current():a);return ListView(padding:const EdgeInsets.all(16),children:[Text('Progress',style:Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),Wrap(spacing:10,runSpacing:10,children:[metric(c,'Habits','${s.habits.length}',Icons.checklist),metric(c,'Check-ins','$done',Icons.done_all),metric(c,'Current streak','$current',Icons.local_fire_department),metric(c,'Best streak','$best',Icons.emoji_events)]),const SizedBox(height:20),...s.habits.map((h)=>ListTile(leading:CircleAvatar(child:Text(h.icon)),title:Text(h.name),subtitle:Text('${h.done.length} check-ins • best ${h.best()} days'),trailing:Text('${h.current()}🔥')))];}}
Widget metric(BuildContext c,String a,String b,IconData i)=>SizedBox(width:MediaQuery.sizeOf(c).width/2-24,height:105,child:Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Icon(i),Text(b,style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),Text(a)]))));

class Profile extends StatelessWidget{const Profile({super.key});Widget build(BuildContext c){final done=s.habits.fold(0,(a,h)=>a+h.done.length);final best=s.habits.fold(0,(a,h)=>h.best()>a?h.best():a);final cur=s.habits.fold(0,(a,h)=>h.current()>a?h.current():a);return ListView(padding:const EdgeInsets.all(16),children:[Center(child:GestureDetector(onTap:()=>profileDialog(c),child:CircleAvatar(radius:42,backgroundImage:s.photo!=null?FileImage(File(s.photo!)):null,child:s.photo==null?const Icon(Icons.person,size:42):null))),const SizedBox(height:8),Center(child:Text(s.name.isEmpty?'Your profile':s.name,style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold))),TextButton(onPressed:()=>profileDialog(c),child:const Text('Edit profile')),Wrap(spacing:10,runSpacing:10,children:[metric(c,'Total habits','${s.habits.length}',Icons.checklist),metric(c,'Completions','$done',Icons.done_all),metric(c,'Current streak','$cur',Icons.local_fire_department),metric(c,'Best streak','$best',Icons.emoji_events)]),ListTile(title:const Text('Joined'),subtitle:Text(DateFormat('d MMMM yyyy').format(s.joined))),ListTile(title:const Text('Appearance'),subtitle:Text(s.theme.name),leading:const Icon(Icons.palette_outlined),onTap:()=>themeDialog(c)),ListTile(title:const Text('Achievements'),leading:const Icon(Icons.emoji_events_outlined),onTap:()=>achievements(c)),ListTile(title:const Text('Export CSV'),leading:const Icon(Icons.table_chart_outlined),onTap:()=>exportCsv(c)),ListTile(title:const Text('Backup JSON'),leading:const Icon(Icons.backup_outlined),onTap:()=>backup(c)),ListTile(title:const Text('Restore JSON'),leading:const Icon(Icons.restore),onTap:()=>restore(c))]);}}

Future<void> profileDialog(BuildContext c)async{final n=TextEditingController(text:s.name);String? ph=s.photo;await showDialog(context:c,builder:(d)=>StatefulBuilder(builder:(d,set)=>AlertDialog(title:const Text('Edit profile'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Name')),const SizedBox(height:10),OutlinedButton.icon(onPressed:()async{final x=await ImagePicker().pickImage(source:ImageSource.gallery,imageQuality:85);if(x!=null)set(()=>ph=x.path);},icon:const Icon(Icons.photo),label:const Text('Choose photo'))]),actions:[TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Cancel')),FilledButton(onPressed:()async{await s.setProfile(n.text,ph);if(d.mounted)Navigator.pop(d);},child:const Text('Save'))])));}

Future<void> habitDialog(BuildContext c,{Habit? habit})async{final n=TextEditingController(text:habit?.name??'');var icon=habit?.icon??'🎯';var days=List<int>.from(habit?.days??[1,2,3,4,5,6,7]);int? r=habit?.reminder;await showDialog(context:c,builder:(d)=>StatefulBuilder(builder:(d,set)=>AlertDialog(title:Text(habit==null?'Create habit':'Edit habit'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:n,decoration:const InputDecoration(labelText:'Habit name')),const SizedBox(height:10),DropdownButtonFormField<String>(initialValue:icon,decoration:const InputDecoration(labelText:'Icon'),items:const['🎯','📚','💧','🏃','🧘','💻','🛌','🥗','🎸','🧠'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v){if(v!=null)set(()=>icon=v);}),const SizedBox(height:10),const Align(alignment:Alignment.centerLeft,child:Text('Repeat on')),Wrap(spacing:4,children:List.generate(7,(i){final x=i+1;return FilterChip(label:Text(['M','T','W','T','F','S','S'][i]),selected:days.contains(x),onSelected:(v)=>set((){v?days.add(x):days.remove(x);days=days.toSet().toList();}));})),SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('One reminder'),subtitle:Text(r==null?'Off':'At ${clock(r!)}'),value:r!=null,onChanged:(v)async{if(!v){set(()=>r=null);return;}final t=await showTimePicker(context:d,initialTime:const TimeOfDay(hour:20,minute:0));if(t!=null)set(()=>r=t.hour*60+t.minute);} )])),actions:[if(habit!=null)TextButton(onPressed:()async{await s.remove(habit);if(d.mounted)Navigator.pop(d);},child:const Text('Delete')),TextButton(onPressed:()=>Navigator.pop(d),child:const Text('Cancel')),FilledButton(onPressed:n.text.trim().isEmpty||days.isEmpty?null:()async{habit==null?await s.add(n.text,icon,days,r):await s.edit(habit,n.text,icon,days,r);if(d.mounted)Navigator.pop(d);},child:Text(habit==null?'Create':'Save'))])));}

void themeDialog(BuildContext c)=>showDialog(context:c,builder:(d)=>SimpleDialog(title:const Text('Appearance'),children:ThemeMode.values.map((m)=>RadioListTile(value:m,groupValue:s.theme,title:Text(m.name[0].toUpperCase()+m.name.substring(1)),onChanged:(v){if(v!=null){s.setTheme(v);Navigator.pop(d);}})).toList()));
void achievements(BuildContext c){final done=s.habits.fold(0,(a,h)=>a+h.done.length);final best=s.habits.fold(0,(a,h)=>h.best()>a?h.best():a);showModalBottomSheet(context:c,builder:(_)=>ListView(padding:const EdgeInsets.all(20),children:[Text('Achievements',style:Theme.of(c).textTheme.headlineSmall),const SizedBox(height:10),ach('🌱','First Habit',s.habits.isNotEmpty),ach('🔥','7-day Streak',best>=7),ach('🚀','30-day Streak',best>=30),ach('💯','100 Check-ins',done>=100)]));}
Widget ach(String i,String t,bool ok)=>ListTile(leading:CircleAvatar(child:Text(i)),title:Text(t),trailing:Icon(ok?Icons.check_circle:Icons.lock_outline));
Future<void> exportCsv(BuildContext c)async{final rows=<List<dynamic>>[['Habit','Date','Day']];for(final h in s.habits)for(final d in h.done.map(DateTime.parse))rows.add([h.name,key(d),DateFormat('EEEE').format(d)]);final f=File('${(await getTemporaryDirectory()).path}/habitflow.csv')..writeAsStringSync(const ListToCsvConverter().convert(rows));if(c.mounted)await Share.shareXFiles([XFile(f.path)],text:'HabitFlow CSV export');}
Future<void> backup(BuildContext c)async{final f=File('${(await getTemporaryDirectory()).path}/habitflow_backup.json')..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(s.backup()));if(c.mounted)await Share.shareXFiles([XFile(f.path)],text:'HabitFlow backup');}
Future<void> restore(BuildContext c)async{final x=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);if(x?.files.single.path==null)return;try{await s.restore(jsonDecode(await File(x!.files.single.path!).readAsString()));if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Backup restored')));}catch(_){if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Invalid backup')));}}
