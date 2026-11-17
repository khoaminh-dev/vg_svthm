# Bộ kiểm thử máy thật (đợt 1: ổn định)

Ghi kết quả mỗi dòng: Đạt / Không đạt + hãng máy, đời Android, ghi chú. Cần ít nhất 3 máy khác hãng (Samsung, Xiaomi/Oppo, một hãng khác). Lỗi chưa bắt được trong app giờ tự vào bảng `events` (tên `app_error`), xem bằng SQL: `select created_at, props from events where name='app_error' order by created_at desc`.

## A. Báo thức thuốc (rủi ro cao nhất)
1. Đặt đơn có cữ sau 3 phút, tắt màn hình, để máy yên: báo thức kêu đúng giờ?
2. Như 1 nhưng bật chế độ máy bay.
3. Khoá máy rồi vuốt xoá app khỏi danh sách gần đây: còn kêu?
4. Tắt máy bật lại, không mở app: cữ kế tiếp còn kêu?
5. Bật tiết kiệm pin / tối ưu pin của hãng: còn kêu? Ghi cài đặt phải chỉnh.
6. Kêu 3 lần cách 2 phút; bấm "Đã uống" ở lần 1 thì dừng?
7. Con đổi giờ từ máy khác: máy bác nhận lịch mới trong bao lâu?

## B. Thông báo đẩy (cần 2 máy, 2 tài khoản)
1. A nhắn B khi B đóng app: B nhận, bấm mở đúng phòng?
2. Như 1 khi B đã vuốt xoá app.
3. Công tắc tắt thông báo / hiện nội dung hoạt động đúng?
4. Đăng xuất rồi đăng nhập tài khoản khác: máy không còn nhận tin của tài khoản cũ?

## C. Liên kết gia đình và SOS (2 máy)
1. Cha mẹ mời, con nhập mã đúng / sai 5 lần (bị khoá?).
2. Cha mẹ đo huyết áp: con thấy trong vài giây? Từ 180/120 con nhận cảnh báo?
3. Giữ SOS 3 giây: con nhận thông báo, bấm "Tôi đã nhận", cha mẹ thấy; thả sớm thì không gửi?
4. Mất mạng bấm SOS: hiện màn thất bại có nút Gọi 115?
5. Cha mẹ gỡ liên kết: con mất quyền ngay?

## D. Chụp đơn thuốc
Chụp 10-20 đơn thật (đã che tên). Mỗi đơn ghi: số thuốc đúng / sai / thiếu, có thuốc đỏ "không thấy trong ảnh" đúng chỗ không. Không ca nào được tự bật lịch khi chưa bấm Lưu.

## E. Đo huyết áp
10 lần đo máy thật (ánh sáng khác nhau): số đọc đúng bao nhiêu lần, mất bao lâu.

## F. Máy của bạn anh bị sập
Ghi lại: hãng, đời Android, bước nào sập (mở app / đăng nhập / mở màn nào). Nếu đăng nhập được thì lỗi đã vào `events`.
