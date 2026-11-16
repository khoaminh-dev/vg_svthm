# Kế hoạch: Gia đình, Thuốc, Bản đồ

Ngày soạn: 16/11/2026. Trạng thái: **kế hoạch, chưa code**. Tài liệu này là nguồn chuẩn để làm từng giai đoạn; mỗi lần đổi quyết định thì sửa ở đây trước.

## 1. Mục tiêu

Con cái đi làm xa nhìn vào cùng một app là biết cha mẹ đang thế nào: huyết áp, nguy cơ, đã uống thuốc chưa, đang ở đâu, và được báo khi có chuyện. Cha mẹ chỉ cần làm những thao tác rất ít và rất to: đo huyết áp, bấm "Đã uống", bấm SOS khi cần.

Nguyên tắc xuyên suốt:
1. **Một app, mỗi người một tài khoản.** "Chế độ con cái" là cách nhìn, không phải tài khoản riêng.
2. **Cha mẹ là người cho phép.** Mọi liên kết do cha mẹ đưa mã, cha mẹ thấy ai đang xem và gỡ được bất cứ lúc nào.
3. **An toàn thuốc hơn tiện lợi.** Máy không bao giờ tự kích hoạt lịch thuốc từ ảnh; không tư vấn thuốc.
4. **Số liệu do máy chủ dựng từ khuôn câu**, không để mô hình ngôn ngữ nói số liệu sức khoẻ (đã áp dụng cho Vy).
5. **Mỗi giai đoạn là một bản phát hành dùng được**, không có "đợi làm xong hết mới thử".

## 2. Quyết định đã chốt (16/11/2026)

| # | Quyết định |
|---|---|
| 1 | Mỗi người một tài khoản, liên kết bằng mã; không dùng chung một tài khoản |
| 2 | "Map" là bản đồ vị trí của cha mẹ cho con xem |
| 3 | Quyền mặc định cho con: huyết áp, nguy cơ, thuốc, vị trí = có. Tin nhắn = không. Lịch sử hỏi Vy = tắt, cha mẹ bật mới có |
| 4 | Nhiều-nhiều: một con theo dõi nhiều cha mẹ, một cha mẹ có nhiều con |
| 5 | Ảnh thuốc: ảnh gốc ở lại máy con; chỉ gửi chữ đã bỏ tên và thông tin cá nhân ra bên thứ ba |
| 6 | Nhắc lại sau 15 phút, báo con sau 45 phút nếu chưa bấm "Đã uống" |

## 3. Nền tảng: tài khoản liên kết

### 3.1 Tại sao không dùng chung một tài khoản

Dùng chung một mật khẩu làm hỏng: phân biệt ai nhắn tin, vị trí của máy nào, ai bấm "Đã uống", đo huyết áp tính cho ai, thu hồi quyền (phải đổi mật khẩu của cha mẹ), nhiều con cùng một mật khẩu, và quyền riêng tư (con thấy hết tin nhắn của cha mẹ). Vì vậy mỗi người một tài khoản.

### 3.2 Mô hình dữ liệu (migration 0021)

**`family_links`**: một dòng cho mỗi cặp (người được chăm sóc, người chăm sóc).

| Cột | Ý nghĩa |
|---|---|
| `id` | khoá |
| `owner_id` | người được chăm sóc (cha mẹ) |
| `carer_id` | người chăm sóc (con) |
| `relation` | `con`, `cháu`, `vợ/chồng`, `khác` (để Vy xưng hô và để hiển thị) |
| `perms` | jsonb: `health`, `meds_view`, `meds_edit`, `location`, `profile_edit`, `vy_history`, `alerts` (mặc định theo mục 2) |
| `status` | `active`, `paused`, `revoked` |
| `created_at`, `revoked_at`, `revoked_by` | |

Ràng buộc: duy nhất `(owner_id, carer_id)`; `owner_id <> carer_id`.

**`link_codes`**: mã 6 số do cha mẹ tạo.

| Cột | Ý nghĩa |
|---|---|
| `owner_id` | người tạo mã |
| `code_hash` | băm của mã (không lưu mã thô) |
| `expires_at` | 10 phút |
| `attempts` | số lần nhập sai; quá 5 thì khoá mã |
| `used_at`, `used_by` | mã dùng một lần |

Hàm (security definer): `create_link_code()`, `redeem_link_code(code, relation)`, `revoke_link(link_id)`, `set_link_perms(link_id, perms)`, `leave_link(link_id)` (con tự rút).
Chống dò mã: giới hạn số lần nhập mã theo người nhập (bảng `api_rate` có sẵn) và theo mã.

**`family_audit`**: ai làm gì lúc nào (xem vị trí, sửa lịch thuốc, sửa hồ sơ, đổi quyền). Cha mẹ đọc được dòng của mình.

**Hàm quyền** (nền của mọi chính sách RLS):
- `can_view(owner, kind)` đúng khi `owner = auth.uid()` hoặc có liên kết `active` với `perms[kind]`.
- `can_edit(owner, kind)` tương tự cho quyền sửa.
Cả hai `security definer stable`, có chỉ mục `(owner_id, carer_id) where status='active'`.

### 3.3 Mở quyền đọc cho con (migration 0022)

Thêm chính sách `select` theo `can_view` cho: `bp_readings`, `health_assessments`, `health_profile`, `health_qa` (khoá `vy_history`), và các bảng thuốc, vị trí về sau. **Không** mở: `messages`, `room_members`, `voice_*`, `ocr_records`, `health_feedback`, `push_prefs`, `device_tokens`.
Thêm quyền ghi có điều kiện: con có `meds_edit` được ghi bảng thuốc; con có `profile_edit` được sửa `health_profile` của cha mẹ; con có `health` + được cha mẹ cho phép thì chụp huyết áp hộ (`bp_readings.insert` với `user_id = owner`), kèm cột mới `recorded_by`.

### 3.4 Thay đổi ở app: khái niệm "chủ thể"

Hiện **17 tệp** trong app đang mặc định "chủ thể = người đăng nhập" (`currentUserProvider`, `auth.uid()`): huyết áp, hồ sơ sức khoẻ, đánh giá, lịch sử hỏi Vy, Trang chủ, Vy, đẩy thông báo…
Cách xử lý: thêm `activeSubjectProvider` (mặc định là chính mình; ở chế độ con cái là người thân đang chọn). Các kho dữ liệu nhận `ownerId` thay vì đọc `auth.uid()`. Làm từng phần, mỗi phần có test: huyết áp, hồ sơ, đánh giá trước; thuốc, vị trí là bảng mới nên viết đúng ngay từ đầu.

Máy chủ:
- `/api/health-risk` nhận thêm `owner` (mặc định chính người gọi); kiểm tra `can_edit` trước khi tính hộ.
- Cron và Edge Function luôn dùng `owner_id` rõ ràng, không suy ra từ người gọi.

