# Bản đồ app Viegrand cho trợ lý Vy (agent)

> **Tài liệu sống.** Vy điều khiển toàn bộ app, nên mỗi lần thiết kế hoặc đổi giao diện/tính năng đều phải cập nhật tệp này **trong cùng một thay đổi**.
> Mục tiêu: sau khi chốt thiết kế, có đủ thông tin để thiết kế "đường đi" (intent, slot, lệnh) cho agent mà không phải dò lại mã nguồn.

Cập nhật lần cuối: 13/11/2026 (sau pha 4, 5, 6 của [UI_REFRESH_PLAN.md](UI_REFRESH_PLAN.md)).

---

## 0. Quy tắc bắt buộc khi thiết kế

1. **Mỗi màn hình có mã (`screen_id`) ổn định và một đường dẫn (route).** Đổi tên chữ trên màn hình không đổi mã.
2. **Mỗi việc người dùng làm được bằng tay phải có một hành động (`action_id`) mà agent gọi được.** Không có việc nào chỉ làm được bằng cử chỉ ẩn (vuốt, giữ lâu).
3. **Mỗi hành động ghi rõ:** làm ở màn nào, cần tham số gì (slot), điều kiện trước, kết quả, câu Vy nói, có cần **xác nhận** không.
4. **Hành động gây hậu quả (gửi tin, xoá, đăng xuất, gọi) luôn qua bước xác nhận**, bằng giọng và bằng nút trên màn Vy.
5. **Mọi màn đều trả lời được "tôi đang ở đâu, làm được gì"**: Vy phải đọc được tên màn và các hành động có thể làm ở màn đó (`screen` được gửi lên server ở mỗi lượt).
6. **Mọi nút phải có `Semantics` (nhãn chữ)**, vì cùng nhãn này dùng cho TalkBack và để agent tìm nút.
7. Thêm/đổi màn hình, hành động, intent ⇒ sửa mục tương ứng ở dưới **và** ghi một dòng vào mục 6 (Nhật ký).

---

## 1. Màn hình (đang có trong app)

Mã hành động ở cột "Hành động" ghi theo dạng `màn.việc`. Ô "Agent" nói agent hiện điều khiển được tới mức nào.

| `screen_id` | Route | Mục đích | Hành động (người dùng) | Agent hiện nay |
|---|---|---|---|---|
| `home` | `/` (tab 1) | Trang chủ kiểu ảnh thật toàn nền (đổi theo buổi): lời chào, số huyết áp gần nhất rất lớn, khối Vy (blob) và nút "Đo huyết áp". Không còn ô "Làm nhanh" | `home.open_profile` (bấm avatar), `home.open_vy` (bấm blob), `home.open_bp` (bấm số huyết áp), `home.measure` | Mở Chat/Đo/Huyết áp: **có** (`open_feature`, `measure_bp`). Mở hồ sơ: **chưa** |
| `rooms` | `/rooms` (tab 2, tên hiển thị "Tin nhắn") | Danh sách phòng chat | `rooms.open_room(room)`, `rooms.new_chat` (mở sheet: chat riêng / nhóm) | Mở một phòng theo tên: **có** (`open_chat`). Tạo chat mới: **chưa** |
| `room` | `/rooms/:id` (không có thanh điều hướng) | Một cuộc chat, tin nhắn realtime | `room.send_text`, `room.quick_reply(text)` (Dạ / Cảm ơn / Đã ăn cơm rồi / Gọi lại giúp nhé), `room.send_image(+chú thích)`, `room.open_members` (nhóm), `room.open_vy` | Gửi tin chữ: **có** (`send_message`, có xác nhận). Gửi ảnh, đọc tin: **chưa** |
| `room.members` | (sheet) | Thành viên nhóm | `members.invite(username)` | **Chưa** |
| `bp` (tên hiển thị **"Sức khoẻ"**) | `/bp` (tab 3) | Sức khoẻ: huyết áp gần nhất, biểu đồ, lịch sử | `bp.capture` (mở OCR), `bp.delete(reading)` | Mở màn: **có** (`show_bp`). Đọc số gần nhất: **có** (`read_bp`). Xoá: **chưa** |
| `profile` | `/profile` (tab 4) | Hồ sơ: thông tin tài khoản, phiên bản app, đăng xuất | `profile.sign_out` (có hộp xác nhận "Ở lại / Đăng xuất") | **Chưa** |
| `measure` | `/measure` (toàn màn hình, ẩn nút Vy) | Đo huyết áp một chạm kiểu Locket: camera + nút chụp; chụp xong tự đọc (AI), phân loại, lưu `ocr_records` + `bp_readings`, nhận xét | `measure.shoot`, `measure.pick_gallery`, `measure.flip`, `measure.flash`, `measure.retake`, `measure.open_history`, `measure.close` | `measure_bp` mở màn này: **có**. Tự bấm chụp: **chưa** (cần agent bấm `measure.shoot`) |
|| `open_feature` | `feature` = `chat` | `ocr` | `bp` | `fun` || `/ocr` | Chụp/chọn ảnh máy đo, danh sách bản ghi OCR | `ocr.scan_camera`, `ocr.scan_gallery`, `ocr.open_record(record)` | Mở màn và hướng dẫn chụp: **có** (`measure_bp`). Tự bấm chụp: **chưa** |
| `ocr.edit` | `/ocr/edit` (extra: bản nháp) | Sửa các chỉ số vừa đọc, lưu | `ocr_edit.change_value(field, value)`, `ocr_edit.save` | **Chưa** |
| `ocr.detail` | `/ocr/detail` (extra: bản ghi) | Xem một bản ghi | `ocr_detail.copy`, `ocr_detail.delete` | **Chưa** |
| `community` | `/community` (toàn màn hình; lối vào là nút "Tìm người" ở thanh trên của `rooms`, chỉ hiện khi cờ `community` bật) | **Chỉ dùng cho đợt thử nghiệm.** Danh sách mọi người dùng (RPC `community_users`), tìm theo tên/@username, bấm "Nhắn tin" để mở chat riêng (kết bạn) | `rooms.open_community`, `community.search(query)`, `community.start_chat(username)` | **Chưa** |
| `login` | `/login` | Đăng nhập email/Google | (chưa đăng nhập, Vy tắt) | Không áp dụng |
| `register` | `/register` | Đăng ký | (Vy tắt) | Không áp dụng |
| `complete_profile` | `/complete-profile` | Hoàn tất hồ sơ sau đăng nhập Google | (Vy tắt) | Không áp dụng |

