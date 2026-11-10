import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../tts/tts_controller.dart';
import 'common.dart';
import 'reader_screen.dart';

class HomeScreen extends StatelessWidget {
  final VoidCallback onGoLibrary;
  const HomeScreen({super.key, required this.onGoLibrary});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Chào buổi sáng';
    if (h < 14) return 'Chào buổi trưa';
    if (h < 18) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final cont = appState.continueBook;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_greeting(), style: const TextStyle(fontSize: 16, color: Colors.white70)),
            const Text('Lumi Reader', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            if (cont != null) _ContinueCard(book: cont) else _EmptyCard(onTap: onGoLibrary),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.shuffle),
                title: const Text('Chọn giúp tôi một cuốn'),
                subtitle: const Text('Chưa biết hôm nay đọc gì?'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  final b = appState.pickRandomUnread();
                  if (b == null) {
                    toast(context, 'Thư viện đang trống');
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));
                },
              ),
            ),
            const SizedBox(height: 12),
            const _StreakCard(),
          ],
        );
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final Book book;
  const _ContinueCard({required this.book});

  @override
  Widget build(BuildContext context) {
    final pct = (book.progress * 100).round();
    final minutesLeft = ((book.chapterCount - book.lastChapter) * 6).clamp(0, 9999);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ĐỌC TIẾP', style: TextStyle(letterSpacing: 1.5, color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BookCover(book, width: 70, height: 100),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      if (book.author.isNotEmpty)
                        Text(book.author, style: const TextStyle(color: Colors.white60)),
                      const SizedBox(height: 6),
                      Text('Chương ${book.lastChapter + 1} / ${book.chapterCount}',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: LinearProgressIndicator(value: book.progress, minHeight: 4)),
                        const SizedBox(width: 8),
                        Text('$pct%', style: const TextStyle(color: Colors.white60)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Còn ~$minutesLeft phút (ước tính)', style: const TextStyle(color: Colors.white60)),
                const Spacer(),
                IconButton.filledTonal(
                  icon: const Icon(Icons.headphones),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReaderScreen(book: book, autoListen: true)),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Đọc'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyCard({required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: const Icon(Icons.library_add, size: 32),
          title: const Text('Chưa có sách nào'),
          subtitle: const Text('Vào Thư viện để nhập tệp EPUB hoặc TXT.'),
          onTap: onTap,
        ),
      );
}

class _StreakCard extends StatelessWidget {
  const _StreakCard();
  @override
  Widget build(BuildContext context) {
    final s = appState.stats;
    final today = DateTime.now();
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final streak = s.currentStreak;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.local_fire_department, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Text('$streak ngày', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            Text('  ·  Kỷ lục ${s.bestStreak}', style: const TextStyle(color: Colors.white60)),
          ]),
          const SizedBox(height: 8),
          Text(s.activeOn(today) ? 'Bạn đã đọc hôm nay, tuyệt vời!' : 'Hôm nay bạn chưa đọc. Mở một chương nhé.',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.emoji_events, size: 16),
            label: Text('${fmtDuration(s.totalListenSeconds)} nghe'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final d in days)
                Expanded(
                  child: Container(
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: s.activeOn(d) ? Theme.of(context).colorScheme.primary : Colors.transparent,
                      border: Border.all(color: Colors.white24),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),
        ]),
      ),
    );
  }
}
