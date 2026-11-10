import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:path/path.dart' as p;

import '../app_state.dart';
import 'sherpa_worker.dart' show floatToWav;

/// Âm nền tự sinh bằng thuật toán (không cần tệp âm thanh có bản quyền).
enum AmbientKind { off, white, pink, brown }

String ambientLabel(AmbientKind k) => switch (k) {
      AmbientKind.off => 'Tắt',
      AmbientKind.white => 'Ồn trắng',
      AmbientKind.pink => 'Ồn hồng',
      AmbientKind.brown => 'Ồn nâu',
    };

class AmbientPlayer {
  final ap.AudioPlayer _player = ap.AudioPlayer();
  AmbientKind kind = AmbientKind.off;
  double volume = 0.25;

  Future<File> _file(AmbientKind k) async {
    final dir = Directory(p.join(appState.docsDir.path, 'ambient'))..createSync(recursive: true);
    final f = File(p.join(dir.path, '${k.name}.wav'));
    if (f.existsSync()) return f;
    const rate = 22050;
    const seconds = 20;
    final n = rate * seconds;
    final rnd = Random(7);
    final out = Float32List(n);
    var b = 0.0;
    var b0 = 0.0, b1 = 0.0, b2 = 0.0, b3 = 0.0, b4 = 0.0, b5 = 0.0, b6 = 0.0;
    for (var i = 0; i < n; i++) {
      final w = rnd.nextDouble() * 2 - 1;
      switch (k) {
        case AmbientKind.white:
          out[i] = w * 0.5;
        case AmbientKind.brown:
          b = (b + 0.02 * w) / 1.02;
          out[i] = b * 3.5;
        case AmbientKind.pink:
          // Bộ lọc Paul Kellet
          b0 = 0.99886 * b0 + w * 0.0555179;
          b1 = 0.99332 * b1 + w * 0.0750759;
          b2 = 0.96900 * b2 + w * 0.1538520;
          b3 = 0.86650 * b3 + w * 0.3104856;
          b4 = 0.55000 * b4 + w * 0.5329522;
          b5 = -0.7616 * b5 - w * 0.0168980;
          out[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362) * 0.11;
          b6 = w * 0.115926;
        case AmbientKind.off:
          break;
      }
    }
    // Làm mờ 0,5 giây ở hai đầu để vòng lặp không bị "tách".
    final fade = rate ~/ 2;
    for (var i = 0; i < fade; i++) {
      final g = i / fade;
      out[i] *= g;
      out[n - 1 - i] *= g;
    }
    await f.writeAsBytes(floatToWav(out, rate));
    return f;
  }

  Future<void> set(AmbientKind k) async {
    kind = k;
    if (k == AmbientKind.off) {
      await _player.stop();
      return;
    }
    final f = await _file(k);
    await _player.setReleaseMode(ap.ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.play(ap.DeviceFileSource(f.path));
  }

  Future<void> setVolume(double v) async {
    volume = v;
    await _player.setVolume(v);
  }

  Future<void> pauseIfOn() async {
    if (kind != AmbientKind.off) await _player.pause();
  }

  Future<void> resumeIfOn() async {
    if (kind != AmbientKind.off) await _player.resume();
  }

  Future<void> dispose() => _player.dispose();
}
