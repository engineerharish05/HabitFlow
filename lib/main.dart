import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.load();
  runApp(App(store));
}

String dateKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

class Habit {
  Habit({required this.id, required this.name, required this.icon, required this.days, Set<String>? done})
      : doneDates = done ?? <String>{};
  String id, name, icon;
  List<int> days;
  Set<String> doneDates;
  bool scheduled(DateTime d) => days.contains(d.weekday);
  bool done(DateTime d) => doneDates.contains(dateKey(d));
  int bestStreak() {
    if (doneDates.isEmpty) return 0;
    final ds = doneDates.map(DateTime.parse).toList()..sort();
    int best = 0, run = 0;
    DateTime? prev;
    for (final d in ds) {
      run = prev != null && d.difference(prev).inDays == 1 ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }
  int streak() {
    var d = onlyDate(DateTime.now());
    if (!done(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    for (var i = 0; i < 366; i++) {
      while (!scheduled(d)) {
        d = d.subtract(const Duration(days: 1));
      }
      if (!done(d)) break;
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }
  Map<String,dynamic> json() => {'id':id,'name':name,'icon':icon,'days':days,'done':doneDates.toList()};
  factory Habit.fromJson(Map<String,dynamic> j) => Habit(
    id: j['id'] as String, name: j['name'] as String, icon: (j['icon'] as String?) ?? '🎯',
    days: List<int>.from(j['days'] ?? [1,2,3,4,5,6,7]),
    done: Set<String>.from(j['done'] ?? []),
  );
}

class Store extends ChangeNotifier {
  final habits = <Habit>[];
  SharedPreferences? p;
  String name = '';
  String? image;
  ThemeMode mode = ThemeMode.system;
  bool onboarded = false;

  Future<void> load() async {
    p = await SharedPreferences.getInstance();
    final raw = p!.getString('habits');
    if (raw != null) habits.addAll((jsonDecode(raw) as List).map((e) => Habit.fromJson(Map<String,dynamic>.from(e))));
    name = p!.getString('name') ?? '';
    image = p!.getString('image');
    onboarded = p!.getBool('onboarded') ?? false;
    mode = ThemeMode.values.firstWhere((x) => x.name == (p!.getString('mode') ?? 'system'), orElse: () => ThemeMode.system);
  }
  Future<void> save() async {
    await p?.setString('habits', jsonEncode(habits.map((h) => h.json()).toList()));
    notifyListeners();
  }
  Future<void> toggle(Habit h, DateTime d) async {
    final k = dateKey(d);
    if (h.doneDates.contains(k)) {
      h.doneDates.remove(k);
    } else {
      h.doneDates.add(k);
      HapticFeedback.mediumImpact();
    }
    await save();
  }
  Future<void> add(String n,String i,List<int>d) async { habits.add(Habit(id:DateTime.now().microsecondsSinceEpoch.toString(),name:n.trim(),icon:i,days:d)); await save(); }
  Future<void> edit(Habit h,String n,String i,List<int>d) async { h.name=n.trim(); h.icon=i; h.days=d; await save(); }
  Future<void> remove(Habit h) async { habits.remove(h); await save(); }
  Future<void> profile(String n,String? img) async {
    name=n.trim(); image=img; await p?.setString('name',name);
    if(img == null) { await p?.remove('image'); } else { await p?.setString('image',img); }
    notifyListeners();
  }
  Future<void> setMode(ThemeMode m) async { mode=m; await p?.setString('mode',m.name); notifyListeners(); }
  Future<void> finish() async { onboarded=true; await p?.setBool('onboarded',true); notifyListeners(); }
  Map<String,dynamic> backup() => {'version':1,'name':name,'mode':mode.name,'habits':habits.map((h)=>h.json()).toList()};
  Future<void> restore(String raw) async {
    final j=Map<String,dynamic>.from(jsonDecode(raw));
    final restored=(j['habits'] as List?) ?? const [];
    habits..clear()..addAll(restored.map((e)=>Habit.fromJson(Map<String,dynamic>.from(e))));
    name=(j['name'] as String?) ?? name;
    final savedMode=j['mode'] as String?;
    if(savedMode != null) mode=ThemeMode.values.firstWhere((x)=>x.name==savedMode,orElse:()=>ThemeMode.system);
    await p?.setString('name',name); await p?.setString('mode',mode.name); await save();
  }
}

class App extends StatelessWidget {
  const App(this.store,{super.key});
  final Store store;
  @override Widget build(BuildContext context) => AnimatedBuilder(
    animation:store,builder:(_,__) => MaterialApp(
      debugShowCheckedModeBanner:false,title:'HabitFlow',themeMode:store.mode,
      theme:theme(Brightness.light),darkTheme:theme(Brightness.dark),
      home:store.onboarded ? Shell(store) : Intro(store),
    ));
}
ThemeData theme(Brightness b) => ThemeData(
  useMaterial3:true,brightness:b,colorSchemeSeed:const Color(0xFF7656E8),
  scaffoldBackgroundColor:b==Brightness.dark ? const Color(0xFF101014) : const Color(0xFFF7F6FA),
  cardTheme:CardThemeData(elevation:0,margin:EdgeInsets.zero,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),
);

class Intro extends StatelessWidget {
  const Intro(this.store,{super.key}); final Store store;
  @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:Center(child:Padding(
    padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
      const CircleAvatar(radius:50,child:Icon(Icons.auto_graph,size:46)),
      const SizedBox(height:24),Text('HabitFlow',style:Theme.of(c).textTheme.headlineLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:8),const Text('Build your future with today’s habit.',textAlign:TextAlign.center),
      const SizedBox(height:12),const Text('Track habits, streaks, progress and consistency.',textAlign:TextAlign.center),
      const SizedBox(height:30),SizedBox(width:double.infinity,child:FilledButton(onPressed:store.finish,child:const Text('Get started'))),
    ]))));
}

class Shell extends StatefulWidget {
  const Shell(this.store,{super.key}); final Store store;
  @override State<Shell> createState()=>_ShellState();
}
class _ShellState extends State<Shell> {
  int tab=0;
  @override Widget build(BuildContext c){
    final pages=[Today(store:widget.store),Calendar(store:widget.store),Stats(store:widget.store),Profile(store:widget.store)];
    return Scaffold(body:SafeArea(child:pages[tab]),
      floatingActionButton:tab==0?FloatingActionButton.extended(onPressed:()=>editHabit(c,widget.store),icon:const Icon(Icons.add),label:const Text('Habit')):null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
        NavigationDestination(icon:Icon(Icons.today_outlined),selectedIcon:Icon(Icons.today),label:'Today'),
        NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendar'),
        NavigationDestination(icon:Icon(Icons.insights_outlined),selectedIcon:Icon(Icons.insights),label:'Stats'),
        NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile'),
      ]));
  }
}

