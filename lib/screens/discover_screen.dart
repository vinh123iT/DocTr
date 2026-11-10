import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import 'reader_screen.dart';

/// Khám phá trong thư viện của bạn: thống kê, đang đọc dở, sách chưa đọc.
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final s = appState.stats;
        final reading = appState.books.where((b) => b.progress > 0.01 && !b.finished).toList();
        final unread = appState.books.where((b) => b.progress <= 0.01).toList();
        final done = appState.books.where((b) => b.finished).toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Khám phá', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Row(children: [
              _Stat('Chuỗi hiện tại', '${s.currentStreak} ngày'),
              _Stat('Kỷ lục', '${s.bestStreak} ngày'),
            ]),
            Row(children: [
              _Stat('Tổng đọc', fmtDuration(s.totalReadSeconds)),
              _Stat('Tổng nghe', fmtDuration(s.totalListenSeconds)),
            ]),
            _Section('Đang đọc dở', reading),
            _Section('Chưa đọc', unread),
            _Section('Đã đọc xong', done),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);
  @override
  Widget build(BuildContext context) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Book> books;
  const _Section(this.title, this.books);
  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      SizedBox(
        height: 190,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: books.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ReaderScreen(book: books[i]))),
            child: SizedBox(
              width: 110,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: BookCover(books[i], width: 110)),
                const SizedBox(height: 6),
                Text(books[i].title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
