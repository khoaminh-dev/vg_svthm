# Rà soát luồng UI/UX (21/11/2026)

Phạm vi và độ tin cậy: đã đọc `app_router.dart`, `main_shell.dart`, trang chủ người cao tuổi, Hồ sơ, Vy panel; đã đọc/quét nút và điều hướng của Huyết áp, Đo huyết áp, Thuốc (xem, sửa, chụp đơn), SOS, Chat, Giải trí, Cộng đồng, Đăng nhập/Đăng ký/Chọn vai trò, Sức khoẻ ban đầu, Thẻ y tế, các màn người thân. Chưa đọc sâu: `camera_screen`, `ocr_*`, `risk_view`, `health_history`, `family_audit`, `live_lab`.
Mỗi mục ghi nguồn: **[máy ảo]** đã thấy tận mắt, **[mã]** đọc từ mã, **[cần kiểm]** suy ra, chưa xác nhận.

## 1. Sơ đồ màn hình

```
Đăng nhập ─┬─ Đăng ký ─→ (quay lại Đăng nhập)
           └─ Google ─→ Hoàn tất hồ sơ (chưa có username) ─→ Chọn vai trò (chưa có role)
Sau đăng nhập, theo vai trò:
  Người cao tuổi: (chưa có hồ sơ sức khoẻ → Sức khoẻ ban đầu, bắt buộc) → TRANG CHỦ
  Người thân:     TRANG CHỦ (Gia đình) · Cảnh báo · Tin nhắn · Tôi
  Cài hộ cha mẹ:  lần đầu vào → Mời người thân
```

Người cao tuổi (không có thanh tab, chỉ thanh "Về trang chủ" + nút Vy):

```
TRANG CHỦ ─ Vy (chạm rồi nói)
 ├─ Avatar → Hồ sơ ─ Mời người thân / Thẻ y tế / Hồ sơ sức khoẻ / Đổi vai trò / Nhắc đo HA / Cài đặt khác / Đăng xuất
 ├─ Thanh "Đến giờ uống thuốc" → Đã uống (tại chỗ)
 ├─ Ô Đo huyết áp → Camera đo → kết quả → Xong → TRANG CHỦ
 ├─ Ô Thuốc → /bp tab Thuốc → Xem/sửa lịch → Danh sách đơn → Sửa/Thêm → (Chụp đơn → Sửa)
 ├─ Ô Sức khoẻ → /bp tab Huyết áp → Lịch sử / Xem nguy cơ
 ├─ Ô Tin nhắn → Danh sách → Nhắn cho <người thân>/người khác → Phòng chat
 ├─ Ô Cộng đồng → Danh sách 57 người → (hỏi lại) → Phòng chat
 ├─ Ô Giải trí → 6 mục → Danh sách video → Trình phát
 └─ Nút SOS (giữ 3 giây) → Màn SOS → Thẻ y tế
```

## 2. Vấn đề tìm được, xếp theo mức

### Nghiêm trọng (an toàn, kẹt luồng)

