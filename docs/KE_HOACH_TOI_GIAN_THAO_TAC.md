# Kế hoạch tối giản thao tác và thiết kế giọng nói trước (voice-first)

Ngày lập: 23/11/2026. Trạng thái: **bản nháp để chốt, chưa làm gì trong mã.**
Cơ sở: đọc mã nhánh `feat/bp-aha-protocol` (cắt từ `ui-modern`). Số bước **đếm từ mã**, chưa đo trên máy thật. Màn Gia đình, Camera và Gói Vy Live mới xem lướt.

## 1. Mục tiêu và nguyên tắc

**Mục tiêu:** người cao tuổi làm mọi việc thường ngày với ít chạm nhất, bằng giọng hoặc bằng tay, mà app vẫn đẹp.

**Quy tắc cứng** (thêm vào mục 0 của [APP_MAP.md](APP_MAP.md) khi chốt):

1. Việc dùng hằng ngày: tối đa **2 chạm** từ Trang chủ.
2. Việc nào quá 2 chạm phải có đường **1 câu nói**; đường giọng nói có tối đa **1 bước xác nhận**.
3. Mỗi màn có tối đa **1 hành động chính** thật to; còn lại là phụ.
4. Không hỏi câu mà app tự biết được (giờ, lần đo trước, vai trò) hoặc câu có thể mặc định.
5. Mọi màn phải khai báo điều khiển cho Vy (`VyControlScope`); không có việc nào chỉ làm được bằng tay.
6. Thông tin hiện ra phải có **ngữ cảnh** (thời điểm, độ tin cậy) và không tô cảnh báo cho số liệu chưa đủ chuẩn.
7. Việc cài đặt và chỉnh chi tiết là của người thân, không đặt trước mặt người lớn tuổi.

**Chỉ số thành công** (đo bằng `Analytics`):

| Chỉ số | Hiện tại (ước từ mã) | Mục tiêu |
|---|---|---|
| Chạm để hoàn tất một lần đo huyết áp | 5 đến 7 | 2 |
| Bước để thêm đơn thuốc | 7 đến 9 | 3 |
| Chạm để nhắn một câu có sẵn | 3 | 2 (hoặc 1 câu nói) |
| Tỉ lệ màn có điều khiển Vy | 8/31 | 100% màn người lớn tuổi dùng |
| Thời gian từ chạm Vy tới nghe được tiếng | chờ kết nối Live đến 6 giây mới có lối thoát | chào ngay, không chặn |

## 2. Hiện trạng: các bất cập chính

### 2.1 Trang chủ và Vy
- Ô "Huyết áp gần nhất" luôn hiện dưới quả cầu Vy ([elder_home_screen.dart](../app/lib/features/home/presentation/elder_home_screen.dart), `_MiniBp`). Không có thời điểm đo; số cũ trông như mới.
- Số đo chưa đủ chuẩn (vừa ngủ dậy, `protocol_ok=false`) vẫn gắn nhãn màu "Cao" → trái với chuẩn AHA vừa làm, gây lo.
- Hai ô thông tin cố định chiếm chỗ của "việc cần làm tiếp theo".
- Trên Trang chủ, thanh Vy nằm ở đầu màn và che lời chào, thẻ "Đến giờ uống thuốc" ([vy_panel.dart](../app/lib/features/voice/presentation/vy_panel.dart), `VyPanelHost`).
- Panel Vy nhiều nút trùng chức năng: mic, "Bấm để nói", hàng nói/kết thúc, X.
- Đang nối Live: nút "dùng Vy thường" chỉ hiện sau 6 giây.
- Lưới lối tắt có "Cộng đồng", là tính năng chỉ dùng cho đợt thử nghiệm (APP_MAP mục `community`).
- Trên Trang chủ không có nút gọi người thân; chỉ gọi được qua Vy.

### 2.2 Đo huyết áp ([measure_screen.dart](../app/lib/features/bp/presentation/screens/measure_screen.dart), [measure_controller.dart](../app/lib/features/bp/presentation/providers/measure_controller.dart))
Luồng: chuẩn bị → nghỉ 5 phút → chụp → (xác nhận số lạ) → (hỏi nhịp tim không đều) → (chờ 1 phút, chụp lần 2) → (hỏi triệu chứng nếu quá 180/120) → thẻ việc cần làm.
- 5 đến 7 chạm và 2 đến 3 câu hỏi, trong đó nhiều câu app có thể mặc định.
- Vy mở màn rồi dừng; người dùng tự bấm nút chụp (APP_MAP: "Tự bấm chụp: chưa").
- Màn này không có `VyControlScope`.

