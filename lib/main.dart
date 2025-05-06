import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'package:dio/dio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ovozli Todo Ilovasi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const TodoListPage(),
    );
  }
}

class Task {
  String title;
  bool isDone;

  Task({required this.title, this.isDone = false});
}

class TodoListPage extends StatefulWidget {
  const TodoListPage({Key? key}) : super(key: key);

  @override
  _TodoListPageState createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage> with SingleTickerProviderStateMixin {
  final List<Task> _tasks = [];
  final TextEditingController _textController = TextEditingController();
  final FlutterTts _flutterTts = FlutterTts();
  final  _audioRecorder = AudioRecorder();
  final Dio _dio = Dio();

  bool _isListening = false;
  String _recognizedText = "";
  late AnimationController _animationController;
  String? _audioFilePath;

  @override
  void initState() {
    super.initState();
    _initTts();

    // Animatsiya kontrollerini sozlash
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Namuna vazifalar
    _tasks.add(Task(title: "Tasklar yozishni boshlash kerak"));

    // Dio konfiguratsiyasi
    _dio.options.headers = {
      'Authorization': '85d94e81-3314-400b-999d-2339f8915140:75fb4fdd-3d97-490c-8176-72eaffb8c543', // API kalitingizni shu yerga qo'ying
      'Content-Type': 'multipart/form-data',
    };
  }

  void _initTts() async {
    await _flutterTts.setLanguage("uz-UZ"); // O'zbek tili uchun
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Widget _buildTaskStats() {
    final total = _tasks.length;
    final done = _tasks.where((t) => t.isDone).length;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16.0,
        runSpacing: 8.0,
        children: [
          Text("Jami: $total", style: const TextStyle(fontWeight: FontWeight.bold)),
          Text("Bajarilgan: $done", style: const TextStyle(fontWeight: FontWeight.bold)),
          ElevatedButton.icon(
            onPressed: _tasks.isNotEmpty ? _clearAllTasks : null,
            icon: const Icon(Icons.delete_forever),
            label: const Text("Barchasini o‘chirish"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  void _clearAllTasks() {
    setState(() {
      _tasks.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Barcha vazifalar o‘chirildi")),
    );
  }
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final task = _tasks.removeAt(oldIndex);
      _tasks.insert(newIndex, task);
    });
  }


  // Ovoz yozib olishni boshlash
  Future<void> _startListening() async {
    if (!_isListening) {
      setState(() => _isListening = true);

      try {
        // Ruxsat so'rash va yozib olishni boshlash
        if (await _audioRecorder.hasPermission()) {
          // Audio file uchun vaqtinchalik katalogni aniqlash
          final directory = await getTemporaryDirectory();
          _audioFilePath = '${directory.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

          // Ovoz yozish boshlanganini ko'rsatish
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ovoz yozib olinmoqda...'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );

          // Audio yozib olishni boshlash
          await _audioRecorder.start(
              const RecordConfig(encoder: AudioEncoder.aacLc),
              path: _audioFilePath!
          );
        } else {
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mikrofon uchun ruxsat berilmadi!'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xato yuz berdi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  // Ovoz yozib olishni to'xtatish va API ga yuborish
  Future<void> _stopListening() async {
    if (_isListening) {
      try {
        // Yozib olishni to'xtatish
        final path = await _audioRecorder.stop();
        setState(() => _isListening = false);

        if (path != null && File(path).existsSync()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio API ga yuborilmoqda...'),
              backgroundColor: Colors.blue,
            ),
          );

          // API ga yuborish
          await _sendAudioToApi(path);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Audio fayl topilmadi! {path}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Xato yuz berdi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Audio faylni API ga yuborish
  Future<void> _sendAudioToApi(String audioPath) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ovoz fayli mavjud emas'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'return_offsets': 'false',
        'run_diarization': 'false',
        'language': 'uz',
        'blocking': 'true',
      });

      final response = await _dio.post(
        'https://uzbekvoice.ai/api/v1/stt',
        data: formData,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['result'] != null && data['result']['text'] != null) {
          _showSuccessModal(data);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Matn aniqlanmadi'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('API xatosi: ${response.statusCode}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Xato yuz berdi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessModal(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Natija'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("State: ${data['status']}"),
                Text("Text: ${data['result']['text']}"),
                Text("Error: ${data['error']}"),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _addTask(data['result']['text']);
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }


  void _addTask(String text) {
    setState(() {
      _tasks.add(Task(title: text));
      _textController.clear();
    });
  }


  void _deleteTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  void _toggleTaskStatus(int index) {
    setState(() {
      _tasks[index].isDone = !_tasks[index].isDone;
    });
  }

  void _speakTaskTitle(String title) async {
    await _flutterTts.speak(title);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ovozli Todo Ilovasi'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Yangi vazifa...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    if (_textController.text.trim().isNotEmpty) {
                      _addTask(_textController.text.trim());
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Iltimos, vazifa matnini kiriting")),
                      );
                    }
                  },
                ),

                // Ovoz yozish uchun animatsiyali tugma
                GestureDetector(
                  onTap: _isListening ? _stopListening : _startListening,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isListening ? Colors.red.shade200 : Colors.blue.shade100,
                      boxShadow: [
                        BoxShadow(
                          color: _isListening ? Colors.red.withOpacity(0.5) : Colors.blue.withOpacity(0.3),
                          spreadRadius: _isListening ? 5 : 1,
                          blurRadius: _isListening ? 7 : 3,
                        ),
                      ],
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: _isListening ? 32 : 24,
                      height: _isListening ? 32 : 24,
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : Colors.blue,
                        size: _isListening ? 28 : 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Ovoz yozilayotganini ko'rsatuvchi indikator va aniqlangan matn
          if (_isListening || _recognizedText.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: _isListening ? Colors.green.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(
                  color: _isListening ? Colors.green : Colors.grey.shade300,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.hearing,
                        color: _isListening ? Colors.green : Colors.grey,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isListening ? "Ovoz yozib olinmoqda..." : "Aniqlangan matn:",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isListening ? Colors.green : Colors.grey.shade700,
                        ),
                      ),
                      if (_isListening)
                        Row(
                          children: [
                            const SizedBox(width: 8),
                            _buildPulsingDot(),
                            const SizedBox(width: 2),
                            _buildPulsingDot(delay: 300),
                            const SizedBox(width: 2),
                            _buildPulsingDot(delay: 600),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _recognizedText.isEmpty ? "Gapiring..." : _recognizedText,
                    style: TextStyle(
                      fontStyle: _recognizedText.isEmpty ? FontStyle.italic : FontStyle.normal,
                      color: _recognizedText.isEmpty ? Colors.grey : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),


          Expanded(
            child: Column(
              children: [
                _buildTaskStats(),
                Expanded(
                  child: ReorderableListView(
                    onReorder: _onReorder,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (int index = 0; index < _tasks.length; index++)
                        Dismissible(
                          key: ValueKey(_tasks[index].title + index.toString()),
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20.0),
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            _deleteTask(index);
                          },
                          child: ListTile(
                            key: ValueKey('task_$index'),
                            title: Text(
                              _tasks[index].title,
                              style: TextStyle(
                                decoration: _tasks[index].isDone
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                            ),
                            leading: Checkbox(
                              value: _tasks[index].isDone,
                              onChanged: (bool? value) {
                                _toggleTaskStatus(index);
                              },
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.volume_up),
                              onPressed: () => _speakTaskTitle(_tasks[index].title),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          )


        ],
      ),
    );
  }

  // Pulsar effektli nuqta widgeti
  Widget _buildPulsingDot({int delay = 0}) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final Animation<double> delayedAnimation = _animationController.drive(
          CurveTween(
            curve: Interval(
              delay / 1000,
              ((delay / 1000) + 0.5).clamp(0.0, 1.0), // end qiymatini cheklaymiz
              curve: Curves.easeInOut,
            ),


          ),
        );

        return Container(
          width: 6 + (delayedAnimation.value * 2),
          height: 6 + (delayedAnimation.value * 2),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.7 - (delayedAnimation.value * 0.5)),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _flutterTts.stop();
    _animationController.dispose();
    super.dispose();
  }
}