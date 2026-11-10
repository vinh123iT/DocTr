import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import 'reader_screen.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen({super.key});
  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _q = '';

  Future<void> _export(String fmt) async {
    if (appState.highlights.isEmpty) {
      toast(context, 'Chưa có đánh dấu nào để xuất');
      return;
    }
    final content = appState.exportHighlights(fmt);
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'danh_dau_noi_bat.$fmt'));
    await f.writeAsString(content);
    await Share.shareXFiles([XFile(f.path)], subject: 'Đánh dấu nổi bật');
  }

  Future<void> _open(Book b, int chapter, {double scroll = 0, int? paragraph}) async {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ReaderScreen(book: b, jumpChapter: chapter, jumpParagraph: paragraph, jumpScroll: scroll)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final hs = appState.highlights
            .where((h) => _q.isEmpty || '${h.text} ${h.note} ${h.bookTitle}'.toLowerCase().contains(_q.toLowerCase()))
            .toList();
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(children: [
              const Expanded(child: Text('Sổ tay', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800))),
              PopupMenuButton<String>(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Xuất đánh dấu',
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'md', child: Text('Xuất Markdown (.md)')),
                  PopupMenuItem(value: 'txt', child: Text('Xuất văn bản (.txt)')),
                  PopupMenuItem(value: 'csv', child: Text('Xuất bảng (.csv)')),
                  PopupMenuItem(value: 'html', child: Text('Xuất HTML (.html)')),
                  PopupMenuItem(value: 'json', child: Text('Xuất JSON (.json)')),
                ],
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Tìm trong sổ tay',
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          TabBar(controller: _tabs, tabs: [
            Tab(text: 'Đánh dấu (${appState.highlights.length})'),
            Tab(text: 'Dấu trang (${appState.bookmarks.length})'),
          ]),
          Expanded(
            child: TabBarView(controller: _tabs, children: [
              hs.isEmpty
                  ? const Center(child: Text('Chọn văn bản khi đọc để đánh dấu.'))
                  : ListView.builder(
                      itemCount: hs.length,
                      itemBuilder: (_, i) {
                        final h = hs[i];
                        final book = appState.books.where((b) => b.id == h.bookId).firstOrNull;
                        return Dismissible(
                          key: ValueKey(h.id),
                          background: Container(color: Colors.red.shade900),
                          onDismissed: (_) => appState.removeHighlight(h),
                          child: ListTile(
                            leading: Container(width: 4, height: 48, color: Color(h.colorValue)),
                            title: Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${h.bookTitle} · ${h.chapterTitle}${h.note.isEmpty ? '' : '\n📝 ${h.note}'}'),
                            isThreeLine: h.note.isNotEmpty,
                            onTap: book == null ? null : () => _open(book, h.chapter, paragraph: h.paragraph),
                            onLongPress: () async {
                              final c = TextEditingController(text: h.note);
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (d) => AlertDialog(
                                  title: const Text('Ghi chú'),
                                  content: TextField(controller: c, autofocus: true, maxLines: 4),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
                                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Lưu')),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                h.note = c.text.trim();
                                appState.changed();
                              }
                            },
                          ),
                        );
                      },
                    ),
              appState.bookmarks.isEmpty
                  ? const Center(child: Text('Bấm biểu tượng dấu trang khi đọc để lưu vị trí.'))
                  : ListView.builder(
                      itemCount: appState.bookmarks.length,
                      itemBuilder: (_, i) {
                        final m = appState.bookmarks[i];
                        final book = appState.books.where((b) => b.id == m.bookId).firstOrNull;
                        return Dismissible(
                          key: ValueKey(m.id),
                          background: Container(color: Colors.red.shade900),
                          onDismissed: (_) => appState.removeBookmark(m),
                          child: ListTile(
                            leading: const Icon(Icons.bookmark),
                            title: Text(m.label),
                            subtitle: Text(book?.title ?? ''),
                            onTap: book == null ? null : () => _open(book, m.chapter, scroll: m.scroll),
                          ),
                        );
                      },
                    ),
            ]),
          ),
        ]);
      },
    );
  }
}
