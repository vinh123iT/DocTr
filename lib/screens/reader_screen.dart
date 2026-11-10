import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app_state.dart';
import '../epub_service.dart';
import '../models.dart';
import '../tts/tts_controller.dart';
import 'common.dart';
import 'player_sheet.dart';

TextStyle readerTextStyle(ReaderSettings s) {
  final base = TextStyle(
    fontSize: s.fontSize,
    height: s.lineHeight,
    letterSpacing: s.letterSpacing,
    color: Color(s.theme.fg),
  );
  switch (s.fontFamily) {
    case 'lora':
      return GoogleFonts.lora(textStyle: base);
    case 'sourceSerif':
      return GoogleFonts.sourceSerif4(textStyle: base);
    case 'sans':
      return base.copyWith(fontFamily: 'sans-serif');
    default:
      return base.copyWith(fontFamily: 'serif');
  }
}

class ReaderScreen extends StatefulWidget {
  final Book book;
  final bool autoListen;
  final int? jumpChapter;
  final int? jumpParagraph;
  final double? jumpScroll;
  const ReaderScreen({
    super.key,
    required this.book,
    this.autoListen = false,
    this.jumpChapter,
    this.jumpParagraph,
    this.jumpScroll,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  BookContent? _content;
  String? _error;
  int _chapter = 0;
  Chapter? _ch;
  bool _chrome = true;

  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();
  Timer? _saveDebounce;
  Timer? _readTimer;
  int _readTicks = 0;
  String _selected = '';
  int _firstVisible = 0;

  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _positions.itemPositions.addListener(_onScroll);
    tts.addListener(_followTts);
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await BookContent.open(book);
      _content = c;
      final start = (widget.jumpChapter ?? book.lastChapter).clamp(0, c.chapterCount - 1);
      _openChapter(start, paragraph: widget.jumpParagraph, scroll: widget.jumpScroll ?? (widget.jumpChapter == null ? book.lastScroll : 0));
      _startReadTimer();
      if (appState.reader.keepScreenOn) WakelockPlus.enable();
      if (widget.autoListen) _listen();
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _openChapter(int i, {int? paragraph, double? scroll}) {
    final ch = _content!.chapter(i);
    setState(() {
      _chapter = i;
      _ch = ch;
      _firstVisible = 0;
    });
    final target = paragraph ??
        ((scroll ?? 0) * ch.paragraphs.length).floor().clamp(0, ch.paragraphs.isEmpty ? 0 : ch.paragraphs.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.isAttached && target > 0) _scroll.jumpTo(index: target);
    });
    appState.updateProgress(book, chapter: i, scroll: ch.paragraphs.isEmpty ? 0 : target / ch.paragraphs.length, paragraph: target);
  }