| # | Vấn đề | Chứng cứ | Đề xuất |
|---|---|---|---|
| A1 | **Thẻ nhắc của Vy che nút SOS và các ô lối tắt.** Thẻ lớn chiếm ~40% đáy màn đúng chỗ nút SOS giữ 3 giây. Người đang được nhắc thuốc muốn bấm SOS thì thấy panel che. | [máy ảo] ảnh chụp Trang chủ lúc có thẻ nhắc: thấy tiêu đề Vy, thẻ thuốc, hai nút to, không thấy SOS | Đưa SOS thành lớp nổi luôn ở trên cùng (trên cả Vy panel) hoặc đặt thẻ nhắc lên đầu màn, dưới lời chào, thay vì đáy |
| A2 | **Ba nơi cùng làm một việc "Đã uống"** (thanh trên cùng, ô "Thuốc: Đang đến giờ", thẻ nhắc Vy): rối, và ô giữa ghi "Bấm Đã uống ở trên" phụ thuộc bố cục | [máy ảo] trang chủ | Khi có thẻ nhắc hoặc thanh "Đến giờ", ẩn ô "Thuốc: Đang đến giờ"; chỉ giữ một nút "Đã uống" |
| A3 | **Back ở trang chủ thoát thẳng app**, không hỏi. Người cao tuổi hay bấm Back nhầm rồi tưởng app hỏng | [máy ảo] bấm Back ở trang chủ ra màn hình điện thoại | "Bấm lần nữa để thoát" hoặc không thoát, giữ ở trang chủ |
| A4 | **Cần kiểm: SOS có thể bị xác nhận hai lần** (giữ 3 giây rồi hộp "Gọi SOS?") làm chậm lúc khẩn cấp | [mã] `sos_widgets.dart:64-80` có hộp "Gọi SOS?"; chưa rõ nó chạy khi nào | Kiểm tra: giữ đủ 3 giây thì gọi luôn; hộp chỉ dành cho chạm nhanh (nếu có) |
| A5 | **`state.extra! as ...` trong router** cho Trình phát, Sửa/Chi tiết OCR: mở lại app giữa chừng hoặc deep link làm `extra` rỗng thì văng lỗi | [mã] `app_router.dart` | Nếu `extra` rỗng thì quay về màn cha, không `!` |

### Quan trọng (dễ hiểu sai, dư, mâu thuẫn)

| # | Vấn đề | Chứng cứ | Đề xuất |
|---|---|---|---|
| B1 | **Số điện thoại của mình nhập ở hai nơi**: Hồ sơ ("Số điện thoại của tôi") và Thẻ y tế ("Số điện thoại của bác") | [mã] `emergency_card_screen.dart:144` và `profile_screen.dart` | Gộp: Thẻ y tế đọc từ `profile_phones`, bỏ ô nhập thứ hai |
| B2 | **"Đổi vai trò" nằm ngay Hồ sơ người cao tuổi**: chạm nhầm là gần đổi giao diện (có hộp xác nhận nhưng vẫn là nút hiếm dùng đặt ở chỗ dễ chạm) | [máy ảo] Hồ sơ | Chuyển vào "Cài đặt khác" |
| B3 | **Số điện thoại của tôi vẫn là mục thấp trong Hồ sơ** sau khi đã đưa ra ngoài; Hồ sơ dài, phải cuộn tới 4 màn hình để tới "Cài đặt khác" | [máy ảo] | Gom nhóm: Người thân · Y tế · Cài đặt; mỗi nhóm một khối |
| B4 | **Ba cách thoát ở Giải trí**: nút X góc phải, "Chọn mục khác", "Quay lại" đáy | [máy ảo] + [mã] | Chỉ giữ "Quay lại" (đáy) và "Chọn mục khác" khi đang xem kết quả |
| B5 | **Điều hướng không nhất quán**: ô Thuốc/Sức khoẻ/Tin nhắn dùng `go` (thay ngăn xếp), ô Đo huyết áp/Cộng đồng/Giải trí dùng `push`. Nút Back hệ thống cho kết quả khác nhau | [mã] `elder_home_screen.dart:74-92` | Thống nhất: mọi ô từ trang chủ dùng `push`; Back luôn về trang chủ |
| B6 | **Ô "Sức khoẻ" và "Thuốc" đều mở `/bp` với tab khác**, "Đo huyết áp" mở thẳng camera: ba ô tối đa hai màn khác nhau, tên màn trước đây không khớp tên ô (đã sửa phần tên) | [máy ảo] | Giữ; kiểm tra thêm: tab dưới của `/bp` hiển thị gì cho người cao tuổi (hiện ẩn) |
| B7 | **Câu trả lời nhanh trong chat bị cắt ngang** ("Gọi lại giúp nh…"), người dùng không biết còn lựa chọn | [máy ảo] phòng chat | Xếp 2 hàng hoặc giảm còn 3 câu |
| B8 | **Nút mic góc phải phòng chat không có chữ** | [máy ảo] | Thêm chữ "Nói" hoặc nhãn khi chạm giữ |
| B9 | **Cộng đồng liệt kê mọi tài khoản** (57) cho người cao tuổi; đã thêm hộp hỏi lại, nhưng đây vẫn là quyết định sản phẩm | [máy ảo] | Ẩn với người cao tuổi hoặc chỉ cho tìm theo @username |
| B10 | **Tên "login flutter"** hiện ở thông báo/hộp chọn tài khoản | báo cáo của chủ dự án | Xem mục 4 |
| B11 | **Đăng ký** bắt chọn vai trò ngay trên form dài, sau đó vẫn có "Chọn vai trò" | [mã] `register_screen.dart`, `choose_role_screen.dart` | Hai chỗ hỏi vai trò: giữ một (khi đăng ký) hoặc bỏ ở đăng ký, hỏi sau (như Google) |
| B12 | **Sức khoẻ ban đầu bắt buộc** (không có "Để sau"); người cao tuổi chưa sẵn sàng phải điền 2 bước mới vào được app | [mã] `app_router.dart` redirect | Cho "Để sau", nhắc lại sau 1 lần dùng |