class Today extends StatelessWidget {
  const Today({super.key,required this.store}); final Store store;
  @override Widget build(BuildContext c){
    final d=onlyDate(DateTime.now()), list=store.habits.where((h)=>h.scheduled(d)).toList();
    final done=list.where((h)=>h.done(d)).length, progress=list.isEmpty?0.0:done/list.length;
    final who=store.name.isEmpty?'there':store.name;
    return ListView(padding:const EdgeInsets.fromLTRB(20,22,20,100),children:[
      Text('Good day, $who 👋'),const SizedBox(height:5),
      Text('Build your future, one habit at a time.',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:5),Text(DateFormat('EEEE, d MMMM').format(d)),
      const SizedBox(height:20),Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[
        SizedBox(width:76,height:76,child:Stack(alignment:Alignment.center,children:[CircularProgressIndicator(value:progress,strokeWidth:8),Text('$done/${list.length}',style:const TextStyle(fontWeight:FontWeight.bold))])),
        const SizedBox(width:18),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(progress==1&&list.isNotEmpty?'Perfect day! 🎉':"Today's progress",style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:5),Text('${(progress*100).round()}% complete'),
        ])),
      ]))),const SizedBox(height:22),
      Text("Today's habits",style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:10),
      if(list.isEmpty) const Card(child:Padding(padding:EdgeInsets.all(28),child:Column(children:[Text('🌱',style:TextStyle(fontSize:42)),SizedBox(height:8),Text('No habits scheduled today'),Text('Add one small habit and start.',textAlign:TextAlign.center)])))
      else ...list.map((h)=>HabitTile(h,store,d)),
    ]);
  }
}
class HabitTile extends StatelessWidget {
  const HabitTile(this.h,this.store,this.d,{super.key}); final Habit h; final Store store; final DateTime d;
  @override Widget build(BuildContext c){final done=h.done(d);return Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(
    borderRadius:BorderRadius.circular(18),onTap:()=>store.toggle(h,d),onLongPress:()=>editHabit(c,store,habit:h),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:15,vertical:14),child:Row(children:[
      CircleAvatar(radius:24,child:Text(h.icon,style:const TextStyle(fontSize:22))),const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(h.name,style:TextStyle(fontWeight:FontWeight.w600,decoration:done?TextDecoration.lineThrough:null)),
        const SizedBox(height:4),Text('🔥 ${h.streak()} day streak · 🏆 ${h.bestStreak()} best',style:const TextStyle(fontSize:12)),
      ])),Icon(done?Icons.check_circle:Icons.circle_outlined,size:32,color:done?Theme.of(c).colorScheme.primary:Colors.grey),
    ]))));
  }
}

