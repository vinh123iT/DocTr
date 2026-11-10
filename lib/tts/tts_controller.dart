import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../epub_service.dart';
import '../models.dart';
import 'ambient.dart';
import 'sherpa_worker.dart';
import 'voice_manager.dart';

/// Điều khiển nghe truyện: giọng hệ thống (flutter_tts) hoặc giọng AI ngoại tuyến (Piper qua sherpa-onnx).
class TtsController extends ChangeNotifier {
  final FlutterTts _sys = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  final AmbientPlayer ambient = AmbientPlayer();

  SherpaClient? _sherpa;
  String? _sherpaVoice;

  Book? book;
  BookContent? content;
  int chapter = 0;
  List<String> paragraphs = [];
  int index = 0;

  bool playing = false;
  bool preparing = false;
  String? error;

  int _session = 0;
  Timer? _tick;
  int _pendingListen = 0;

  // Hẹn giờ ngủ
  Timer? _sleepTimer;
  DateTime? sleepAt;
  bool sleepEndOfChapter = false;

  /// Cho giao diện báo thay đổi từ bên ngoài (ví dụ đổi âm nền).
  void refresh() => notifyListeners();

  bool get hasBook => book != null;
  String get chapterTitle =>
      content == null ? '' : content!.chapterTitles[chapter.clamp(0, content!.chapterCount - 1)];

  Future<void> init() async {
    await _sys.setLanguage('vi-VN');
    await _sys.awaitSpeakCompletion(true);
  }

  // ---------- Nạp sách ----------

  Future<void> open(Book b, {BookContent? preloaded, int? chapterIndex, int? paragraphIndex}) async {
    await stop();
    book = b;
    content = preloaded ?? await BookContent.open(b);
    chapter = (chapterIndex ?? b.lastChapter).clamp(0, content!.chapterCount - 1);
    _loadChapter(chapter);
    index = (paragraphIndex ?? b.lastParagraph).clamp(0, paragraphs.isEmpty ? 0 : paragraphs.length - 1);
    notifyListeners();
  }

