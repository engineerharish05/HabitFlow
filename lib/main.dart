import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = HabitStore();
  await store.load();
  runApp(HabitFlowApp(store: store));
}

String dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
DateTime dateOnly(DateTime d) => DateTime(d.year,d.month,d.day);

class Habit {
  String id, name, emoji;
  List<int> days;
  Set<String> completions;
  Habit({required this.id,required this.name,required this.emoji,required this.days,Set<String>? completions})
      : completions=completions??{};
  bool scheduled(DateTime d)=>days.contains(d.weekday);
  bool done(DateTime d)=>completions.contains(dayKey(d));
  int currentStreak(){
    DateTime d=dateOnly(DateTime.now());
    int count=0;
    // For today: if incomplete, start from previous scheduled day.
    if(!done(d)) d=d.subtract(const Duration(days:1));
    while(true){
      while(!scheduled(d)) d=d.subtract(const Duration(days:1));
      if(!done(d)) break;
      count++;
      d=d.subtract(const Duration(days:1));
    }
    return count;
  }
  int longestStreak(){
    if(completions.isEmpty)return 0;
    final ds=completions.map(DateTime.parse).toList()..sort();
    int best=0,run=0; DateTime? prev;
    for(final d in ds){
      if(prev!=null){
        final gap=d.difference(prev!).inDays;
        if(gap==1) run++; else run=1;
      } else run=1;
      best=best<run?run:best; prev=d;
    }
    return best;
  }
  Map<String,dynamic> toJson()=>{'id':id,'name':name,'emoji':emoji,'days':days,'completions':completions.toList()};
  factory Habit.fromJson(Map<String,dynamic> j)=>Habit(id:j['id'],name:j['name'],emoji:j['emoji']??'🎯',
    days:List<int>.from(j['days']??[1,2,3,4,5,6,7]),completions:Set<String>.from(j['completions']??[]));
}

class HabitStore extends ChangeNotifier {
  final habits=<Habit>[];
  String profileName='';
  String? profileImage;
  ThemeMode themeMode=ThemeMode.system;
  SharedPreferences? prefs;
  Future<void> load() async {
    prefs=await SharedPreferences.getInstance();
    final raw=prefs!.getString('habits');
    if(raw!=null) habits.addAll((jsonDecode(raw) as List).map((e)=>Habit.fromJson(e)));
    profileName=prefs!.getString('profileName')??'';
    profileImage=prefs!.getString('profileImage');
    themeMode=ThemeMode.values.firstWhere((e)=>e.name==(prefs!.getString('theme')??'system'),orElse:()=>ThemeMode.system);
    notifyListeners();
  }
  Future<void> save() async {
    await prefs?.setString('habits',jsonEncode(habits.map((h)=>h.toJson()).toList()));
    notifyListeners();
  }
  Future<void> add(String n,String e,List<int>d)async{habits.add(Habit(id:DateTime.now().microsecondsSinceEpoch.toString(),name:n.trim(),emoji:e,days:d));await save();}
  Future<void> update(Habit h,String n,String e,List<int>d)async{h.name=n.trim();h.emoji=e;h.days=d;await save();}
  Future<void> remove(Habit h)async{habits.remove(h);await save();}
  Future<void> toggle(Habit h,DateTime d)async{final k=dayKey(d);h.completions.contains(k)?h.completions.remove(k):h.completions.add(k);await save();}
  Future<void> setProfile(String n,String? image)async{profileName=n.trim();profileImage=image;await prefs?.setString('profileName',profileName); if(image==null)await prefs?.remove('profileImage');else await prefs?.setString('profileImage',image);notifyListeners();}
  Future<void> setTheme(ThemeMode m)async{themeMode=m;await prefs?.setString('theme',m.name);notifyListeners();}
  Future<void> importJson(String raw)async{
    final j=jsonDecode(raw) as Map<String,dynamic>;
    habits..clear()..addAll((j['habits'] as List).map((e)=>Habit.fromJson(e)));
    profileName=j['profileName']??profileName;
    await prefs?.setString('profileName',profileName);
    await save();
  }
  Map<String,dynamic> backup()=>{'version':1,'profileName':profileName,'habits':habits.map((h)=>h.toJson()).toList()};
}