Ghi chú:
- `/rooms/:id`, `/ocr/edit`, `/ocr/detail` nhận dữ liệu qua `extra` (đối tượng `Room`, `OcrDraft`, `OcrRecord`). Agent **không** đi thẳng tới `ocr.edit` / `ocr.detail` được nếu thiếu dữ liệu; phải đi qua màn cha.
- Vy chỉ bật khi đã đăng nhập và hồ sơ đầy đủ (`enabled` trong `VoiceOverlay`).

## 2. Thành phần dùng chung (có mặt ở nhiều màn)

| Thành phần | Mã | Vai trò với agent |
|---|---|---|
| Thanh điều hướng dưới (Trang chủ · Tin nhắn · **Vy** · Sức khoẻ · Hồ sơ) | `global.nav_bar` | Chỉ có ở 4 tab chính (`MainShell`). Nút giữa là Vy. Tab = `home`, `rooms`, `bp`, `profile` |
| Nút Vy | `global.vy_button` | Lối vào Vy. Ở 4 tab chính nằm giữa thanh điều hướng; trong `room` là biểu tượng mic ở thanh trên; ở màn phụ (OCR...) là nút nổi 64dp góc dưới phải |
| Màn Vy toàn màn hình | `global.vy_screen` | Trạng thái: sẵn sàng, nghe, nghĩ, nói. Nút chính, "Kết thúc", chip gợi ý, nút xác nhận Gửi/Sửa/Hủy |
| Hộp thoại cập nhật | `global.update_gate` | Chặn khi bản app thấp hơn `min_supported_build`. Agent **không** được tự bấm cập nhật |
| Thanh thông báo (snackbar) | `global.snackbar` | Kết quả/ lỗi ngắn. Vy nên đọc lại lỗi quan trọng |

## 3. Intent Vy đã hỗ trợ (server `api/_lib/voice/dm.ts` + `voice_controller.dart`)

