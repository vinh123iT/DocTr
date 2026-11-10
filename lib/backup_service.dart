import 'dart:convert';
import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'app_state.dart';
import 'models.dart';

/// Sao lưu cục bộ + đồng bộ Google Drive (thư mục ẩn của app, không lẫn với tệp của bạn).
///
/// Google Drive cần cấu hình OAuth một lần trong Google Cloud (xem README).
class BackupService {
  static final _gsi = GoogleSignIn(scopes: [drive.DriveApi.driveAppdataScope]);
  static const _dataName = 'lumi_backup.json';

  static GoogleSignInAccount? get account => _gsi.currentUser;

  // ---------- Cục bộ ----------

  static Future<void> shareLocalBackup() async {
    final f = await appState.writeLocalBackup();
    await Share.shareXFiles([XFile(f.path)], subject: 'Sao lưu Lumi Reader');
  }

  /// Trả về số mục đã gộp, hoặc null nếu hủy.
  static Future<bool> restoreFromFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    if (r == null || r.files.single.path == null) return false;
    final j = jsonDecode(await File(r.files.single.path!).readAsString());
    if (j is! Map || j['app'] != 'lumi_reader') {
      throw const FormatException('Đây không phải tệp sao lưu của Lumi Reader');
    }
    appState.importData(Map<String, dynamic>.from(j));
    return true;
  }

  // ---------- Google Drive ----------

  static Future<drive.DriveApi?> _api({bool interactive = true}) async {
    var acc = _gsi.currentUser ?? await _gsi.signInSilently();
    if (acc == null && interactive) acc = await _gsi.signIn();
    if (acc == null) return null;
    final client = await _gsi.authenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  static Future<bool> signIn() async => (await _api()) != null;

  static Future<void> signOut() => _gsi.signOut();

  static Future<drive.File?> _find(drive.DriveApi api, String name) async {
    final res = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name' and trashed = false",
      $fields: 'files(id,name,modifiedTime)',
    );
    return res.files?.isEmpty ?? true ? null : res.files!.first;
  }

  static Future<void> _upload(drive.DriveApi api, String name, File file) async {
    final existing = await _find(api, name);
    final media = drive.Media(file.openRead(), await file.length());
    if (existing == null) {
      await api.files.create(
        drive.File(name: name, parents: ['appDataFolder']),
        uploadMedia: media,
      );
    } else {
      await api.files.update(drive.File(), existing.id!, uploadMedia: media);
    }
  }

  /// Sao lưu dữ liệu + tệp sách lên Drive. [onProgress] nhận 0..1.
  static Future<void> backupToDrive({
    bool interactive = true,
    bool includeBooks = true,
    void Function(double)? onProgress,
  }) async {
    final api = await _api(interactive: interactive);
    if (api == null) throw StateError('Chưa đăng nhập Google');

    final tmp = File(p.join(appState.docsDir.path, _dataName));
    await tmp.writeAsString(jsonEncode(appState.exportData()));
    await _upload(api, _dataName, tmp);

    if (includeBooks) {
      final total = appState.books.length;
      for (var i = 0; i < total; i++) {
        final b = appState.books[i];
        final name = 'book_${b.id}${p.extension(b.filePath)}';
        if (await _find(api, name) == null && File(b.filePath).existsSync()) {
          await _upload(api, name, File(b.filePath));
        }
        onProgress?.call((i + 1) / total);
      }
    }
    appState.lastBackupAt = DateTime.now().toIso8601String();
    appState.changed();
  }

  /// Khôi phục từ Drive: tải dữ liệu, tải lại sách còn thiếu, rồi gộp vào máy.
  static Future<int> restoreFromDrive({void Function(double)? onProgress}) async {
    final api = await _api();
    if (api == null) throw StateError('Chưa đăng nhập Google');
    final meta = await _find(api, _dataName);
    if (meta == null) throw StateError('Không tìm thấy bản sao lưu trên Drive');

    Future<List<int>> download(String id) async {
      final media = await api.files.get(id, downloadOptions: drive.DownloadOptions.fullMedia)
          as drive.Media;
      final bytes = <int>[];
      await for (final c in media.stream) {
        bytes.addAll(c);
      }
      return bytes;
    }

    final j = jsonDecode(utf8.decode(await download(meta.id!))) as Map<String, dynamic>;
    final booksDir = Directory(p.join(appState.docsDir.path, 'books'))..createSync(recursive: true);
    final list = (j['books'] as List).cast<Map<String, dynamic>>();
    var restored = 0;
    for (var i = 0; i < list.length; i++) {
      final bj = list[i];
      final ext = p.extension(bj['filePath'] as String);
      final dest = p.join(booksDir.path, '${bj['id']}$ext');
      if (!File(dest).existsSync()) {
        final f = await _find(api, 'book_${bj['id']}$ext');
        if (f != null) {
          await File(dest).writeAsBytes(await download(f.id!));
          restored++;
        }
      }
      bj['filePath'] = dest;
      bj['coverPath'] = null;
      onProgress?.call((i + 1) / list.length);
    }
    appState.importData(j);
    return restored;
  }

  /// Gọi khi mở app: tự sao lưu nếu đã quá 24 giờ.
  static Future<void> autoBackupIfDue() async {
    if (!appState.autoBackup) return;
    final last = DateTime.tryParse(appState.lastBackupAt ?? '');
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    try {
      await appState.writeLocalBackup();
    } catch (_) {}
    try {
      await backupToDrive(interactive: false);
    } catch (_) {
      // Chưa đăng nhập Google hoặc không có mạng: bỏ qua, lần sau thử lại.
    }
  }
}
