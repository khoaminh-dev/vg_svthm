# Phát hành bản cập nhật cho người test (Android)

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
