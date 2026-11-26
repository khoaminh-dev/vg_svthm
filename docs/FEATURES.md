# Danh sách tính năng

Cập nhật: 27/11/2026, theo nhánh `feat/bp-aha-protocol` (app 1.0.52+53).
Trạng thái: ✅ xong · 🧪 xong, **chưa thử máy thật** · 🚧 đang làm · ⬜ chưa làm · ➖ tạm bỏ

Chi tiết từng màn hình, hành động và ý định của Vy: [APP_MAP.md](APP_MAP.md).

## 1. Tài khoản
| Tính năng | Trạng thái |
|---|---|
| Đăng ký (họ tên, username, email, mật khẩu), chặn trùng email/username | ✅ |
| Đăng nhập email, đăng nhập Google, hoàn tất hồ sơ sau Google | ✅ |
| Đăng xuất (có hộp xác nhận), giữ phiên | ✅ |
| Chọn vai trò: người cao tuổi / người thân (đổi được trong Hồ sơ) | ✅ |
| Số điện thoại cá nhân để Vy gọi "con trai", "mẹ" (bảng riêng, không lộ cho người lạ) | ✅ |
| Quên / đặt lại mật khẩu | ➖ |
| Sửa tên/username, ảnh đại diện, xoá tài khoản | ⬜ |

## 2. Chat
| Tính năng | Trạng thái |
|---|---|
| Phòng nhóm, chat 1-1, thêm thành viên theo username, realtime, online | ✅ |
| Tin cuối + số tin chưa đọc ở danh sách phòng | ✅ |
| Gửi ảnh kèm chú thích (tự hết hạn sau 90 ngày) | ✅ |
| Chip trả lời nhanh (Dạ / Cảm ơn / Đã ăn cơm rồi / Gọi lại giúp nhé) | ✅ |
| Gọi 1 chạm từ danh sách tin nhắn của người cao tuổi | ✅ |
| Người thân gửi video; thẻ video trong chat | 🧪 |
| Tìm người dùng khác (Cộng đồng, bật/tắt bằng cờ `community`, chỉ cho đợt thử) | ✅ |
| Sửa, xoá tin nhắn; rời phòng; quản lý thành viên | ⬜ |

## 3. Huyết áp và sức khoẻ
| Tính năng | Trạng thái |
|---|---|
| Đo một chạm: camera + chụp máy đo, tự đọc bằng AI, phân loại AHA, lưu `bp_readings` | ✅ |
| Quy trình đo chuẩn AHA/ACC: đếm ngược nghỉ 5 phút, 2 số cách nhau 1 phút, hỏi bối cảnh đo và triệu chứng, xác nhận số bất thường, hỏi nhịp tim không đều | 🧪 |
| Màn Sức khoẻ: số gần nhất, biểu đồ, lịch sử, tiến độ 7 ngày | ✅ |
| Nhắc đo huyết áp chủ động (thông báo trên máy, bỏ qua nếu đã đo, giờ yên tĩnh) | ✅ |
| Hồ sơ sức khoẻ (2 màn) + đánh giá nguy cơ đột quỵ và tim mạch 10 năm tự chạy sau mỗi lần đo | ✅ (mốc chia mức còn tạm thời) |
| Đồng ý tham gia nghiên cứu, hỏi Vy về sức khoẻ có lưu lịch sử (xoá sau 90 ngày) | ✅ |
| OCR tổng quát (hoá đơn, bảng biểu), lịch sử OCR | ✅ |
| Nhập huyết áp tay, xuất báo cáo | ⬜ |

## 4. Thuốc
| Tính năng | Trạng thái |
|---|---|
| Lịch thuốc theo "cữ" (Sáng/Trưa/Chiều/Tối), thuốc lẻ, thuốc khi cần, múi giờ của người dùng | ✅ |
| Quét đơn thuốc bằng camera, "Lưu luôn" khi mọi thuốc khớp ảnh | ✅ |
| Nhắc uống thuốc, ghi đã uống / bỏ qua, nhắc sắp hết, nhắc tái khám | ✅ |

