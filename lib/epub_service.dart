import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'models.dart';

/// Kết quả đọc siêu dữ liệu một cuốn sách khi nhập.
class ParsedBookInfo {
  final String title;
  final String author;
  final int chapterCount;
  final List<int>? coverBytes;
  final String? coverExt;
  ParsedBookInfo(this.title, this.author, this.chapterCount, this.coverBytes, this.coverExt);
}

class TocEntry {
  final String title;
  final String href;
  TocEntry(this.title, this.href);
}

/// Bộ đọc EPUB tối giản, tự viết bằng archive + xml + html.
class EpubDocument {
  final Archive _archive;
  final String _opfDir;
  final List<String> _spineHrefs;
  final Map<String, String> _manifestHrefById;
  final Map<String, String> _titleByHref;
  final String title;
  final String author;
  final String? _coverHref;

  EpubDocument._(this._archive, this._opfDir, this._spineHrefs, this._manifestHrefById,
      this._titleByHref, this.title, this.author, this._coverHref);

  int get chapterCount => _spineHrefs.length;

  static Future<EpubDocument> open(String path) async {
    final bytes = await File(path).readAsBytes();
    return fromBytes(bytes);
  }

  static EpubDocument fromBytes(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    ArchiveFile? find(String name) {
      for (final f in archive) {
        if (f.name == name) return f;
      }
      final lower = name.toLowerCase();
      for (final f in archive) {
        if (f.name.toLowerCase() == lower) return f;
      }
      return null;
    }

    String readText(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

    final container = find('META-INF/container.xml');
    if (container == null) throw const FormatException('Không phải tệp EPUB hợp lệ');
    final containerXml = XmlDocument.parse(readText(container));
    final opfPath = containerXml
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path')!;
    final opfFile = find(opfPath);
    if (opfFile == null) throw const FormatException('Thiếu tệp OPF');
    final opf = XmlDocument.parse(readText(opfFile));
    final opfDir = p.posix.dirname(opfPath) == '.' ? '' : p.posix.dirname(opfPath);

    String? meta(String name) {
      for (final e in opf.findAllElements(name)) {
        final t = e.innerText.trim();
        if (t.isNotEmpty) return t;
      }
      return null;
    }

    final title = meta('dc:title') ?? meta('title') ?? p.basenameWithoutExtension(opfPath);
    final author = meta('dc:creator') ?? meta('creator') ?? '';

    final manifest = <String, String>{};
    final mediaTypeById = <String, String>{};
    final propsById = <String, String>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = Uri.decodeFull(href);
      mediaTypeById[id] = item.getAttribute('media-type') ?? '';
      propsById[id] = item.getAttribute('properties') ?? '';
    }

    final spine = <String>[];
    for (final ref in opf.findAllElements('itemref')) {
      final idref = ref.getAttribute('idref');
      if (idref == null) continue;
      if (ref.getAttribute('linear') == 'no') continue;
      final href = manifest[idref];
      if (href == null) continue;
      final mt = mediaTypeById[idref] ?? '';
      if (mt.contains('html') || mt.contains('xml') || mt.isEmpty) spine.add(href);
    }

    // Ảnh bìa
    String? coverHref;
    for (final e in manifest.entries) {
      if ((propsById[e.key] ?? '').contains('cover-image')) coverHref = e.value;
    }
    if (coverHref == null) {
      for (final m in opf.findAllElements('meta')) {
        if (m.getAttribute('name') == 'cover') {
          coverHref = manifest[m.getAttribute('content')];
        }
      }
    }
    coverHref ??= manifest.entries
        .where((e) => (mediaTypeById[e.key] ?? '').startsWith('image/') &&
            e.value.toLowerCase().contains('cover'))
        .map((e) => e.value)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);

    // Mục lục: EPUB3 nav hoặc EPUB2 ncx
    final titleByHref = <String, String>{};
    try {
      String? navHref;
      String? ncxHref;
      for (final e in manifest.entries) {
        if ((propsById[e.key] ?? '').contains('nav')) navHref = e.value;
        if ((mediaTypeById[e.key] ?? '').contains('dtbncx')) ncxHref = e.value;
      }
      String resolve(String href) {
        final joined = opfDir.isEmpty ? href : p.posix.normalize(p.posix.join(opfDir, href));
        return joined;
      }

      if (navHref != null) {
        final f = find(resolve(navHref));
        if (f != null) {
          final navDir = p.posix.dirname(navHref);
          final doc = html_parser.parse(readText(f));
          for (final a in doc.querySelectorAll('nav a')) {
            final h = a.attributes['href'];
            if (h == null) continue;
            final clean = Uri.decodeFull(h.split('#').first);
            final full = p.posix.normalize(p.posix.join(navDir == '.' ? '' : navDir, clean));
            titleByHref.putIfAbsent(full, () => a.text.trim());
          }
        }
      } else if (ncxHref != null) {
        final f = find(resolve(ncxHref));
        if (f != null) {
          final ncxDir = p.posix.dirname(ncxHref);
          final ncx = XmlDocument.parse(readText(f));
          for (final np in ncx.findAllElements('navPoint')) {
            final label = np.findElements('navLabel').firstOrNull?.innerText.trim() ?? '';
            final src = np.findElements('content').firstOrNull?.getAttribute('src');
            if (src == null) continue;
            final clean = Uri.decodeFull(src.split('#').first);
            final full = p.posix.normalize(p.posix.join(ncxDir == '.' ? '' : ncxDir, clean));
            titleByHref.putIfAbsent(full, () => label);
          }
        }
      }
    } catch (_) {
      // Mục lục lỗi thì dùng tên mặc định.
    }

