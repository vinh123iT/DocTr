import 'dart:convert';

enum BookFormat { epub, txt }

class Chapter {
  final int index;
  final String title;

  /// Danh sách đoạn văn đã làm sạch (dùng cho cả đọc và nghe).
  final List<String> paragraphs;

  Chapter({required this.index, required this.title, required this.paragraphs});
}

class Book {
  final String id;
  String title;
  String author;
  final String filePath;
  final BookFormat format;
  String? coverPath;
  int chapterCount;
  int lastChapter; // 0-based
  double lastScroll; // 0..1 trong chương
  int lastParagraph; // vị trí nghe/đọc gần nhất
  DateTime addedAt;
  DateTime? lastOpenedAt;
  List<String> tags;
  bool finished;

  Book({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.format,
    this.coverPath,
    this.chapterCount = 0,
    this.lastChapter = 0,
    this.lastScroll = 0,
    this.lastParagraph = 0,
    DateTime? addedAt,
    this.lastOpenedAt,
    List<String>? tags,
    this.finished = false,
  })  : addedAt = addedAt ?? DateTime.now(),
        tags = tags ?? [];

  double get progress {
    if (chapterCount <= 0) return 0;
    return ((lastChapter + lastScroll) / chapterCount).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'filePath': filePath,
        'format': format.name,
        'coverPath': coverPath,
        'chapterCount': chapterCount,
        'lastChapter': lastChapter,
        'lastScroll': lastScroll,
        'lastParagraph': lastParagraph,
        'addedAt': addedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'tags': tags,
        'finished': finished,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'],
        title: j['title'],
        author: j['author'] ?? '',
        filePath: j['filePath'],
        format: BookFormat.values.firstWhere((f) => f.name == j['format'],
            orElse: () => BookFormat.epub),
        coverPath: j['coverPath'],
        chapterCount: j['chapterCount'] ?? 0,
        lastChapter: j['lastChapter'] ?? 0,
        lastScroll: (j['lastScroll'] ?? 0).toDouble(),
        lastParagraph: j['lastParagraph'] ?? 0,
        addedAt: DateTime.tryParse(j['addedAt'] ?? '') ?? DateTime.now(),
        lastOpenedAt: DateTime.tryParse(j['lastOpenedAt'] ?? ''),
        tags: List<String>.from(j['tags'] ?? const []),
        finished: j['finished'] ?? false,
      );
}

class Highlight {
  final String id;
  final String bookId;
  final String bookTitle;
  final int chapter;
  final String chapterTitle;
  final int paragraph;
  final String text;
  String note;
  int colorValue;
  final DateTime createdAt;