### 2.3 Thuốc
- Thêm đơn: Thuốc → thêm → Chụp ảnh → màn trập → "Kiểm tra và chỉnh" → form khoảng 7 ô nhập, 15 nút ([med_scan_screen.dart](../app/lib/features/meds/presentation/med_scan_screen.dart), [med_plan_edit_screen.dart](../app/lib/features/meds/presentation/med_plan_edit_screen.dart)).
- Cữ thuốc trễ phải vào Sức khoẻ → tab Thuốc; Trang chủ chỉ có nút "Đã uống" cho cữ đang đến giờ.

### 2.4 Chat
- Chat mới: sheet → chọn loại → gõ @username (4 bước trở lên), trong khi người dùng thường chỉ nhắn người thân đã liên kết.

### 2.5 Hồ sơ và cài đặt
- Danh sách khoảng 17 dòng; 7 công tắc về Vy và nhắc nằm cạnh nhau ([profile_screen.dart](../app/lib/features/profile/presentation/profile_screen.dart)).

### 2.6 Đăng ký lần đầu
- Đăng ký (3 ô) → chọn vai trò → hoàn tất hồ sơ → thiết lập sức khoẻ (năm sinh, giới tính, chiều cao/cân nặng): khoảng 5 màn trước khi dùng được.

### 2.7 Độ phủ giọng nói
- Chỉ 8 trong 31 màn có `VyControlScope`: bp, community, entertainment, elder_home, main_shell, meds_view, profile và bộ đăng ký.
- Chưa có: đo huyết áp, chat, danh sách phòng, quét/sửa thuốc, thiết lập sức khoẻ, SOS, các màn Gia đình, đăng nhập/đăng ký.
- Vy chỉ đáp khi được hỏi, chưa dẫn dắt khi đang đo (không báo "còn 3 phút", "đưa máy vào khung").

## 3. Thiết kế đề xuất

### 3.1 Trang chủ người lớn tuổi
Từ trên xuống: lời chào + avatar → **thẻ "Việc kế tiếp"** → quả cầu Vy lớn → hàng 3 nút lớn → SOS.

- **Thẻ "Việc kế tiếp"** tự chọn một việc, ưu tiên: (1) thuốc đến giờ ("Đã uống"), (2) đến giờ đo huyết áp mà chưa đo ("Đo bây giờ"), (3) tin nhắn mới ("Nghe"), (4) cữ thuốc kế tiếp, (5) không có việc: gợi ý một câu nói. Dùng lại logic chọn nhắc có sẵn ở [vy_reminders.dart](../app/lib/features/voice/core/vy_reminders.dart) (`decideReminder`), để thẻ trên Trang chủ và nhắc của Vy luôn cùng một nguồn.
- **Số huyết áp gần nhất** chuyển sang tab Sức khoẻ. Nếu vẫn muốn hiện ở Trang chủ: luôn ghi thời điểm ("hôm qua 7:05") và **không tô nhãn mức** khi số đó `protocol_ok=false`.
- **3 nút lớn:** Đo huyết áp · Gọi / Nhắn con · Thuốc. "Gọi / Nhắn con" mở thẳng người liên hệ chính (người thân đã liên kết đầu tiên), gọi 1 chạm.
- Bỏ "Cộng đồng" và "Giải trí" khỏi lưới Trang chủ người lớn tuổi (Giải trí vẫn mở bằng "mở nhạc cho tôi"). **Cần chốt, xem mục 6.**
- **Panel Vy trên Trang chủ:** một nút nói lớn, một nút Kết thúc; bỏ nút lặp. Không che thẻ "Việc kế tiếp": đặt thanh Vy ở đáy khi Trang chủ không còn lưới lối tắt ở đáy (SOS vẫn cần chừa chỗ).
- **Mở Vy không chặn:** chào bằng giọng máy ngay (đã có), nút "dùng Vy thường" hiện sau **2 giây** thay vì 6; Live nối xong thì tự chuyển, không cần người dùng chọn.