| Intent | Slot | Xác nhận | Việc app làm | Sau khi chạy |
|---|---|---|---|---|
| `send_message` | `room_id`, `content` | **Có** (Gửi/Sửa/Hủy) | gửi tin chữ vào phòng, mở phòng | thu gọn màn Vy |
| `open_chat` | `room_id` | Không | mở phòng chat | thu gọn màn Vy |
| `open_feature` | `feature` = `chat` | `ocr` | `bp` | `fun` |\| `ocr` \| `bp` | Không | `router.go` tới màn tương ứng | thu gọn màn Vy |
| `measure_bp` | — | Không | mở `ocr`, nhắc chụp màn máy đo | thu gọn màn Vy |
| `show_bp` | — | Không | mở| `open_feature` | `feature` = `chat` | `ocr` | `bp` | `fun` | thu gọn màn Vy |
| `read_bp` | — | Không | đọc lần đo gần nhất (từ `bpReadingsProvider`) | màn Vy **giữ mở** |
| `go_home` / `go_back` | — | Không | về trang chủ / lùi một màn | thu gọn màn Vy |
| `emergency` (nhận diện lời khẩn cấp) | — | — | Vy trả lời khẩn, không thực thi lệnh | — |
| `cancel` / `repeat` | — | — | huỷ lượt / nhắc lại câu trước | — |

Hội thoại nhiều bước: dialog gửi lên server ở mỗi lượt gồm `task`, `pending`, `expects` (`command`, `free_text`, `yes_no`, `choice`, `name`), `choices`. Vy tự mở mic sau khi hỏi (`expects_reply`).

Giọng đọc: **giọng máy (flutter_tts) cho mọi câu** từ 13/11/2026; ElevenLabs tắt bằng `SpeechPlayer.serverVoice = false`.

## 4. Khoảng trống cần thiết kế cho agent (đề xuất, chưa làm)

Các hành động người dùng làm được bằng tay nhưng Vy chưa gọi được. Chọn theo mức hữu ích cho người lớn tuổi:

| Ưu tiên | Hành động đề xuất | Gợi ý intent / slot | Xác nhận |
|---|---|---|---|
| Cao | Đọc tin nhắn mới nhất của một người | `read_messages(room_id, count)` | Không |
| Cao | Gửi ảnh vừa chụp cho ai đó | `send_image(room_id, source)` | Có |
| Cao | Chụp máy đo và lưu chỉ số | `scan_bp()` → `ocr.edit.save` | Có (đọc lại số rồi xác nhận) |
| Cao | Hỏi chỉ số sức khoẻ theo thời gian ("tuần này thế nào") | `summarize_health(range)` | Không |
| Vừa | Nhập chỉ số bằng lời | `add_bp(sys, dia, pulse)` | Có |
| Vừa | Gọi / nhắn nhanh người thân đã đặt tên ("con trai") | dùng `voice_aliases` (đã có) | Có |
| Vừa | Tạo chat mới, mời thành viên | `new_chat`, `invite_member` | Có |
| Vừa | Xoá bản ghi / chỉ số | `delete_record`, `delete_bp` | **Có, nói rõ không hoàn tác được** |
| Thấp | Đăng xuất | `sign_out` | Có |
| Thấp | Đổi cách xưng hô (bác/cô/chú…) | `set_honorific` | Không (hiện chưa có giao diện) |

## 5. Hướng kỹ thuật để agent bền vững (đề xuất)

Một **sổ đăng ký năng lực (capability registry)** duy nhất trong mã làm nguồn sự thật, thay vì rải rác ở `dm.ts`, `voice_controller.dart` và giao diện:

```
Screen(id, route, title, parent?)
Action(id, screen, label, slots[], needsConfirm, destructive, sayOnDone, execute())
```

- Giao diện (nút), TalkBack (`Semantics`) và agent **cùng đọc** sổ này, nên thêm một nút mới là agent có hành động tương ứng.
- Server lấy danh sách hành động khả dụng theo `screen` của lượt (đã gửi `screen`) để gợi ý cho LLM, nên LLM không bịa lệnh.
- Mỗi hành động có test: gọi bằng agent và bằng nút ra cùng kết quả.

Chưa làm; sẽ chốt khi xong thiết kế toàn bộ màn hình.

---

## 6. Nhật ký thay đổi giao diện (ghi mỗi lần đổi)