### 3.5 Tài khoản cho cha mẹ chưa dùng điện thoại thạo: "Thiết lập hộ"

Đây là cách dùng thực tế: **con cầm máy cha mẹ, cài app, thiết lập một lần.** Luồng:
1. Con mở app trên máy cha mẹ, bấm "Đăng nhập bằng Google" (tài khoản Google của máy; hoặc tạo tên đăng nhập, mật khẩu).
2. Trình hướng dẫn (5 bước): tên và cách xưng hô, năm sinh và hồ sơ sức khoẻ, cấp quyền (thông báo, báo thức chính xác, tắt tối ưu pin, vị trí), cho phép nghiên cứu hay không, **tạo mã liên kết**.
3. Con nhập mã trên máy của con. Xong; con có thể về lại máy mình.
4. Cha mẹ nhận thông báo "Con Minh đang theo dõi bác. Bác có thể gỡ trong Hồ sơ."

Chia sẻ lời mời qua Zalo hoặc Messenger (share sheet) cho trường hợp con ở xa và cha mẹ tự bấm được.

## 4. Chế độ con cái

### 4.1 Khái niệm

"Chế độ" không phải thuộc tính tài khoản. Ai có ít nhất một liên kết `carer` thì thấy tab **Gia đình** và công tắc ở Hồ sơ "Chế độ: Dùng cho bản thân | Theo dõi người thân". Một người có thể vừa là con của người này vừa là cha của người khác; chế độ chỉ nhớ lần chọn cuối. Người chưa có liên kết không bao giờ thấy gì khác.

### 4.2 Điều hướng

| | Người được chăm sóc (chế độ bản thân) | Người chăm sóc (chế độ theo dõi) |
|---|---|---|
| Tab | Trang chủ, Tin nhắn, Sức khoẻ, Hồ sơ | **Gia đình**, Thuốc, Bản đồ, Tin nhắn, Hồ sơ |
| Thuốc | Thẻ "Thuốc hôm nay" ở Trang chủ + mục thứ ba trong Sức khoẻ (Huyết áp / Đánh giá / Thuốc) | Tab riêng |
| Chữ | To như hiện nay | Gọn hơn, nhiều thông tin hơn |
| Vy | Như hiện nay | Hiểu "mẹ", "ba" trỏ vào người thân; chỉ đọc số liệu khi có quyền |

### 4.3 Màn Gia đình (tổng quan)

Mỗi người thân một thẻ, có **đèn trạng thái** tính từ luật rõ ràng (một nơi duy nhất trong mã, có test):

| Đèn | Khi nào |
|---|---|
| Đỏ | Huyết áp từ 180/120 trong 24 giờ; SOS chưa xử lý; quên thuốc quá 45 phút; điện thoại không báo gì quá 24 giờ |
| Vàng | Huyết áp cao (từ 140/90) 2 lần liên tiếp; nguy cơ "Cao"; quên 1 cữ hôm nay; chưa đo huyết áp quá 3 ngày; pin dưới 15% |
| Xanh | Còn lại |

Thẻ hiện: tên, huyết áp gần nhất và giờ đo, 3 vòng nguy cơ thu nhỏ, thuốc hôm nay (2/3 cữ), vị trí ("ở nhà · 08:12"), pin. Nút nhanh: **Gọi**, **Nhắn tin**, **Nhờ đo huyết áp** (đẩy một thông báo to lên máy cha mẹ).
Bấm vào thẻ mở **chi tiết người thân** với 4 mục: Tổng quan, Huyết áp (biểu đồ 7/30 ngày có vùng bình thường), Nguy cơ (xu hướng), Hồ sơ sức khoẻ (con sửa được nếu có quyền; hiện "Con Minh sửa lúc …").
Đổi người bằng bộ chọn "Đang xem: Mẹ ▾".

### 4.4 Các chỗ xung đột và cách xử lý

| Tình huống | Xử lý |
|---|---|
| Con về thăm, đo huyết áp hộ | Hỏi "Đo cho ai: Mình / Mẹ", lưu `recorded_by` |
| Con đọc lịch sử hỏi Vy của mẹ | Mặc định không; mẹ bật `vy_history` mới có |
| Con đổi lịch thuốc của mẹ | Áp dụng ngay, **nhưng** báo mẹ ("Con Minh vừa đổi lịch thuốc") và Vy nhắc ở cữ kế; có nhật ký thay đổi |
| Hai con sửa cùng lúc | Lưu phiên bản; lần sửa sau thấy "Anh Nam vừa sửa, tải lại" |
| Đồng ý nghiên cứu, phản hồi kết quả | Chỉ chính chủ bấm được; ẩn ở chế độ theo dõi |
| Cha mẹ gỡ liên kết | Có hiệu lực ngay; con mất toàn bộ quyền đọc; con nhận thông báo |
| Con rời | Cha mẹ nhận thông báo |
| Cha mẹ xoá tài khoản | Xoá kéo theo (đã có `on delete cascade`); liên kết biến mất |
| Anh em có thấy nhau? | Cha mẹ thấy danh sách người đang xem. Các con thấy tên nhau trong cảnh báo ("Anh Nam đã nhận") để không gọi trùng |
| Người dùng vừa là con vừa là cha mẹ | Hai chiều liên kết độc lập; giao diện chuyển bằng bộ chọn chủ thể |

## 5. Thông báo và cảnh báo

Hạ tầng FCM đã có (bản 1.0.15). Cần thêm phân loại:

| Loại | Người nhận | Cách gửi | Ghi chú |
|---|---|---|---|
| Nhắc thuốc | Cha mẹ | **Báo thức cục bộ trên máy** + FCM dự phòng | Không phụ thuộc mạng |
| Nhắc lại | Cha mẹ | Máy chủ, sau 15 phút | |
| Quên thuốc | Con (có `alerts`) | Máy chủ, sau 45 phút | Một thông báo cho mỗi cữ |
| Huyết áp rất cao | Con | Ngay khi lưu số đo | Kèm nút Gọi |
| SOS | Con (tất cả) | Ngay, độ ưu tiên cao, kèm vị trí | Con đầu tiên bấm "Tôi đã nhận" thì những người còn lại thấy "Minh đã nhận" |
| Tóm tắt cuối ngày | Con (bật tuỳ chọn) | 20:00 giờ của cha mẹ | "Mẹ hôm nay: 128/80, uống 3/3 cữ" |
| Sắp hết thuốc, sắp tái khám | Cha mẹ + con | 3 túi cuối, 2 ngày trước hẹn | |
| Pin yếu, mất liên lạc | Con | Theo luật mục 4.3 | |