### 3.2 Đo huyết áp: 2 chạm
- Vào màn là **vào thẳng đếm ngược "Ngồi yên 5 phút"** (Vy nói bằng giọng). Bỏ màn "đã nghỉ chưa" khi mở từ nhắc hoặc khi đã biết lần đo gần nhất cách quá 30 phút; chỉ hỏi ngoại lệ ("vừa uống cà phê, hút thuốc, đi lại?") bằng một nút phụ nhỏ "Tôi vừa… " thay vì bước bắt buộc. Nút "Bỏ qua, đo luôn" vẫn có và đánh dấu số chưa đủ chuẩn như hiện nay.
- **Camera tự chụp** khi nhận ra khung số của máy đo ổn định khoảng 1 giây (vẫn có nút chụp tay). Cần thử nghiệm: dùng khung có sẵn hoặc kiểm tra nhanh bằng OCR cục bộ; chưa rõ độ chính xác, xem rủi ro.
- **Số lạ** (đang có `bpLooksSuspicious`): Vy hỏi "Máy hiện 150/95 đúng không ạ?" bằng giọng, trả lời "đúng/không" hoặc chạm; không bắt chạm khi số bình thường.
- **Nhịp tim không đều:** chuyển từ câu hỏi bắt buộc sang nút phụ "Máy báo nhịp không đều?" ở thẻ kết quả, mặc định không. Nếu OCR nhận ra biểu tượng thì tự ghi.
- **Lần đo thứ hai** tự đếm 60 giây rồi mở camera, không cần chạm.
- **Hỏi triệu chứng** chỉ khi số quá 180/120 (giữ nguyên, an toàn).
- **Giọng nói:** thêm điều khiển `measure.shoot`, `measure.retake`, `measure.skip_rest`, `measure.flash`; Vy chủ động báo "còn 2 phút", "đưa máy đo vào khung", "con đọc được 130 trên 80, đúng không ạ?".
- **Ghi bằng lời** (`record_bp`, đã có): giữ nguyên, 1 câu + 1 xác nhận.

### 3.3 Thuốc
- **Thêm đơn:** chụp → Vy đọc "Con thấy 3 thuốc: …, uống sáng và tối, lưu nhé?" → "Lưu" (3 bước). Màn chi tiết `med_plan_edit` chỉ mở khi người dùng nói/chạm "Sửa".
- **Cữ trễ** hiện ngay ở thẻ "Việc kế tiếp" với "Đã uống / Nhắc lại 15 phút" (đã có logic `snooze`).
- Thêm điều khiển Vy cho `meds_scan` và `med_plan_edit`.

### 3.4 Tin nhắn và gọi
- Danh sách phòng mở sẵn người thân đã liên kết lên đầu; "Chat mới" chỉ còn trong menu phụ cho người lớn tuổi.
- Trong phòng: giữ câu nhanh (đã có); thêm nút gọi lớn ở thanh trên; điều khiển Vy cho `rooms` và `room`.

### 3.5 Hồ sơ và cài đặt
- Với người lớn tuổi chỉ hiện: tên, Đổi giọng/cỡ chữ (nếu có), Thẻ y tế khẩn cấp, Đăng xuất.
- Gom "Vy tự nhắc …" (3), "Hiện chữ khi Vy nói", "Ô gõ chữ", "Tiếng bật/tắt Vy", "Đọc lời khuyên", "Nhắc đo huyết áp", "Thông báo tin nhắn" vào mục **"Cài đặt nâng cao"** (thu gọn), và cho người thân chỉnh từ xa (cần thiết kế quyền riêng ở bước sau).
- "Mời người thân": 1 chạm mở sheet chia sẻ có sẵn mã.

### 3.6 Đăng ký lần đầu
- Dùng đăng nhập Google làm đường chính; gộp "hoàn tất hồ sơ" với "vai trò" thành một màn khi chọn "Tôi là người lớn tuổi".
- Thiết lập sức khoẻ: giữ nút "Để sau" (đã có), hỏi từng câu một với nút lớn, cho trả lời bằng giọng.

### 3.7 Giọng nói chủ động và độ phủ
- Mọi màn người lớn tuổi dùng đều có `VyControlScope` với nhãn và `aliases`; thêm kiểm thử tự động: duyệt các route, báo lỗi nếu màn không có điều khiển.
- Intent mới đáng làm (APP_MAP mục 4 đã nêu): `read_messages`, `send_image`, `scan_bp` (tự bấm chụp), `summarize_health`.
- Mọi thay đổi giao diện ghi vào APP_MAP (mục 1 và 6) trong cùng thay đổi.

## 4. Đợt triển khai

Mỗi đợt: một nhánh nhỏ, test bằng chữ trước, một lần thử giọng thật ở cuối (theo quy ước tiết kiệm của chủ dự án).

