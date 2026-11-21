# Kế hoạch sửa UI/UX (từ docs/UI_FLOW_AUDIT.md)

Nhánh: `ui-modern`. Mỗi đợt = 1 commit, `flutter test` xanh, kiểm trên máy ảo `emulator-5554`, ghi `docs/APP_MAP.md`.
Quy tắc chung: không gọi/SOS thật trên máy ảo; xoá dữ liệu thử khỏi Supabase prod; chưa phát hành.

## Đợt 0 – "login flutter" / logo Flutter trên thông báo
Đã kiểm mã: biểu tượng nhỏ thông báo (`ic_stat_viegrand`), FCM `default_notification_icon`, launcher (mipmap + adaptive) đều là logo Viegrand. Không có logo Flutter trong nguồn.
Nghi vấn theo thứ tự:
1. Bản app đang cài trên máy bạn là bản cũ (trước khi đổi icon) → cài lại bản mới.
2. Thông báo/hộp thoại của **Google đăng nhập** (OAuth consent screen: logo + tên app đặt ở Google Cloud Console) → sửa ở Console, không sửa trong app.
3. Thông báo từ app khác/hệ thống (debug build `flutter run` dùng icon mặc định).
Việc làm: bạn cho biết thông báo đó hiện ở đâu (màn hình khoá? lúc bấm đăng nhập Google?) + ảnh chụp. Tôi chỉ sửa khi biết đúng nguồn.

## Đợt 1 – An toàn (làm trước)
| # | Việc | File chính | Cách làm | Kiểm tra |
|---|------|-----------|----------|----------|
| 1.1 (A1) | Thẻ nhắc của Vy không che SOS/lối tắt | `voice/presentation/vy_panel.dart`, `proactive_host.dart` | Thẻ nhắc chủ động chỉ dạng thanh mỏng ở TRÊN màn; chừa vùng đáy (SOS + lối tắt). Nút SOS luôn nằm trên lớp Vy (z-order) | widget test: SOS tìm thấy & bấm được khi thẻ nhắc hiện; máy ảo |
| 1.2 (A2) | Gộp 3 nút "Đã uống" | `home/.../elder_home_screen.dart`, `meds/presentation/meds_view.dart` | Chỉ giữ 1 nơi duy nhất (thẻ thuốc to ở giữa); bỏ ô lặp + bỏ chữ "Bấm Đã uống ở trên" | `elder_home_test` cập nhật; máy ảo |
| 1.3 (A3) | Back ở trang chủ không thoát app | `home/presentation/main_shell.dart` (+ PopScope) | Elder/Family ở tab gốc: Back lần 1 → toast "Bấm lần nữa để thoát"; 2 giây; lần 2 mới thoát. Tab khác → về trang chủ | widget test PopScope; máy ảo |
| 1.4 (A4) | SOS xác nhận 2 lần | `shared/widgets/sos_widgets.dart:64-80` | Giữ 3 giây = đã xác nhận → bỏ hộp "Gọi SOS?"; chỉ hiện đếm ngược 5 giây có nút "Huỷ" | test: giữ đủ → gọi tới `SosService` (fake), không dialog |
| 1.5 (A5) | `state.extra! as ...` văng lỗi | `core/router/app_router.dart` (player, ocrEdit, ocrDetail) | Đổi sang `extra is T ? … : null`; thiếu → redirect về màn danh sách hoặc tải lại theo id trên URL | test router: mở thẳng path không extra không crash |

## Đợt 2 – Điều hướng & nhầm lẫn
| # | Việc | Cách làm |
|---|------|----------|
| 2.1 (B1) | SĐT của mình nhập 2 nơi | Chỉ Hồ sơ là nguồn thật (`profile_phones`). Thẻ y tế: ô "Số điện thoại của bác" đọc từ Hồ sơ, bấm → mở hộp sửa của Hồ sơ |
| 2.2 (B2) | "Đổi vai trò" quá nổi | Chuyển xuống mục "Cài đặt khác", thêm hộp xác nhận (tên vai trò hiện tại → mới) |
| 2.3 (B4) | Giải trí 3 lối thoát | Giữ 1: thanh "Về trang chủ" của shell; bỏ nút back/X trùng trong Giải trí |
| 2.4 (B5) | go/push lẫn lộn từ ô trang chủ | Quy ước: ô trang chủ → `push` (Back về trang chủ); chuyển giữa tab → `go`. Rà `elder_home_screen.dart` |
| 2.5 (B7) | Câu trả lời nhanh trong chat bị cắt | `chat_screen.dart`: `Wrap` nhiều dòng thay hàng cuộn ngang bị cắt, cỡ chữ ≥ 18 |
| 2.6 (B8) | Mic trong chat không nhãn | Thêm nhãn "Nói" dưới mic + `Semantics` + tooltip |

## Đợt 3 – Quyết định sản phẩm (cần bạn chọn, tôi đề xuất)
| # | Vấn đề | Đề xuất |
|---|--------|---------|
| 3.1 (B9) | Cộng đồng liệt kê 57 người lạ | Mặc định ẩn danh sách; chỉ hiện ô tìm kiếm + "Gợi ý 5 người". Giữ hộp xác nhận |
| 3.2 (B11) | Hỏi vai trò 2 lần | Hỏi 1 lần ở `chooseRole`, màn đăng ký bỏ câu hỏi, dùng giá trị đã chọn |
| 3.3 (B12) | Hồ sơ sức khoẻ bắt buộc | Thêm "Để sau" (nhắc lại ở Trang chủ bằng 1 thẻ nhỏ); bỏ ràng buộc router cho nhóm elder |

## Đợt 4 – Rà nốt màn chưa đọc sâu
Màn: `camera_screen`, `ocr_*`, `risk_view`, `health_history`, `family_audit`, `live_lab`, nhánh người thân.
Cho mỗi màn: liệt kê nút → hành vi → màn đích → tình huống lỗi (mất mạng, từ chối quyền, dữ liệu rỗng) → chồng lấp/cắt chữ ở cỡ chữ lớn (textScale 1.3–2.0) → ghi vào `UI_FLOW_AUDIT.md` mục D, rồi lập đợt sửa nhỏ.

## Kiểm thử chung (mỗi đợt)
1. `flutter analyze` + `flutter test` (hiện 341 xanh).
2. Test chữ trước (miễn phí), một lần test giọng thật ở cuối.
3. Máy ảo release build (`adb install -r`), dump UI bằng toạ độ; không bấm Back ở trang chủ trước khi xong 1.3.
4. Rà textScale 1.0 / 1.5 / 2.0 trên màn đã sửa.
5. Cập nhật `docs/APP_MAP.md` + memory `vy-gd1-status.md`.

## Thứ tự & ước lượng
Đợt 1 (≈ 1 phiên) → Đợt 2 (≈ 1 phiên) → bạn chọn Đợt 3 → Đợt 4 (≈ 1–2 phiên) → test giọng thật → merge/phát hành (chỉ khi bạn bảo).