  Highlight({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.chapter,
    required this.chapterTitle,
    required this.paragraph,
    required this.text,
    this.note = '',
    this.colorValue = 0xFFFFE082,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'bookTitle': bookTitle,
        'chapter': chapter,
        'chapterTitle': chapterTitle,
        'paragraph': paragraph,
        'text': text,
        'note': note,
        'colorValue': colorValue,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: j['id'],
        bookId: j['bookId'],
        bookTitle: j['bookTitle'] ?? '',
        chapter: j['chapter'] ?? 0,
        chapterTitle: j['chapterTitle'] ?? '',
        paragraph: j['paragraph'] ?? 0,
        text: j['text'] ?? '',
        note: j['note'] ?? '',
        colorValue: j['colorValue'] ?? 0xFFFFE082,
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class Bookmark {
  final String id;
  final String bookId;
  final int chapter;
  final double scroll;
  final String label;
  final DateTime createdAt;

  Bookmark({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.scroll,
    required this.label,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'chapter': chapter,
        'scroll': scroll,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id'],
        bookId: j['bookId'],
        chapter: j['chapter'] ?? 0,
        scroll: (j['scroll'] ?? 0).toDouble(),
        label: j['label'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? '') ?? DateTime.now(),
      );
}

class ReaderTheme {
  final String id;
  final String name;
  final int bg;
  final int fg;
  const ReaderTheme(this.id, this.name, this.bg, this.fg);
}

const readerThemes = <ReaderTheme>[
  ReaderTheme('light', 'Sáng', 0xFFFFFFFF, 0xFF111111),
  ReaderTheme('dark', 'Tối', 0xFF121212, 0xFFE0E0E0),
  ReaderTheme('sepia', 'Nâu cổ điển', 0xFFF1E7D0, 0xFF5B4636),
  ReaderTheme('paper', 'Giấy', 0xFFFBF8F3, 0xFF2B2B2B),
  ReaderTheme('night', 'Đêm', 0xFF0E1A26, 0xFFA9C7E0),
  ReaderTheme('warm', 'Ấm', 0xFF2A1A0E, 0xFFE8B866),
  ReaderTheme('mint', 'Xanh xô thơm', 0xFFE6EBE3, 0xFF22352A),
  ReaderTheme('mist', 'Sương', 0xFFF0F0F0, 0xFF333333),
];

class ReaderSettings {
  double fontSize;
  double lineHeight;
  double letterSpacing;
  String fontFamily; // 'serif' | 'lora' | 'sourceSerif' | 'sans'
  String themeId;
  bool paged; // false = cuộn
  double sidePadding;
  bool keepScreenOn;
  bool tapToTurn;

  ReaderSettings({
    this.fontSize = 18,
    this.lineHeight = 1.5,
    this.letterSpacing = 0,
    this.fontFamily = 'serif',
    this.themeId = 'paper',
    this.paged = false,
    this.sidePadding = 16,
    this.keepScreenOn = true,
    this.tapToTurn = true,
  });

  ReaderTheme get theme =>
      readerThemes.firstWhere((t) => t.id == themeId, orElse: () => readerThemes[3]);

  Map<String, dynamic> toJson() => {
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'letterSpacing': letterSpacing,
        'fontFamily': fontFamily,
        'themeId': themeId,
        'paged': paged,
        'sidePadding': sidePadding,
        'keepScreenOn': keepScreenOn,
        'tapToTurn': tapToTurn,
      };

  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
        fontSize: (j['fontSize'] ?? 18).toDouble(),
        lineHeight: (j['lineHeight'] ?? 1.5).toDouble(),
        letterSpacing: (j['letterSpacing'] ?? 0).toDouble(),
        fontFamily: j['fontFamily'] ?? 'serif',
        themeId: j['themeId'] ?? 'paper',
        paged: j['paged'] ?? false,
        sidePadding: (j['sidePadding'] ?? 16).toDouble(),
        keepScreenOn: j['keepScreenOn'] ?? true,
        tapToTurn: j['tapToTurn'] ?? true,
      );
}

class ReadingStats {
  /// 'yyyy-MM-dd' -> giây đọc / giây nghe
  Map<String, int> readSeconds;
  Map<String, int> listenSeconds;
  ReadingStats({Map<String, int>? read, Map<String, int>? listen})
      : readSeconds = read ?? {},
        listenSeconds = listen ?? {};

  static String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool activeOn(DateTime d) =>
      (readSeconds[key(d)] ?? 0) > 0 || (listenSeconds[key(d)] ?? 0) > 0;

  int get currentStreak {
    var d = DateTime.now();
    if (!activeOn(d)) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (activeOn(d)) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get bestStreak {
    final days = <String>{...readSeconds.keys, ...listenSeconds.keys}.toList()..sort();
    var best = 0, cur = 0;
    DateTime? prev;
    for (final s in days) {
      final d = DateTime.parse(s);
      if (!activeOn(d)) continue;
      if (prev != null && d.difference(prev).inDays == 1) {
        cur++;
      } else {
        cur = 1;
      }
      if (cur > best) best = cur;
      prev = d;
    }
    return best;
  }

  int get totalListenSeconds => listenSeconds.values.fold(0, (a, b) => a + b);
  int get totalReadSeconds => readSeconds.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {'read': readSeconds, 'listen': listenSeconds};

  factory ReadingStats.fromJson(Map<String, dynamic> j) => ReadingStats(
        read: Map<String, int>.from(j['read'] ?? const {}),
        listen: Map<String, int>.from(j['listen'] ?? const {}),
      );
}

String encodePretty(Object o) => const JsonEncoder.withIndent('  ').convert(o);