| Đợt | Nội dung | Tệp chính | Xong khi |
|---|---|---|---|
| 1 | Trang chủ: thẻ "Việc kế tiếp", bỏ ô huyết áp cố định (hoặc ghi thời điểm, không tô nhãn số chưa chuẩn), 3 nút lớn, gọn panel Vy, rút mốc "dùng Vy thường" xuống 2 giây | `elder_home_screen.dart`, `vy_panel.dart`, `vy_reminders.dart`, `vy_core.dart` | Widget test: mỗi tình huống (thuốc đến giờ, đến giờ đo, tin mới, không việc) hiện đúng một thẻ; số chưa chuẩn không có nhãn màu |
| 2 | Đo huyết áp 2 chạm: vào thẳng đếm ngược, câu hỏi thành tuỳ chọn, lần 2 tự chạy, điều khiển Vy, Vy báo trạng thái | `measure_screen.dart`, `measure_controller.dart`, `voice_actions.dart` | Test controller: đường mặc định ≤ 2 chạm; test giọng bằng chữ; phiên cũ vẫn lưu `protocol_ok` đúng |
| 3 | Camera tự chụp (thử nghiệm sau cờ) | `measure_screen.dart`, dịch vụ OCR | Thử trên máy thật với 2 đến 3 máy đo; tỉ lệ đọc đúng không thấp hơn chụp tay |
| 4 | Thuốc: quét → đọc lại → lưu 1 chạm; cữ trễ ở thẻ việc kế tiếp | `med_scan_screen.dart`, `med_plan_edit_screen.dart` | Test luồng 3 bước; sửa chi tiết vẫn dùng được |
| 5 | Chat/gọi, Hồ sơ gọn, đăng ký gộp, mời 1 chạm | `room_list_screen.dart`, `chat_screen.dart`, `profile_screen.dart`, màn auth | Chỉ số chạm đạt mục tiêu; không mất tính năng của người thân |
| 6 | Phủ `VyControlScope` mọi màn, intent mới, kiểm thử duyệt route, cập nhật APP_MAP | các màn còn lại, `api/_lib/voice/dm.ts` | Kiểm thử duyệt route xanh; APP_MAP đủ |

Đề xuất làm theo thứ tự 1 → 2 → 4 → 5 → 6; đợt 3 thử song song khi có máy.

## 5. Rủi ro và cách giảm

- **Bỏ câu hỏi "đã nghỉ chưa" làm số đo kém chuẩn:** mặc định vẫn bắt nghỉ 5 phút; chỉ bớt bước chọn, không bớt nghỉ. Giữ nhãn `protocol_ok`.
- **Tự chụp sai số:** luôn cho người dùng xác nhận số lạ; để sau cờ và đo tỉ lệ đọc đúng trước khi bật rộng.
- **Ẩn cài đặt khỏi người lớn tuổi:** cần chỗ cho người thân chỉnh từ xa; làm sau, giữ mục "nâng cao" trước.
- **Bỏ ô số huyết áp khỏi Trang chủ:** một số người quen thấy ngay; thử với người dùng thật trước khi bỏ hẳn (có thể giữ dạng nhỏ, có thời điểm).
- **Giọng nói tốn chi phí khi thử:** thử bằng chữ trước, một lần thử giọng cuối mỗi đợt.
- **Không phá bản đã phát hành:** thay đổi giao diện không đụng cấu trúc dữ liệu; đợt 2 giữ nguyên cột và quy tắc AHA hiện có.

## 6. Việc cần chốt trước khi làm

1. Nút thứ ba trên Trang chủ: "Thuốc" hay "Giải trí"? (Đề xuất: Thuốc; Giải trí mở bằng giọng và trong menu phụ.)
2. Số huyết áp gần nhất: bỏ hẳn khỏi Trang chủ, hay giữ nhỏ kèm thời điểm và không tô nhãn số chưa chuẩn?
3. "Gọi / Nhắn con": chọn người liên hệ chính tự động (người thân đầu tiên) hay cho người dùng chọn một lần?
4. Người thân có được chỉnh cài đặt Vy và nhắc từ xa không (liên quan quyền và nhật ký)?
5. Camera tự chụp có làm ngay ở đợt 2 hay thử riêng ở đợt 3?

## 7. Chưa kiểm tra

- Chưa chạy app trên máy thật nên số chạm là ước từ mã.
- Chưa đọc kỹ màn Gia đình, Camera, Gói Vy Live, thiết lập sức khoẻ (từng bước), và các bước đăng nhập.
- Chưa có số liệu dùng thật (tỉ lệ bỏ giữa chừng từng bước). Nên lấy từ `Analytics` (`tap_feature`, `bp_prep_view`, `bp_rest_skip`, `vy_open`, `vy_close`) trước khi quyết định bỏ hẳn ô nào.