class HabitFlowApp extends StatelessWidget {
  final HabitStore store;
  const HabitFlowApp({super.key,required this.store});
  @override Widget build(BuildContext context)=>AnimatedBuilder(
    animation:store,builder:(_,__)=>MaterialApp(
      debugShowCheckedModeBanner:false,title:'HabitFlow',themeMode:store.themeMode,
      theme:appTheme(Brightness.light),darkTheme:appTheme(Brightness.dark),
      home:Home(store:store),
    ));
}
ThemeData appTheme(Brightness b){
  final dark=b==Brightness.dark;
  return ThemeData(
    useMaterial3:true,brightness:b,colorSchemeSeed:const Color(0xFF7656E8),
    scaffoldBackgroundColor:dark?const Color(0xFF101014):const Color(0xFFF7F6FA),
    cardTheme:CardThemeData(elevation:0,margin:EdgeInsets.zero,color:dark?const Color(0xFF1A1A20):Colors.white,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18))),
    inputDecorationTheme:const InputDecorationTheme(border:OutlineInputBorder(),filled:true),
  );
}

class Home extends StatefulWidget{
  final HabitStore store; const Home({super.key,required this.store});
  @override State<Home> createState()=>_HomeState();
}
class _HomeState extends State<Home>{
  int tab=0;
  @override Widget build(BuildContext c){
    final pages=[Today(store:widget.store),CalendarPage(store:widget.store),Stats(store:widget.store),Profile(store:widget.store)];
    return Scaffold(body:SafeArea(child:pages[tab]),
      floatingActionButton:tab==0?FloatingActionButton.extended(onPressed:()=>editor(c,widget.store),icon:const Icon(Icons.add),label:const Text('Habit')):null,
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i)=>setState(()=>tab=i),destinations:const[
        NavigationDestination(icon:Icon(Icons.today_outlined),selectedIcon:Icon(Icons.today),label:'Today'),
        NavigationDestination(icon:Icon(Icons.calendar_month_outlined),selectedIcon:Icon(Icons.calendar_month),label:'Calendar'),
        NavigationDestination(icon:Icon(Icons.insights_outlined),selectedIcon:Icon(Icons.insights),label:'Stats'),
        NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Profile'),
      ]));
  }
}

class Today extends StatelessWidget{
  final HabitStore store; const Today({super.key,required this.store});
  @override Widget build(BuildContext c){
    final now=dateOnly(DateTime.now()), active=store.habits.where((h)=>h.scheduled(now)).toList();
    final done=active.where((h)=>h.done(now)).length; final p=active.isEmpty?0:done/active.length;
    final upcoming=store.habits.where((h)=>!h.scheduled(now)).toList();
    final name=store.profileName.isEmpty?'there':store.profileName;
    return ListView(padding:const EdgeInsets.fromLTRB(20,22,20,100),children:[
      Text('Good ${now.hour<12?'morning':now.hour<17?'afternoon':'evening'}, $name 👋',style:Theme.of(c).textTheme.titleMedium),
      const SizedBox(height:5),Text('Build your future, one habit at a time.',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:5),Text(DateFormat('EEEE, d MMMM').format(now),style:TextStyle(color:Colors.grey.shade600)),
      const SizedBox(height:20),
      Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[
        SizedBox(width:76,height:76,child:Stack(alignment:Alignment.center,children:[CircularProgressIndicator(value:p,strokeWidth:8),Text('$done/${active.length}',style:const TextStyle(fontWeight:FontWeight.bold))])),
        const SizedBox(width:18),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(p==1&&active.isNotEmpty?'Perfect day! 🎉':"Today's progress",style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:5),Text(active.isEmpty?'Start with one small habit.':'${(p*100).round()}% complete'),
        ]))
      ]))),
      const SizedBox(height:22),Text("Today's habits",style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:10),
      if(active.isEmpty) Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(children:const[Text('🌱',style:TextStyle(fontSize:42)),SizedBox(height:10),Text('No habits scheduled today',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),SizedBox(height:5),Text('Add a habit and start building your future.',textAlign:TextAlign.center)])))
      else ...active.map((h)=>HabitTile(h:h,store:store,date:now)),
      if(upcoming.isNotEmpty)...[const SizedBox(height:20),Text('Upcoming',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:10),...upcoming.take(4).map((h)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:CircleAvatar(child:Text(h.emoji)),title:Text(h.name),subtitle:Text('Scheduled ${h.days.map((d)=>['','Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d]).join(', ')}'))))]
    ]);
  }
}
class HabitTile extends StatelessWidget{
  final Habit h;final HabitStore store;final DateTime date;
  const HabitTile({super.key,required this.h,required this.store,required this.date});
  @override Widget build(BuildContext c){final done=h.done(date);return Card(margin:const EdgeInsets.only(bottom:9),child:InkWell(
    borderRadius:BorderRadius.circular(18),onTap:()=>store.toggle(h,date),onLongPress:()=>editor(c,store,habit:h),
    child:Padding(padding:const EdgeInsets.symmetric(horizontal:15,vertical:14),child:Row(children:[
      CircleAvatar(radius:24,child:Text(h.emoji,style:const TextStyle(fontSize:22))),const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(h.name,style:TextStyle(fontWeight:FontWeight.w600,fontSize:16,decoration:done?TextDecoration.lineThrough:null)),
        const SizedBox(height:4),Text('🔥 ${h.currentStreak()} day streak · 🏆 ${h.longestStreak()} best',style:TextStyle(fontSize:12,color:Colors.grey))
      ])),
      Icon(done?Icons.check_circle:Icons.circle_outlined,size:32,color:done?Theme.of(c).colorScheme.primary:Colors.grey)
    ]))));
  }
}