### Nhỏ (làm cho gọn)

- C1 Màn Huyết áp trống chiếm cả màn chỉ với một câu; thêm hình minh hoạ hoặc ví dụ kết quả.
- C2 "Lát nữa nhắc" ở thẻ Vy không nói thời gian; ghi "(15 phút)" trong nội dung thẻ.
- C3 Màn Thuốc hôm nay không có cữ nào, nút "Xem và sửa lịch thuốc" ở đáy bị đẩy xuống dưới thanh Về trang chủ khi danh sách dài [cần kiểm].
- C4 `medsPlanFor(owner, planId)` bỏ qua `planId` (tham số thừa).
- C5 Hồ sơ người cao tuổi hiện tên không dấu "Nguoi Thu Nghiem" (tài khoản thử, không phải lỗi).

## 3. Luồng từng nút (người cao tuổi): tình huống có thể xảy ra

### Trang chủ
| Nút | Bình thường | Tình huống lạ | Đã xử lý? |
|---|---|---|---|
| Vy (quả cầu) | Mở panel, nghe | Mất mạng → Vy thường (giọng máy) rồi báo lỗi; im lặng 30 giây → hỏi "còn cần con không?" rồi tự đóng | Có |
| Avatar | Hồ sơ | – | Có |
| Đã uống (thanh trên) | Ghi nhận, báo "Đã ghi nhận" | Mạng lỗi → báo lỗi, giữ thanh | Có [mã] |
| Ô Đo huyết áp | Camera đo | Từ chối camera → "Chưa mở được camera. Bác cho phép… hoặc chọn ảnh có sẵn" | Có [mã] |
| Ô Thuốc / Sức khoẻ / Tin nhắn / Cộng đồng / Giải trí | Mở màn | Vy đang mở: bấm ô vẫn đi tiếp, panel thu về thanh nhỏ | Có |
| SOS giữ 3 giây | Màn SOS, báo người thân | Không mạng → "Chưa gửi được" + "Thử gửi lại"; vẫn có nút gọi 115 | Có [mã] |
| Back hệ thống | **Thoát app** | – | **Chưa** (A3) |

### Đo huyết áp
Chụp → "Đang đọc số…" → kết quả tự lưu ("Đã tự lưu") → Nghe lại / Chụp lại / Xong. Tình huống: số không đọc được (chụp lại, hoặc chọn ảnh có sẵn); số cao thấy nút "Gọi 115" và "Tăng huyết áp" [mã]; đang đo thì Vy nhắc thuốc: tránh (đã đặt "busy" khi ở màn đo).

### SOS
Giữ đủ 3 giây → gửi → màn SOS theo dõi mỗi 5 giây: "Đang chờ người thân nhận" → "… đã nhận" / "SOS đã huỷ". Huỷ có hộp "Bác ổn, bấm nhầm?". Có nút "Điền hoặc sửa thẻ y tế khẩn cấp".

