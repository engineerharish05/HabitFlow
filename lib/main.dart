import 'package:flutter/material.dart';

void main() => runApp(const HabitFlowApp());

class HabitFlowApp extends StatelessWidget {
  const HabitFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'HabitFlow',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.deepPurple),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> habits = ['Read 20 minutes', 'Exercise', 'Study'];
  final Set<int> completed = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HabitFlow')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Today', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 6),
          const Text("Build your future with today's habit."),
          const SizedBox(height: 20),
          for (int i = 0; i < habits.length; i++)
            Card(
              child: ListTile(
                title: Text(habits[i]),
                subtitle: const Text('Every day'),
                trailing: IconButton(
                  icon: Icon(completed.contains(i)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked),
                  onPressed: () => setState(() {
                    if (completed.contains(i)) {
                      completed.remove(i);
                    } else {
                      completed.add(i);
                    }
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