class CalendarPage extends StatefulWidget{final HabitStore store;const CalendarPage({super.key,required this.store});@override State<CalendarPage> createState()=>_CalState();}
class _CalState extends State<CalendarPage>{
  Habit? selected;
  DateTime month=dateOnly(DateTime.now());
  @override Widget build(BuildContext c){
    final h=selected; final first=DateTime(month.year,month.month,1),days=DateTime(month.year,month.month+1,0).day,offset=first.weekday-1;
    return ListView(padding:const EdgeInsets.all(20),children:[
      Text('Calendar',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),
      const SizedBox(height:4),Text('See your consistency at a glance.',style:TextStyle(color:Colors.grey)),
      const SizedBox(height:18),
      DropdownButtonFormField<Habit?>(value:h,decoration:const InputDecoration(labelText:'Habit'),items:[
        const DropdownMenuItem(value:null,child:Text('All habits')),
        ...widget.store.habits.map((x)=>DropdownMenuItem(value:x,child:Text('${x.emoji} ${x.name}')))
      ],onChanged:(v)=>setState(()=>selected=v)),
      const SizedBox(height:15),
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month-1,1)),icon:const Icon(Icons.chevron_left)),
          Text(DateFormat('MMMM yyyy').format(month),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
          IconButton(onPressed:()=>setState(()=>month=DateTime(month.year,month.month+1,1)),icon:const Icon(Icons.chevron_right)),
        ]),
        Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:['M','T','W','T','F','S','S'].map((x)=>SizedBox(width:34,child:Text(x,textAlign:TextAlign.center,style:const TextStyle(fontWeight:FontWeight.bold))).toList()),
        const SizedBox(height:8),
        GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:7,mainAxisSpacing:7,crossAxisSpacing:5),
          itemCount:offset+days,itemBuilder:(_,i){if(i<offset)return const SizedBox();final d=DateTime(month.year,month.month,i-offset+1);
            final relevant=h!=null?[h]:widget.store.habits; final scheduled=relevant.any((x)=>x.scheduled(d));final complete=scheduled&&relevant.where((x)=>x.scheduled(d)).every((x)=>x.done(d));
            return Container(decoration:BoxDecoration(shape:BoxShape.circle,color:complete?Theme.of(c).colorScheme.primary.withOpacity(.9):scheduled?Theme.of(c).colorScheme.primary.withOpacity(.10):null),alignment:Alignment.center,child:Text('${d.day}',style:TextStyle(fontWeight:complete?FontWeight.bold:null,color:complete?Colors.white:null)));
          })
      ]))),
      const SizedBox(height:12),const Text('Tip: select a habit to inspect its individual history.',style:TextStyle(color:Colors.grey))
    ]);
  }
}

