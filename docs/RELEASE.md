# Phát hành bản cập nhật cho người test (Android)

Cập nhật: 27/11/2026. Bản mới nhất trong mã: `1.0.52+53`. Trên Supabase, `app_versions`: `android` = build 53, `android_preview` = build 47.

App tự hỏi bảng `app_versions` lúc mở. Có bản mới thì hiện hộp thoại, bấm "Cập nhật" sẽ tải APK và mở trình cài của Android.

## Mỗi lần phát hành
1. Tăng số sau dấu `+` trong `app/pubspec.yaml` (vd `1.0.1+2`). Số này là versionCode, phải luôn tăng.
2. Chạy script (build arm64 để APK nhỏ, khoảng 50 MB; máy ảo x86 không cài được bản này):
   ```bash
   scripts/release_android.sh "Thêm gửi ảnh trong chat"
   ```
   Script build, đưa APK lên **GitHub Releases** của repo (công khai, tải không cần đăng nhập, file tới 2 GB) và in sẵn câu SQL.
3. Chạy câu SQL đó trong Supabase SQL editor. Từ lúc này người test mở app sẽ thấy hộp thoại cập nhật.
   - `min_supported_build`: bản thấp hơn số này bị **chặn** cho đến khi cập nhật (dùng khi backend đổi không tương thích). Giữ bằng 1 nếu chỉ muốn nhắc nhẹ.

## Lưu ý
- Mọi bản phải ký bằng cùng một khoá: `app/android/app/upload-keystore.jks` + `app/android/key.properties` (không commit). **Sao lưu 2 file này**, mất là người test phải gỡ app cài lại.
- Người test lần đầu cần bật "Cho phép cài ứng dụng từ nguồn này" cho Viegrand.
- APK nằm trên GitHub Releases vì Supabase Storage gói miễn phí giới hạn 50 MB mỗi file. Bucket `app-releases` vẫn còn nhưng không dùng.
- Repo phải là **công khai** thì app mới tải được APK. Nếu chuyển repo sang riêng tư, đổi nơi đặt APK.

## Kênh bản thử (migration 0034)
- Bảng `app_versions` có thêm dòng `platform = 'android_preview'`. Chỉ tài khoản nằm trong `preview_testers` mới thấy dòng này; mọi người khác chỉ thấy dòng `android`.
- Dùng khi muốn cho một nhóm nhỏ thử bản mới trước. Script `release_android.sh` hiện chỉ in câu SQL cho `platform = 'android'`; muốn đẩy bản thử thì tự đổi `where platform = 'android_preview'` trong câu SQL đó.

## Trước khi phát hành bản có migration mới
- Chạy migration trước, rồi mới nâng `latest_build`. Hiện **0036 (`media_daily`) chưa chạy**: chưa chạy thì tóm tắt nghe/xem cho người thân luôn trống, app vẫn chạy bình thường.
- Tệp `release_b48.sql` (chưa commit, ở gốc repo) có nội dung giống migration 0035 (phiên đo AHA/ACC); trên Supabase các cột này đã có. Việc phát hành b48 chưa được chủ dự án trả lời, không tự chạy gì.
