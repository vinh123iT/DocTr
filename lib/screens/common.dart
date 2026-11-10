import 'dart:io';

import 'package:flutter/material.dart';

import '../models.dart';

class BookCover extends StatelessWidget {
  final Book book;
  final double? width;
  final double? height;
  const BookCover(this.book, {super.key, this.width, this.height});

  @override
  Widget build(BuildContext context) {
    final cp = book.coverPath;
    Widget child;
    if (cp != null && File(cp).existsSync()) {
      child = Image.file(File(cp), fit: BoxFit.cover, width: width, height: height);
    } else {
      // Bìa mặc định: màu theo tên sách, không dùng hình của ai khác.
      final hue = (book.title.hashCode % 360).abs().toDouble();
      final color = HSLColor.fromAHSL(1, hue, 0.35, 0.28).toColor();
      child = Container(
        width: width,
        height: height,
        color: color,
        padding: const EdgeInsets.all(10),
        alignment: Alignment.topLeft,
        child: Text(
          book.title,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: child);
  }
}

String fmtDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h giờ $m phút';
  return '$m phút';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}