class Stats extends StatelessWidget{final HabitStore store;const Stats({super.key,required this.store});
  @override Widget build(BuildContext c){
    final now=dateOnly(DateTime.now());int scheduled=0,completed=0,total=0,best=0,current=0;
    for(final h in store.habits){total+=h.completions.length;best=best<h.longestStreak()?h.longestStreak():best;current=current<h.currentStreak()?h.currentStreak():current;for(int i=0;i<7;i++){final d=now.subtract(Duration(days:i));if(h.scheduled(d)){scheduled++;if(h.done(d))completed++;}}}
    final rate=scheduled==0?0:(completed/scheduled*100).round();
    return ListView(padding:const EdgeInsets.all(20),children:[
      Text('Statistics',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:5),Text('Measure consistency, not perfection.',style:TextStyle(color:Colors.grey)),const SizedBox(height:20),
      Row(children:[Stat('🔥','$current','Current'),const SizedBox(width:8),Stat('🏆','$best','Best'),const SizedBox(width:8),Stat('📈','$rate%','7-day')]),const SizedBox(height:20),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Last 7 days',style:TextStyle(fontWeight:FontWeight.bold,fontSize:17)),const SizedBox(height:14),
        ...List.generate(7,(i){final d=now.subtract(Duration(days:6-i));final s=store.habits.where((h)=>h.scheduled(d)).length,done=store.habits.where((h)=>h.scheduled(d)&&h.done(d)).length;final p=s==0?0:done/s;return Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[SizedBox(width:38,child:Text(DateFormat('EEE').format(d))),Expanded(child:LinearProgressIndicator(value:p,minHeight:9,borderRadius:BorderRadius.circular(9))),const SizedBox(width:8),Text('$done/$s')]));})
      ]))),const SizedBox(height:20),Text('Your habits',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:10),
      ...store.habits.map((h)=>Card(margin:const EdgeInsets.only(bottom:8),child:ListTile(leading:Text(h.emoji,style:const TextStyle(fontSize:25)),title:Text(h.name),subtitle:Text('${h.completions.length} completed · ${h.longestStreak()} best streak'),trailing:Text('🔥 ${h.currentStreak()}')))
    ]);
  }}