## 5. Gia đình và an toàn
| Tính năng | Trạng thái |
|---|---|
| Liên kết người thân bằng mã mời, quyền xem theo từng nhóm dữ liệu, nhật ký truy cập | ✅ |
| Người thân xem tình hình (huyết áp, thuốc, cảnh báo) và nhận thông báo | ✅ |
| SOS: giữ 3 giây, gửi kèm vị trí, tự báo lại khi chưa ai nhận, nhắc gọi 115 | 🧪 |
| Thẻ y tế khẩn cấp | ✅ |
| Tóm tắt cuối ngày, giờ yên tĩnh, cài đặt thông báo | ✅ |
| Cảnh báo khẩn cấp DEMO từ module ngoài (màn đỏ, "Tôi đã nhận", gọi 115) + công tắc nhận ở Hồ sơ | 🧪 |
| Camera giám sát (demo, cờ `camera` mặc định tắt) | ✅ (demo) |

## 6. Vy (trợ lý giọng nói)
| Tính năng | Trạng thái |
|---|---|
| Màn Vy toàn màn hình; nút giữa thanh điều hướng; hội thoại nhiều bước, xác nhận trước khi gửi/gọi | ✅ |
| Lệnh: gửi tin, mở chat, mở màn, đo huyết áp, đọc huyết áp (hôm qua / trung bình tuần / cao nhất…), nhắc thuốc, bỏ qua cữ, về trang chủ, quay lại | ✅ |
| Khẩn cấp: nhận 49 cụm nguy hiểm, nói thẳng + nút Gọi 115 / Báo SOS (không tự gọi) | 🧪 |
| Thuốc an toàn: không nói liều, quá liều → gọi 115/bác sĩ, quên thuốc → không uống gấp đôi | 🧪 |
| Nhắc việc bằng giọng (lưu trên máy), cỡ chữ bằng giọng, hỏi giờ/thứ, tâm sự | 🧪 |
| Hiểu cách nói miền Nam ("coi", "nghen", "bữa nay"…), cuộn danh sách bằng giọng (mới ở màn Giải trí) | 🧪 |
| Vy cho người thân: "mẹ uống thuốc chưa", "huyết áp của mẹ" | 🧪 |
| Vy Live (giọng thời gian thực, theo gói) | 🚧 (spike, xem `PREMIUM_LIVE_DESIGN.md`) |
| Kiểm danh mục câu qua LLM thật (`api/_tests/llm_catalog.ts`) | ⬜ cần khoá Groq của chủ dự án |

## 7. Giải trí
| Tính năng | Trạng thái |
|---|---|
| Tìm và phát YouTube (lưới 6 chủ đề, trình phát có nút lớn, tự sang bài kế, hàng đợi tự bổ sung) | ✅ |
| Lệnh giọng khi đang phát: dừng/tiếp, tua, hẹn giờ tắt, bài trước/sau, to/nhỏ, "bài này hay / không thích" | 🧪 |
| Nhớ người dùng nghe gì (trên máy), "xem tiếp", "mở như mọi khi", rào nội dung sức khoẻ | 🧪 |
| Nhạc nhường chỗ cho Vy và việc khẩn (hạ 20%, tạm dừng, dừng hẳn khi SOS) | 🧪 |
| Vy chủ động gợi ý đúng giờ quen nghe | 🧪 |
| Người thân xem tóm tắt nghe gì, bao lâu (cần chạy migration 0036) | ⬜ **0036 chưa chạy trên Supabase** |
| Danh sách nguồn tin sức khoẻ đã duyệt (`healthStrictAllowlist`) | ⬜ chờ chủ dự án và bác sĩ duyệt |

## 8. Gói và phát hành
| Tính năng | Trạng thái |
|---|---|
| Gói Vy Live: người thân mua, cha mẹ hưởng; admin bấm xác nhận đã thanh toán | ✅ |
| Tự cập nhật app Android qua `app_versions`, kênh bản thử cho tài khoản được phép | ✅ |
| Thông báo đẩy FCM (tin nhắn, thuốc, SOS, gia đình, cảnh báo DEMO) | ✅ |
| Ghi lỗi chưa bắt được thành sự kiện `app_error` | ✅ |

## 9. Máy chủ và quản trị
| Tính năng | Trạng thái |
|---|---|
| `/api/*` trên Vercel (LLM, STT, TTS, OCR, YouTube, nguy cơ, Vy, cảnh báo) + router xoay vòng key | ✅ |
| Web admin `/admin`: KPI, biểu đồ theo ngày, người dùng, nhật ký, khoá API (mã hoá), gói Vy Live, thống kê huyết áp | ✅ |
| Chuẩn bị cho ~500 người dùng (index, thống kê trong SQL, giới hạn tần suất dùng chung) | ✅ |
| CI (flutter analyze + test) | ✅ (chưa chạy trên GitHub) |
| SMTP riêng khi bật xác nhận email | ⬜ |