  void _onScroll() {
    final pos = _positions.itemPositions.value;
    if (pos.isEmpty || _ch == null) return;
    final first = pos.where((p) => p.itemTrailingEdge > 0).map((p) => p.index).reduce((a, b) => a < b ? a : b);
    _firstVisible = first;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 1200), () {
      final n = _ch!.paragraphs.length;
      appState.updateProgress(book,
          chapter: _chapter, scroll: n == 0 ? 0 : (first / n).clamp(0.0, 1.0), paragraph: first.clamp(0, n == 0 ? 0 : n - 1));
    });
  }

  void _startReadTimer() {
    _readTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      _readTicks++;
      if (_readTicks >= 15) {
        appState.addReadSeconds(_readTicks);
        _readTicks = 0;
      }
    });
  }

  // Khi đang nghe, cuộn theo đoạn đang đọc.
  int _lastFollowed = -1;
  void _followTts() {
    if (!mounted || tts.book?.id != book.id || !tts.playing) return;
    if (tts.chapter != _chapter && _content != null) {
      _openChapter(tts.chapter);
    }
    if (tts.index != _lastFollowed && _scroll.isAttached) {
      _lastFollowed = tts.index;
      _scroll.scrollTo(index: tts.index, duration: const Duration(milliseconds: 400), alignment: 0.1);
    }
    setState(() {});
  }

  Future<void> _listen() async {
    if (_content == null) return;
    if (tts.book?.id != book.id || tts.chapter != _chapter || !tts.hasBook) {
      await tts.open(book, preloaded: _content, chapterIndex: _chapter, paragraphIndex: _firstVisible);
    }
    if (!mounted) return;
    await showPlayerSheet(context);
    if (tts.playing == false && tts.book?.id == book.id) return;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    tts.removeListener(_followTts);
    _positions.itemPositions.removeListener(_onScroll);
    _saveDebounce?.cancel();
    _readTimer?.cancel();
    if (_readTicks > 0) appState.addReadSeconds(_readTicks);
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ---------- Đánh dấu ----------

  int _paragraphOf(String text) {
    final ps = _ch!.paragraphs;
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].contains(flat)) return i;
    }
    for (var i = 0; i < ps.length; i++) {
      if (flat.length > 20 && ps[i].contains(flat.substring(0, 20))) return i;
    }
    return _firstVisible;
  }

  Future<void> _highlight({bool withNote = false, int color = 0xFFFFE082}) async {
    final text = _selected.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return;
    var note = '';
    if (withNote) {
      final c = TextEditingController();
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
      if (ok != true) return;
      note = c.text.trim();
    }
    appState.addHighlight(
      book: book,
      chapter: _chapter,
      chapterTitle: _ch!.title,
      paragraph: _paragraphOf(text),
      text: text,
      note: note,
      color: color,
    );
    if (mounted) {
      toast(context, 'Đã đánh dấu');
      setState(() {});
    }
  }

  List<InlineSpan> _spans(String para, TextStyle style) {
    final hs = appState.highlights
        .where((h) => h.bookId == book.id && h.chapter == _chapter && para.contains(h.text))
        .toList();
    if (hs.isEmpty) return [TextSpan(text: para)];
    // Chỉ tô màu đoạn trùng đầu tiên của mỗi đánh dấu; chồng lấn thì bỏ qua.
    final ranges = <(int, int, Color)>[];
    for (final h in hs) {
      final s = para.indexOf(h.text);
      final e = s + h.text.length;
      if (ranges.every((r) => e <= r.$1 || s >= r.$2)) ranges.add((s, e, Color(h.colorValue)));
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final out = <InlineSpan>[];
    var pos = 0;
    for (final r in ranges) {
      if (r.$1 > pos) out.add(TextSpan(text: para.substring(pos, r.$1)));
      out.add(TextSpan(
        text: para.substring(r.$1, r.$2),
        style: TextStyle(backgroundColor: r.$3.withValues(alpha: 0.55), color: Colors.black87),
      ));
      pos = r.$2;
    }
    if (pos < para.length) out.add(TextSpan(text: para.substring(pos)));
    return out;
  }

  // ---------- Điều hướng ----------

  void _page(int dir) {
    final pos = _positions.itemPositions.value.toList()..sort((a, b) => a.index.compareTo(b.index));
    if (pos.isEmpty) return;
    final first = pos.first.index;
    final last = pos.last.index;
    final span = (last - first).clamp(1, 1000);
    final n = _ch!.paragraphs.length;
    final target = dir > 0 ? last : (first - span + 1);
    if (dir > 0 && last >= n - 1) {
      _nextChapter();
      return;
    }
    _scroll.scrollTo(index: target.clamp(0, n - 1), duration: const Duration(milliseconds: 250));
  }

  void _nextChapter() {
    if (_chapter + 1 < _content!.chapterCount) _openChapter(_chapter + 1);
  }

  void _prevChapter() {
    if (_chapter > 0) _openChapter(_chapter - 1);
  }

  void _toggleChrome() {
    setState(() => _chrome = !_chrome);
    SystemChrome.setEnabledSystemUIMode(_chrome ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  void _onTap(TapUpDetails d, double width) {
    final s = appState.reader;
    final x = d.localPosition.dx / width;
    if (s.paged && s.tapToTurn && x < 0.28) {
      _page(-1);
    } else if (s.paged && s.tapToTurn && x > 0.72) {
      _page(1);
    } else {
      _toggleChrome();
    }
  }

  void _showToc() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (ctx, sc) {
          final titles = _content!.chapterTitles;
          return Column(children: [
            ListTile(
              title: const Text('Mục lục', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              subtitle: Text('Đã tìm thấy ${titles.length} chương'),
              trailing: Text('${_chapter + 1}/${titles.length}'),
            ),
            Expanded(
              child: ListView.builder(
                controller: sc,
                itemCount: titles.length,
                itemBuilder: (_, i) => ListTile(
                  leading: Text('${i + 1}', style: const TextStyle(color: Colors.white60)),
                  title: Text(titles[i]),
                  selected: i == _chapter,
                  trailing: i == _chapter ? const Icon(Icons.check_circle_outline) : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _openChapter(i, scroll: 0);
                  },
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  void _showSearch() {
    final ctl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        final q = ctl.text.trim().toLowerCase();
        final results = <int>[];
        if (q.length >= 2) {
          for (var i = 0; i < _ch!.paragraphs.length; i++) {
            if (_ch!.paragraphs[i].toLowerCase().contains(q)) results.add(i);
          }
        }
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: ctl,
                  autofocus: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm trong chương này'),
                  onChanged: (_) => set(() {}),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (_, k) => ListTile(
                    title: Text(_ch!.paragraphs[results[k]], maxLines: 3, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(ctx);
                      _scroll.scrollTo(index: results[k], duration: const Duration(milliseconds: 300));
                    },
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _showDisplay() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DisplaySheet(onChanged: () {
        setState(() {});
        if (appState.reader.keepScreenOn) {
          WakelockPlus.enable();
        } else {
          WakelockPlus.disable();
        }
      }),
    );
  }

  // ---------- Giao diện ----------

  @override
  Widget build(BuildContext context) {
    final s = appState.reader;
    final theme = s.theme;
    final style = readerTextStyle(s);
    final fg = Color(theme.fg);
    return Scaffold(
      backgroundColor: Color(theme.bg),
      appBar: _chrome
          ? AppBar(
              backgroundColor: Colors.black,
              title: Text(_ch?.title ?? book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () {
                    final n = _ch?.paragraphs.length ?? 0;
                    appState.addBookmark(book, _chapter, n == 0 ? 0 : _firstVisible / n,
                        '${_ch?.title ?? ''} · ${(book.progress * 100).round()}%');
                    toast(context, 'Đã lưu dấu trang');
                  },
                ),
                IconButton(icon: const Icon(Icons.search), onPressed: _ch == null ? null : _showSearch),
              ],
            )
          : null,
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Không mở được sách:\n$_error')))
          : _ch == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: (d) => _onTap(d, box.maxWidth),
                    child: SelectionArea(
                      onSelectionChanged: (c) => _selected = c?.plainText ?? '',
                      contextMenuBuilder: (ctx, state) => AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: state.contextMenuAnchors,
                        buttonItems: [
                          ...state.contextMenuButtonItems.where((i) => i.type == ContextMenuButtonType.copy),
                          ContextMenuButtonItem(
                            label: 'Đánh dấu',
                            onPressed: () {
                              state.hideToolbar();
                              _highlight();
                            },
                          ),
                          ContextMenuButtonItem(
                            label: 'Ghi chú',
                            onPressed: () {
                              state.hideToolbar();
                              _highlight(withNote: true);
                            },
                          ),
                          ContextMenuButtonItem(
                            label: 'Nghe từ đây',
                            onPressed: () async {
                              state.hideToolbar();
                              final i = _paragraphOf(_selected);
                              await tts.open(book, preloaded: _content, chapterIndex: _chapter, paragraphIndex: i);
                              await tts.play();
                              if (mounted) await showPlayerSheet(context);
                            },
                          ),
                        ],
                      ),
                      child: ScrollablePositionedList.builder(
                        itemScrollController: _scroll,
                        itemPositionsListener: _positions,
                        padding: EdgeInsets.symmetric(horizontal: s.sidePadding, vertical: 12),
                        itemCount: _ch!.paragraphs.length + 1,
                        itemBuilder: (_, i) {
                          if (i == _ch!.paragraphs.length) return _footer(fg);
                          final speaking = tts.playing && tts.book?.id == book.id && tts.chapter == _chapter && tts.index == i;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: speaking
                                ? BoxDecoration(
                                    color: fg.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  )
                                : null,
                            child: Text.rich(
                              TextSpan(children: _spans(_ch!.paragraphs[i], style)),
                              style: style,
                              textAlign: TextAlign.start,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
      bottomNavigationBar: _chrome && _ch != null
          ? Container(
              color: Colors.black,
              child: SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(children: [
                      Expanded(child: LinearProgressIndicator(value: book.progress, minHeight: 3)),
                      const SizedBox(width: 10),
                      Text('${(book.progress * 100).round()}% · ${_chapter + 1}/${_content!.chapterCount}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ]),
                  ),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _nav(Icons.format_list_bulleted, 'Mục lục', _showToc),
                    _nav(Icons.text_fields, 'Hiển thị', _showDisplay),
                    _nav(Icons.headphones, 'Nghe', _listen),
                  ]),
                ]),
              ),
            )
          : null,
    );
  }

  Widget _nav(IconData i, String t, VoidCallback f) => InkWell(
        onTap: f,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(i), const SizedBox(height: 2), Text(t, style: const TextStyle(fontSize: 12))]),
        ),
      );

  Widget _footer(Color fg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(
              onPressed: _chapter > 0 ? _prevChapter : null,
              icon: Icon(Icons.chevron_left, color: fg),
              label: Text('Chương trước', style: TextStyle(color: fg))),
          TextButton.icon(
              onPressed: _chapter + 1 < _content!.chapterCount ? _nextChapter : null,
              icon: Icon(Icons.chevron_right, color: fg),
              label: Text('Chương sau', style: TextStyle(color: fg))),
        ]),
      );
}

/// Bảng chỉnh giao diện đọc: cỡ chữ, giãn dòng, phông, chủ đề, chế độ đọc.
class DisplaySheet extends StatefulWidget {
  final VoidCallback onChanged;
  const DisplaySheet({super.key, required this.onChanged});
  @override
  State<DisplaySheet> createState() => _DisplaySheetState();
}

class _DisplaySheetState extends State<DisplaySheet> {
  ReaderSettings get s => appState.reader;
  void _upd(VoidCallback f) {
    setState(f);
    appState.changed();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.all(16), children: [
        Row(children: [
          const Expanded(child: Text('Giao diện', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700))),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _upd(() {
              appState.reader = ReaderSettings();
            }),
          ),
        ]),
        _slider('Cỡ chữ', s.fontSize, 12, 36, (v) => _upd(() => s.fontSize = v.roundToDouble()), '${s.fontSize.round()}'),
        _slider('Khoảng cách dòng', s.lineHeight, 1.0, 2.4, (v) => _upd(() => s.lineHeight = double.parse(v.toStringAsFixed(2))), s.lineHeight.toStringAsFixed(2)),
        _slider('Giãn chữ', s.letterSpacing, 0, 3, (v) => _upd(() => s.letterSpacing = double.parse(v.toStringAsFixed(1))), s.letterSpacing.toStringAsFixed(1)),
        _slider('Lề hai bên', s.sidePadding, 4, 48, (v) => _upd(() => s.sidePadding = v.roundToDouble()), '${s.sidePadding.round()}'),
        const SizedBox(height: 8),
        const Text('PHÔNG CHỮ', style: TextStyle(letterSpacing: 1.5, color: Colors.white60, fontSize: 12)),
        Wrap(spacing: 8, children: [
          for (final f in const {'serif': 'Có chân', 'lora': 'Lora', 'sourceSerif': 'Source Serif', 'sans': 'Không chân'}.entries)
            ChoiceChip(label: Text(f.value), selected: s.fontFamily == f.key, onSelected: (_) => _upd(() => s.fontFamily = f.key)),
        ]),
        const SizedBox(height: 16),
        const Text('CHỦ ĐỀ', style: TextStyle(letterSpacing: 1.5, color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.9,
          children: [
            for (final t in readerThemes)
              GestureDetector(
                onTap: () => _upd(() => s.themeId = t.id),
                child: Column(children: [
                  Expanded(
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Color(t.bg),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: s.themeId == t.id ? Colors.white : Colors.transparent, width: 2),
                      ),
                      child: Text('Aa', style: TextStyle(color: Color(t.fg), fontWeight: FontWeight.w700, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(t.name, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Lật trang bằng chạm mép'),
          subtitle: const Text('Chạm mép trái/phải để cuộn một trang'),
          value: s.paged,
          onChanged: (v) => _upd(() => s.paged = v),
        ),
        SwitchListTile(
          title: const Text('Giữ màn hình sáng khi đọc'),
          value: s.keepScreenOn,
          onChanged: (v) => _upd(() => s.keepScreenOn = v),
        ),
      ]),
    );
  }

  Widget _slider(String label, double v, double min, double max, ValueChanged<double> f, String shown) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Text(label), const Spacer(), Text(shown, style: const TextStyle(color: Colors.white60))]),
          Slider(value: v.clamp(min, max), min: min, max: max, onChanged: f),
        ],
      );
}
