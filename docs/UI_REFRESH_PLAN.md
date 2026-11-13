# Kế hoạch cải tiến giao diện Viegrand (đặc biệt là trợ lý giọng nói Vy)

Tài liệu tham khảo lấy từ Mobbin (iOS). Mỗi dẫn chứng có link mở thẳng trên Mobbin.
Đối tượng chính: **người lớn tuổi** dùng app, con cháu dùng để theo dõi. Từ khoá thiết kế: **sang, sạch, ấm, ít thứ cùng lúc, chữ to, nút to**.

---

## 1. Hiện trạng (nhìn từ màn hình thật)

| Vấn đề | Chi tiết |
|---|---|
| Nút mic nổi che nội dung | Nút tròn 88px + nhãn "Nói với trợ lý" nằm đè lên bong bóng ảnh và nút Gửi trong chat. Nó là lớp phủ trên **mọi** màn hình nên luôn tranh chỗ với nội dung. |
| Giọng nói chỉ là bảng nhỏ | Trợ lý chỉ có một bảng thả nổi phía trên nút mic. Không có trạng thái rõ ràng (nghe, nghĩ, nói), không có hoạt ảnh đủ "sống", chữ chuyển động ít. |
| Trang chủ chung chung | Lưới 2 cột thẻ giống mọi app Material, một banner "Sức khỏe trong tầm tay" chỉ để lấp chỗ, thẻ "Trợ lý Vy — Sắp có" đã lỗi thời, nút đăng xuất chiếm chỗ trên thanh tiêu đề. |
| Chưa có nhận diện riêng | Theme Material 3 mặc định từ màu `0F4C81`, phông Roboto, chưa có hệ phông chữ, bo góc, đổ bóng thống nhất. |
| Chat | Bong bóng xanh đậm/xám lạnh, thiếu trả lời nhanh, chưa có trạng thái trống, ảnh chưa có nhãn giờ chồng lên ảnh. |

---

## 2. Các hướng thiết kế rút ra từ tham khảo

### 2.1 Trợ lý giọng nói: chuyển từ "nút nổi" sang "chế độ toàn màn hình"

Mọi app AI lớn đều làm giọng nói thành **một màn hình riêng**, không phải nút phủ lên màn hình khác:

- **Một quả cầu (orb) ở giữa là nhân vật chính**, đổi hình theo trạng thái: [Meta AI](https://mobbin.com/screens/a13d716b-b9dc-4775-9934-b5c881b221a3) (quả cầu gradient, chữ trả lời bên dưới), [WhatsApp / Meta AI](https://mobbin.com/screens/6474d2b9-3803-4bd3-90ee-143cf9dda044) (vòng gradient, một nút tắt tiếng, một nút kết thúc đỏ), [Roku](https://mobbin.com/screens/9fc48322-f53d-463a-bde8-f2a5a92825d3) (vòng sáng quanh mic).
- **Chữ trạng thái cực lớn, một dòng**: [Google Search Live](https://mobbin.com/screens/b1ede01b-db3f-432e-8df6-2c659f1e96eb) ("Listening…" + câu hướng dẫn nhỏ hơn), [Microsoft Copilot](https://mobbin.com/screens/dde18761-b196-4a1d-919e-10fbe3421871) ("I'm listening"), [5 Minute Journal](https://mobbin.com/screens/99119daa-b9fa-40c4-abb2-264279823eca) ("Eva is listening…", nền kem ấm, chữ serif).
- **Thanh điều khiển ít nút, có nhãn chữ dưới icon**: Google Search Live có Mute / Video / Transcript. Người lớn tuổi hiểu nhanh hơn icon trơn.
- **Hiện lời hai bên bằng thẻ trong mờ**: [Speak](https://mobbin.com/screens/61556f91-425a-4d72-8912-56b2e0bd840e) (thẻ trả lời kèm nút nghe lại). Hợp với bước **xác nhận trước khi gửi tin**.
- **Nhập chữ vẫn ở gần để dự phòng**: Meta AI có ô "Talk or type…", [Grok](https://mobbin.com/screens/4ffe8a05-4425-4382-b41a-77525f7ea180) có thanh sóng âm kèm nút huỷ và nút xong.

Điều **không** học theo: nền tím neon tối (Roku) và gradient bão hoà. Viegrand là app chăm sóc, nên cần cảm giác **dịu, ấm, tin cậy**: nền sáng dịu (mượn cảm giác của 5 Minute Journal nhưng giữ nền trắng lạnh), quả cầu dùng bảng màu thương hiệu (xanh ngọc `55CCD5` → xanh navy `0F4C81`, điểm nhấn cam `E0785F`).

### 2.2 Trang chủ: chào hỏi, một việc chính, tóm tắt sức khoẻ

- **Lời chào có tên + một hành động chính thật to**: [Withings](https://mobbin.com/screens/6852bc4c-c9d3-434d-b52f-54521e690076) ("Good morning, John" + danh sách việc hôm nay), [pillowtalk](https://mobbin.com/screens/f6365c8f-6650-4a2e-aa2f-54d4515cf75f) (câu hỏi lớn + ba nút tròn), [Shazam](https://mobbin.com/screens/966e975a-0116-43b2-970a-09a90697e805) (một vòng tròn khổng lồ "Tap to…").
- **Thẻ tóm tắt chỉ số, có màu theo mức**: [Apple Health](https://mobbin.com/screens/e60672f4-262f-478f-9326-6a6a2262f43f) (thẻ trắng bo lớn, số to, ngày), [Bevel](https://mobbin.com/screens/9bd15c0a-b45b-48f4-98a0-f86762959c81), [Cal AI](https://mobbin.com/screens/190067d0-66e6-4c8b-ada7-29e093e0f82d) (thẻ + thanh điều hướng dạng viên thuốc nổi).
- **Thanh điều hướng dưới dạng viên thuốc nổi** (Apple Health, Cal AI, Bevel): hiện đại và để nút Vy ở giữa tự nhiên.

### 2.3 Chat

- **Ảnh bo góc, giờ chồng lên góc ảnh**: [Shopee](https://mobbin.com/screens/e5ee65d2-2b09-438a-aa5c-0bd10ec03a89) (ảnh to, giờ trong ảnh) và **chip trả lời nhanh** ngay trên ô nhập ("Hi", "OK", "Thank you", "I'm at home"). Rất hợp: "Dạ", "Con khoẻ", "Bác đã ăn rồi".
- **Nút mic nằm trong ô nhập**: [BFF](https://mobbin.com/screens/214c2d35-d40c-4735-a77e-6c5ade3418c3) (mic, ảnh, GIF trong thanh nhập), [PlayStation](https://mobbin.com/screens/c7c67a82-0b93-4a54-9d7e-1cac06c3f1e9) (khay ảnh bật lên dưới ô nhập). Nhờ vậy **hết cảnh mic nổi đè lên nút Gửi**.
- **Xem trước ảnh kèm chú thích có nút x**: [Google Maps](https://mobbin.com/screens/b841b95e-1a77-47f8-a717-4006d4d8b42a) (đúng cách app hiện tại đang làm, giữ lại và làm đẹp hơn).

### 2.4 Huyết áp

- **Chọn khoảng thời gian dạng viên thuốc (D/W/M/6M/Y), số to, khoảng thời gian bên dưới**: [Apple Health](https://mobbin.com/screens/f6471b67-8921-4d71-826b-476849a1ec61).
- **Vùng màu theo mức (bình thường / cao nhẹ / cao)** nền biểu đồ: [Garmin](https://mobbin.com/screens/fb761ada-c11c-4fe8-842f-5469fb959e42). Người già nhìn màu là hiểu ngay mà không phải đọc số.
- **Nhập tay bằng bàn phím số to, mỗi ô một chỉ số, ghi chú giới hạn hợp lệ**: [Apple Health](https://mobbin.com/screens/3a9a08ca-331a-4a53-864a-a3cb8b7109f4), [Garmin](https://mobbin.com/screens/52304000-0515-44dc-9d8f-bf33f7e071ff), danh sách chọn loại số liệu ở [Withings](https://mobbin.com/screens/fcbf72ea-cdcf-407a-8807-7023f2eea773).

---

## 3. Hệ thiết kế đề xuất (nền móng)

**Màu** (giữ nhận diện navy/ngọc hiện tại, thêm nền ấm):

| Vai trò | Giá trị gợi ý |
|---|---|
| Chính | `0F4C81` (giữ) |
| Ngọc / nhấn Vy | `55CCD5` → `2F9FB0` |
| Ấm / cảnh báo mềm | `E0785F` (giữ) |
| Nền sáng | trắng lạnh `F5F8FC`, thẻ trắng `FFFFFF` (đã chốt, xem mục 8) |
| Mức huyết áp | xanh lá `2D8B72` / vàng `D9A441` / cam `E0785F` / đỏ `C94A4A` |

**Chữ**: dùng **Be Vietnam Pro** (thiết kế cho tiếng Việt, dấu rõ). Đóng gói trong `assets/fonts` để khỏi tải qua mạng. Thang chữ: cỡ nội dung tối thiểu 18sp, tiêu đề màn hình 28 đến 32sp, trong chế độ giọng nói 24 đến 30sp.

**Hình khối**: bo góc 20 (thẻ), 28 (tấm lớn), viên thuốc cho chip/nút/thanh điều hướng. Bóng đổ mềm, rất nhẹ thay vì viền cứng.

**Thành phần dùng lại**: `VyOrb` (quả cầu có trạng thái), `BigTile` (ô việc lớn), `StatusChip` (mức huyết áp), `PillNavBar` (thanh điều hướng nổi), `QuickReplyBar`, `SectionHeader`, `EmptyState`, `Skeleton`.

**Truy cập (bắt buộc, không phải trang trí)**: vùng chạm ≥ 56dp; tương phản chữ chính ≥ 7:1; không thông tin chỉ bằng màu (luôn kèm chữ/icon); chịu được cỡ chữ hệ thống tới 150% mà không tràn; `Semantics` đọc trạng thái Vy (live region); tuỳ chọn giảm chuyển động.

---

## 4. Thiết kế chi tiết trải nghiệm giọng nói Vy

### 4.1 Lối vào
- **Trang chủ**: thẻ lớn "Bác cần gì ạ?" với quả cầu nhỏ động nhẹ (thở) và nút **Nói chuyện với Vy**. Thay hẳn thẻ "Sắp có".
- **Thanh điều hướng dưới**: nút Vy tròn nổi ở giữa, có mặt ở các tab chính.
- **Trong chat**: biểu tượng mic **bên trong ô nhập** để đọc chính tả (không mở Vy toàn màn hình), cùng nút Vy ở thanh trên nếu cần.
- **Bỏ lớp phủ nút mic toàn app** (nguyên nhân che nút Gửi, che nội dung).

### 4.2 Màn hình Vy (toàn màn hình, trượt lên từ dưới)

```
┌─────────────────────────────┐
│ ✕                      Chữ ⌨ │  thanh trên: đóng, bật/tắt phụ đề, gõ chữ
│                             │
│          ◯  (VyOrb)         │  quả cầu đổi hình theo trạng thái
│                             │
│     Vy đang nghe…           │  chữ trạng thái 28sp, một dòng
│  "Bác nói tên người cần     │  lời bác nói (đang nhận dạng) 22sp, mờ dần
│   nhắn nhé"                 │
│                             │
│  [Nhắn cho con] [Đo huyết áp]│  gợi ý (chip lớn, tối đa 3)
│                             │
│  [Tắt tiếng]  ●  [Kết thúc] │  3 nút có nhãn chữ dưới icon
└─────────────────────────────┘
```

**Bốn trạng thái, mỗi trạng thái nhìn là biết ngay (kể cả không nghe thấy gì):**

| Trạng thái | Quả cầu | Chữ | Âm thanh / rung |
|---|---|---|---|
| Sẵn sàng | Thở chậm, tối nhạt | "Bác bấm để nói chuyện" | — |
| Đang nghe | Vòng sáng **phình theo âm lượng thật** (đã có `level`), màu ngọc | "Vy đang nghe…" | tiếng "tít" mềm lúc bắt đầu |
| Đang nghĩ | Gradient xoay chậm / các chấm nhịp nhàng | "Vy đang nghĩ…" | **âm thanh "nghĩ" lặp nhẹ** (xem 4.4), tắt khi bắt đầu nói |
| Đang nói | Quả cầu nhấp nhô theo nhịp lời, màu ấm hơn | chính câu Vy đang nói, to, chạy theo từng cụm | rung rất nhẹ lúc bắt đầu |

**Hoạt ảnh**: vẽ bằng `CustomPainter` + một `AnimationController` chung (không dùng gói nặng), 60fps, mức âm lượng nội suy mượt. Có chế độ giảm chuyển động: chỉ đổi màu và kích thước theo bậc.

### 4.3 Xác nhận gửi tin (cải thiện lớn về độ an toàn)
Khi Vy hỏi "Gửi cho Minh: 'tối nay mẹ không ăn cơm nhà' nhé?", hiện **thẻ xác nhận lớn** (mượn kiểu thẻ của Speak): ảnh đại diện người nhận, nội dung tin, hai nút to **Gửi** (xanh) và **Sửa** (viền). Bấm hoặc nói "gửi / sửa" đều được. Giảm lỗi nhận nhầm ("nhắn" thành "nhận") mà người già không phải nghe kỹ.

### 4.4 Âm thanh "đang nghĩ" kiểu GPT Live
- Tiếng "bong bóng" nhỏ, nhẹ, **lặp mỗi khoảng 1,2 giây**, hơi lên xuống cao độ, âm lượng thấp hơn giọng nói.
- Phát bằng `just_audio` ngay khi vào trạng thái "đang nghĩ", fade-out 150ms khi chuyển sang "đang nói" hoặc huỷ.
- File sinh bằng mã (không vướng bản quyền), ~30KB, đóng gói trong app, chạy offline.
- Có công tắc "Âm thanh của Vy" trong cài đặt.

### 4.5 Lỗi và chờ lâu
- Quá 6 giây vẫn đang nghĩ: chữ đổi thành "Vy đang tìm, bác chờ một chút nhé" và hiện nút **Thử lại**.
- Mất mạng: thẻ lỗi với một nút lớn, kèm gợi ý dùng chữ thay vì giọng nói (phụ đề + ô gõ).
- Luôn có **nút Kết thúc** thấy được, không dùng cử chỉ ẩn.

### 4.5b Tốc độ phản hồi (làm cùng lúc vì ảnh hưởng cảm nhận)
- Server trả quyết định giọng (máy hay ElevenLabs) **ngay trong kết quả lượt**, app bỏ lần gọi `/api/voice/tts` thừa.
- Tải danh bạ **song song** lúc đang ghi âm thay vì sau khi nói xong.
- Giọng máy làm mặc định, ElevenLabs chỉ cho câu quan trọng (cần bạn xác nhận, xem phần 8).
- Hiện lời bác nói ngay khi có, trước khi Vy trả lời xong.

---

## 5. Các màn còn lại

**Trang chủ mới**: lời chào theo giờ + tên ("Chào buổi sáng, bác Minh"); thẻ Vy to; thẻ **Huyết áp gần nhất** (số lớn, chip mức màu, giờ đo, nút "Đo mới" / "Xem lịch sử"); ba ô lớn hàng dọc (Tin nhắn, Chụp chỉ số, Lịch sử huyết áp), mỗi ô 72dp có icon + chữ + một dòng mô tả; hồ sơ/đăng xuất chuyển sang menu ở avatar góc trên (như Withings).

**Chat**: bong bóng bo 20, nền ngọc nhạt cho tin của mình, trắng cho người kia; ảnh bo 16 với nhãn giờ chồng góc dưới; chip trả lời nhanh ngay trên ô nhập; mic chính tả trong ô nhập; trạng thái trống có hình minh hoạ và nút "Nhắn tin đầu tiên"; đang gõ/đã gửi/đã xem rõ ràng.

**Huyết áp**: số lớn "118/78" + chip mức màu; chọn khoảng thời gian dạng viên thuốc; biểu đồ có vùng màu; danh sách đo có icon mức; nhập tay bằng sheet có bàn phím số to và gợi ý giới hạn hợp lệ.

**Đăng nhập, hoàn tất hồ sơ, hộp thoại cập nhật**: áp cùng hệ thiết kế (nền trắng lạnh, nút viên thuốc, phông mới), giữ khả năng đọc chữ to.

---

## 6. Lộ trình thực hiện (mỗi pha chạy được, kiểm tra được, commit riêng)

| Pha | Nội dung | Tệp chính | Kiểm tra |
|---|---|---|---|
| 0 | Chốt quyết định ở mục 8 | — | — |
| 1 | **Nền tảng**: bảng màu, phông, thang chữ, bo góc, thành phần dùng lại (`VyOrb` bản tĩnh, `BigTile`, `StatusChip`, `PillNavBar`) | `core/theme/*`, `shared/widgets/*` | analyze + test widget, ảnh chụp từng thành phần |
| 2 | **Vy toàn màn hình**: `VoiceScreen`, `VyOrb` có 4 trạng thái, thẻ xác nhận, âm thanh "nghĩ", bỏ lớp phủ nổi, gắn lối vào | `features/voice/presentation/*`, `app.dart`, router | test controller + widget; thử trên máy thật |
| 3 | **Giảm trễ**: trả quyết định giọng trong lượt, bỏ gọi `/tts` thừa, tải danh bạ song song | `api/voice/turn.ts`, `speech_player.dart`, `voice_controller.dart` | đo `total_ms` trước và sau trên máy thật |
| 4 | **Trang chủ + thanh điều hướng nổi** | `features/home/*`, router (ShellRoute) | test điều hướng, ảnh chụp |
| 5 | **Chat**: bong bóng, chip trả lời nhanh, mic trong ô nhập, trạng thái trống | `features/chat/*` | test chat hiện có + mới |
| 6 | **Huyết áp**: số lớn, vùng màu, nhập tay | `features/bp/*` | test + ảnh chụp |
| 7 | Đăng nhập, hồ sơ, hộp thoại cập nhật, chế độ tối | `features/auth/*`, `update_gate.dart` | ảnh chụp sáng/tối |
| 8 | **Hoàn thiện**: cỡ chữ 150%, TalkBack, tương phản, giảm chuyển động, hiệu năng; phát hành bản thử qua `release_android.sh` | toàn app | danh sách kiểm tra ở mục 7 |

Ước lượng: pha 1 và 2 là phần nặng nhất (khoảng một nửa công sức). Có thể giao từng pha để bạn xem trước trên điện thoại.

---

## 7. Cách kiểm tra chất lượng
- `flutter analyze` sạch, toàn bộ test hiện có (40) vẫn qua, thêm test cho từng trạng thái Vy và thẻ xác nhận.
- Ảnh chụp **điện thoại thật** (vivo V2339) và máy ảo cho mỗi màn, cả sáng và tối.
- Thử cỡ chữ hệ thống 100%, 130%, 150%: không tràn, không mất nút.
- Bật TalkBack, đi qua luồng "nhắn tin cho con" bằng giọng nói.
- Đo độ trễ lượt giọng nói (trước/sau) từ bảng `voice_turns`.
- Hiệu năng: hoạt ảnh quả cầu giữ 60fps trên máy thật, không gây nóng máy.

---

## 8. Quyết định đã chốt (13/11/2026)
1. **Giọng đọc: giọng máy cho mọi câu**, cho tới khi có giải pháp tốt hơn. Đường ElevenLabs vẫn còn trong mã, tắt bằng `SpeechPlayer.serverVoice = false`.
2. **Điều hướng dưới**: Trang chủ · Tin nhắn · (Vy) · **Sức khoẻ** · Hồ sơ. "Huyết áp" đổi thành **Sức khoẻ** vì sẽ có thêm các chỉ số khác (huyết áp là mục đầu tiên bên trong).
3. **Nền trắng lạnh** (không dùng nền kem). Bảng màu bám logo Viegrand: **xanh navy** + **xanh da trời**, điểm nhấn ngọc.
4. **Chế độ tối: để sau.**
5. Phông Be Vietnam Pro đóng gói sẵn (chờ xác nhận tải tệp phông).

### Bảng màu cuối (lấy từ logo)
| Vai trò | Giá trị | Ghi chú |
|---|---|---|
| Navy chính | `0048A8` | màu chữ thập trong logo, nút chính, tương phản với chữ trắng ≈ 8:1 |
| Navy đậm (chữ tiêu đề, nền tối) | `0B2447` | |
| Xanh da trời | `4FB3F0` | nền chip, quả cầu Vy, điểm nhấn thân thiện |
| Ngọc | `58E0E0` | màu thứ hai trong logo, vệt sáng của Vy |
| Nền | `F5F8FC` (trắng lạnh hơi xanh), thẻ `FFFFFF` | |
| Chữ phụ | `5B6B82` | |
| Mức huyết áp | `2D8B72` / `D9A441` / `E0785F` / `C94A4A` | |