Chống thông báo dồn dập: mỗi loại có thời gian nghỉ (ví dụ huyết áp cao tối đa 1 lần/3 giờ); **giờ yên tĩnh** của con áp cho cảnh báo thường, **không** áp cho SOS và huyết áp từ 180/120.
Cài đặt thông báo của con mở rộng từ bảng `push_prefs` (thêm các cột theo loại).

## 6. Thuốc

### 6.1 Thực tế dùng thuốc ở Việt Nam (cơ sở của thiết kế)

- Thuốc thường được **chia sẵn vào từng túi theo buổi** (Sáng, Trưa, Chiều, Tối). Uống thì lấy đúng túi.
- Thuốc lẻ lấy thêm từ **hũ** (vitamin, thuốc đặc biệt) hoặc thuốc **khi cần** (ngậm khi đau ngực, hạ sốt).
- Đơn mạn tính thường theo tháng, kèm **ngày tái khám**.
- Chỉ dẫn hay gặp: trước ăn, sau ăn, trong bữa ăn, lúc đói, trước khi ngủ.
- Người bệnh thường **không biết tên thuốc**, chỉ biết "túi sáng".

**Hệ quả quan trọng:** túi chia sẵn chỉ ghi "Sáng/Chiều", **tên thuốc thường không in trên túi**. Vì vậy chụp ảnh túi thường chỉ đọc được nhãn buổi, không biết bên trong có gì. Muốn biết thuốc gì thì phải chụp **đơn thuốc** (có danh sách). Thiết kế vì thế có **chế độ túi**: nhắc "lấy túi Sáng" mà **không bắt buộc liệt kê thuốc**; liệt kê là tuỳ chọn, để con ghi cho rõ.

### 6.2 Mô hình dữ liệu (migration 0023)

| Bảng | Nội dung |
|---|---|
| `med_plans` | Đơn thuốc: `owner_id`, tên (vd "Đơn BV 14/11"), `start_date`, `end_date`, `recheck_date`, bác sĩ, ghi chú, `source` (`manual`, `photo`), `created_by`, `status` |
| `med_slots` | Cữ uống: `plan_id`, nhãn ("Sáng"), giờ `HH:MM`, cửa sổ chấp nhận (trước/sau X phút), ngày trong tuần, `mode` (`bag` túi / `list` danh sách), màu túi, `meal_rel`, `bags_remaining` |
| `med_items` | Thuốc trong một cữ (tuỳ chọn ở chế độ túi): tên, hàm lượng, số lượng, đơn vị (`viên`, `gói`, `ml`, `đơn vị`), `source` (`bag`, `jar`), ghi chú |
| `med_prn` | Thuốc "khi cần": tên, chỉ dẫn do con nhập, giới hạn tối đa mỗi ngày (chỉ để hiện, không tính toán y khoa) |
| `dose_events` | Mỗi lần đến giờ: `slot_id`, `owner_id`, `due_at`, `status` (`pending`, `taken`, `skipped`, `missed`), `acted_at`, `acted_by`, `snoozed_until`, `escalation` (0, 1, 2) |

Sinh `dose_events` cho 48 giờ tới bằng hàm theo giờ (pg_cron). Múi giờ của lịch lấy theo **múi giờ của cha mẹ** (cột mới `profiles.timezone`), vì con có thể làm việc ở nước ngoài.
Tiêm (ví dụ insulin) chỉ hỗ trợ ở mức **nhắc theo chữ do con nhập**, đơn vị "đơn vị"; app không tính liều.

### 6.3 Luồng của cha mẹ

1. Đến giờ: **báo thức cục bộ** kêu to, rung, lặp 3 lần cách nhau 2 phút. Vy đọc "Bác ơi, đến giờ uống thuốc buổi sáng, bác lấy túi Sáng nhé". Nếu có liệt kê thì đọc kèm ("gồm thuốc huyết áp và thuốc tiểu đường").
2. Màn hình hiện **một nút rất to "Đã uống"**, thêm "Nhắc lại sau 15 phút" và "Bỏ qua".
3. Có thêm thuốc từ hũ: dòng "Thêm 1 viên Aspirin từ hũ" nằm trong cữ, tích riêng.
4. Quên: không bao giờ nói "uống gấp đôi". Nếu quá cửa sổ thì đánh dấu "Chưa uống" và hiện câu cố định "Bác không uống bù. Nếu băn khoăn, bác hỏi bác sĩ."
5. Trang chủ có thẻ "Thuốc hôm nay": các cữ đã qua (✓), cữ tiếp theo (giờ), còn mấy túi.

### 6.4 Luồng của con

- **Nhập tay (làm trước):** "Thêm đơn" → chọn chế độ túi hay danh sách → thêm cữ (Sáng/Trưa/Chiều/Tối, giờ) → thêm thuốc nếu muốn → ngày bắt đầu, số ngày, ngày tái khám → xác nhận. Mẫu nhanh: "Sáng và Tối", "Sáng/Trưa/Chiều/Tối".
- **Đơn mới thay đơn cũ:** hỏi "Dừng đơn cũ?" (mặc định có, hiện chỗ khác nhau) để không bị hai lịch chồng nhau.
- **Xem tuân thủ:** lịch 7 ngày (đã uống / bỏ lỡ / bỏ qua), tỉ lệ đúng giờ.
- **Con xác nhận hộ** ("Mẹ đã uống rồi, con gọi hỏi"): được phép, nhưng ghi rõ `acted_by` và hiện là "Con Minh xác nhận".

### 6.5 Chụp ảnh nhập thuốc (giai đoạn 3)

Đường đi, tất cả **trên máy con** trừ bước 4:
1. Camera ở phần ghi sức khoẻ → chọn loại: Đơn thuốc, Túi thuốc, Hộp/vỉ thuốc.
2. **Đọc chữ trên máy** (ML Kit Latin có sẵn trong app, hỗ trợ dấu tiếng Việt ở mức khá, không hoàn hảo).
3. **Che thông tin cá nhân** trên máy bằng luật: dòng sau "Họ tên/Bệnh nhân", ngày sinh, số điện thoại, mã BHYT 15 ký tự, CCCD 9 hoặc 12 số, địa chỉ.
4. Gửi **chữ đã che** tới Edge Function `med-parse` (mô hình ngôn ngữ, bắt buộc trả JSON theo lược đồ). Ảnh gốc không rời máy.
5. **Kiểm chứng bằng chứng**: mỗi trường mô hình trả về phải kèm đoạn trích; app kiểm tra đoạn đó có thật trong chữ đã đọc (so khớp chuỗi, cho phép sai 1-2 ký tự). Trường nào không có bằng chứng thì bị đánh dấu đỏ và để trống.
6. **Màn kiểm tra**: ảnh gốc nằm cạnh bản nhập, trường chắc chắn là xanh, trường không chắc là vàng, trường không có bằng chứng là đỏ trống. Con phải sửa hoặc xác nhận từng cữ mới lưu được.
7. Lưu nháp; chỉ khi con bấm "Kích hoạt lịch" mới có báo thức. **Không có đường nào để ảnh tự kích hoạt lịch.**

