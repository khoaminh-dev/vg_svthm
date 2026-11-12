# Danh sách tính năng

Trạng thái: ✅ xong · 🚧 đang làm · ⬜ chưa làm · ➖ tạm bỏ

## 1. Tài khoản (Auth)
| Tính năng | Trạng thái |
|---|---|
| Đăng ký (họ tên, username, email, mật khẩu) | ✅ |
| Đăng nhập, đăng xuất, giữ phiên | ✅ |
| Chặn đăng ký trùng email / username | ✅ |
| Trang chủ + thông tin người dùng | ✅ |
| Đăng nhập Google (code có sẵn, đang ẩn nút) | ➖ |
| Quên / đặt lại mật khẩu | ➖ |
| Sửa hồ sơ (tên, username) | ⬜ |
| Upload ảnh đại diện (bucket `avatars` đã có) | ⬜ |
| Xoá tài khoản | ⬜ |

## 2. Chat realtime
| Tính năng | Trạng thái |
|---|---|
| Danh sách phòng, tạo phòng | 🚧 |
| Thêm thành viên theo username | 🚧 |
| Gửi / nhận tin nhắn realtime | 🚧 |
| Hiện ai đang online trong phòng (Presence) | 🚧 |
| Chat 1-1 (tạo phòng trực tiếp với @username) | ⬜ |
| Tin nhắn cuối + số tin chưa đọc ở danh sách phòng | ⬜ |
| Gửi ảnh / file | ⬜ |
| Sửa, xoá tin nhắn | ⬜ |
| Thông báo đẩy (FCM) | ⬜ |
| Rời phòng, quản lý thành viên | ⬜ |

## 3. OCR số liệu
| Tính năng | Trạng thái |
|---|---|
| Chụp ảnh / chọn ảnh từ thư viện | ⬜ |
| Đọc chữ bằng ML Kit (chạy trên máy) | ⬜ |
| Tách số liệu (regex, tuỳ chọn LLM để ra JSON) | ⬜ |
| Màn hình sửa tay kết quả | ⬜ |
| Lưu vào `ocr_records`, xem lịch sử | ⬜ |
| Xuất CSV / chia sẻ vào chat | ⬜ |

## 4. Giọng nói
| Tính năng | Trạng thái |
|---|---|
| Nhận giọng nói (`speech_to_text` hoặc `/api/stt`) | ⬜ |
| Parse lệnh bằng LLM → hành động JSON (`/api/llm`) | ⬜ |
| Thực thi lệnh (mở chat, chụp OCR, đọc số liệu...) | ⬜ |
| Đọc phản hồi bằng ElevenLabs (`/api/tts`) | ⬜ |

## 5. Server / API (Vercel)
| Tính năng | Trạng thái |
|---|---|
| Viết `/api/llm`, `/api/stt`, `/api/tts` + router xoay vòng key | ✅ (chưa kiểm tra) |
| Kiểm tra TypeScript (`tsc`), deploy lên Vercel | ⬜ |
| Trỏ `api.<domain>` về Vercel | ⬜ |
| Nhập key Groq, ElevenLabs, Gemini vào Vercel | ⬜ |

## 6. Chung
| Tính năng | Trạng thái |
|---|---|
| Theme sáng/tối, component dùng chung | ✅ |
| CI (flutter analyze + test) | ✅ (chưa chạy trên GitHub) |
| Push code lên GitHub | ⬜ |
| SMTP riêng (Resend/Brevo) khi bật xác nhận email | ⬜ |
| Build APK bản demo cho khách | ⬜ |