class Calendar extends StatefulWidget {
  const Calendar({super.key,required this.store}); final Store store;
  @override State<Calendar> createState()=>_CalendarState();
}
class _CalendarState extends State<Calendar>{
  Habit? selected; DateTime month=onlyDate(DateTime.now());
  @override Widget build(BuildContext c){
    final first=DateTime(month.year,month.month,1),count=DateTime(month.year,month.month+1,0).day,offset=first.weekday-1;
    final hs=selected==null?widget.store.habits:<Habit>[selected!];
    return ListView(padding:const EdgeInsets.all(20),children:[
      Text('Calendar',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:4),const Text('See your consistency at a glance.'),const SizedBox(height:18),
      DropdownButtonFormField<Habit?>(initialValue:selected,decoration:const InputDecoration(labelText:'Habit'),items:[
        const DropdownMenuItem<Habit?>(value:null,child:Text('All habits')),
        ...widget.store.habits.map((h)=>DropdownMenuItem<Habit?>(value:h,child:Text('${h.icon} ${h.name}'))),
      ],onChanged:(v)=>setState(()=>selected=v)),const SizedBox(height:15),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month-1,1)),icon:const Icon(Icons.chevron_left)),
          Text(DateFormat('MMMM yyyy').format(month),style:const TextStyle(fontWeight:FontWeight.bold)),
          IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month+1,1)),icon:const Icon(Icons.chevron_right)),
        ]),
        Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:['M','T','W','T','F','S','S'].map((x)=>SizedBox(width:34,child:Text(x,textAlign:TextAlign.center))).toList()),
        const SizedBox(height:8),
        GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:offset+count,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,mainAxisSpacing:7,crossAxisSpacing:5),
          itemBuilder:(_,i){if(i<offset)return const SizedBox();final d=DateTime(month.year,month.month,i-offset+1);
            final scheduled=hs.any((h)=>h.scheduled(d)), complete=scheduled&&hs.where((h)=>h.scheduled(d)).every((h)=>h.done(d));
            return Container(decoration:BoxDecoration(shape:BoxShape.circle,color:complete?Theme.of(c).colorScheme.primary:scheduled?Theme.of(c).colorScheme.primary.withValues(alpha:.12):null),alignment:Alignment.center,child:Text('${d.day}',style:TextStyle(color:complete?Colors.white:null,fontWeight:complete?FontWeight.bold:null)));
          }),
      ]))),
    ]);
  }
}