### Thuốc
Cữ đến giờ: Đã uống / Nhắc sau 15 phút / Bỏ qua cữ. Chưa có lịch: "Thêm lịch thuốc" / "Chụp đơn thuốc". Chụp đơn: đọc chữ trên máy → "Kiểm tra và chỉnh trước khi lưu" → chỉ sau khi bấm Lưu mới có báo thức (đúng nguyên tắc an toàn).

### Tin nhắn / Cộng đồng
Rỗng: một nút "Nhắn cho người khác" + dòng hướng dẫn. Người thân liên kết hiện nút "Nhắn cho <tên>". Cộng đồng: chạm vào ai cũng hỏi "Nhắn tin cho …?" trước khi tạo phòng.

### Giải trí
Chọn mục → "Đang tìm video…" → lưới video (có số) → Trình phát. Lỗi: "Chưa tìm được video… thử lại". Video không cho nhúng: nút "Mở bằng app YouTube" (rời app, quay lại bằng Back).

## 4. "login flutter"

Không có chuỗi này trong mã nguồn, manifest hay cấu hình của app (đã quét). Nhãn app là "Viegrand". Khả năng cao nhất: tên **màn hình đồng ý OAuth của Google** (Google Cloud Console → APIs & Services → OAuth consent screen → App name) hoặc tên dự án Firebase/OAuth client dùng cho "Đăng nhập bằng Google", hiện ở hộp chọn tài khoản. Cần chủ dự án gửi ảnh chụp để xác nhận nơi hiện chữ. Sửa ở Google Cloud Console, không phải mã.

## 5. Thứ tự đề xuất làm

1. A1 (SOS không bị che) + A2 (gộp "Đã uống") + A3 (Back trang chủ).
2. A4 (kiểm SOS 2 lần xác nhận), A5 (router `extra`).
3. B1 (gộp số điện thoại), B2, B4, B5, B7, B8.
4. B9, B11, B12 cần quyết định sản phẩm.
5. Rà nốt các màn chưa đọc sâu (camera, OCR, risk_view, lịch sử, nhật ký, live lab) và toàn bộ nhánh người thân.

---

## D. Rà Đợt 4: các màn còn lại và nhánh người thân (21/11/2026)

Cách rà: đọc mã từng màn (nút, đích đến, trạng thái rỗng/lỗi), tìm nơi dẫn tới màn đó. Chưa chạy từng màn trên máy ảo và chưa thử chữ cỡ 1.5–2.0.

### D.1 Bản đồ nút (tóm tắt)
| Màn | Vào từ | Nút → đích | Trạng thái |
|---|---|---|---|
| Camera (`/camera`) | Thẻ "Camera" ở Gia đình (chỉ người thân, cờ `camera`) | Quay lại (pop) · Cài đặt camera (bảng dưới: kiểu khung, ngưỡng) · chip chọn phòng · Nhận diện bật/tắt · Làm mới · Phóng to / Thu nhỏ | Có đủ: đang kết nối, lỗi + Thử lại |
| OCR (`/ocr`, `/ocr/edit`, `/ocr/detail`) | **Không có nút nào dẫn tới** | Chụp ảnh / Thư viện → sửa → Lưu; chi tiết: Sao chép, Xoá (có hộp xác nhận) | Đầy đủ lỗi; `extra` thiếu đã được sửa ở Đợt 1 |
| Risk (khối trong tab Sức khoẻ) | Tab Sức khoẻ | Đo huyết áp · Hồ sơ sức khoẻ · Lịch sử hỏi Vy · gọi cấp cứu · Đồng ý / Không, cảm ơn (xin phép) | Lỗi biểu đồ ẩn im lặng |
| Lịch sử hỏi Vy | Risk → "Lịch sử" | Xoá hết (xác nhận) · Thử lại | Rỗng có gợi ý câu nói |
| Nhật ký gia đình | Người thân theo dõi → "Nhật ký" | Quay lại | Lỗi: chỉ một nút "Thử lại" trơ trọi |
| Live lab | Chạm 7 lần dòng phiên bản, chỉ debug/`VG_LAB` | — | Nội bộ, người dùng thường không thấy: bỏ qua |
| Gia đình (family home) | Tab 1 | Thẻ người → chi tiết · Nhắn tin (hỏi qua tạo phòng) · Thuốc · Nhờ đo · Nhập mã | Rỗng có "Nhập mã người thân" |
| Chi tiết người thân | Thẻ ở Gia đình | Xem/sửa lịch thuốc · Điền/sửa thẻ y tế | Có "Chưa tải được thẻ" |
| Cảnh báo | Tab 2 | Chạm cảnh báo → SOS hoặc chi tiết người | Lỗi có Thử lại; rỗng có "Nhập mã của cha mẹ" |
| Mời / Tham gia | Hồ sơ / Gia đình | Chép mã · Gửi mã · Tạo mã mới · Gỡ (xác nhận) · Theo dõi | Mã 7 ký tự có bộ lọc |

