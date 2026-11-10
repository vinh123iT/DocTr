import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Tạo tệp WAV 16-bit mono từ mẫu float [-1, 1].
Uint8List floatToWav(Float32List samples, int sampleRate) {
  final dataLen = samples.length * 2;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);
  final pcm = ByteData(dataLen);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    pcm.setInt16(i * 2, v, Endian.little);
  }
  b.add(pcm.buffer.asUint8List());
  return b.toBytes();
}

class _InitMsg {
  final SendPort reply;
  final String model;
  final String tokens;
  final String dataDir;
  final String lexicon;
  final int threads;
  _InitMsg(this.reply, this.model, this.tokens, this.dataDir, this.lexicon, this.threads);
}

void _entry(_InitMsg init) {
  late sherpa.OfflineTts tts;
  try {
    sherpa.initBindings();
    final vits = sherpa.OfflineTtsVitsModelConfig(
      model: init.model,
      tokens: init.tokens,
      dataDir: init.dataDir,
      lexicon: init.lexicon,
    );
    final modelConfig = sherpa.OfflineTtsModelConfig(
      vits: vits,
      numThreads: init.threads,
      debug: false,
      provider: 'cpu',
    );
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: modelConfig));
  } catch (e) {
    init.reply.send('ERR:$e');
    return;
  }

  final port = ReceivePort();
  init.reply.send(port.sendPort);
  port.listen((msg) {
    // msg = [id, text, speed, sid, replyPort]
    final id = msg[0] as int;
    final reply = msg[4] as SendPort;
    try {
      final audio = tts.generate(
        text: msg[1] as String,
        sid: msg[3] as int,
        speed: msg[2] as double,
      );
      final wav = floatToWav(audio.samples, audio.sampleRate);
      reply.send([id, TransferableTypedData.fromList([wav])]);
    } catch (e) {
      reply.send([id, 'ERR:$e']);
    }
  });
}

/// Chạy mô hình VITS/Piper trong isolate riêng để không giật giao diện.
class SherpaClient {
  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _results = ReceivePort();
  final Map<int, Completer<Uint8List>> _pending = {};
  int _nextId = 0;

  SherpaClient._(this._isolate, this._send) {
    _results.listen((msg) {
      final id = msg[0] as int;
      final c = _pending.remove(id);
      if (c == null) return;
      final payload = msg[1];
      if (payload is String) {
        c.completeError(StateError(payload));
      } else {
        c.complete((payload as TransferableTypedData).materialize().asUint8List());
      }
    });
  }

  static Future<SherpaClient> start({
    required String model,
    required String tokens,
    required String dataDir,
    String lexicon = '',
    int threads = 2,
  }) async {
    final reply = ReceivePort();
    final iso = await Isolate.spawn(
        _entry, _InitMsg(reply.sendPort, model, tokens, dataDir, lexicon, threads));
    final first = await reply.first;
    reply.close();
    if (first is String) {
      iso.kill(priority: Isolate.immediate);
      throw StateError(first);
    }
    return SherpaClient._(iso, first as SendPort);
  }

  Future<Uint8List> synth(String text, {double speed = 1.0, int sid = 0}) {
    final id = _nextId++;
    final c = Completer<Uint8List>();
    _pending[id] = c;
    _send.send([id, text, speed, sid, _results.sendPort]);
    return c.future;
  }

  void dispose() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('disposed'));
    }
    _pending.clear();
    _results.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}