class Stats extends StatelessWidget {
  const Stats({super.key,required this.store}); final Store store;
  @override Widget build(BuildContext c){
    final now=onlyDate(DateTime.now());int completions=0,best=0,current=0,scheduled=0,done=0;
    for(final h in store.habits){completions+=h.doneDates.length;if(h.bestStreak()>best)best=h.bestStreak();if(h.streak()>current)current=h.streak();for(var i=0;i<7;i++){final d=now.subtract(Duration(days:i));if(h.scheduled(d)){scheduled++;if(h.done(d))done++;}}}
    final rate=scheduled==0?0.0:done/scheduled;
    return ListView(padding:const EdgeInsets.all(20),children:[
      Text('Statistics',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:5),const Text('Measure consistency, not perfection.'),const SizedBox(height:20),
      Row(children:[StatCard('🔥','$current','Current'),const SizedBox(width:8),StatCard('🏆','$best','Best'),const SizedBox(width:8),StatCard('✓','$completions','Total')]),const SizedBox(height:15),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('7-day completion rate',style:TextStyle(fontWeight:FontWeight.bold)),const SizedBox(height:10),LinearProgressIndicator(value:rate,minHeight:9)])),const SizedBox(width:15),Text('${(rate*100).round()}%')])))
    ]);
  }
}
class StatCard extends StatelessWidget {
  const StatCard(this.icon,this.value,this.label,{super.key}); final String icon,value,label;
  @override Widget build(BuildContext c)=>Expanded(child:Card(child:Padding(padding:const EdgeInsets.symmetric(vertical:15),child:Column(children:[Text(icon),const SizedBox(height:5),Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(label,style:const TextStyle(fontSize:11))]))));
}

class Profile extends StatelessWidget {
  const Profile({super.key,required this.store}); final Store store;
  Future<void> profileEditor(BuildContext c) async {
    final n=TextEditingController(text:store.name);String? img=store.image;final picker=ImagePicker();
    await showModalBottomSheet<void>(context:c,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>Padding(
      padding:EdgeInsets.fromLTRB(20,10,20,MediaQuery.of(ctx).viewInsets.bottom+20),child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Edit profile',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:18),
        GestureDetector(onTap:()async{final x=await picker.pickImage(source:ImageSource.gallery,imageQuality:85);if(x!=null)set(()=>img=x.path);},child:CircleAvatar(radius:44,backgroundImage:img==null?null:FileImage(File(img!)),child:img==null?const Icon(Icons.add_a_photo):null)),
        const SizedBox(height:15),TextField(controller:n,decoration:const InputDecoration(labelText:'Your name')),const SizedBox(height:15),
        SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{await store.profile(n.text,img);if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Save'))),
      ]))));
  }
  Future<void> csvExport() async {
    final rows=<List<dynamic>>[['Date','Habit','Scheduled','Completed','Current Streak','Best Streak']];
    for(final h in store.habits){for(var i=0;i<365;i++){final d=onlyDate(DateTime.now().subtract(Duration(days:i)));if(h.scheduled(d)||h.done(d)){rows.add([dateKey(d),h.name,h.scheduled(d),h.done(d),h.streak(),h.bestStreak()]);}}}
    final dir=await getTemporaryDirectory(),f=File('${dir.path}/habitflow.csv');await f.writeAsString(const ListToCsvConverter().convert(rows));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow CSV');
  }
  Future<void> backup() async {final dir=await getTemporaryDirectory(),f=File('${dir.path}/habitflow_backup.json');await f.writeAsString(jsonEncode(store.backup()));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow backup');}
  Future<void> restore(BuildContext c) async {
    final r=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json']);if(r==null||r.files.single.path==null)return;
    await store.restore(await File(r.files.single.path!).readAsString());if(c.mounted)ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content:Text('Backup restored')));
  }
  @override Widget build(BuildContext c){
    final total=store.habits.fold<int>(0,(s,h)=>s+h.doneDates.length),best=store.habits.fold<int>(0,(m,h)=>h.bestStreak()>m?h.bestStreak():m);
    return ListView(padding:const EdgeInsets.fromLTRB(20,24,20,40),children:[
      Text('Profile',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:18),
      Card(child:ListTile(contentPadding:const EdgeInsets.all(18),leading:CircleAvatar(radius:34,backgroundImage:store.image==null?null:FileImage(File(store.image!)),child:store.image==null?Text(store.name.isEmpty?'?':store.name[0].toUpperCase(),style:const TextStyle(fontSize:25)):null),title:Text(store.name.isEmpty?'Your name':store.name,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:const Text('Build your future with today’s habit.'),trailing:IconButton(onPressed:()=>profileEditor(c),icon:const Icon(Icons.edit_outlined)))),
      const SizedBox(height:12),Row(children:[StatCard('🔥','${store.habits.length}','Habits'),const SizedBox(width:8),StatCard('✓','$total','Completions'),const SizedBox(width:8),StatCard('🏆','$best','Best')]),const SizedBox(height:20),
      Card(child:Column(children:[
        ListTile(leading:const Icon(Icons.emoji_events_outlined),title:const Text('Achievements'),onTap:()=>achievements(c)),
        ListTile(leading:const Icon(Icons.file_download_outlined),title:const Text('Export CSV'),onTap:csvExport),
        ListTile(leading:const Icon(Icons.backup_outlined),title:const Text('Backup JSON'),onTap:backup),
        ListTile(leading:const Icon(Icons.restore_outlined),title:const Text('Restore JSON'),onTap:()=>restore(c)),
        ListTile(leading:const Icon(Icons.dark_mode_outlined),title:const Text('Appearance'),subtitle:Text(store.mode.name),onTap:()=>themeDialog(c)),
      ])),
    ]);
  }
  void themeDialog(BuildContext c)=>showDialog<void>(context:c,builder:(x)=>SimpleDialog(title:const Text('Appearance'),children:ThemeMode.values.map((m)=>SimpleDialogOption(onPressed:(){store.setMode(m);Navigator.pop(x);},child:Row(children:[Icon(store.mode==m?Icons.radio_button_checked:Icons.radio_button_unchecked),const SizedBox(width:12),Text(m.name)])).toList()));
  void achievements(BuildContext c){final done=store.habits.fold<int>(0,(s,h)=>s+h.doneDates.length),best=store.habits.fold<int>(0,(m,h)=>h.bestStreak()>m?h.bestStreak():m);showModalBottomSheet<void>(context:c,showDragHandle:true,builder:(_)=>ListView(padding:const EdgeInsets.all(20),children:[const Text('Achievements',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold)),Achievement('🌱','First Habit',store.habits.isNotEmpty),Achievement('🔥','7-day Streak',best>=7),Achievement('🚀','30-day Streak',best>=30),Achievement('💯','100 Check-ins',done>=100)]));}
}
class Achievement extends StatelessWidget{const Achievement(this.icon,this.title,this.ok,{super.key});final String icon,title;final bool ok;@override Widget build(BuildContext c)=>ListTile(leading:CircleAvatar(child:Text(icon)),title:Text(title),trailing:Icon(ok?Icons.check_circle:Icons.lock_outline,color:ok?Theme.of(c).colorScheme.primary:Colors.grey));}