| Ngày | Thay đổi | Ảnh hưởng tới agent |
|---|---|---|
| 13/11/2026 | **Pha 1:** theme mới (navy `0048A8`, xanh da trời, nền `F5F8FC`), phông Be Vietnam Pro, 4 thành phần dùng lại (`StatusChip`, `BigTile`, `PillNavBar`, `VyOrb`) | Không đổi hành động |
| 13/11/2026 | **Pha 2:** Vy chuyển từ nút mic nổi 88px + bảng nhỏ sang **màn toàn màn hình** (`global.vy_screen`) có quả cầu 4 trạng thái, nút xác nhận Gửi/Sửa/Hủy, âm thanh "đang nghĩ" | Lệnh đổi màn hình (`_navIntents`) tự thu gọn màn Vy; `read_bp` giữ mở. Nút Back đóng màn Vy trước |
| 13/11/2026 | Nút Vy nổi thu còn 64dp; ẩn trong `room`, thay bằng mic ở thanh trên; thẻ "Trợ lý Vy" trên trang chủ bấm được (`home.open_vy`) | Thêm 2 lối vào Vy: `room.open_vy`, `home.open_vy` |
| 13/11/2026 | Giọng đọc: giọng máy cho mọi câu | Không còn gọi `/api/voice/tts` |
| 13/11/2026 | **Pha 4:** thêm `MainShell` và thanh điều hướng dưới dạng viên thuốc nổi cho 4 tab (`home`, `rooms`, `bp`, `profile`); nút giữa là Vy. Trang chủ làm lại (lời chào, thẻ Vy, huyết áp gần nhất, 3 ô làm nhanh). Thêm màn `profile` (đăng xuất có xác nhận). `room`, `ocr*` phủ lên toàn màn hình, không có thanh điều hướng. Nút Vy nổi chỉ còn ở màn phụ | Thêm màn `profile`. `go_back` trong tab không còn "lùi" mà nên về `home`. `open_feature` cần thêm `profile`, `health` khi mở rộng |
| 13/11/2026 | **Pha 5:** chat đẹp hơn: bong bóng bo 20 với góc nhọn phía người gửi, chữ 18, chip trả lời nhanh (`room.quick_reply`), trạng thái trống mới; danh sách phòng đổi tên "Tin nhắn" | Thêm hành động `room.quick_reply(text)`. Agent có thể dùng cùng 4 câu này |
| 13/11/2026 | **Pha 6:** màn Sức khoẻ (route `/bp`): tiêu đề "Sức khoẻ", số huyết áp lớn kèm chip mức, lịch sử hàng cao hơn, trạng thái trống mới | Không đổi hành động; tên hiển thị khi Vy đọc màn là "Sức khoẻ" |
| 13/11/2026 | Đổi tên mục điều hướng dự kiến "Huyết áp" thành **"Sức khoẻ"** (chứa huyết áp và các chỉ số khác về sau) | Khi làm pha 4, `bp` sẽ nằm dưới `health`; `open_feature` cần thêm `feature = health` |

### Các thay đổi đã quyết nhưng chưa làm (sẽ ảnh hưởng agent)
- Màn `health` riêng chứa nhiều chỉ số (hiện `bp` đang dùng tên "Sức khoẻ"); khi có thêm chỉ số khác thì tách `health.bp`, `health.<chỉ số>`.
- Nhập huyết áp thủ công (`bp.add`), bộ chọn khoảng thời gian D/W/M cho biểu đồ.
- Cài đặt cách xưng hô của Vy (`profile.set_honorific`).
- Chế độ tối (để sau).
| 13/11/2026 | **OCR:** bỏ công tắc "Đọc bằng AI"; luôn đọc bằng AI (`ocr_ai`). Bỏ action tương ứng, không còn `toggle_ai_ocr` | Agent không cần bật/tắt AI |
| 13/11/2026 | **Đo một chạm:** thêm màn `measure` (`/measure`, gói `camera`, quyền CAMERA). Home, tab Sức khoẻ và intent `measure_bp` giờ mở `measure` thay vì `ocr`;| `open_feature` | `feature` = `chat` | `ocr` | `bp` | `fun` |(bản ghi tổng quát) hiện không còn lối vào từ UI | Quyết định có giữ `ocr` cho hoá đơn/bảng biểu |
| 13/11/2026 | **Cộng đồng (thử nghiệm):** bảng `app_flags` (khoá `community`), RPC `community_users`, màn `/community`, nút "Tìm người" ở màn Tin nhắn (đã chuyển từ trang chủ 13/11). Tắt sau đợt test bằng `update app_flags set enabled=false where key='community'` | Thêm màn `community` và hành động `community.start_chat`; agent có thể dùng làm cách tìm người để nhắn khi còn bật |