Giới hạn trung thực: đơn viết tay của bác sĩ nhiều khả năng đọc không ra. Khi đó màn kiểm tra trống nhiều và con nhập tay. Có thể thêm **từ điển tên thuốc** để sửa lỗi chính tả khi đọc; tôi **chưa kiểm tra** nguồn dữ liệu và giấy phép nào dùng được, nên chưa hứa. Bắt đầu bằng từ điển xây dần từ những tên con đã xác nhận.

Ghi chú: tính năng đọc số đo huyết áp hiện nay gửi **cả ảnh** tới nhà cung cấp mô hình thị giác (`api/ocr.ts`). Ảnh máy đo huyết áp không chứa thông tin cá nhân nên chấp nhận được; đơn thuốc thì không, nên dùng đường đi riêng ở trên.

### 6.6 Báo thức trên Android (chỗ dễ hỏng nhất)

| Vấn đề | Cách xử lý |
|---|---|
| Android 12+ hạn chế báo thức chính xác | Xin quyền báo thức chính xác lúc thiết lập, kiểm tra trạng thái mỗi lần mở app, cảnh báo nếu bị thu hồi |
| Tắt máy bật lại | Đặt lại toàn bộ báo thức khi khởi động |
| Doze, tiết kiệm pin | Dùng báo thức chính xác kể cả khi nghỉ; tắt tối ưu pin cho Viegrand |
| Xiaomi, Oppo, Vivo, Huawei tự diệt app nền | Màn hướng dẫn từng hãng, mở thẳng trang cài đặt tự khởi chạy và pin (gói `android_intent_plus`) |
| Màn hình tắt, máy khoá | Thông báo toàn màn hình ("full-screen intent"), kênh riêng độ ưu tiên cao, âm lượng kênh báo thức |
| Lịch đổi khi máy đang tắt mạng | Máy lưu lịch cục bộ; đồng bộ khi mở app và khi nhận FCM `plan_changed` |
| Quá nhiều báo thức xếp trước | Chỉ đặt 7 ngày tới và đặt lại mỗi lần mở app hoặc mỗi ngày |
| Báo thức không kêu vì lý do nào đó | **Lưới an toàn máy chủ** (mục 6.7) |

Gói cần thêm: `flutter_local_notifications` + `timezone`, `android_intent_plus`, `permission_handler`.
Cần thử trên máy thật: ít nhất 3 hãng (Samsung, Xiaomi/Oppo, một máy gần stock).

### 6.7 Lưới an toàn ở máy chủ

Edge Function `meds-tick` chạy mỗi phút bằng pg_cron:
- `pending` quá 15 phút sau giờ → đẩy nhắc lại cho cha mẹ (`escalation = 1`).
- `pending` quá 45 phút → báo con có `alerts` (`escalation = 2`).
- Hết cửa sổ → `missed`.
Chi phí: khoảng 43.000 lượt gọi một tháng, trong hạn mức miễn phí của Supabase.
Chỉ mục: `dose_events (due_at) where status = 'pending'`.

### 6.8 Điều app tuyệt đối không làm

- Không tư vấn thuốc, không bảo uống hay bỏ thuốc, không nói tên thuốc thay bác sĩ.
- Không tự suy luận liều từ ảnh; không "gợi ý" liều.
- Không cảnh báo tương tác thuốc bằng mô hình ngôn ngữ. Nếu sau này cần, phải dùng cơ sở dữ liệu dược chính thống và có người chuyên môn rà.
- Không hứa "thay thế" việc dùng thuốc đúng.

## 7. Bản đồ

### 7.1 Ba mức

| Mức | Cách làm | Pin | Quyền Android |
|---|---|---|---|
| 1. Vị trí gần nhất | Gửi vị trí khi mở app, khi đo huyết áp, khi bấm "Đã uống", khi bấm SOS | Không đáng kể | Vị trí khi đang dùng |
| 2. Định kỳ | Mỗi 15-30 phút ở nền, vị trí thô, có biểu tượng thông báo thường trực | Có | Vị trí nền (xin thêm một bước riêng), dịch vụ chạy nền kiểu "vị trí" |
| 3. Cảnh báo thông minh | "Ở nhà / ra ngoài", ra khỏi nhà lúc khuya, cả ngày không di chuyển, SOS | Có | Như mức 2 + vùng địa lý |

Làm tuần tự. **SOS không cần vị trí nên làm sớm (giai đoạn 4)**; có vị trí thì gửi kèm.

### 7.2 Dữ liệu (migration 0024)

- `location_latest(owner_id pk, lat, lng, accuracy_m, battery_pct, charging, at, source)`: một dòng cho mỗi người, ghi đè.
- `location_history(id, owner_id, lat, lng, accuracy_m, at, source)`: giữ **14 ngày** rồi xoá.
- `places(id, owner_id, name, lat, lng, radius_m, kind)`: nhà và các nơi quen.
Mọi bảng chỉ đọc qua `can_view(owner, 'location')`; ghi chỉ chính chủ. Mỗi lần con mở bản đồ ghi một dòng `family_audit` ("Con Minh xem vị trí lúc …").
Ước lượng tải: 500 người × 48 lần/ngày ≈ 24.000 dòng/ngày, nhỏ.

### 7.3 Bản đồ hiển thị

Gói `flutter_map` + `latlong2` (OpenStreetMap), `geolocator` cho vị trí.
- Hiện: chấm vị trí, vòng sai số, "cập nhật 08:12", pin, "vị trí cũ 5 giờ" bằng chữ đỏ nếu quá 2 giờ.
- Tên địa chỉ: **không** tra ngược trong bản đầu (dịch vụ miễn phí có giới hạn dùng); chỉ hiện "Ở nhà / Cách nhà 3,2 km / Ở Quận 1 (nếu bác đặt tên nơi quen)".
- Ô bản đồ miễn phí của OpenStreetMap có chính sách dùng hạn chế và bắt buộc ghi nguồn: đủ cho thử nghiệm nhỏ. Triển khai thật nên dùng nhà cung cấp riêng (MapTiler, hoặc Goong/Vietmap cho dữ liệu Việt Nam tốt hơn). **Chưa so sánh bảng giá**; sẽ làm trước khi mở rộng.

### 7.4 Riêng tư và tin cậy

- Cha mẹ thấy "Đang chia sẻ vị trí với: Minh, Nam", có công tắc **Tạm dừng 1 giờ / 8 giờ / tắt**, thấy **ai đã xem** gần đây.
- Biểu tượng thông báo thường trực khi chạy nền (bắt buộc của Android, cũng là minh bạch).
- Phát hiện té ngã bằng cảm biến **không làm**: sai nhiều, hậu quả cao. "Cả ngày không di chuyển" chỉ là gợi ý, ghi rõ không phải thiết bị an toàn.
- Cảnh báo "ra khỏi nhà lúc khuya" dễ báo sai; có thời gian nghỉ và con tắt được từng loại.

