import 'package:flutter/material.dart';

import '../app_state.dart';
import '../tts/ambient.dart';
import '../tts/tts_controller.dart';
import '../tts/voice_manager.dart';
import 'voice_screen.dart';

Future<void> showPlayerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const PlayerSheet(),
  );
}

/// Thanh phát nhỏ nằm trên thanh điều hướng.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1B1B1D),
      child: InkWell(
        onTap: () => showPlayerSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tts.chapterTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(tts.book?.title ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ]),
            ),
            IconButton(icon: const Icon(Icons.skip_previous), onPressed: tts.prev),
            tts.preparing
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(icon: Icon(tts.playing ? Icons.pause_circle : Icons.play_circle, size: 36), onPressed: tts.toggle),
            IconButton(icon: const Icon(Icons.skip_next), onPressed: tts.next),
            IconButton(icon: const Icon(Icons.close), onPressed: tts.stop),
          ]),
        ),
      ),
    );
  }
}

class PlayerSheet extends StatelessWidget {
  const PlayerSheet({super.key});

  String _voiceName() {
    final v = voiceManager.all.where((e) => e.id == appState.activeVoiceId).firstOrNull;
    return v?.name ?? 'Giọng hệ thống';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([tts, appState, voiceManager]),
      builder: (context, _) {
        final total = tts.paragraphs.length;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Nghe', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('Dừng nghe'),
                  onPressed: () {
                    tts.stop();
                    Navigator.pop(context);
                  },
                ),
              ]),
              Text(tts.book?.title ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              Text(tts.chapterTitle, style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF111113), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.format_quote, color: Theme.of(context).colorScheme.primary, size: 18),
                    const SizedBox(width: 6),
                    Text('ĐANG ĐỌC', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12, letterSpacing: 1)),
                    const Spacer(),
                    Text('Đoạn ${total == 0 ? 0 : (tts.index + 1).clamp(1, total)} / $total',
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    total == 0 || tts.index >= total ? '' : tts.paragraphs[tts.index],
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, height: 1.4),
                  ),
                ]),
              ),
              Slider(
                value: total == 0 ? 0 : tts.index.clamp(0, total - 1).toDouble(),
                min: 0,
                max: total <= 1 ? 1 : (total - 1).toDouble(),
                onChanged: total <= 1 ? null : (v) => tts.seekParagraph(v.round()),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(iconSize: 32, icon: const Icon(Icons.skip_previous), onPressed: tts.prev),
                const SizedBox(width: 16),
                tts.preparing
                    ? const SizedBox(width: 64, height: 64, child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                    : IconButton.filled(
                        iconSize: 36,
                        icon: Icon(tts.playing ? Icons.pause : Icons.play_arrow),
                        onPressed: tts.toggle,
                      ),
                const SizedBox(width: 16),
                IconButton(iconSize: 32, icon: const Icon(Icons.skip_next), onPressed: tts.next),
              ]),
              if (tts.preparing)
                const Center(child: Text('Đang chuẩn bị giọng đọc, có thể mất vài giây', style: TextStyle(color: Colors.white60))),
              if (tts.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tts.error!, style: const TextStyle(color: Colors.redAccent)),
                ),
              const SizedBox(height: 12),
              Row(children: [
                _tile(context, Icons.speed, '${appState.ttsSpeed.toStringAsFixed(1)}×', () => _speed(context)),
                _tile(context, Icons.graphic_eq, _voiceName(), () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceScreen()));
                }),
                _tile(context, Icons.timer_outlined, tts.sleepLabel == null ? 'Hẹn giờ ngủ' : 'Ngủ sau ${tts.sleepLabel}', () => _sleep(context)),
                _tile(context, Icons.music_note, ambientLabel(tts.ambient.kind), () => _ambient(context)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Widget _tile(BuildContext context, IconData i, String t, VoidCallback f) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Material(
            color: const Color(0xFF1B1B1D),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: f,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Column(children: [
                  Icon(i),
                  const SizedBox(height: 4),
                  Text(t, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
            ),
          ),
        ),
      );

  void _speed(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          for (final v in [0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            ListTile(
              title: Text('${v.toStringAsFixed(2)}×'),
              trailing: appState.ttsSpeed == v ? const Icon(Icons.check) : null,
              onTap: () {
                tts.setSpeed(v);
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }

  void _sleep(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          for (final m in [15, 30, 45, 60, 90])
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: Text('$m phút'),
              onTap: () {
                tts.setSleepMinutes(m);
                Navigator.pop(context);
              },
            ),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: const Text('Hết chương này'),
            onTap: () {
              tts.setSleepEndOfChapter();
              Navigator.pop(context);
            },
          ),
          if (tts.sleepLabel != null)
            ListTile(
              leading: const Icon(Icons.timer_off),
              title: const Text('Tắt hẹn giờ'),
              onTap: () {
                tts.cancelSleep();
                Navigator.pop(context);
              },
            ),
        ]),
      ),
    );
  }

  void _ambient(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final k in AmbientKind.values)
              ListTile(
                title: Text(ambientLabel(k)),
                trailing: tts.ambient.kind == k ? const Icon(Icons.check) : null,
                onTap: () async {
                  await tts.ambient.set(k);
                  set(() {});
                  tts.refresh();
                },
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Icon(Icons.volume_down),
                Expanded(
                  child: Slider(
                    value: tts.ambient.volume,
                    onChanged: (v) {
                      tts.ambient.setVolume(v);
                      set(() {});
                    },
                  ),
                ),
                const Icon(Icons.volume_up),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