| 13/11/2026 | **Trang chủ kiểu Oura:** ảnh thật CC0 toàn nền theo buổi (`assets/images/`, nguồn `docs/CREDITS.md`), số huyết áp lớn, blob Vy gradient méo theo nhịp (`VyOrb`), nút kính mờ "Đo huyết áp". Bỏ các ô "Làm nhanh" (trùng thanh dưới) | Semantics giữ nguyên tên hành động; blob là lối vào Vy thứ hai cạnh nút giữa thanh dưới |
| 13/11/2026 | **Giao diện kiểu iOS cho các tab:** tiêu đề lớn (`LargeTitle`), nút tròn trên thanh tiêu đề (`SoftIconButton`), danh sách gom nhóm (`InsetGroup`), thẻ không viền. Tin nhắn: nút "+" (Chat mới) và "Tìm người" (Cộng đồng) ở tiêu đề, bỏ FAB. Sức khoẻ: nút máy ảnh ở tiêu đề thay FAB. Hồ sơ: nhóm thông tin + hàng "Đăng xuất" đỏ. Mạch hiển thị chữ "Mạch" thay biểu tượng trái tim | Các hành động giữ nguyên nhãn Semantics (`Chat mới`, `Tìm người dùng khác`, `Đo huyết áp`, `Đăng xuất`) |
| 13/11/2026 | **Thanh điều hướng + Vy:** thanh dưới trắng nổi không viền, không còn nền đặc cho mục đang chọn. Nút Vy giữa thanh là blob (`VyButton` dùng `VyOrb`), ẩn ở tab Trang chủ vì Trang chủ đã có blob lớn (`home.open_vy`). Bong bóng chat nhận không còn viền | `open_vy_from_nav` chỉ có ở 3 tab Tin nhắn, Sức khoẻ, Hồ sơ |
| 13/11/2026 | **Đo nhanh hơn:** `/api/ocr` nhận `mode=bp` (chỉ đọc SYS/DIA/PULSE, câu trả lời ngắn); màn `measure` hiện kết quả ngay sau khi đọc, lưu chạy ngầm ("Đang lưu…" → "Đã tự lưu"), tải lịch sử song song với lúc đọc | Không đổi hành động của agent |
| 13/11/2026 | **Giải trí (YouTube):** thêm màn `entertainment` (`/entertainment`: ô tìm `video-search`, chip gợi ý, danh sách thẻ video) và `entertainment.play` (`/entertainment/play`, trình phát nhúng `youtube_player_iframe`, nút "Mở bằng app YouTube" khi video cấm nhúng). Trang chủ thêm nút "Giải trí" (`home-fun`, hành động `home.open_fun`). Tìm kiếm qua `POST /api/youtube` (YouTube Data API, khoá `YOUTUBE_API_KEY` ở Vercel, lọc `videoEmbeddable` + `safeSearch=strict`, cache 6 giờ, giới hạn theo người dùng); lỗi thì app tự quay về đọc trang YouTube | Intent mới `play_video` (`content` = từ khoá): từ khoá cụ thể phát ngay kết quả đầu, từ khoá chung ("nhạc xưa") hiện danh sách để chọn. `open_feature` thêm `feature = fun` |
| 13/11/2026 | **Giải trí dễ dùng hơn:** `entertainment` mở ra là lưới 6 ô lớn (Nhạc xưa, Cải lương, Tin tức, Thiền thư giãn, Hài kịch, Dưỡng sinh), chạm là tìm, ô gõ để ở dưới; khi có kết quả có nút "Chọn mục khác" (`Chọn mục khác`) quay về lưới. `entertainment.play` có nút to `Bài trước` / `Tạm dừng`-`Phát` / `Bài kế tiếp`, `Lùi 15 giây`, `Tới 15 giây`, dòng "Tiếp theo", tự sang bài kế khi hết bài, nút Vy nổi hiện ở màn này (khung YouTube bị chặn chạm). Danh sách đang phát lưu ở `videoQueueProvider` | Intent mới `video_control` (`content` = `pause` \| `play` \| `next` \| `previous` \| `louder` \| `quieter`): nói "dừng", "tiếp tục", "bài khác", "bài trước", "to lên", "nhỏ đi"; chỉ chạy khi màn phát đang mở, không thì Vy báo chưa có video. Âm lượng chỉ chỉnh trong khung phát, muốn to hơn phải dùng nút máy |