## 8. Bảo mật, riêng tư, pháp lý

**Mối nguy cần chặn bằng thiết kế:**
- Theo dõi cưỡng ép (người nhà kiểm soát): liên kết **chỉ** tạo từ máy của người được theo dõi; có thông báo hằng tháng "Có N người đang theo dõi bác"; log người xem vị trí; gỡ một chạm.
- Người mất khả năng quyết định (sa sút trí tuệ) không thể tự đồng ý hợp lệ. Việc đó cần người giám hộ; app **không** xác định được, chỉ nêu trong hướng dẫn. Cần quy ước với tester.
- Dò mã: mã 6 số dùng một lần, 10 phút, khoá sau 5 lần sai, giới hạn theo người nhập.
- Rò dữ liệu qua RLS sai: **viết kiểm thử chính sách ở mức cơ sở dữ liệu** (đặt vai `authenticated` với hai người dùng giả, kiểm tra con A không đọc được dữ liệu của người không liên kết, người đã bị gỡ không còn đọc, v.v.).

**Pháp lý (cần người có chuyên môn rà, tôi không phải luật sư):**
- Sức khoẻ và vị trí là dữ liệu cá nhân nhạy cảm theo Nghị định 13/2023/NĐ-CP: cần đồng ý rõ ràng, có thể rút lại, có hồ sơ đánh giá tác động, quyền xuất và xoá dữ liệu.
- App có nguy cơ bị xem là phần mềm y tế nếu nói quá tay ("chẩn đoán", "điều trị"). Giữ câu chữ ở mức nhắc nhở và theo dõi, kèm "không thay thế bác sĩ".
- Nếu đưa lên Google Play: nhắc thuốc chính xác, vị trí nền, thông báo toàn màn hình, và ứng dụng theo dõi người thân đều có yêu cầu khai báo và chính sách riêng. Hiện app phát hành bằng tệp APK nên chưa gặp.
- Hiện **chưa có nút xoá tài khoản trong app** (chỉ có xoá kéo theo ở cơ sở dữ liệu). Cần thêm trước khi mở rộng, và Google Play cũng yêu cầu.

## 9. Hạ tầng và giới hạn đã biết

| Chủ đề | Tình trạng | Hướng xử lý |
|---|---|---|
| Hàm Vercel | **Đã đủ 12/12** (giới hạn gói miễn phí) | Mọi thứ mới đặt ở **Edge Function Supabase** (đã có `push`) hoặc hàm SQL (RPC) |
| Lịch chạy định kỳ | pg_cron có sẵn | `meds-tick` mỗi phút; dọn vị trí hằng ngày; sinh `dose_events` mỗi giờ |
| Kết nối realtime | Hạn mức miễn phí Supabase là 200 kết nối đồng thời | **Chưa kiểm tra gói đang dùng.** Nếu muốn ~500 người, cần xác nhận gói; con xem số liệu mới nhất bằng kéo làm mới và thông báo, không giữ kết nối liên tục |
| Dung lượng cơ sở dữ liệu | Gói miễn phí 500 MB | Lịch sử vị trí tự xoá 14 ngày; `dose_events` giữ 90 ngày |
| Dung lượng APK | 53 MB | Thêm bản đồ và báo thức tăng khoảng 3-6 MB; chấp nhận được |
| Khoá mô hình ngôn ngữ cho `med-parse` | Đang nằm trong bảng `provider_keys` và biến môi trường Vercel | Edge Function đọc từ `provider_keys` qua service role |
| Thông báo đẩy | Đã chạy; giới hạn: máy không có dịch vụ Google không nhận | Giữ báo thức cục bộ làm đường chính cho nhắc thuốc |
| Máy chủ giữ giờ | Múi giờ | Lưu UTC, hiển thị theo múi giờ chủ sở hữu; giờ thuốc theo múi giờ cha mẹ |

## 10. Kế hoạch theo giai đoạn

Quy ước cỡ: **S** (một ngày làm việc), **M** (2-4 ngày), **L** (1-2 tuần). Cỡ chỉ để so sánh, không phải cam kết.

### Giai đoạn 0 (S): hoàn thiện tab Đánh giá
- Thêm biểu đồ cột kiểu wifi (mức huyết áp của lần đo gần nhất) vào đầu tab.
- Thêm **biểu đồ xu hướng**: đường theo thời gian cho Đột quỵ, Tim mạch, Tiểu đường (từ bảng `health_assessments`, 30 lần gần nhất), có chấm khi mức đổi. Bản ghi trước 1.0.16 không có tiểu đường nên đường đó bắt đầu muộn hơn.
- Ghi chú: nếu "2 cái đó" của anh có nghĩa khác, nói tôi trước khi làm.
- Nghiệm thu: test widget, ảnh dựng kiểm tra, ghi `APP_MAP`.

### Giai đoạn 1 (L): gia đình và chế độ con cái
| Bước | Nội dung | Cỡ |
|---|---|---|
| 1a | Migration 0021-0022: bảng liên kết, mã, hàm quyền, RLS mở đọc; kiểm thử RLS ở mức cơ sở dữ liệu; chưa đổi giao diện | M |
| 1b | Chủ thể (`activeSubjectProvider`), chuyển kho huyết áp, hồ sơ, đánh giá sang nhận `ownerId` | M |
| 1c | Màn liên kết: "Mời người thân" (tạo mã, đếm ngược, chia sẻ qua Zalo), "Nhập mã", danh sách người đang xem, gỡ, quyền từng người | M |
| 1d | Chế độ con cái: công tắc ở Hồ sơ, tab Gia đình, thẻ người thân, chi tiết (huyết áp, nguy cơ, hồ sơ), bộ chọn người | L |
| 1e | "Thiết lập hộ" (trình hướng dẫn 5 bước trên máy cha mẹ) | M |
| 1f | Cảnh báo cho con: huyết áp rất cao, mất liên lạc, "Nhờ đo huyết áp" từ xa; Vy hiểu "mẹ hôm nay…" | M |
| 1g | Nhật ký (`family_audit`), thông báo cho cha mẹ khi có người theo dõi mới hoặc rời | S |
- Nghiệm thu: hai tài khoản thật liên kết; con thấy số đo vừa chụp của cha mẹ trong vài giây; con không thấy tin nhắn; cha mẹ gỡ thì con mất quyền ngay; mã sai 5 lần bị khoá.