class Stat extends StatelessWidget{final String icon,value,label;const Stat(this.icon,this.value,this.label,{super.key});@override Widget build(BuildContext c)=>Expanded(child:Card(child:Padding(padding:const EdgeInsets.symmetric(vertical:16),child:Column(children:[Text(icon),const SizedBox(height:5),Text(value,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(label,style:const TextStyle(fontSize:11,color:Colors.grey))])));}

class Profile extends StatelessWidget{final HabitStore store;const Profile({super.key,required this.store});
  Future<void> edit(BuildContext c)async{final name=TextEditingController(text:store.profileName);final pick=ImagePicker();String? img=store.profileImage;
    await showModalBottomSheet(context:c,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>Padding(padding:EdgeInsets.fromLTRB(20,10,20,MediaQuery.of(ctx).viewInsets.bottom+20),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text('Edit profile',style:Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:18),
      GestureDetector(onTap:()async{final x=await pick.pickImage(source:ImageSource.gallery,imageQuality:85);if(x!=null)set(()=>img=x.path);},child:CircleAvatar(radius:44,backgroundImage:img!=null?FileImage(File(img!)):null,child:img==null?const Icon(Icons.add_a_photo,size:28):null)),
      const SizedBox(height:15),TextField(controller:name,decoration:const InputDecoration(labelText:'Your name')),
      const SizedBox(height:15),Row(children:[Expanded(child:FilledButton(onPressed:()async{await store.setProfile(name.text,img);if(ctx.mounted)Navigator.pop(ctx);},child:const Text('Save'))),const SizedBox(width:8),if(img!=null)IconButton(onPressed:() => set(()=>img=null),icon:const Icon(Icons.delete_outline))])
    ]))));
  }
  Future<void> exportCsv(BuildContext c)async{
    final rows=<List<dynamic>>[['Date','Habit','Scheduled','Completed','Current Streak','Longest Streak']];
    for(final h in store.habits){final dates=<String>{...h.completions};for(int i=0;i<365;i++){final d=dateOnly(DateTime.now().subtract(Duration(days:i)));if(h.scheduled(d)||dates.contains(dayKey(d)))rows.add([dayKey(d),h.name,h.scheduled(d),h.done(d),h.currentStreak(),h.longestStreak()]);}}
    final dir=await getTemporaryDirectory();final f=File('${dir.path}/habitflow_export.csv');await f.writeAsString(const ListToCsvConverter().convert(rows));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow data export');
  }
  Future<void> backup(BuildContext c)async{final dir=await getTemporaryDirectory();final f=File('${dir.path}/habitflow_backup.json');await f.writeAsString(jsonEncode(store.backup()));await Share.shareXFiles([XFile(f.path)],text:'HabitFlow backup');}
  @override Widget build(BuildContext c){final total=store.habits.fold(0,(n,h)=>n+h.completions.length);final best=store.habits.fold(0,(n,h)=>n>h.longestStreak()?n:h.longestStreak());
    return ListView(padding:const EdgeInsets.fromLTRB(20,24,20,40),children:[
      Text('Profile',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:18),
      Card(child:Padding(padding:const EdgeInsets.all(20),child:Row(children:[
        CircleAvatar(radius:38,backgroundImage:store.profileImage!=null?FileImage(File(store.profileImage!)):null,child:store.profileImage==null?Text(store.profileName.isEmpty?'?':store.profileName[0].toUpperCase(),style:const TextStyle(fontSize:30,fontWeight:FontWeight.bold)):null),
        const SizedBox(width:15),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(store.profileName.isEmpty?'Your name':store.profileName,style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:4),const Text('Build your future with today’s habit.',style:TextStyle(color:Colors.grey))])),IconButton(onPressed:()=>edit(c),icon:const Icon(Icons.edit_outlined))
      ]))),
      const SizedBox(height:12),Row(children:[Stat('🔥','${store.habits.fold(0,(n,h)=>n+h.currentStreak())}','Habit streaks'),const SizedBox(width:8),Stat('🏆','$best','Best'),const SizedBox(width:8),Stat('✓','$total','Completed')]),
      const SizedBox(height:22),Text('Tools',style:Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:8),
      Card(child:Column(children:[
        ListTile(leading:const Icon(Icons.emoji_events_outlined),title:const Text('Achievements'),subtitle:const Text('Milestones and consistency badges'),onTap:()=>showAchievements(c,store)),
        ListTile(leading:const Icon(Icons.file_download_outlined),title:const Text('Export CSV'),subtitle:const Text('Share your habit history and statistics'),onTap:()=>exportCsv(c)),
        ListTile(leading:const Icon(Icons.backup_outlined),title:const Text('Backup data'),subtitle:const Text('Create a JSON backup'),onTap:()=>backup(c)),
        ListTile(leading:const Icon(Icons.dark_mode_outlined),title:const Text('Appearance'),subtitle:Text(store.themeMode==ThemeMode.system?'System default':store.themeMode==ThemeMode.dark?'Dark':'Light'),onTap:()=>themeDialog(c,store)),
        ListTile(leading:const Icon(Icons.info_outline),title:const Text('About HabitFlow'),subtitle:const Text('Version 1.1.0'),onTap:()=>showAboutDialog(context:c,applicationName:'HabitFlow',applicationVersion:'1.1.0',applicationLegalese:'Build your future with today’s habit.')),
      ]))
    ]);
  }
}

