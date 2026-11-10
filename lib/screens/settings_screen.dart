import 'package:flutter/material.dart';

import '../app_state.dart';
import '../backup_service.dart';
import 'common.dart';
import 'voice_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;
  double? _progress;

  Future<void> _run(String label, Future<String?> Function() job) async {
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      final msg = await job();
      if (mounted && msg != null) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, '$label thất bại: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final acc = BackupService.account;
        final last = DateTime.tryParse(appState.lastBackupAt ?? '');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Cài đặt', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            if (_busy) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: _progress)),
            const _Header('Nghe truyện'),
            ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('Giọng đọc (TTS)'),
              subtitle: const Text('Giọng hệ thống và giọng AI ngoại tuyến'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceScreen())),
            ),
            const _Header('Sao lưu & đồng bộ'),
            SwitchListTile(
              secondary: const Icon(Icons.backup_outlined),
              title: const Text('Tự động sao lưu'),
              subtitle: Text(last == null
                  ? 'Mỗi 24 giờ khi mở app. Chưa có bản sao lưu.'
                  : 'Mỗi 24 giờ khi mở app. Gần nhất: ${last.day}/${last.month}/${last.year} ${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}'),
              value: appState.autoBackup,
              onChanged: (v) {
                appState.autoBackup = v;
                appState.changed();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: Text(acc == null ? 'Đăng nhập Google Drive' : 'Google Drive: ${acc.email}'),
              subtitle: const Text('Sao lưu vào thư mục riêng của app, không lẫn với tệp của bạn'),
              trailing: acc == null ? null : TextButton(onPressed: () async { await BackupService.signOut(); setState(() {}); }, child: const Text('Đăng xuất')),
              onTap: acc != null || _busy
                  ? null
                  : () => _run('Đăng nhập', () async {
                        final ok = await BackupService.signIn();
                        setState(() {});
                        return ok ? 'Đã đăng nhập' : 'Đã hủy đăng nhập';
                      }),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Sao lưu lên Drive ngay'),
              subtitle: const Text('Dữ liệu đọc, đánh dấu và cả tệp sách'),
              enabled: !_busy,
              onTap: () => _run('Sao lưu', () async {
                await BackupService.backupToDrive(onProgress: (p) => setState(() => _progress = p));
                return 'Đã sao lưu lên Drive';
              }),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Khôi phục từ Drive'),
              subtitle: const Text('Gộp với dữ liệu hiện có, không xóa gì'),
              enabled: !_busy,
              onTap: () => _run('Khôi phục', () async {
                final n = await BackupService.restoreFromDrive(onProgress: (p) => setState(() => _progress = p));
                return 'Đã khôi phục ($n sách tải lại)';
              }),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Xuất bản sao lưu thành tệp'),
              enabled: !_busy,
              onTap: () => _run('Xuất', () async {
                await BackupService.shareLocalBackup();
                return null;
              }),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Khôi phục từ tệp sao lưu'),
              enabled: !_busy,
              onTap: () => _run('Khôi phục', () async {
                final ok = await BackupService.restoreFromFile();
                return ok ? 'Đã khôi phục' : null;
              }),
            ),
            const _Header('Giới thiệu'),
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Lumi Reader 1.0'),
              subtitle: Text('Ứng dụng đọc và nghe truyện ngoại tuyến. Không quảng cáo, không khóa tính năng.'),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(letterSpacing: 1.5, fontSize: 12, color: Theme.of(context).colorScheme.primary)),
      );
}