### Giai đoạn 2 (L): thuốc nhập tay
| Bước | Nội dung | Cỡ |
|---|---|---|
| 2a | Migration 0023, hàm sinh `dose_events`, múi giờ cha mẹ | M |
| 2b | Màn con: tạo đơn, chế độ túi/danh sách, mẫu nhanh, đơn mới thay đơn cũ | M |
| 2c | Màn cha mẹ: thẻ "Thuốc hôm nay", màn nhắc với nút to "Đã uống", Vy đọc, thuốc hũ, "khi cần" | M |
| 2d | **Báo thức cục bộ**: đặt, đặt lại khi khởi động, quyền chính xác, thông báo toàn màn hình, hướng dẫn tối ưu pin theo hãng | L |
| 2e | Đồng bộ lịch khi con đổi (FCM `plan_changed`), thông báo cho cha mẹ, nhật ký thay đổi | S |
| 2f | Con xem tuân thủ 7 ngày, xác nhận hộ, nhắc sắp hết và tái khám | M |
- Nghiệm thu: lịch đặt từ máy con làm máy cha mẹ **kêu đúng giờ khi tắt màn hình và tắt mạng** trên 3 hãng máy; "Đã uống" hiện trên máy con trong vài giây.

### Giai đoạn 3 (L): chụp ảnh nhập thuốc
- Đọc chữ trên máy, che thông tin cá nhân (kiểm thử bằng bộ đơn mẫu đã bỏ tên), Edge Function `med-parse`, kiểm chứng bằng chứng, màn kiểm tra có ảnh cạnh bên.
- Cần anh chụp **10-20 đơn thuốc thật** (đã che tên) để chỉnh. Không có dữ liệu thật thì không đánh giá được độ đúng.
- Nghiệm thu: tỉ lệ trường đúng và tỉ lệ "đánh dấu đỏ đúng chỗ" trên bộ mẫu; **không có ca nào kích hoạt lịch khi chưa xác nhận**.

### Giai đoạn 4 (M): lưới an toàn, SOS, chất lượng thông báo
- `meds-tick`; nhắc lại 15 phút, báo con 45 phút; thời gian nghỉ, giờ yên tĩnh; tóm tắt cuối ngày.
- **SOS**: nút đỏ trên Trang chủ cha mẹ (giữ 3 giây), đẩy cho mọi con, "Tôi đã nhận", nút Gọi.
- Thẻ y tế khẩn cấp (nhóm máu, dị ứng, bệnh nền, thuốc đang dùng, liên hệ khẩn cấp) hiện khi bấm SOS và cho con xem.

### Giai đoạn 5 (M rồi L): bản đồ
- 5a (M): mức 1, bản đồ con, công tắc tạm dừng, nhật ký xem, giữ 14 ngày.
- 5b (L): mức 2 (nền) + nơi quen + "ở nhà".
- 5c (M): cảnh báo ra khỏi nhà lúc khuya, không di chuyển cả ngày.
- Nghiệm thu mức 2: đo pin trong 24 giờ trên 2 máy; vị trí đến máy con đúng hạn 15-30 phút.

### Giai đoạn 6: thử nghiệm với 3-5 gia đình
- Bộ câu hỏi, chỉ số: tỉ lệ ghép được liên kết, tỉ lệ báo thức kêu đúng giờ, tỉ lệ "Đã uống" đúng cữ, số cảnh báo giả, mức hao pin, số lần phải hỗ trợ.
- Cập nhật hướng dẫn cho người thử (tài liệu tester hiện do một phiên khác quản lý; sẽ đề xuất nội dung, không sửa trực tiếp).

## 11. Kịch bản phải thử

1. Bác đổi điện thoại, đăng nhập lại: báo thức, mã thiết bị, liên kết còn nguyên.
2. Bác tắt máy qua đêm: sáng bật lên, báo thức đặt lại; cữ đã qua đánh dấu đúng.
3. Mất mạng cả ngày: báo thức cục bộ vẫn kêu; "Đã uống" xếp hàng gửi sau.
4. Con ở nước ngoài khác múi giờ: giờ thuốc và "cuối ngày" theo giờ của bác.
5. Hai con đặt lịch trùng hoặc sửa cùng lúc.
6. Đang trong cữ mà con đổi giờ.
7. Bác bấm "Đã uống" nhầm: có "Hoàn tác" trong 2 phút.
8. Bác hết pin: con thấy "Mất liên lạc từ 14:30, pin lần cuối 8%".
9. Con xoá tài khoản: bác nhận thông báo, dữ liệu của bác còn nguyên.
10. Bác gỡ liên kết lúc con đang mở bản đồ: màn con đóng đúng cách, không treo.
11. Một người vừa là con của A vừa là cha của B.
12. Đơn mới thay đơn cũ có cữ trùng.
13. Cữ qua nửa đêm ("Tối 23:30", "Khuya 00:30").
14. Máy bác không có dịch vụ Google: nhắc thuốc cục bộ vẫn chạy, đẩy thông báo không đến.

## 12. Rủi ro chính

| Rủi ro | Mức | Cách giảm |
|---|---|---|
| Báo thức không kêu trên một số hãng máy | Cao | Hướng dẫn theo hãng, kiểm tra trạng thái quyền mỗi lần mở app, lưới an toàn máy chủ, thử trên máy thật |
| Đọc nhầm liều thuốc từ ảnh | Cao | Ảnh không tự kích hoạt; bằng chứng bắt buộc; màn kiểm tra bắt xác nhận từng cữ |
| RLS sai làm lộ dữ liệu | Cao | Kiểm thử chính sách ở mức cơ sở dữ liệu trước khi làm giao diện |
| Hao pin vì vị trí nền | Vừa | Mức 1 trước; vị trí thô; đo pin trước khi mở rộng |
| Cảnh báo giả làm con tắt hết thông báo | Vừa | Thời gian nghỉ, giờ yên tĩnh, gom theo cữ |
| Theo dõi cưỡng ép | Vừa | Liên kết chỉ từ máy người được theo dõi, nhật ký xem, thông báo định kỳ |
| Vi phạm quy định dữ liệu | Vừa | Rà pháp lý trước khi mở rộng; nút xoá tài khoản; xuất dữ liệu |
| Quá phạm vi, giai đoạn 1 kéo dài | Vừa | Cắt nhỏ 1a-1g, mỗi bước phát hành được |
| Giới hạn gói miễn phí (realtime, hàm) | Vừa | Đặt mọi thứ mới ở Edge Function và RPC; xác nhận gói trước khi mở rộng |

## 13. Việc cần anh chốt thêm