void showAchievements(BuildContext c,HabitStore s){final completed=s.habits.fold(0,(n,h)=>n+h.completions.length),best=s.habits.fold(0,(n,h)=>n>h.longestStreak()?n:h.longestStreak());showModalBottomSheet(context:c,showDragHandle:true,builder:(_)=>ListView(padding:const EdgeInsets.all(20),children:[
  Text('Achievements',style:Theme.of(c).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:12),
  Achievement('🌱','First Habit','Create your first habit',s.habits.isNotEmpty),Achievement('🔥','On Fire','Reach a 7-day streak',best>=7),Achievement('🔥','Unstoppable','Reach a 30-day streak',best>=30),Achievement('💯','Century','Complete 100 habit check-ins',completed>=100),Achievement('👑','Perfect Week','Complete every scheduled habit for 7 days',perfectWeek(s))
]));}
bool perfectWeek(HabitStore s){final now=dateOnly(DateTime.now());for(int i=0;i<7;i++){final d=now.subtract(Duration(days=i));for(final h in s.habits){if(h.scheduled(d)&&!h.done(d))return false;}}return s.habits.isNotEmpty;}
class Achievement extends StatelessWidget{final String icon,title,desc;final bool unlocked;const Achievement(this.icon,this.title,this.desc,this.unlocked,{super.key});@override Widget build(BuildContext c)=>ListTile(leading:CircleAvatar(child:Text(icon)),title:Text(title,style:TextStyle(fontWeight:FontWeight.bold,color:unlocked?null:Colors.grey)),subtitle:Text(desc),trailing:Icon(unlocked?Icons.check_circle:Icons.lock_outline,color:unlocked?Theme.of(c).colorScheme.primary:Colors.grey));}

void themeDialog(BuildContext c,HabitStore s)=>showDialog(context:c,builder:(_)=>SimpleDialog(title:const Text('Appearance'),children:[
  RadioListTile(value:ThemeMode.system,groupValue:s.themeMode,onChanged:(v){if(v!=null){s.setTheme(v);Navigator.pop(c);}},title:const Text('System default')),
  RadioListTile(value:ThemeMode.light,groupValue:s.themeMode,onChanged:(v){if(v!=null){s.setTheme(v);Navigator.pop(c);}},title:const Text('Light')),
  RadioListTile(value:ThemeMode.dark,groupValue:s.themeMode,onChanged:(v){if(v!=null){s.setTheme(v);Navigator.pop(c);}},title:const Text('Dark')),
]));

Future<void> editor(BuildContext c,HabitStore s,{Habit? habit})async{
  final n=TextEditingController(text:habit?.name??'');String e=habit?.emoji??'🎯';List<int>d=List<int>.from(habit?.days??[1,2,3,4,5,6,7]);final icons=['🎯','📚','💧','🏃','🧘','💻','🛌','🥗','🧹','🎸','✍️','🧠'];
  await showModalBottomSheet(context:c,isScrollControlled:true,showDragHandle:true,builder:(ctx)=>StatefulBuilder(builder:(ctx,set)=>Padding(padding:EdgeInsets.fromLTRB(20,8,20,MediaQuery.of(ctx).viewInsets.bottom+24),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(habit==null?'Create habit':'Edit habit',style:Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:16),
    TextField(controller:n,decoration:const InputDecoration(labelText:'Habit name',hintText:'e.g. Read 20 minutes')),const SizedBox(height:15),
    const Text('Icon',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,children:icons.map((x)=>ChoiceChip(label:Text(x,style:const TextStyle(fontSize:19)),selected:e==x,onSelected:(_)=>set(()=>e=x))).toList()),
    const SizedBox(height:15),const Text('Repeat on',style:TextStyle(fontWeight:FontWeight.bold)),Wrap(spacing:6,children:List.generate(7,(i){final x=i+1;final lab=['M','T','W','T','F','S','S'][i];return FilterChip(label:Text(lab),selected:d.contains(x),onSelected:(v)=>set(()=>v?d.add(x):d.remove(x)));})),
    const SizedBox(height:20),SizedBox(width:double.infinity,child:FilledButton(onPressed:n.text.trim().isEmpty||d.isEmpty?null:()async{habit==null?await s.add(n.text,e,d):await s.update(habit,n.text,e,d);if(ctx.mounted)Navigator.pop(ctx);},child:Text(habit==null?'Create habit':'Save changes'))),
    if(habit!=null)SizedBox(width:double.infinity,child:TextButton.icon(onPressed:()async{await s.remove(habit);if(ctx.mounted)Navigator.pop(ctx);},icon:const Icon(Icons.delete_outline),label:const Text('Delete habit')))
  ]))));
}