Future<void> editHabit(BuildContext c,Store s,{Habit? habit}) async {
  final n=TextEditingController(text:habit?.name??'');var icon=habit?.icon??'🎯';var days=List<int>.from(habit?.days??[1,2,3,4,5,6,7]);const icons=['🎯','📚','💧','🏃','🧘','💻','🛌','🥗','🎸','🧠'];
  await showModalBottomSheet<void>(context:c,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>Padding(
    padding:EdgeInsets.fromLTRB(20,10,20,MediaQuery.of(ctx).viewInsets.bottom+20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(habit==null?'Create habit':'Edit habit',style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold)),const SizedBox(height:15),
      TextField(controller:n,decoration:const InputDecoration(labelText:'Habit name')),const SizedBox(height:15),const Text('Icon',style:TextStyle(fontWeight:FontWeight.bold)),
      Wrap(spacing:6,children:icons.map((x)=>ChoiceChip(label:Text(x),selected:icon==x,onSelected:(_)=>set(()=>icon=x))).toList()),const SizedBox(height:15),
      const Text('Repeat on',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,children:List.generate(7,(i){final d=i+1;const labels=['M','T','W','T','F','S','S'];return FilterChip(label:Text(labels[i]),selected:days.contains(d),onSelected:(v)=>set(()=>v?days.add(d):days.remove(d));})),
      const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton(onPressed:n.text.trim().isEmpty||days.isEmpty?null:()async{if(habit==null){await s.add(n.text,icon,days);}else{await s.edit(habit,n.text,icon,days);}if(ctx.mounted)Navigator.pop(ctx);},child:Text(habit==null?'Create habit':'Save'))),
      if(habit!=null)SizedBox(width:double.infinity,child:TextButton.icon(onPressed:()async{await s.remove(habit);if(ctx.mounted)Navigator.pop(ctx);},icon:const Icon(Icons.delete_outline),label:const Text('Delete habit'))),
    ]))));
}
