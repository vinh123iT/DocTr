import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'epub_service.dart';
import 'models.dart';

/// Trạng thái toàn app. Mọi tính năng đều mở sẵn, không có khóa Pro.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;
  late Directory _docs;

  List<Book> books = [];
  List<Highlight> highlights = [];
  List<Bookmark> bookmarks = [];
  ReaderSettings reader = ReaderSettings();
  ReadingStats stats = ReadingStats();

  // Giọng đọc
  String activeVoiceId = 'system';
  double ttsSpeed = 1.0;
  String? lastBackupAt;
  bool autoBackup = true;

  bool get isLoaded => _loaded;
  bool _loaded = false;

  Directory get docsDir => _docs;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _docs = await getApplicationDocumentsDirectory();
    books = _decodeList(_prefs.getString('books'), Book.fromJson);
    highlights = _decodeList(_prefs.getString('highlights'), Highlight.fromJson);
    bookmarks = _decodeList(_prefs.getString('bookmarks'), Bookmark.fromJson);
    final r = _prefs.getString('reader');
    if (r != null) reader = ReaderSettings.fromJson(jsonDecode(r));
    final s = _prefs.getString('stats');
    if (s != null) stats = ReadingStats.fromJson(jsonDecode(s));
    activeVoiceId = _prefs.getString('voice') ?? 'system';
    ttsSpeed = _prefs.getDouble('ttsSpeed') ?? 1.0;
    lastBackupAt = _prefs.getString('lastBackupAt');
    autoBackup = _prefs.getBool('autoBackup') ?? true;
    _loaded = true;
    notifyListeners();
  }

  List<T> _decodeList<T>(String? s, T Function(Map<String, dynamic>) f) {
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => f(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save() async {
    await _prefs.setString('books', jsonEncode(books.map((e) => e.toJson()).toList()));
    await _prefs.setString('highlights', jsonEncode(highlights.map((e) => e.toJson()).toList()));
    await _prefs.setString('bookmarks', jsonEncode(bookmarks.map((e) => e.toJson()).toList()));
    await _prefs.setString('reader', jsonEncode(reader.toJson()));
    await _prefs.setString('stats', jsonEncode(stats.toJson()));
    await _prefs.setString('voice', activeVoiceId);
    await _prefs.setDouble('ttsSpeed', ttsSpeed);
    await _prefs.setBool('autoBackup', autoBackup);
    if (lastBackupAt != null) await _prefs.setString('lastBackupAt', lastBackupAt!);
  }

  void changed() {
    notifyListeners();
    save();
  }

  // ---------- Thư viện ----------

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  /// Nhập một tệp EPUB/TXT: chép vào thư mục app, đọc siêu dữ liệu, lưu bìa.
  Future<Book> importFile(String srcPath) async {
    final ext = p.extension(srcPath).toLowerCase();
    final id = _newId();
    final booksDir = Directory(p.join(_docs.path, 'books'))..createSync(recursive: true);
    final dest = p.join(booksDir.path, '$id$ext');
    await File(srcPath).copy(dest);

    String title = p.basenameWithoutExtension(srcPath);
    String author = '';
    int chapters = 0;
    String? coverPath;
    BookFormat format = BookFormat.txt;

    if (ext == '.epub') {
      format = BookFormat.epub;
      final doc = await EpubDocument.open(dest);
      title = doc.title;
      author = doc.author;
      chapters = doc.chapterCount;
      final cover = doc.coverBytes();
      if (cover != null) {
        final coversDir = Directory(p.join(_docs.path, 'covers'))..createSync(recursive: true);
        coverPath = p.join(coversDir.path, '$id${doc.coverExt ?? '.jpg'}');
        await File(coverPath).writeAsBytes(cover);
      }
    } else {
      final doc = await TxtDocument.open(dest);
      chapters = doc.chapters.length;
    }

    final book = Book(
      id: id,
      title: title,
      author: author,
      filePath: dest,
      format: format,
      coverPath: coverPath,
      chapterCount: chapters,
    );
    books.insert(0, book);
    changed();
    return book;
  }

  Future<void> removeBook(Book b) async {
    books.removeWhere((e) => e.id == b.id);
    highlights.removeWhere((h) => h.bookId == b.id);
    bookmarks.removeWhere((m) => m.bookId == b.id);
    try {
      await File(b.filePath).delete();
      if (b.coverPath != null) await File(b.coverPath!).delete();
    } catch (_) {}
    changed();
  }

  void updateProgress(Book b, {int? chapter, double? scroll, int? paragraph}) {
    if (chapter != null) b.lastChapter = chapter;
    if (scroll != null) b.lastScroll = scroll;
    if (paragraph != null) b.lastParagraph = paragraph;
    b.lastOpenedAt = DateTime.now();
    b.finished = b.chapterCount > 0 && b.lastChapter >= b.chapterCount - 1 && b.lastScroll > 0.95;
    changed();
  }

  Book? get continueBook {
    final opened = books.where((b) => b.lastOpenedAt != null).toList()
      ..sort((a, b) => b.lastOpenedAt!.compareTo(a.lastOpenedAt!));
    return opened.isEmpty ? null : opened.first;
  }

  Book? pickRandomUnread() {
    final pool = books.where((b) => b.progress < 0.02).toList();
    if (pool.isEmpty) return books.isEmpty ? null : (books.toList()..shuffle()).first;
    return (pool..shuffle()).first;
  }

  // ---------- Thống kê ----------

  void addReadSeconds(int s) {
    final k = ReadingStats.key(DateTime.now());
    stats.readSeconds[k] = (stats.readSeconds[k] ?? 0) + s;
    changed();
  }

  void addListenSeconds(int s) {
    final k = ReadingStats.key(DateTime.now());
    stats.listenSeconds[k] = (stats.listenSeconds[k] ?? 0) + s;
    changed();
  }

  // ---------- Đánh dấu & ghi chú ----------

  Highlight addHighlight({
    required Book book,
    required int chapter,
    required String chapterTitle,
    required int paragraph,
    required String text,
    String note = '',
    int? color,
  }) {
    final h = Highlight(
      id: _newId(),
      bookId: book.id,
      bookTitle: book.title,
      chapter: chapter,
      chapterTitle: chapterTitle,
      paragraph: paragraph,
      text: text,
      note: note,
      colorValue: color ?? 0xFFFFE082,
    );
    highlights.insert(0, h);
    changed();
    return h;
  }

  void removeHighlight(Highlight h) {
    highlights.removeWhere((e) => e.id == h.id);
    changed();
  }

  void addBookmark(Book b, int chapter, double scroll, String label) {
    bookmarks.insert(
        0, Bookmark(id: _newId(), bookId: b.id, chapter: chapter, scroll: scroll, label: label));
    changed();
  }

  void removeBookmark(Bookmark m) {
    bookmarks.removeWhere((e) => e.id == m.id);
    changed();
  }

  // ---------- Sao lưu / khôi phục ----------

  /// Bản sao lưu gồm dữ liệu + (tùy chọn) tệp sách + bìa. Dữ liệu nhẹ dùng cho Drive.
  Map<String, dynamic> exportData() => {
        'app': 'lumi_reader',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'books': books.map((e) => e.toJson()).toList(),
        'highlights': highlights.map((e) => e.toJson()).toList(),
        'bookmarks': bookmarks.map((e) => e.toJson()).toList(),
        'reader': reader.toJson(),
        'stats': stats.toJson(),
        'voice': activeVoiceId,
        'ttsSpeed': ttsSpeed,
      };

  /// Gộp dữ liệu từ bản sao lưu (không xóa gì đang có).
  void importData(Map<String, dynamic> j) {
    final existing = books.map((b) => b.id).toSet();
    for (final e in (j['books'] as List? ?? [])) {
      final b = Book.fromJson(Map<String, dynamic>.from(e));
      if (existing.contains(b.id)) {
        final cur = books.firstWhere((x) => x.id == b.id);
        if ((b.lastOpenedAt ?? DateTime(2000)).isAfter(cur.lastOpenedAt ?? DateTime(2000))) {
          cur
            ..lastChapter = b.lastChapter
            ..lastScroll = b.lastScroll
            ..lastParagraph = b.lastParagraph
            ..lastOpenedAt = b.lastOpenedAt;
        }
      } else if (File(b.filePath).existsSync()) {
        books.add(b);
      }
    }
    final hIds = highlights.map((e) => e.id).toSet();
    for (final e in (j['highlights'] as List? ?? [])) {
      final h = Highlight.fromJson(Map<String, dynamic>.from(e));
      if (!hIds.contains(h.id)) highlights.add(h);
    }
    final mIds = bookmarks.map((e) => e.id).toSet();
    for (final e in (j['bookmarks'] as List? ?? [])) {
      final m = Bookmark.fromJson(Map<String, dynamic>.from(e));
      if (!mIds.contains(m.id)) bookmarks.add(m);
    }
    if (j['reader'] != null) reader = ReaderSettings.fromJson(Map<String, dynamic>.from(j['reader']));
    if (j['stats'] != null) {
      final s = ReadingStats.fromJson(Map<String, dynamic>.from(j['stats']));
      for (final e in s.readSeconds.entries) {
        stats.readSeconds[e.key] = (stats.readSeconds[e.key] ?? 0) > e.value
            ? stats.readSeconds[e.key]!
            : e.value;
      }
      for (final e in s.listenSeconds.entries) {
        stats.listenSeconds[e.key] = (stats.listenSeconds[e.key] ?? 0) > e.value
            ? stats.listenSeconds[e.key]!
            : e.value;
      }
    }
    changed();
  }

  /// Ghi bản sao lưu cục bộ (giữ 7 bản gần nhất).
  Future<File> writeLocalBackup() async {
    final dir = Directory(p.join(_docs.path, 'backups'))..createSync(recursive: true);
    final name = 'lumi_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final f = File(p.join(dir.path, name));
    await f.writeAsString(encodePretty(exportData()));
    final all = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in all.skip(7)) {
      try {
        old.deleteSync();
      } catch (_) {}
    }
    lastBackupAt = DateTime.now().toIso8601String();
    changed();
    return f;
  }

  // ---------- Xuất đánh dấu nổi bật ----------

  String exportHighlights(String format, {String? bookId}) {
    final list = highlights.where((h) => bookId == null || h.bookId == bookId).toList()
      ..sort((a, b) {
        final c = a.bookTitle.compareTo(b.bookTitle);
        if (c != 0) return c;
        final d = a.chapter.compareTo(b.chapter);
        return d != 0 ? d : a.paragraph.compareTo(b.paragraph);
      });
    switch (format) {
      case 'json':
        return encodePretty(list.map((e) => e.toJson()).toList());
      case 'csv':
        String q(String s) => '"${s.replaceAll('"', '""')}"';
        final sb = StringBuffer('Sách,Chương,Trích đoạn,Ghi chú,Ngày\n');
        for (final h in list) {
          sb.writeln([q(h.bookTitle), q(h.chapterTitle), q(h.text), q(h.note), q(h.createdAt.toIso8601String())]
              .join(','));
        }
        return sb.toString();
      case 'html':
        String esc(String s) =>
            s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
        final sb = StringBuffer(
            '<!doctype html><meta charset="utf-8"><title>Đánh dấu nổi bật</title>'
            '<body style="font-family:serif;max-width:700px;margin:auto;padding:16px">');
        String? cur;
        for (final h in list) {
          if (h.bookTitle != cur) {
            cur = h.bookTitle;
            sb.writeln('<h2>${esc(cur)}</h2>');
          }
          sb.writeln('<blockquote>${esc(h.text)}</blockquote>'
              '<p><small>${esc(h.chapterTitle)}</small></p>');
          if (h.note.isNotEmpty) sb.writeln('<p><em>${esc(h.note)}</em></p>');
        }
        return sb.toString();
      case 'txt':
        final sb = StringBuffer();
        for (final h in list) {
          sb.writeln('[${h.bookTitle} · ${h.chapterTitle}]');
          sb.writeln(h.text);
          if (h.note.isNotEmpty) sb.writeln('Ghi chú: ${h.note}');
          sb.writeln();
        }
        return sb.toString();
      case 'md':
      default:
        final sb = StringBuffer('# Đánh dấu nổi bật\n\n');
        String? cur;
        for (final h in list) {
          if (h.bookTitle != cur) {
            cur = h.bookTitle;
            sb.writeln('\n## $cur\n');
          }
          sb.writeln('> ${h.text.replaceAll('\n', '\n> ')}');
          sb.writeln('> — ${h.chapterTitle}\n');
          if (h.note.isNotEmpty) sb.writeln('**Ghi chú:** ${h.note}\n');
        }
        return sb.toString();
    }
  }
}

final appState = AppState();