1. **Thứ tự giai đoạn:** 0, 1, 2, 3, 4, 5, 6 như trên, hay đẩy bản đồ lên trước thuốc?
2. **Ai được sửa thuốc:** mọi con có quyền `meds_edit`, hay chỉ một "người chăm chính" do cha mẹ chọn? Tôi nghiêng về mọi con có quyền, kèm thông báo và nhật ký.
3. **Con đổi lịch thuốc:** áp dụng ngay và báo cha mẹ (tôi đề xuất), hay cha mẹ phải bấm đồng ý? Bắt đồng ý an toàn hơn nhưng nhiều cha mẹ sẽ không bấm.
4. **Bản đồ:** dùng OpenStreetMap cho đợt thử nghiệm, hay chọn ngay nhà cung cấp trả phí (Goong hoặc MapTiler)?
5. **SOS có kèm tin nhắn SMS tới con** khi máy bác không có mạng dữ liệu không? (SMS tốn tiền theo người dùng, cần quyền gửi SMS, nhạy cảm; tôi đề xuất chưa làm.)
6. **"Thiết lập hộ"** có là luồng chính khi tặng app cho cha mẹ không? (Tôi đề xuất có.)
7. **Tóm tắt cuối ngày** gửi cho con: mặc định bật hay tắt? (Tôi đề xuất tắt, con tự bật.)
8. **Từ điển tên thuốc:** anh có nguồn dữ liệu hợp pháp nào không? Nếu không, xây dần từ các tên đã xác nhận.
9. **Dự định lên Google Play** hay tiếp tục phát APK? Ảnh hưởng tới cách xin quyền vị trí nền và báo thức.
10. **Thiết bị thử nghiệm:** có tối thiểu 3 máy khác hãng (Samsung, Xiaomi/Oppo, một máy khác) để thử báo thức không?
11. **Nút xoá tài khoản** làm trong giai đoạn 1 chứ?

## 14. Ý tưởng để sau (chưa trong phạm vi)

Lịch hẹn khám tổng quát, nhật ký triệu chứng và ghi chú, báo cáo tuần gửi bác sĩ (PDF qua Zalo), nhắc uống nước và vận động, đo đường huyết tương tự đo huyết áp (cùng đường chụp ảnh), chia sẻ lịch uống thuốc với người giúp việc hoặc điều dưỡng.

## 15. Tiến độ

| Giai đoạn | Trạng thái | Ghi chú |
|---|---|---|
| 0 | Xong (1.0.17) | Cột huyết áp và xu hướng ở tab Đánh giá |
| 1a | Xong | Migration 0021-0022, kiểm thử quyền `supabase/tests/family_rls.sql` (đạt). Lưu ý: nhập mã trả về `(link_id, error)` thay vì ném lỗi, vì ném lỗi huỷ luôn dòng nhật ký nhập sai |
| 1b | Xong một phần | Mọi truy vấn dữ liệu của chính mình đã lọc theo `user_id`; thay vì chuyển cả app sang "chủ thể", các màn của người thân dùng bộ provider riêng theo `ownerId`. Chưa có: con đo huyết áp hộ |
| 1c | Xong | Mời, nhập mã, quyền, tạm dừng, gỡ |
| 1d | Xong | Chế độ theo dõi, màn Gia đình, chi tiết người thân. Chưa có: sửa hồ sơ hộ |
| 1e | Đổi cách làm | Không ép bước mời trong thiết lập; "Thiết lập hộ" = con cài trên máy cha mẹ rồi vào Hồ sơ, Mời người thân |
| 1f | Xong một phần | Cảnh báo huyết áp rất cao, báo liên kết, nhờ đo từ xa (migration 0023). Chưa có: Vy hiểu "mẹ", mất liên lạc |
| 1g | Xong | Nhật ký gia đình (`family_audit`) và thông báo liên kết |
| 2 | Xong (1.0.19) | Thuốc nhập tay, báo thức cục bộ (đã thử kêu đúng giờ trên emulator, bản release chạy tốt), con xem tuân thủ. Chưa: nhắc sắp hết, thông báo đẩy dự phòng khi báo thức không kêu |
| 3 | Xong (1.0.20), chưa thử với đơn thật | Chụp ảnh nhập thuốc: ML Kit trên máy, che thông tin cá nhân, `api/ocr.ts` chế độ `med_text` (không phải Edge Function: khoá mô hình nằm ở biến môi trường Vercel, không ở `provider_keys`), kiểm chứng bằng chứng ở máy chủ, màn kiểm tra rồi mới lưu. **Chưa đo độ đúng**: cần 10-20 đơn thật đã che tên. Chưa có: từ điển tên thuốc |
| 4 | Xong (1.0.21), chưa thử trên máy thật | Migration `0026`, kiểm thử `safety_rls.sql` (đạt). Lưới an toàn 15/45 phút, SOS (giữ 3 giây, nhận, huỷ), thẻ y tế khẩn cấp, giờ yên tĩnh, tóm tắt cuối ngày, nhắc sắp hết/tái khám. Chưa: vị trí kèm SOS, SMS, nhận SOS khi con tắt hẳn thông báo của máy |
| 5 | Chưa | Bản đồ |

## 16. Kế hoạch chi tiết giai đoạn 4 (lưới an toàn, SOS, chất lượng thông báo)

Quyết định đã chọn (không hỏi lại): không gửi SMS; SOS chưa kèm vị trí (vị trí làm ở giai đoạn 5, cột `lat/lng` đã chừa sẵn); giữ nút SOS 3 giây; con nhận SOS không cần mở khoá thêm gì; mọi việc chạy bằng pg_cron + hàm SQL, **không thêm Edge Function mới** (hàm `push` có sẵn thêm các loại thông báo).

### 16.1 Lưới an toàn thuốc (máy chủ)
| Điều kiện | Việc làm |
|---|---|
| `pending`, quá giờ 15 phút, `escalation = 0`, không đang hoãn | Gửi cha mẹ "Đã quá giờ uống thuốc" (không bao giờ nói uống bù); `escalation = 1` |
| `pending`, quá giờ 45 phút, `escalation < 2`, còn trong cửa sổ | Gửi mọi con có `alerts` + `meds_view` (bỏ qua ai tắt "báo khi quên thuốc" hoặc đang trong giờ yên tĩnh); `escalation = 2` |
| Nhiều cữ cùng quá hạn một lượt | Gộp thành một thông báo cho mỗi người (chống dồn dập) |
Hàm `meds_escalate()` chạy mỗi phút (pg_cron), dùng chỉ mục từng phần `dose_events_pending_idx`. Bấm "Nhắc lại sau 15 phút" đặt `escalation = 0` nên được nhắc lại đúng một lần nữa.