### D.2 Vấn đề tìm được
| # | Vấn đề | Mức | Đề xuất |
|---|---|---|---|
| D1 | **Ba màn OCR mồ côi**: có route, có test nhưng không nút nào mở, nên người dùng không bao giờ thấy | Trung bình | Quyết: gắn vào màn Đo huyết áp ("Chụp ảnh màn hình máy đo") hoặc bỏ khỏi bản phát hành |
| D2 | **Người thân không gọi được cha mẹ ngay từ thẻ** dù đã có số điện thoại (`profile_phones`) | Cao (giá trị) | Thêm nút "Gọi" ở thẻ Gia đình và trang chi tiết, số lấy bằng `PhoneRepository.ofUsers`; không có số thì ẩn nút hoặc dẫn "Chưa có số" |
| D3 | Camera hiện chữ nội bộ: "Ngưỡng cảnh báo demo", "Nhận diện: bật/tắt", chữ cỡ 15; chip phòng cuộn ngang (cùng lỗi cắt chữ như chat) | Thấp | Đổi nhãn dễ hiểu; chip dùng Wrap; chữ ≥ 16 |
| D4 | **Màn đẩy từ trang chủ người cao tuổi không có thanh "Về trang chủ"** (Đo huyết áp, Thẻ y tế, Hồ sơ sức khoẻ, Lịch sử, Thuốc, Phòng chat...): chỉ Cộng đồng và Giải trí có `ElderBackBar` | Trung bình | Bọc các màn này bằng thanh to chung (hoặc làm trong `MainShell`) để cách thoát giống nhau |
| D5 | Màn Nhật ký lỗi chỉ có nút "Thử lại", không có lời; biểu đồ Risk ẩn lỗi im lặng | Thấp | Thêm dòng "Chưa tải được, bác thử lại nhé" |
| D6 | Chữ "bác" viết cứng ở nhiều màn trong khi Vy dùng cách xưng hô đã chọn (`loadHonorific`) | Thấp | Dùng chung một hàm xưng hô cho chữ trên màn |
| D7 | Nút "Nhờ đo" ở thẻ Gia đình chưa rõ nghĩa | Thấp | Đổi thành "Nhắc đo" và ghi rõ trong thông báo kết quả |
| D8 | Nhắn tin từ thẻ Gia đình tạo phòng ngay không hỏi (khác Cộng đồng đã hỏi) | Thấp | Có thể giữ: người thân đã liên kết, không phải người lạ |

### D.3 Đã kiểm, ổn
Hộp xác nhận xoá OCR/lịch sử/gỡ người thân có đủ chữ và nút; `extra` thiếu không còn văng lỗi; Live lab bị khoá ngoài bản nội bộ; mã mời có chép/gửi/tạo mới; trạng thái rỗng và lỗi có hướng dẫn ở Cảnh báo, Gia đình, Lịch sử.

### D.4 Thứ tự đề xuất cho Đợt 5
1. D2 nút Gọi cho người thân (giá trị lớn nhất, đã có dữ liệu).
2. D4 thanh "Về trang chủ" thống nhất cho người cao tuổi.
3. D1 quyết OCR.
4. D3, D5, D6, D7 chữ và nhãn.
