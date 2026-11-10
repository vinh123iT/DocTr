import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app_state.dart';
import 'backup_service.dart';
import 'screens/shell.dart';
import 'tts/tts_controller.dart';
import 'tts/voice_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.vinh.lumireader.audio',
    androidNotificationChannelName: 'Nghe truyện',
    androidNotificationOngoing: true,
  );
  await appState.load();
  await voiceManager.load();
  await tts.init();
  runApp(const LumiApp());
  BackupService.autoBackupIfDue();
}

const accent = Color(0xFFE0967C);

class LumiApp extends StatelessWidget {
  const LumiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumi Reader',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0B0C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          primary: accent,
          surface: const Color(0xFF1B1B1D),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1B1B1D),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: accent),
      home: const Shell(),
    );
  }
}
