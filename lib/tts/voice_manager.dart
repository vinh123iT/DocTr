import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';

class VoiceInfo {
  final String id;
  final String name;
  final String desc;

  /// 'system' hoặc 'piper'
  final String kind;

  /// Liên kết tải gói .tar.bz2 định dạng sherpa-onnx (chứa .onnx, tokens.txt, espeak-ng-data/).
  final String? url;
  final int approxMb;
  final bool custom;

  const VoiceInfo({
    required this.id,
    required this.name,
    required this.desc,
    required this.kind,
    this.url,
    this.approxMb = 0,
    this.custom = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'desc': desc,
        'kind': kind,
        'url': url,
        'approxMb': approxMb,
      };
}

const _base = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models';

/// Giọng tiếng Việt mã nguồn mở (Piper) có trong kho tts-models của sherpa-onnx.
/// Lưu ý: liên kết chưa được kiểm tra từ môi trường build; nếu một liên kết hỏng,
/// dùng "Thêm giọng từ liên kết" trong màn hình giọng đọc.
const builtinVoices = <VoiceInfo>[
  VoiceInfo(
    id: 'system',
    name: 'Giọng hệ thống',
    desc: 'Dùng ngay, không cần tải',
    kind: 'system',
  ),
  VoiceInfo(
    id: 'vi-vais1000',
    name: 'Vais1000',
    desc: 'Piper · tiếng Việt · chất lượng vừa',
    kind: 'piper',
    url: '$_base/vits-piper-vi_VN-vais1000-medium.tar.bz2',
    approxMb: 60,
  ),
  VoiceInfo(
    id: 'vi-vivos',
    name: 'Vivos',
    desc: 'Piper · tiếng Việt · nhẹ',
    kind: 'piper',
    url: '$_base/vits-piper-vi_VN-vivos-x_low.tar.bz2',
    approxMb: 20,
  ),
  VoiceInfo(
    id: 'vi-25hours',
    name: '25hours Single',
    desc: 'Piper · tiếng Việt · nhẹ',
    kind: 'piper',
    url: '$_base/vits-piper-vi_VN-25hours_single-low.tar.bz2',
    approxMb: 60,
  ),
];

/// Đường dẫn các tệp cần để nạp một giọng đã cài.
class VoiceFiles {
  final String model;
  final String tokens;
  final String dataDir;
  VoiceFiles(this.model, this.tokens, this.dataDir);
}

class VoiceManager extends ChangeNotifier {
  List<VoiceInfo> customVoices = [];
  final Map<String, double> progress = {}; // 0..1, đang tải
  final Map<String, String> errors = {};

  List<VoiceInfo> get all => [...builtinVoices, ...customVoices];

  Directory get _root =>
      Directory(p.join(appState.docsDir.path, 'voices'))..createSync(recursive: true);

  Directory dirOf(String id) => Directory(p.join(_root.path, id));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('customVoices');
    if (s != null) {
      customVoices = (jsonDecode(s) as List)
          .map((e) => VoiceInfo(
                id: e['id'],
                name: e['name'],
                desc: e['desc'] ?? 'Giọng thêm thủ công',
                kind: 'piper',
                url: e['url'],
                approxMb: e['approxMb'] ?? 0,
                custom: true,
              ))
          .toList();
    }
    notifyListeners();
  }

  Future<void> _saveCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('customVoices', jsonEncode(customVoices.map((e) => e.toJson()).toList()));
  }

  Future<void> addCustom(String name, String url) async {
    final id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
    customVoices.add(VoiceInfo(
        id: id, name: name, desc: 'Giọng thêm thủ công', kind: 'piper', url: url, custom: true));
    await _saveCustom();
    notifyListeners();
  }

  Future<void> removeCustom(String id) async {
    await delete(id);
    customVoices.removeWhere((v) => v.id == id);
    await _saveCustom();
    notifyListeners();
  }

  bool isInstalled(String id) {
    if (id == 'system') return true;
    return files(id) != null;
  }

  /// Tìm .onnx, tokens.txt, espeak-ng-data trong thư mục giọng.
  VoiceFiles? files(String id) {
    final d = dirOf(id);
    if (!d.existsSync()) return null;
    String? model, tokens, data;
    for (final e in d.listSync(recursive: true)) {
      final name = p.basename(e.path);
      if (e is File && name.endsWith('.onnx') && model == null) model = e.path;
      if (e is File && name == 'tokens.txt' && tokens == null) tokens = e.path;
      if (e is Directory && name == 'espeak-ng-data' && data == null) data = e.path;
    }
    if (model == null || tokens == null || data == null) return null;
    return VoiceFiles(model, tokens, data);
  }

  Future<void> download(VoiceInfo v) async {
    if (v.url == null || progress.containsKey(v.id)) return;
    progress[v.id] = 0;
    errors.remove(v.id);
    notifyListeners();
    final tmp = File(p.join(_root.path, '${v.id}.tar.bz2.part'));
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(v.url!));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw HttpException('Máy chủ trả về mã ${resp.statusCode}');
      }
      final total = resp.contentLength ?? (v.approxMb * 1024 * 1024);
      var got = 0;
      final sink = tmp.openWrite();
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        got += chunk.length;
        progress[v.id] = total > 0 ? (got / total).clamp(0.0, 0.95) : 0.5;
        notifyListeners();
      }
      await sink.close();
      client.close();

      // Giải nén trong isolate riêng để không đứng giao diện.
      final out = dirOf(v.id).path;
      final archivePath = tmp.path;
      await Isolate.run(() => _extract(archivePath, out));
      progress[v.id] = 1;
      notifyListeners();
      if (files(v.id) == null) {
        throw const FormatException('Gói giọng thiếu .onnx, tokens.txt hoặc espeak-ng-data');
      }
    } catch (e) {
      errors[v.id] = '$e';
      await delete(v.id);
    } finally {
      progress.remove(v.id);
      if (tmp.existsSync()) tmp.deleteSync();
      notifyListeners();
    }
  }

  Future<void> delete(String id) async {
    final d = dirOf(id);
    if (d.existsSync()) await d.delete(recursive: true);
    notifyListeners();
  }
}

void _extract(String archivePath, String outDir) {
  final bytes = File(archivePath).readAsBytesSync();
  final tarBytes = BZip2Decoder().decodeBytes(bytes);
  final tar = TarDecoder().decodeBytes(tarBytes);
  for (final f in tar) {
    final path = p.join(outDir, f.name);
    // Chặn đường dẫn thoát khỏi thư mục đích.
    if (!p.isWithin(outDir, path)) continue;
    if (f.isFile) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync(f.content as List<int>);
    } else {
      Directory(path).createSync(recursive: true);
    }
  }
}

final voiceManager = VoiceManager();
