import 'package:flutter/material.dart';

import '../app_state.dart';
import '../tts/tts_controller.dart';
import '../tts/voice_manager.dart';
import 'common.dart';

class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key});

  Future<void> _addCustom(BuildContext context) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Thêm giọng từ liên kết'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Tên giọng')),
          TextField(
            controller: url,
            decoration: const InputDecoration(
              labelText: 'Liên kết .tar.bz2',
              helperText: 'Gói VITS/Piper định dạng sherpa-onnx (có .onnx, tokens.txt, espeak-ng-data)',
              helperMaxLines: 3,
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Thêm')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty && url.text.trim().startsWith('http')) {
      await voiceManager.addCustom(name.text.trim(), url.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Giọng đọc (TTS)'), actions: [
        IconButton(icon: const Icon(Icons.add_link), tooltip: 'Thêm giọng từ liên kết', onPressed: () => _addCustom(context)),
      ]),
      body: ListenableBuilder(
        listenable: Listenable.merge([voiceManager, appState]),
        builder: (context, _) {
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Tất cả giọng đều dùng được ngay, không giới hạn số lượng. '
                  'Giọng AI chạy hoàn toàn ngoại tuyến sau khi tải về.',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              for (final v in voiceManager.all) _VoiceTile(v),
            ],
          );
        },
      ),
    );
  }
}

class _VoiceTile extends StatelessWidget {
  final VoiceInfo v;
  const _VoiceTile(this.v);

  @override
  Widget build(BuildContext context) {
    final installed = voiceManager.isInstalled(v.id);
    final prog = voiceManager.progress[v.id];
    final err = voiceManager.errors[v.id];
    final active = appState.activeVoiceId == v.id;

    Widget trailing;
    if (prog != null) {
      trailing = SizedBox(
        width: 90,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(value: prog >= 0.95 ? null : prog),
          Text(prog >= 0.95 ? 'Giải nén…' : '${(prog * 100).round()}%', style: const TextStyle(fontSize: 12)),
        ]),
      );
    } else if (!installed) {
      trailing = FilledButton.tonal(
        onPressed: () => voiceManager.download(v),
        child: Text(v.approxMb > 0 ? 'Tải ~${v.approxMb} MB' : 'Tải'),
      );
    } else if (active) {
      trailing = const Chip(avatar: Icon(Icons.check, size: 16), label: Text('Đang dùng'));
    } else {
      trailing = OutlinedButton(
        onPressed: () => tts.setVoice(v.id),
        child: const Text('Dùng'),
      );
    }

    return Column(children: [
      ListTile(
        leading: Icon(v.kind == 'system' ? Icons.phone_android : Icons.graphic_eq),
        title: Text(v.name),
        subtitle: Text(v.desc),
        trailing: trailing,
        onLongPress: (installed && v.kind != 'system')
            ? () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: Text('Xóa giọng ${v.name}?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
                      FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Xóa')),
                    ],
                  ),
                );
                if (ok == true) {
                  if (active) await tts.setVoice('system');
                  v.custom ? await voiceManager.removeCustom(v.id) : await voiceManager.delete(v.id);
                }
              }
            : null,
      ),
      if (err != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Text('Tải thất bại: $err', style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ),
      if (installed && v.kind != 'system')
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 72),
            child: TextButton(
              onPressed: () async {
                final prev = appState.activeVoiceId;
                await tts.setVoice(v.id);
                if (tts.hasBook) {
                  // Nghe thử đoạn hiện tại bằng giọng này.
                  await tts.play();
                } else if (context.mounted) {
                  toast(context, 'Mở một cuốn sách rồi bấm Nghe để thử giọng');
                  if (prev != v.id) await tts.setVoice(prev);
                }
              },
              child: const Text('Nghe thử'),
            ),
          ),
        ),
    ]);
  }
}