## 8. Tiến độ thực hiện (24/11/2026)

Đã làm trong một lượt, trên nhánh `feat/bp-aha-protocol` (chưa commit, chưa phát hành). Các điểm cần chốt ở mục 6 dùng mặc định đề xuất.

| Đợt | Kết quả | Ghi chú |
|---|---|---|
| 1 | Xong | Trang chủ: thẻ "Việc kế tiếp" (`home/domain/next_task.dart`), 3 nút lớn, bỏ ô số huyết áp cố định và lưới 4 ô; panel Vy bỏ nút "Tắt Vy" lặp, nút "Nói bằng Vy thường" sau 2 giây. **Chưa làm:** dời thanh Vy khỏi đầu Trang chủ (vẫn che thẻ khi mở); thẻ tin nhắn mới (cần nguồn dữ liệu riêng, Vy vẫn tự nhắc tin) |
| 2 | Xong một phần | Vào màn đo là đếm ngược 5 phút ngay; "Bác đã ngồi nghỉ rồi, đo luôn"; "Vừa uống cà phê, đi lại" mở chọn bối cảnh; số đầu cao vừa phải tự đếm 1 phút; điều khiển Vy cho màn đo. **Chưa làm:** hỏi nhịp tim không đều chuyển thành tuỳ chọn; Vy chủ động báo "còn n phút"; lặp lại câu hỏi số lạ bằng giọng |
| 3 | Chưa làm | Camera tự chụp: cần thử trên máy thật với máy đo thật, nên để riêng |
| 4 | Xong một phần | "Lưu luôn" khi mọi thuốc khớp ảnh, không mục bị bỏ, chưa có đơn đang dùng; vẫn có "Chỉnh trước khi lưu". Giữ nguyên nguyên tắc: không tự bật lịch khi còn mục "gần giống" hoặc bị bỏ. **Chưa làm:** cữ trễ ở thẻ việc kế tiếp |
| 5 | Xong một phần | Điều khiển Vy cho danh sách phòng và câu trả lời nhanh (mức xác nhận). **Không cần làm:** Hồ sơ người cao tuổi đã gọn sẵn (3 lối tắt, còn lại trong "Cài đặt khác"); màn Tin nhắn đã có nút "Nhắn cho …" một chạm. **Chưa làm:** nút gọi 1 chạm, mời người thân 1 chạm, gộp đăng ký |
| 6 | Xong một phần | Điều khiển Vy cho màn đo, quét thuốc, danh sách phòng, chat; thêm `test/vy_coverage_test.dart` giữ độ phủ; APP_MAP đã cập nhật. **Còn thiếu:** `med_plan_edit`, `med_plan_list`, `health_setup`, `sos`, `player`, các màn Gia đình |

**Điều chỉnh so với mục 2:** sau khi đọc kỹ, Hồ sơ của người cao tuổi và màn Tin nhắn đã được rút gọn từ trước, nên hai mục 2.4 và 2.5 đánh giá nặng hơn thực tế.

### Đợt bổ sung (24/11/2026)

- **Trang chủ:** thẻ "Việc kế tiếp" ẩn (giữ chỗ) khi Vy mở, nên thanh Vy không còn che lên thẻ. Cữ thuốc trễ: không thêm vì cữ còn trong cửa sổ uống đã hiện ở thẻ "Đã uống"; quá cửa sổ thì hệ thống không cho ghi uống.
- **Đo huyết áp:** câu hỏi nhịp tim không đều chỉ còn một dòng nhỏ tuỳ chọn (mặc định không); Vy tự nói "còn 2 phút", "còn 1 phút" và "hết giờ nghỉ, bấm nút chụp".
- **Tin nhắn:** nút gọi xanh cạnh "Nhắn cho …" gọi thẳng bằng số người thân tự điền ở Hồ sơ (1 chạm; chưa có số thì báo rõ, không gọi). Vy có điều khiển `rooms.call.<id>` (mức xác nhận).
- **Điều khiển Vy thêm:** sửa đơn thuốc (`plan.save`, `plan.slot.*`), danh sách đơn (`plans.new`, `plans.scan`), thiết lập sức khoẻ (`setup.next`, `setup.skip`), mời người thân (`invite.create`, `invite.share`).
- **Còn lại có chủ ý:** camera tự chụp (cần thử máy thật); mời người thân 1 chạm và gộp đăng ký (đụng luồng đăng nhập, cần thử riêng); điều khiển cho SOS (việc an toàn, người dùng tự bấm), trình phát (Vy đã điều khiển được bằng lệnh video), màn Gia đình (của người thân).