### 16.2 SOS
- Bảng `sos_events` (chủ, thời điểm, `lat/lng` rỗng, `open|handled`, người nhận). RLS: chủ và con có `alerts` xem; **ghi chỉ qua hàm**.
- `trigger_sos()`: chủ gọi; trong 2 phút chỉ có một SOS mở (bấm lại không gửi lại). Đẩy tới mọi con có `alerts`, **bỏ qua giờ yên tĩnh và tuỳ chọn thông báo**.
- `ack_sos(id)`: con đầu tiên bấm "Tôi đã nhận" thì những người còn lại và cha mẹ thấy "Minh đã nhận".
- `cancel_sos(id)`: chủ huỷ khi bấm nhầm ("Tôi ổn, bấm nhầm"); các con nhận "đã huỷ".
- App cha mẹ: nút đỏ trên Trang chủ, **giữ 3 giây** (vòng tiến trình, rung, không bấm thoáng qua được). Sau khi gửi: màn SOS với nút **Gọi 115**, nút gọi người thân trong thẻ khẩn cấp, danh sách con đã được báo, trạng thái "đã nhận", nút "Tôi ổn, bấm nhầm". Chưa có người thân liên kết thì vẫn hiện màn này và nói rõ "chưa báo cho ai", để bác gọi 115.
- App con: thông báo `sos` mở màn SOS của người đó (thẻ khẩn cấp, thuốc đang dùng, nút Gọi, "Tôi đã nhận"); trang Gia đình có băng đỏ khi có SOS đang mở.

### 16.3 Thẻ y tế khẩn cấp
Bảng `emergency_cards` (nhóm máu, dị ứng, bệnh nền, số điện thoại của bác, tối đa 3 người liên hệ, ghi chú). Chủ và con có `profile_edit` sửa được (ghi nhật ký gia đình); con có `health` hoặc `alerts` xem được. Hiện khi bấm SOS và ở trang chi tiết người thân. Thuốc đang dùng lấy từ lịch thuốc, không nhập lại. App **không** suy luận gì từ thẻ này.

### 16.4 Chất lượng thông báo
- `push_prefs` thêm: `dose_alerts` (mặc định bật), `digest` (mặc định tắt), `quiet_start`, `quiet_end` (theo múi giờ của người nhận). Giờ yên tĩnh áp cho "quên thuốc", tóm tắt, nhắc hẹn; **không** áp cho SOS và huyết áp từ 180/120.
- Tóm tắt cuối ngày: 20:00-20:30 giờ của cha mẹ, một lần mỗi ngày, "Hôm nay: 128/80, uống 3/3 cữ" (hoặc "chưa đo huyết áp").
- Nhắc sắp hết túi (còn đúng 3 túi) và nhắc tái khám (còn 2 ngày): 09:00-09:30 giờ của cha mẹ, gửi cha mẹ và các con có `meds_view`. Bảng `notice_log` chống gửi trùng.
- Cài đặt trong Hồ sơ: công tắc "Báo khi bác quên thuốc", "Tóm tắt cuối ngày", chọn giờ yên tĩnh.

### 16.5 Kiểm thử
`supabase/tests/safety_rls.sql` (SOS mở một lần, nhận chỉ một người, người ngoài không thấy, thẻ khẩn cấp theo quyền, `meds_escalate` đúng mốc 15 và 45 phút kể cả khi hoãn); test Flutter cho nút giữ 3 giây, màn SOS, cài đặt.

## 17. Tách giao diện theo vai trò (người cao tuổi / người thân)

### 17.1 Vì sao (dữ liệu dùng thật, 56 tài khoản, ngày 16/11/2026)
- **Tin nhắn** là tab được mở nhiều nhất sau Trang chủ (190 lần chuyển tab, 45 người); **Sức khoẻ** 155 lần (34 người); **Hồ sơ** 89 lần (25 người). **Cộng đồng** có 35 người dùng, **Giải trí** chỉ 10 người, **Vy** 33 người, đo huyết áp 36 người.
- Chức năng gia đình gần như không ai dùng: 2 mã mời được tạo, 1 liên kết, 1 người đặt lịch thuốc. Chỉ 6 hồ sơ sức khoẻ được điền. Một phần vì chức năng mới, một phần vì **nằm sâu trong Hồ sơ** và giao diện chỉ viết cho một kiểu người dùng ("bác" ở khắp nơi).
- Giới hạn: bảng sự kiện không ghi tuổi hay vai trò, nên chưa phân biệt được người cao tuổi với người thân trong số liệu. Phản hồi bằng lời của tester chưa có trong hệ thống. Sau khi có vai trò sẽ ghi vai trò vào mọi sự kiện để lần sau phân tích được.
- Kết luận: **Tin nhắn và Cộng đồng phải giữ trong giao diện người cao tuổi**; Giải trí đưa vào ô "Thư giãn" riêng, không chiếm chỗ chính; chức năng gia đình phải là thứ đầu tiên người thân thấy.

### 17.2 Quyết định
- Mỗi tài khoản có **một** vai trò tại một thời điểm (`elder` hoặc `family`), chọn lúc đăng ký, đổi trong Hồ sơ. Dữ liệu và liên kết không đổi khi đổi vai trò.
- Có lựa chọn thứ ba lúc đăng ký: **"Tôi cài hộ cho cha mẹ"** → tạo tài khoản người cao tuổi rồi đưa thẳng tới màn mời người thân (mã 6 số) để con nhập ở máy của con.
- Vai trò lưu ở metadata phiên đăng nhập (đọc đồng bộ để chuyển hướng) và sao lên `profiles.role` (hàm `set_my_role`, migration `0027`).
- **Tài khoản cũ**: chưa có vai trò thì lần mở app kế tiếp hiện màn "Bạn là ai?" một lần, có chọn sẵn theo dữ liệu (đang theo dõi người khác thì Người thân, còn lại Người cao tuổi). Không gán ngẫu nhiên, vì gán sai thì người cao tuổi nhận giao diện người thân.
- Người thân không bị ép điền hồ sơ sức khoẻ của chính mình.
- Giao diện người cao tuổi: lưới ô lớn, không thanh điều hướng, gồm Đo huyết áp, Nói với Vy, Thuốc và sức khoẻ, Tin nhắn, Cộng đồng, Thư giãn; thuốc kế tiếp với nút "Đã uống" và SOS luôn ở trang chủ. Giao diện người thân: 4 tab Gia đình, Cảnh báo, Tin nhắn, Tôi.

### 17.3 Các bước
| Bước | Nội dung | Kích cỡ |
|---|---|---|
| A | **Xong (1.0.24).** Cột vai trò, chọn lúc đăng ký (cả 3 lựa chọn), màn "Bạn là ai?" cho tài khoản cũ và Google, đổi trong Hồ sơ, người thân bỏ bước hồ sơ sức khoẻ, ghi vai trò vào sự kiện | S |
| B | Bộ khung người cao tuổi (lưới ô lớn, chữ to, Thư giãn) | L |
| C | Bộ khung người thân (4 tab, tab Cảnh báo, câu chữ trung tính, mục "Sức khoẻ của tôi") | M |
| D | Thông báo mở đúng khung theo vai trò, Vy theo vai trò, thử với người dùng thật | M |

