# Lumi Reader

Ứng dụng đọc và nghe truyện EPUB/TXT cho Android, viết bằng Flutter. Mọi tính năng đều mở sẵn, không quảng cáo, không khóa.

## Tính năng

- Thư viện: nhập nhiều tệp EPUB/TXT cùng lúc (bộ chọn tệp của Android cũng chọn được từ Google Drive), bìa tự trích từ EPUB, thẻ, tìm kiếm, lọc, ghi nhớ chương và vị trí đọc
- Trình đọc: mục lục, tìm trong chương, cỡ chữ, giãn dòng, giãn chữ, lề, 4 phông, 8 chủ đề màu, cuộn hoặc lật trang bằng chạm mép, giữ sáng màn hình
- Đánh dấu nổi bật và ghi chú: bôi đen văn bản để đánh dấu, dấu trang, xuất ra Markdown, TXT, CSV, HTML, JSON
- Nghe truyện: giọng hệ thống hoặc giọng AI ngoại tuyến (Piper qua sherpa-onnx), tốc độ 0,75–2×, hẹn giờ ngủ (theo phút hoặc hết chương), âm nền (ồn trắng/hồng/nâu), tự sang chương, nghe khi tắt màn hình
- Chuỗi ngày đọc, thống kê giờ đọc và giờ nghe
- Sao lưu: tự động mỗi 24 giờ, xuất/nhập tệp, đồng bộ Google Drive (dữ liệu và cả tệp sách)

## Build APK

### Cách 1: GitHub Actions (không cần cài gì trên máy)

1. Tạo repo GitHub, đẩy toàn bộ thư mục này lên nhánh `main`
2. Vào tab **Actions**, chạy workflow **Build APK** (hoặc nó tự chạy khi push)
3. Chờ khoảng 10–15 phút, tải artifact **lumi-reader-apk**
4. Với điện thoại đời mới, cài `app-arm64-v8a-release.apk`

### Cách 2: Trên máy tính

Cần Flutter (kênh stable), Android SDK, JDK 17, Python 3.

```bash
chmod +x build.sh && ./build.sh
```

APK nằm trong `build/app/outputs/flutter-apk/`.

## Giọng đọc AI

Màn hình **Cài đặt → Giọng đọc** tải gói giọng về máy rồi chạy ngoại tuyến. Có sẵn 3 giọng tiếng Việt mã nguồn mở (Vais1000, Vivos, 25hours Single) từ kho `tts-models` của sherpa-onnx. Liên kết tải nằm trong `lib/tts/voice_manager.dart` và **chưa được kiểm tra**; nếu liên kết nào lỗi, dùng nút "Thêm giọng từ liên kết" (biểu tượng liên kết ở góc trên) để dán URL gói `.tar.bz2` của sherpa-onnx khác.

Các giọng riêng của Readexa (Lạc Phi, Quang Minh, Ngọc Huyền...) không nằm trong app này vì không phải giọng mở.

## Google Drive

Đăng nhập Google cần cấu hình OAuth một lần, nếu không nút đăng nhập sẽ báo lỗi:

1. Vào Google Cloud Console, tạo project, bật **Google Drive API**
2. Tạo **OAuth consent screen**, thêm email của bạn vào Test users
3. Tạo **OAuth client ID** loại Android: package `com.vinh.lumi_reader`, SHA-1 lấy bằng `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android` (bản build từ GitHub Actions dùng khóa debug ngẫu nhiên của runner, nên SHA-1 sẽ khác; hãy ký APK bằng keystore của riêng bạn nếu muốn dùng Drive ổn định)

App chỉ dùng quyền `drive.appdata` (thư mục ẩn của riêng app), không đọc được tệp khác trên Drive của bạn.

## Lưu ý

Mã nguồn này **chưa từng được biên dịch hay chạy thử** (môi trường viết không có Flutter). Lần build đầu có thể gặp vài lỗi cú pháp hoặc API đổi tên giữa các phiên bản gói; gửi log lỗi lại để sửa.
