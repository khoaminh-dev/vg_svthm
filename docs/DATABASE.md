# Database (Supabase / Postgres)

Project: **Viegrand** (`jsntzeyrnhwiflydcmfd`, region ap-northeast-1).

## Sơ đồ bảng (schema `public`)

| Bảng | Nội dung | Ghi chú |
|---|---|---|
| `profiles` | 1-1 với `auth.users`: `username` (duy nhất, null với tài khoản Google chưa hoàn tất hồ sơ), `display_name`, `avatar_url`, `last_seen_at` | Trigger `on_auth_user_created` tự tạo |
| `rooms` | `name`, `type` (`group` / `direct`), `direct_key` (duy nhất, chỉ phòng 1-1), `created_by` | Tên 1-50 ký tự |
| `room_members` | (`room_id`, `user_id`) | Bật realtime |
| `messages` | `room_id`, `user_id`, `content` (1-2000 ký tự), `created_at` | Bật realtime, index (`room_id`, `created_at`) |
| `ocr_records` | `title`, `raw_text`, `values` (jsonb: danh sách `{label, value, unit}`), `image_path` | Index (`user_id`, `created_at`) |

Storage:
- `avatars`: công khai để đọc, mỗi người chỉ ghi vào thư mục mang user id của mình.
- `ocr-images`: riêng tư, mỗi người chỉ đọc/ghi/xoá thư mục của mình (xem ảnh qua signed URL).

## Hàm (RPC)

| Hàm | Quyền | Việc |
|---|---|---|
| `is_username_available(text)` | anon, authenticated | Kiểm tra username còn trống (form đăng ký) |
| `create_or_get_direct_room(text)` | authenticated | Mở/tạo chat 1-1 với một `@username` |
| `add_member_by_username(uuid, text)` | authenticated | Thành viên phòng nhóm mời người khác |
| `my_rooms()` | authenticated | Phòng của tôi + thông tin người kia (chat 1-1); chạy dưới quyền người gọi |
| `is_room_member(uuid)` | authenticated | Dùng trong chính sách RLS |
| `handle_new_user()` | không ai | Trigger tạo profile |

## Quy tắc

1. **Mọi thay đổi là một file mới** trong `supabase/migrations/` (đánh số `0005_...`). Không sửa file đã chạy.
2. File `0001` được sửa vài lần lúc đầu vì khi đó chưa chạy ở đâu; từ `0001` đã áp dụng lên Supabase thì cố định.
3. **Mọi bảng bật RLS.** Hàm `security definer` luôn thu hồi quyền của `public`/`anon` trừ khi chủ ý công khai.
4. Sau mỗi lần sửa schema, chạy kiểm tra bảo mật của Supabase (Advisors). Cảnh báo còn lại hiện là chủ ý: `is_username_available` công khai; `rls_auto_enable` do Supabase tạo.
5. Không dùng `service_role` key trong app. App chỉ có URL và key publishable.

## Lịch sử migration

| File | Nội dung |
|---|---|
| `0001_init.sql` | Bảng, trigger profile, bucket avatars, RLS, realtime cho `messages` |
| `0002_harden_functions.sql` | Thu hồi quyền gọi hàm không cần thiết |
| `0003_chat.sql` | Chỉ tự thêm vào phòng do mình tạo; hàm mời thành viên; giới hạn độ dài |
| `0004_direct_chat.sql` | Chat 1-1, `my_rooms()`, realtime cho `room_members` |
| `0005_ocr.sql` | Bucket `ocr-images`, cột `ocr_records.title`, index lịch sử |

## Gói free: cần biết

- **Không có sao lưu tự động.** Cấu trúc nằm trong migration (Git). Dữ liệu thì thỉnh thoảng xuất bằng `pg_dump`. Nâng gói khi khách trả tiền.
- **Tự tạm dừng** sau khoảng 1 tuần không hoạt động: mở app một lần trước buổi demo.
- **Dung lượng:** database 500 MB, Storage 1 GB.
- Nên có project thứ hai (free cho 2 project) để thử migration trước khi chạy lên project chính.

## Kế hoạch tiếp theo

| Bước | Thay đổi database |
|---|---|
| Tin cuối + số tin chưa đọc | `room_members.last_read_at`; mở rộng `my_rooms()` |
| Mã mời vào phòng | `rooms.invite_code`; hàm `join_by_code` |
| Rời phòng, đổi tên, đuổi thành viên | `room_members.role` (`owner` / `member`) |
| Gửi ảnh trong chat | Bucket mới, cột `messages.image_path` |
| `seed.sql` | Tài khoản và phòng mẫu cho demo |