  void _loadChapter(int c) {
    chapter = c;
    paragraphs = content!
        .chapter(c)
        .paragraphs
        .where((s) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s))
        .toList();
    index = 0;
  }

  // ---------- Điều khiển ----------

  Future<void> play() async {
    if (book == null || playing) return;
    playing = true;
    error = null;
    final s = ++_session;
    _startTick();
    await ambient.resumeIfOn();
    notifyListeners();
    unawaited(_run(s));
  }

  Future<void> pause() async {
    if (!playing) return;
    playing = false;
    _session++;
    await _stopOutput();
    await ambient.pauseIfOn();
    _stopTick();
    _persist();
    notifyListeners();
  }

  Future<void> toggle() => playing ? pause() : play();

  Future<void> stop() async {
    playing = false;
    _session++;
    await _stopOutput();
    await ambient.set(AmbientKind.off);
    _stopTick();
    cancelSleep();
    _persist();
    notifyListeners();
  }

  Future<void> _stopOutput() async {
    try {
      await _sys.stop();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> seekParagraph(int i) async {
    final was = playing;
    if (was) await pause();
    index = i.clamp(0, paragraphs.isEmpty ? 0 : paragraphs.length - 1);
    notifyListeners();
    if (was) await play();
  }

  Future<void> next() => seekParagraph(index + 1);
  Future<void> prev() => seekParagraph(index - 1);

  Future<void> goChapter(int c) async {
    final was = playing;
    if (was) await pause();
    if (content == null) return;
    _loadChapter(c.clamp(0, content!.chapterCount - 1));
    _persist();
    notifyListeners();
    if (was) await play();
  }

  Future<void> setSpeed(double v) async {
    appState.ttsSpeed = v;
    appState.changed();
    final was = playing;
    if (was) await pause();
    notifyListeners();
    if (was) await play();
  }

  Future<void> setVoice(String id) async {
    final was = playing;
    if (was) await pause();
    appState.activeVoiceId = id;
    appState.changed();
    notifyListeners();
    if (was) await play();
  }

  // ---------- Vòng đọc chính ----------

  Future<void> _run(int s) async {
    while (s == _session && playing) {
      if (index >= paragraphs.length) {
        if (sleepEndOfChapter) {
          sleepEndOfChapter = false;
          await pause();
          return;
        }
        if (chapter + 1 >= content!.chapterCount) {
          await pause();
          return;
        }
        _loadChapter(chapter + 1);
        notifyListeners();
        continue;
      }
      final text = paragraphs[index];
      try {
        if (appState.activeVoiceId == 'system') {
          await _speakSystem(text);
        } else {
          await _speakAi(text, s);
        }
      } catch (e) {
        if (s == _session) {
          error = '$e';
          playing = false;
          _stopTick();
          notifyListeners();
        }
        return;
      }
      if (s != _session || !playing) return;
      index++;
      _persist();
      notifyListeners();
    }
  }

  Future<void> _speakSystem(String text) async {
    final rate = (0.5 * appState.ttsSpeed).clamp(0.1, 1.0);
    await _sys.setSpeechRate(rate);
    await _sys.speak(text);
  }

  List<String> _chunks(String text) {
    if (text.length <= 260) return [text];
    final parts = text.split(RegExp(r'(?<=[\.\!\?…;:])\s+'));
    final out = <String>[];
    var cur = StringBuffer();
    for (final part in parts) {
      if (cur.length + part.length > 260 && cur.isNotEmpty) {
        out.add(cur.toString().trim());
        cur = StringBuffer();
      }
      cur.write('$part ');
    }
    if (cur.toString().trim().isNotEmpty) out.add(cur.toString().trim());
    return out;
  }

  Future<SherpaClient> _ensureSherpa(String voiceId) async {
    if (_sherpa != null && _sherpaVoice == voiceId) return _sherpa!;
    _sherpa?.dispose();
    _sherpa = null;
    final f = voiceManager.files(voiceId);
    if (f == null) throw StateError('Giọng chưa được tải. Vào Cài đặt > Giọng đọc để tải.');
    preparing = true;
    notifyListeners();
    try {
      _sherpa = await SherpaClient.start(
        model: f.model,
        tokens: f.tokens,
        dataDir: f.dataDir,
        threads: 2,
      );
      _sherpaVoice = voiceId;
    } finally {
      preparing = false;
      notifyListeners();
    }
    return _sherpa!;
  }

  Future<void> _speakAi(String text, int s) async {
    final client = await _ensureSherpa(appState.activeVoiceId);
    final cache = await getTemporaryDirectory();
    final chunks = _chunks(text);
    Future<Uint8List> synth(String t) => client.synth(t, speed: appState.ttsSpeed);

    Future<Uint8List> pending = synth(chunks.first);
    for (var i = 0; i < chunks.length; i++) {
      if (s != _session) return;
      final wav = await pending;
      // Dịch trước đoạn kế tiếp khi đang phát đoạn này.
      if (i + 1 < chunks.length) {
        pending = synth(chunks[i + 1]);
      }
      final f = File(p.join(cache.path, 'tts_${DateTime.now().microsecondsSinceEpoch}.wav'));
      await f.writeAsBytes(wav);
      if (s != _session) {
        f.deleteSync();
        return;
      }
      await _player.setAudioSource(AudioSource.uri(
        Uri.file(f.path),
        tag: MediaItem(
          id: '${book!.id}-$chapter-$index-$i',
          title: chapterTitle,
          album: book!.title,
          artist: book!.author.isEmpty ? null : book!.author,
          artUri: book!.coverPath == null ? null : Uri.file(book!.coverPath!),
        ),
      ));
      await _player.play();
      try {
        f.deleteSync();
      } catch (_) {}
    }
  }

  // ---------- Theo dõi thời gian & tiến độ ----------

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _pendingListen++;
      if (_pendingListen >= 15) {
        appState.addListenSeconds(_pendingListen);
        _pendingListen = 0;
      }
    });
  }

  void _stopTick() {
    _tick?.cancel();
    if (_pendingListen > 0) {
      appState.addListenSeconds(_pendingListen);
      _pendingListen = 0;
    }
  }

  void _persist() {
    final b = book;
    if (b == null) return;
    final frac = paragraphs.isEmpty ? 0.0 : index / paragraphs.length;
    appState.updateProgress(b, chapter: chapter, scroll: frac, paragraph: index);
  }

  // ---------- Hẹn giờ ngủ ----------

  void setSleepMinutes(int minutes) {
    cancelSleep();
    sleepAt = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      sleepAt = null;
      await pause();
    });
    notifyListeners();
  }

  void setSleepEndOfChapter() {
    cancelSleep();
    sleepEndOfChapter = true;
    notifyListeners();
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepAt = null;
    sleepEndOfChapter = false;
    notifyListeners();
  }

  String? get sleepLabel {
    if (sleepEndOfChapter) return 'Hết chương';
    if (sleepAt == null) return null;
    final left = sleepAt!.difference(DateTime.now());
    return '${left.inMinutes + 1} phút';
  }

  @override
  void dispose() {
    _sherpa?.dispose();
    _player.dispose();
    ambient.dispose();
    super.dispose();
  }
}

final tts = TtsController();