    return EpubDocument._(archive, opfDir, spine, manifest, titleByHref, title, author, coverHref);
  }

  String _full(String href) =>
      _opfDir.isEmpty ? href : p.posix.normalize(p.posix.join(_opfDir, href));

  ArchiveFile? _file(String path) {
    for (final f in _archive) {
      if (f.name == path) return f;
    }
    return null;
  }

  List<int>? coverBytes() {
    if (_coverHref == null) return null;
    final f = _file(_full(_coverHref!));
    return f == null ? null : (f.content as List<int>);
  }

  String? get coverExt => _coverHref == null ? null : p.extension(_coverHref!);

  /// Danh sách tiêu đề (không đọc nội dung từng chương).
  List<String> chapterTitles() {
    final out = <String>[];
    for (var i = 0; i < _spineHrefs.length; i++) {
      final key = _full(_spineHrefs[i]);
      final t = _titleByHref[key] ?? _titleByHref[_spineHrefs[i]];
      out.add((t == null || t.isEmpty) ? 'Chương ${i + 1}' : t);
    }
    return out;
  }

  Chapter chapter(int index) {
    final href = _spineHrefs[index];
    final f = _file(_full(href));
    final titles = chapterTitles();
    if (f == null) {
      return Chapter(index: index, title: titles[index], paragraphs: const []);
    }
    final raw = utf8.decode(f.content as List<int>, allowMalformed: true);
    return Chapter(
      index: index,
      title: titles[index],
      paragraphs: htmlToParagraphs(raw),
    );
  }
}

/// Tách HTML thành danh sách đoạn văn thuần.
List<String> htmlToParagraphs(String raw) {
  final doc = html_parser.parse(raw);
  doc.querySelectorAll('script,style,head,nav').forEach((e) => e.remove());
  final out = <String>[];
  const blockTags = {'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'blockquote'};

  void walk(dynamic node) {
    final children = node.nodes as List;
    final hasBlockChild = children.any((c) =>
        c.nodeType == 1 && blockTags.contains((c as dynamic).localName));
    if (!hasBlockChild) {
      final t = (node.text as String).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) out.add(t);
      return;
    }
    // Có thẻ khối con: gom chữ trần giữa các khối, rồi đi sâu vào từng khối.
    final buf = StringBuffer();
    void flush() {
      final t = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) out.add(t);
      buf.clear();
    }

    for (final c in children) {
      if (c.nodeType == 1 && blockTags.contains((c as dynamic).localName)) {
        flush();
        walk(c);
      } else {
        buf.write((c as dynamic).text ?? '');
      }
    }
    flush();
  }

  final body = doc.body;
  if (body != null) walk(body);
  return out;
}

/// Chia văn bản TXT thành các chương theo mẫu "Chương N", "Chapter N", "Hồi N"...
class TxtDocument {
  final String title;
  final List<Chapter> chapters;
  TxtDocument(this.title, this.chapters);

  static final _chapterRe = RegExp(
      r'^\s*(chương|chuong|chapter|hồi|hoi|quyển|phần)\s+[\dIVXLC]+.*$',
      caseSensitive: false);

  static Future<TxtDocument> open(String path) async {
    final bytes = await File(path).readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    return parse(p.basenameWithoutExtension(path), text);
  }

  static TxtDocument parse(String title, String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final chapters = <Chapter>[];
    var curTitle = 'Mở đầu';
    var cur = <String>[];

    void commit() {
      final paras = cur.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (paras.isNotEmpty || chapters.isEmpty) {
        chapters.add(Chapter(index: chapters.length, title: curTitle, paragraphs: paras));
      }
      cur = [];
    }

    for (final line in lines) {
      if (_chapterRe.hasMatch(line) && line.trim().length < 120) {
        if (cur.any((s) => s.trim().isNotEmpty)) commit();
        curTitle = line.trim();
      } else {
        cur.add(line);
      }
    }
    commit();
    // Không tìm thấy chương nào: cắt theo ~3000 ký tự để dễ đọc.
    if (chapters.length == 1 && chapters.first.paragraphs.length > 80) {
      final all = chapters.first.paragraphs;
      final out = <Chapter>[];
      var buf = <String>[];
      var len = 0;
      for (final para in all) {
        buf.add(para);
        len += para.length;
        if (len > 3000) {
          out.add(Chapter(index: out.length, title: 'Phần ${out.length + 1}', paragraphs: buf));
          buf = [];
          len = 0;
        }
      }
      if (buf.isNotEmpty) {
        out.add(Chapter(index: out.length, title: 'Phần ${out.length + 1}', paragraphs: buf));
      }
      return TxtDocument(title, out);
    }
    return TxtDocument(title, chapters);
  }
}

/// Giao diện chung cho EPUB và TXT.
abstract class BookContent {
  int get chapterCount;
  List<String> get chapterTitles;
  Chapter chapter(int index);

  static Future<BookContent> open(Book b) async {
    if (b.format == BookFormat.epub) {
      return _EpubContent(await EpubDocument.open(b.filePath));
    }
    return _TxtContent(await TxtDocument.open(b.filePath));
  }
}

class _EpubContent implements BookContent {
  final EpubDocument doc;
  late final List<String> _titles = doc.chapterTitles();
  _EpubContent(this.doc);
  @override
  int get chapterCount => doc.chapterCount;
  @override
  List<String> get chapterTitles => _titles;
  @override
  Chapter chapter(int index) => doc.chapter(index);
}

class _TxtContent implements BookContent {
  final TxtDocument doc;
  _TxtContent(this.doc);
  @override
  int get chapterCount => doc.chapters.length;
  @override
  List<String> get chapterTitles => doc.chapters.map((c) => c.title).toList();
  @override
  Chapter chapter(int index) => doc.chapters[index];
}
