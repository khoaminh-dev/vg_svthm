# Bảo mật trang admin và khoá API

Áp dụng cho trang `/admin` và các khoá lưu ở Cài đặt (ElevenLabs, DeepSeek, Groq, Gemini, **OpenAI**).

## Những gì hệ thống đã làm
- **Khoá OpenAI bắt buộc mã hoá khi lưu** (AES-256-GCM, bí mật `KEY_ENCRYPTION_SECRET` nằm ở Vercel, không nằm trong DB). Lộ DB, bản sao lưu hay SQL injection không làm lộ khoá. Các khoá khác cũng được mã hoá nếu bí mật có. Bản mã gắn với tên nhà cung cấp (chép sang chỗ khác không giải được).
- **Khoá không bao giờ rời server:** app chỉ gửi SDP, server dùng khoá gọi OpenAI. Admin chỉ thấy 4 ký tự cuối. Lỗi từ OpenAI không trả về app (có thể chứa một phần khoá) và bị che (`sk-***`) trong log.
- **Thao tác nhạy cảm cần đăng nhập mới (≤ 15 phút):** thêm/xoá/bật tắt khoá, đổi ngưỡng và công tắc, đổi danh sách Live. Token bị lộ hoặc để quên trên máy khác không đổi được khoá.
- **Đăng nhập:** tối đa 10 lần/5 phút mỗi IP và 40 lần/15 phút toàn hệ thống; mỗi lần sai chờ 0,5 giây; mật khẩu mặc định `123` bị khoá không cho quản lý khoá.
- **Nhật ký quản trị** (`admin_audit`): chỉ thêm, không sửa/xoá (trigger trong DB), giữ 180 ngày; ghi đăng nhập, thêm/xoá/bật/tắt/thử khoá (chỉ dấu vân tay 8 ký tự), đổi ngưỡng, đổi danh sách Live. IP chỉ lưu dạng băm một chiều.
- **Công tắc tắt khẩn cấp `live_enabled`** (mặc định TẮT) + danh sách tài khoản được thử Live + giới hạn mở phiên (6 lần/5 phút, 60 lần/ngày mỗi người), vì mỗi phiên mở tốn tiền.
- **Header an toàn** cho `/admin` và `/api/admin`: không cache, chống nhúng khung (clickjacking), chặn đoán kiểu nội dung, không gửi referrer, không cho công cụ tìm kiếm lập chỉ mục.
- Kiểm tra repo: không có khoá nào trong mã nguồn; `app/env.json`, `key.properties` đã được git bỏ qua.

## Việc anh cần làm (hệ thống không tự làm được)
1. **Đặt biến Vercel** (Project → Settings → Environment Variables, rồi redeploy):
   - `KEY_ENCRYPTION_SECRET`: chuỗi ngẫu nhiên ≥ 32 ký tự. Tạo ở máy anh (không dán vào chat) bằng PowerShell:
     `$b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); [Convert]::ToBase64String($b) | Set-Clipboard` (chép thẳng vào clipboard, không hiện ra màn hình)
     Lưu bản sao ở nơi an toàn (trình quản lý mật khẩu): mất nó là các khoá đã mã hoá không giải được.
   - `ADMIN_PASS`: ≥ 12 ký tự, không dùng lại ở nơi khác. `ADMIN_USER`: đổi khỏi `admin`.
   - `ADMIN_SESSION_SECRET`: chuỗi ngẫu nhiên riêng (hiện đang dùng chung khoá service của Supabase).
2. **Thêm khoá OpenAI qua trang admin** (Cài đặt → Thêm key → OpenAI), không qua chat. Nếu khoá từng bị dán vào chat/ảnh chụp/tệp, hãy thu hồi và tạo khoá mới.
3. **Trên bảng điều khiển OpenAI:** dùng khoá của một *dự án riêng* cho Viegrand, đặt **giới hạn chi tiêu hàng tháng (hard limit)** và cảnh báo, chỉ cấp quyền cần thiết (Models read + Live). Đây là chốt chặn cuối cùng nếu có sự cố, hệ thống không thay được.
4. Bật xác thực hai lớp cho tài khoản Vercel, Supabase, OpenAI, GitHub.
5. Mỗi 90 ngày (hoặc khi nghi ngờ) xoay khoá: thêm khoá mới → thử → xoá khoá cũ → thu hồi khoá cũ ở OpenAI.

## Đổi KEY_ENCRYPTION_SECRET
Đặt giá trị cũ vào `KEY_ENCRYPTION_SECRET_PREV`, giá trị mới vào `KEY_ENCRYPTION_SECRET`, redeploy. Khoá cũ vẫn dùng được (giải bằng bí mật cũ). Để chuyển hẳn sang bí mật mới: thêm lại khoá qua admin rồi xoá bản cũ, sau đó bỏ `_PREV`.

## Giới hạn hiện tại (nói thẳng)
- Admin vẫn là **một tài khoản dùng chung** (`ADMIN_USER`/`ADMIN_PASS`); nhật ký ghi "ai" ở mức tài khoản đó. Khi có nhiều người quản trị cần tách theo người (đã nằm trong thiết kế Đợt B).
- Phiên admin lưu trong `sessionStorage` của trình duyệt (mất khi đóng tab) và ký bằng HMAC; chưa có xác thực hai lớp riêng cho trang admin.
- Khoá lấy từ biến môi trường Vercel (`OPENAI_API_KEY`, `GROQ_KEYS`...) không được mã hoá thêm; Vercel tự bảo vệ chúng.
