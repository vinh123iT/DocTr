import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import 'reader_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  String? _tag;
  int _filter = 0; // 0 tất cả, 1 sách (epub), 2 tài liệu (txt)
  bool _importing = false;

  Future<void> _import() async {
    // Trên Android, bộ chọn tệp hệ thống cũng cho chọn từ Google Drive.
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'txt'],
      allowMultiple: true,
    );
    if (r == null) return;
    setState(() => _importing = true);
    var ok = 0;
    for (final f in r.files) {
      if (f.path == null) continue;
      try {
        await appState.importFile(f.path!);
        ok++;
      } catch (e) {
        if (mounted) toast(context, 'Không nhập được ${f.name}: $e');
      }
    }
    if (mounted) {
      setState(() => _importing = false);
      toast(context, 'Đã nhập $ok tệp');
    }
  }

  List<Book> get _visible {
    return appState.books.where((b) {
      if (_filter == 1 && b.format != BookFormat.epub) return false;
      if (_filter == 2 && b.format != BookFormat.txt) return false;
      if (_tag != null && !b.tags.contains(_tag)) return false;
      if (_query.isNotEmpty &&
          !('${b.title} ${b.author}'.toLowerCase().contains(_query.toLowerCase()))) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (b.lastOpenedAt ?? b.addedAt).compareTo(a.lastOpenedAt ?? a.addedAt));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final tags = {for (final b in appState.books) ...b.tags}.toList()..sort();
        final list = _visible;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Tìm trong thư viện',
                      filled: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                IconButton(
                  icon: _importing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add),
                  onPressed: _importing ? null : _import,
                ),
              ]),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final e in ['Tất cả', 'Sách', 'Tài liệu'].asMap().entries)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _filter == e.key,
                      onSelected: (_) => setState(() => _filter = e.key),
                    ),
                  ),
                for (final t in tags)
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: FilterChip(
                      avatar: const Icon(Icons.label_outline, size: 16),
                      label: Text(t),
                      selected: _tag == t,
                      onSelected: (v) => setState(() => _tag = v ? t : null),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.menu_book, size: 56, color: Colors.white24),
                        const SizedBox(height: 12),
                        const Text('Chưa có sách. Bấm + để nhập EPUB hoặc TXT.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: _import, icon: const Icon(Icons.upload_file), label: const Text('Nhập tệp')),
                      ]),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 0.52,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _BookTile(book: list[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  final Book book;
  const _BookTile({required this.book});

  @override
  Widget build(BuildContext context) {
    final status = book.finished
        ? 'Đã đọc'
        : (book.lastOpenedAt != null && book.progress > 0 ? 'Đang đọc' : 'Chưa đọc');
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderScreen(book: book))),
      onLongPress: () => _menu(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              BookCover(book),
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
                  child: Text(status, style: const TextStyle(fontSize: 11)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('${book.format.name.toUpperCase()}  ${(book.progress * 100).round()}%',
              style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ],
      ),
    );
  }

  void _menu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Sửa thẻ'),
            onTap: () async {
              Navigator.pop(ctx);
              final c = TextEditingController(text: book.tags.join(', '));
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: const Text('Thẻ (cách nhau bằng dấu phẩy)'),
                  content: TextField(controller: c, autofocus: true),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Lưu')),
                  ],
                ),
              );
              if (ok == true) {
                book.tags = c.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                appState.changed();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Đặt lại tiến độ'),
            onTap: () {
              Navigator.pop(ctx);
              book
                ..lastChapter = 0
                ..lastScroll = 0
                ..lastParagraph = 0
                ..finished = false
                ..lastOpenedAt = null;
              appState.changed();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text('Xóa khỏi thư viện'),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(
                context: context,
                builder: (d) => AlertDialog(
                  title: Text('Xóa "${book.title}"?'),
                  content: const Text('Đánh dấu và dấu trang của sách này cũng sẽ bị xóa.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
                    FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Xóa')),
                  ],
                ),
              );
              if (ok == true) await appState.removeBook(book);
            },
          ),
        ]),
      ),
    );
  }
}
