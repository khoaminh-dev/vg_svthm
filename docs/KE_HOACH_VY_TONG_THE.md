# Kế hoạch: Vy tổng thể (ngoài giải trí) và các lỗi gặp khi dùng thật

Ngày lập: 24/11/2026. Trạng thái: **bản nháp chờ chủ dự án duyệt, chưa viết mã**.
Gồm: (1) bốn lỗi chủ dự án gặp khi dùng bản b51; (2) phân tích các mảng Vy khác (khẩn cấp, thuốc, huyết áp, tin nhắn, gọi điện, hằng ngày, người thân, hội thoại); (3) nguyên nhân gốc chung; (4) danh mục tình huống; (5) đợt làm và quyết định cần duyệt.
Nối tiếp [KE_HOACH_VY_GIAI_TRI.md](KE_HOACH_VY_GIAI_TRI.md) (đã làm 5 đợt).

## 1. Bốn lỗi chủ dự án gặp (24/11/2026, bản b51)

| # | Hiện tượng | Nguyên nhân gốc (đã xác minh bằng mã và thử bằng chữ) | Cách sửa |
|---|---|---|---|
| L1 | Từ trang tìm video, bấm **Quay lại** không thoát được | Vy mở màn bằng `router.go(...)` nên ngăn xếp chỉ còn đúng màn đó; nút Quay lại gọi `context.pop()` mà **không còn gì để thoát**. Cùng lỗi ở **27 chỗ `context.pop()` trong 17 màn** (Giải trí, Cộng đồng, Kế hoạch, đo huyết áp, thuốc, hồ sơ, thẻ y tế, SOS…) | Hàm chung `safePop`: có trang trước thì thoát, không thì về Trang chủ. Thay cả 27 chỗ. Thêm kiểm tra: mọi màn mở bằng giọng đều thoát được bằng nút Quay lại và nút Back của máy |
| L2 | Nói "tôi muốn **coi** thời sự" thì Vy chỉ mở màn Giải trí, không phát thời sự | Từ **"coi"** (tiếng miền Nam, nghĩa là "xem") **không có trong bất kỳ luật nào** (luật nhanh, bộ ghép số thứ tự, gợi ý cho LLM). Câu rơi sang LLM, LLM chọn "mở mục Giải trí". Thử: "xem thời sự" thì phát đúng, "coi thời sự" thì không | Bảng chuẩn hoá cách nói vùng miền chạy **trước** mọi luật (coi→xem, bật lên, mở lên, cho coi…). Thêm ví dụ vào lời nhắc LLM |
| L3 | Nói "coi **video đầu tiên trong danh sách**" thì Vy mở video có tên "đầu tiên" | (a) luật chọn theo số thứ tự chỉ nhận **nguyên câu** đúng mẫu ("video đầu tiên"), không nhận "trong danh sách", "ở trên cùng", "tôi muốn coi…"; (b) câu rơi xuống luật tìm video và coi "đầu tiên trong danh sách" là **tên bài**. Thử: "xem video đầu tiên trong danh sách" ra `play_video: "Đầu tiên trong danh sách"` | (1) Ghép số thứ tự linh hoạt: tìm cụm "đầu tiên/thứ hai/số 3/cuối" **ở bất cứ đâu trong câu** khi đang có danh sách; (2) **lưới an toàn sau mọi đường** (luật lẫn LLM): nội dung tìm video mà là tham chiếu ("đầu tiên", "cái trên cùng", "trong danh sách") thì không bao giờ đem đi tìm, mà chọn mục trong danh sách đang hiện hoặc hỏi lại |
| L4 | Nói "**lướt xuống** để tôi xem mấy video khác" thì Vy nói "không làm được" | **Không có lệnh cuộn nào** trong cả app lẫn máy chủ; sổ điều khiển chỉ biết nút và danh sách số, không biết cuộn | Lệnh cuộn toàn cục: "lướt/cuộn/kéo xuống", "xuống nữa", "lên trên", "về đầu", "xem thêm", "mấy cái khác". Mỗi màn có danh sách đăng ký vùng cuộn; cuộn một trang mỗi lần. Kèm **Vy đọc 3 mục tiếp theo** ("Bài 4: …, bài 5: …") để người nhìn kém không cần nhìn |

**Hệ quả**: lỗi L1 làm người dùng **bị kẹt** (không thoát được màn nào Vy mở bằng giọng). Nặng hơn một lỗi tính năng, nên làm đầu tiên và phát hành riêng (b52).

**Tiến độ Đợt 0 (24/11/2026)**: đã làm cả 4 lỗi L1–L4, chưa thử máy thật.
- L1: `safePop` thay 27 chỗ ở 17 màn + thanh Quay lại của người cao tuổi; có test: mở bằng `go`, `push`, đường dẫn thẳng, và màn Giải trí.
- L2: `api/_lib/voice/dialect.ts`; "coi" và vài cách nói miền Nam; chạy trong `dm.ts` và `ui_cmd.ts`. Có kiểm thử không làm đổi nghĩa ("túi sáng", "máy hỏng", "bác sĩ"…): "tui" chỉ đổi khi đi trước động từ của người nói vì bỏ dấu trùng "túi" (túi thuốc).
- L3: số thứ tự nhận ở bất kỳ chỗ nào trong câu; `isReferentialQuery` + lưới an toàn sau mọi đường (kể cả LLM).
- L4: `scroll`, `read_list` (máy chủ), `ControlRegistry.scroll` + `VyControlScope(scroll:)` (app), đăng ký ở màn Giải trí.
- Kiểm thử: máy chủ 542 test (thêm `dialect.test.ts` 63 mục), Flutter thêm `safe_pop_scroll_test.dart` 11 test.
- Còn lại của đợt 0: cuộn bằng giọng mới có ở màn Giải trí; các màn có danh sách khác (tin nhắn, thuốc, cộng đồng) để đợt 4. Nút Back vật lý của Android ở màn gốc chưa thử.

## 2. Kết quả phân tích các mảng Vy khác (tóm tắt, chi tiết ở phần hội thoại ngày 24/11)

Thử ~190 câu nói thật bằng chữ qua tầng luật nhanh (LLM giả: các câu "rơi sang LLM" chưa biết kết quả thật).

| Mảng | Vấn đề chính |
|---|---|
| **An toàn** | Khẩn cấp chỉ nhận 11 cụm: "tôi bị ngã" (thiếu "rồi"), "cứu tôi với", "tôi sắp ngất", "có người ngã" đều bị trả lời "Việc này con chưa làm được". "Tôi bị đột quỵ" bị hiểu là **hỏi nguy cơ đột quỵ** (đọc số liệu). "Gọi cấp cứu" chỉ nhận được một đoạn khuyên, không quay 115 như "gọi 115". Dấu hiệu đột quỵ (mặt méo, tay yếu, nói khó) gần như không nhận. Thuốc: "uống nhầm thuốc", "uống gấp đôi liều", "hết thuốc rồi" rơi vào câu từ chối chung |
| **Hiểu sai** | "Nhắc tôi đo huyết áp lúc 8 giờ" mở màn đo ngay. "Huyết áp bao nhiêu là cao" đọc số đo gần nhất. "Nhắn cho cô Hoa" tách thành người nhận "cô" + nội dung "Hoa". "Gửi ảnh cho con" lấy "ảnh" làm người nhận. "Gửi lại" khớp mờ với Lan. "Mẹ uống thuốc chưa", "đo huyết áp cho mẹ" làm việc cho chính người nói |
| **Chưa có** | Giờ, ngày, thứ; nhắc giờ/báo thức; thời tiết; gọi lại số vừa rồi; sửa/thêm/đổi giờ thuốc, bỏ qua cữ; xem số đo hôm qua/trung bình tuần; cỡ chữ, âm lượng; mở màn ngoài 5 mục (cộng đồng, thư giãn, cá nhân, thẻ y tế, mời người thân) từ màn không khai báo điều khiển đó |
| **Người thân** | Máy chủ không dùng vai trò; Vy của người thân chỉ làm việc của chính họ. Không có "huyết áp của mẹ", "mẹ uống thuốc chưa", "xem cảnh báo", "gọi mẹ". Nhắc chủ động chỉ cho người cao tuổi |
| **Hội thoại** | Mọi câu không hiểu ra cùng một câu lạnh ("Việc này con chưa làm được. Con giúp bác nhắn tin hoặc đo huyết áp nhé?"), kể cả "kể chuyện cười", "bạn tên gì", "mấy giờ rồi". Không nhớ "nó/cái đó/trả lời/đọc lại". Câu trợ giúp không nhắc giải trí, thuốc, gọi điện |

## 3. Nguyên nhân gốc chung (sửa gốc thì nhiều lỗi lẻ hết theo)

1. **Từ vựng cứng, không có cách nói vùng miền.** "Coi", "mần", "tui", "hông", "dzô", "má/tía", "nghe thử", "lên", "dùm/giùm"… Mỗi luật tự liệt kê từ nên thiếu ở chỗ này chỗ kia. → **Một bảng chuẩn hoá chung** chạy trước mọi luật.
2. **Đường LLM không có lưới an toàn.** Kết quả LLM đi thẳng ra hành động: "đầu tiên" thành từ khoá tìm kiếm, "coi thời sự" thành "mở Giải trí". → **Bộ kiểm sau LLM**: nội dung tham chiếu, ý định mơ hồ, hành động không khớp màn hình thì chặn hoặc hỏi lại.
3. **Điều hướng bằng `go` làm mất lịch sử**, nút Quay lại hỏng. → `safePop` + quy ước: màn Vy mở luôn có đường về.
4. **Sổ điều khiển chỉ biết "nút" và "danh sách số"**, không biết cuộn, đọc danh sách, mở màn theo tên. → mở rộng sổ: vùng cuộn, đọc N mục, bảng "tên màn → đường dẫn".
5. **Máy chủ không biết vai trò** (cha mẹ hay người thân) và **không có đối tượng của câu** ("mẹ", "ba"). → truyền vai trò, thêm đối tượng.
6. **Không có trí nhớ hội thoại ngoài việc đang dở.** → nhớ "đối tượng gần nhất" (người nhận, bài, danh sách, tin vừa đọc).

## 4. Danh mục tình huống (cột "Nay": ✅ đúng, 🟡 một phần, ❌ sai/chưa có, ? chưa rõ do cần LLM thật)

### A. Cách nói vùng miền và biến thể (nền cho mọi nhóm)
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| A1 | "Tôi muốn **coi** thời sự", "coi tin tức", "coi cải lương", "coi phim", "coi tivi" | Như "xem" | ❌ |
| A2 | "Mở thời sự **lên** coi", "bật lên", "mở **dùm/giùm** tôi" | Bỏ đệm, hiểu như lệnh thường | 🟡 |
| A3 | "**Tui** muốn nghe nhạc", "**hông** thích bài này", "**má** nhắn gì chưa" | Hiểu tui=tôi, hông=không, má/ba/tía/me=mẹ/bố | ❌ |
| A4 | "Cho tôi **coi thử**", "nghe thử", "mở xem" | Như xem/nghe | ❌ |
| A5 | "Bữa nay", "hồi nãy", "bữa hổm" | Hiểu hôm nay, lúc nãy, hôm trước | ❌ |
| A6 | Nói lẫn, ngập ngừng: "ờ… mở… cái… thời sự đi" | Gọt đệm, giữ ý chính | ✅ |

### B. Danh sách, số thứ tự, cuộn (lỗi L3, L4)
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| B1 | "Coi video đầu tiên trong danh sách", "cái đầu", "cái trên cùng" | Chọn mục 1 | ❌ (mở video tên "đầu tiên") |
| B2 | "Cái thứ hai", "số 3", "bài cuối", "cái áp chót" | Chọn đúng mục | ✅ (chỉ khi nguyên câu) |
| B3 | "**Lướt xuống** để tôi xem mấy video khác", "cuộn xuống", "kéo xuống", "xuống nữa" | Cuộn một trang, đọc 3 mục mới hiện | ❌ |
| B4 | "Lên trên", "về đầu danh sách", "lên lại" | Cuộn ngược | ❌ |
| B5 | "Xem thêm", "mấy cái khác", "còn gì nữa không" | Cuộn hoặc tìm thêm | ❌ |
| B6 | "Đọc tên các video", "có những bài nào", "đọc cho tôi nghe" | Đọc 3 mục, hỏi "bác chọn số mấy" | ❌ |
| B7 | Số vượt quá ("cái thứ mười" khi có 5) | "Chỉ có 5 bài" | ✅ |
| B8 | Hai danh sách cùng lúc (video + bài hát) | Hỏi "video hay bài hát" | 🟡 |

### C. Thoát và quay lại (lỗi L1)
| # | Tình huống | Vy/app làm | Nay |
|---|---|---|---|
| C1 | Màn Vy mở bằng giọng, bấm nút "Quay lại" | Thoát; không có trang trước thì về Trang chủ | ❌ (27 chỗ kẹt) |
| C2 | Nút Back của máy ở màn gốc | Về Trang chủ trước, bấm lần nữa mới thoát app | ❓ |
| C3 | "Quay lại", "thoát", "về" | Như bấm Quay lại | 🟡 |
| C4 | Đang hộp thoại, nói "thôi" | Đóng hộp thoại | ✅ |
| C5 | Màn kẹt không có nút nào | Không bao giờ xảy ra: kiểm thử tự động mọi màn | ❌ |

### D. Khẩn cấp và an toàn
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| D1 | "Tôi bị ngã", "tôi té", "tôi ngã rồi" | Khẩn cấp: nhắc giữ nút SOS/gọi 115, báo người thân theo quy tắc đã chốt | ❌/✅ (chỉ "ngã rồi") |
| D2 | "Cứu tôi với", "cứu", "giúp với, nguy lắm" | Như D1 | ❌ |
| D3 | "Tôi sắp ngất", "choáng", "tối sầm", "tim đập mạnh" | Như D1, hỏi triệu chứng | ❌ |
| D4 | "Tôi bị đột quỵ", "mặt tôi méo", "tay yếu không nhấc được", "nói không rõ" | Như D1, nói rõ dấu hiệu đột quỵ, **không** đọc nguy cơ | ❌ (đọc nguy cơ) |
| D5 | "Gọi cấp cứu", "gọi xe cấp cứu" | Quay 115 có đếm ngược và nút Huỷ (như "gọi 115") | ❌ |
| D6 | "Có người ngã" (người thân/hàng xóm) | Hỏi "ai ngã, bác có đang bên cạnh không", gợi ý 115 | ❌ |
| D7 | "Đau ngực", "khó thở", "bất tỉnh" | Khẩn cấp | ✅ |
| D8 | Nói khẩn cấp lúc đang phát video/đang đo | Dừng mọi thứ, ưu tiên cao nhất | 🟡 |
| D9 | Nhận nhầm ("mệt lắm" khi chỉ mệt) | Hỏi lại một câu thay vì báo động ngay | 🟡 |

### E. Thuốc
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| E1 | "Tôi uống thuốc rồi", "uống rồi" | Ghi cữ đến giờ | ✅ |
| E2 | "Chưa uống", "lát nữa uống" | Hoãn 15 phút | ✅ |
| E3 | "Tối nay uống thuốc gì", "sáng nay uống chưa" | Đọc lịch | ✅ |
| E4 | "Tôi **uống nhầm** thuốc", "uống gấp đôi liều được không" | Kịch bản an toàn: không khuyên liều, gọi bác sĩ/dược sĩ, có triệu chứng thì 115, đề nghị gọi người thân | ❌ |
| E5 | "Hết thuốc rồi", "sắp hết thuốc" | Ghi chú, báo người thân/nhắc mua | ❌ |
| E6 | "Đổi giờ uống thuốc", "nhắc uống thuốc lúc 7 giờ", "thêm thuốc mới" | Mở đúng màn sửa lịch, hoặc làm bằng giọng có xác nhận | ❌ |
| E7 | "Bỏ qua cữ này", "hôm nay không uống" | Ghi bỏ qua, hỏi lý do nếu bỏ nhiều cữ | ❌ |
| E8 | "Thuốc này tác dụng phụ gì", "uống lúc nào" | Đọc từ đơn đã quét nếu có; không có thì chỉ dẫn hỏi bác sĩ | ? |
| E9 | "Quên uống thuốc" | Hiểu là chưa uống cữ vừa qua, hỏi "uống bù thế nào hỏi bác sĩ", ghi trễ | ? |

### F. Huyết áp
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| F1 | "Đo huyết áp", "đo lại" | Mở màn đo (nghỉ 5 phút trước) | ✅ |
| F2 | "**Nhắc tôi đo huyết áp lúc 8 giờ**" | Đặt giờ nhắc, **không** mở màn đo | ❌ |
| F3 | "Huyết áp **bao nhiêu là cao**", "bao nhiêu là bình thường" | Trả lời bảng ngưỡng AHA (đã có kịch bản), không đọc số đo | ❌ |
| F4 | "Huyết áp hôm nay bao nhiêu" | Đọc số gần nhất | ✅ |
| F5 | "Số đo hôm qua", "trung bình một tuần", "cao nhất tuần này" | Đọc từ lịch sử | ❌ |
| F6 | "Huyết áp 130 trên 80" | Hỏi xác nhận rồi ghi | ✅ |
| F7 | "Tôi chóng mặt/đau đầu" (khi vừa đo cao) | Kịch bản AHA: ngồi nghỉ, đo lại; có dấu hiệu nặng thì 115 | 🟡 |
| F8 | "Tôi nên đo lúc nào" | Trả lời theo chuẩn: sáng sau thức dậy, tối trước ngủ; gợi ý đặt nhắc | ❌ |

### G. Tin nhắn
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| G1 | "Nhắn cho con trai là mai bác về" | Tìm người, đọc lại, xác nhận | ✅ |
| G2 | "Nhắn cho **cô Hoa**", "nhắn cho **chú Ba**" | Hiểu "cô Hoa" là tên | ❌ (tách "cô" / "Hoa") |
| G3 | "**Gửi ảnh** cho con" | Nói rõ chưa gửi ảnh bằng giọng được, mở khung chat | ❌ ("ảnh" thành người nhận) |
| G4 | "**Trả lời** Lan là dạ", "trả lời" (sau khi đọc tin) | Trả lời đúng người vừa đọc | ❌ |
| G5 | "**Gửi lại**", "nhắn lại" | Gửi lại tin vừa rồi hoặc hỏi | ❌ (khớp mờ với Lan) |
| G6 | "Đọc lại tin vừa rồi", "Lan nhắn gì đó" | Đọc lại tin của Lan | ❌ |
| G7 | "Mở tin nhắn của Lan", "mở chat với Hùng" | Mở đúng phòng | ❌ |
| G8 | "Nhắn vào nhóm gia đình là…" | Gửi vào nhóm có xác nhận | ✅ |
| G9 | Tên khó nghe, trùng tên | Hỏi chọn có chip | ✅ |

### H. Gọi điện
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| H1 | "Gọi cho con trai", "gọi Lan" | Đếm ngược rồi gọi | ✅/? |
| H2 | "Gọi **lại** số vừa rồi", "ai vừa gọi cho tôi" | Đọc/gọi lại từ nhật ký cuộc gọi (cần quyền) | ❌ |
| H3 | "Gọi video cho con" | Nói rõ chưa có, đề nghị gọi thoại hoặc nhắn | ✅ |
| H4 | "Gọi nhà", "gọi xe", "gọi taxi" | Nhà: hỏi gọi ai; xe: nói chưa làm được | ❌ |
| H5 | "Gọi cho bác sĩ" | Gọi liên hệ "bác sĩ" trong thẻ y tế, chưa có thì hướng dẫn thêm | 🟡 |

### I. Việc hằng ngày
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| I1 | "Mấy giờ rồi", "bây giờ là mấy giờ" | Đọc giờ (không cần mạng) | ❌ |
| I2 | "Hôm nay thứ mấy", "hôm nay ngày bao nhiêu", "âm lịch" | Đọc thứ/ngày (âm lịch: quyết định) | ❌ |
| I3 | "Thời tiết hôm nay", "có mưa không" | Cần nguồn thời tiết (quyết định) | ❌ |
| I4 | "**Nhắc tôi** 8 giờ đi khám", "báo thức 6 giờ", "nhắc tôi uống nước" | Đặt nhắc cục bộ, đọc lại giờ, xác nhận | ❌ |
| I5 | "Hôm nay có việc gì", "lịch hôm nay" | Đọc thuốc + nhắc đã đặt | ❌ |
| I6 | "Tăng cỡ chữ", "chữ to lên", "to tiếng Vy", "tắt tiếng" | Đổi cài đặt tương ứng | ❌ |
| I7 | "Đổi cách xưng hô" | Hỏi xưng hô, lưu | ? |

### J. Tâm sự và trò chuyện
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| J1 | "Tôi buồn", "chán", "cô đơn" | Hỏi một câu và gợi ý nghe/xem (đã làm ở đợt Giải trí) | ✅ |
| J2 | "Kể chuyện cười", "kể chuyện" | Mở hài kịch/truyện hoặc kể một câu ngắn | ❌ |
| J3 | "Bạn tên gì", "bạn là ai" | "Con là Vy, trợ lý của bác" | ❌ |
| J4 | "Cảm ơn Vy", "Vy giỏi quá" | Đáp ấm áp, ngắn | ✅/🟡 |
| J5 | Câu không hiểu | **Không** nói "chưa làm được" chung chung: nêu 2–3 việc gần với câu nhất, hoặc hỏi lại "bác muốn con làm gì ạ" | ❌ |
| J6 | "Giúp tôi với" (không rõ khẩn cấp) | Hỏi "bác cần giúp gì ạ? Nếu nguy hiểm bác nói 'cứu tôi'" | ❌ |

### K. Điều hướng toàn cục
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| K1 | "Mở cộng đồng", "mở thư giãn", "mở cá nhân", "mở hồ sơ", "mở cài đặt" | Mở màn từ **bất cứ màn nào** | 🟡 (chỉ khi màn hiện có điều khiển đó) |
| K2 | "Mở thẻ y tế", "mời người thân", "mở camera", "mở lịch thuốc", "chụp đơn thuốc" | Như trên | 🟡 |
| K3 | "Về trang chủ", "quay lại" | Như trên | ✅ |
| K4 | "Đăng xuất" | Nói Vy không làm việc này, chỉ vào nút (mức 3) | ✅ |

### L. Người thân hỏi về cha/mẹ (vai trò Gia đình)
| # | Người nói | Vy làm | Nay |
|---|---|---|---|
| L1 | "Huyết áp của mẹ thế nào", "mẹ đo huyết áp chưa" | Đọc số đo gần nhất của mẹ (theo quyền `health`) | ❌ (đọc/đo của chính mình) |
| L2 | "Mẹ uống thuốc chưa", "hôm nay mẹ quên cữ nào" | Đọc theo quyền `meds_view` | ❌ |
| L3 | "Mẹ có ổn không" | Tóm tắt: đèn trạng thái, đo hôm nay, thuốc, cảnh báo | ❌ |
| L4 | "Xem cảnh báo", "có cảnh báo gì không" | Đọc cảnh báo chưa xem | ❌ |
| L5 | "Gọi mẹ", "nhắn mẹ là con sắp về" | Gọi/nhắn đúng người liên kết (có số trong hồ sơ) | 🟡 |
| L6 | Có nhiều cha/mẹ liên kết | Hỏi "mẹ hay ba ạ" bằng chip | ❌ |
| L7 | Không có quyền xem | Nói rõ "mẹ chưa cho phép con xem mục này" | ❌ |

### M. Hội thoại nhiều lượt
| # | Tình huống | Vy làm | Nay |
|---|---|---|---|
| M1 | Vừa đọc tin của Lan, nói "trả lời là dạ" | Hiểu trả lời Lan | ❌ |
| M2 | "Cái đó", "nó", "bài đó" | Hiểu đối tượng gần nhất | ❌ |
| M3 | "Nói lại", "chậm thôi", "to lên" (về giọng Vy) | Đọc lại chậm hơn, to hơn | 🟡 |
| M4 | Sửa nửa chừng: "không phải, nhắn cho Hùng" | Đổi người nhận | ✅ |
| M5 | Im lặng sau câu hỏi | Chọn mặc định hoặc hỏi lại một lần (nguyên tắc đợt Giải trí) | 🟡 |

## 5. Thiết kế đề xuất (cho các nguyên nhân gốc ở mục 3)

**5.1 Bảng chuẩn hoá cách nói** (`api/_lib/voice/dialect.ts`, chạy ngay sau bỏ dấu, trước mọi luật):
- Đồng nghĩa động từ: coi, coi thử, cho coi→xem; nghe thử→nghe; "mở … lên", "bật … lên"→mở.
- Đại từ: tui/tôi/mình→tôi; má/mạ/mẹ/u/bầm→mẹ; ba/tía/bố/cha→ba; "hông/hổng/hok"→không; "dzô/zô"→vào; "dùm/giùm/hộ"→bỏ.
- Thời gian: bữa nay→hôm nay; hồi nãy→lúc nãy; bữa hổm→hôm trước.
- Có kiểm thử riêng: mỗi cặp một dòng, và kiểm không làm hỏng câu thường ("bác sĩ", "ba" trong số đếm).

**5.2 Lưới an toàn sau mọi đường** (`guardDecision` trong `dm.ts`, chạy sau luật lẫn LLM):
- `play_video` mà nội dung là tham chiếu (đầu tiên, cuối, thứ N, trong danh sách, trên cùng…) → chọn mục (nếu có danh sách) hoặc hỏi lại.
- `open_feature` không khớp từ nào trong câu (như "coi thời sự" → Giải trí) → hỏi lại hoặc đổi sang `play_video` nếu có chủ đề.
- `unsupported` → chọn lời đáp theo nhóm (giờ, ngày, tâm sự, thời tiết, nhắc giờ) thay cho câu chung.
- Khẩn cấp luôn thắng mọi ý định.

**5.3 Sổ điều khiển mở rộng** (app + `ui_cmd.ts`):
- `VyScrollTarget` (đăng ký bộ điều khiển cuộn của màn), lệnh `scroll` (xuống, lên, đầu, cuối, thêm) và `read_list` (đọc N mục hiện/kế tiếp).
- Bảng "tên màn → đường dẫn" (`vy_nav`) dùng chung app và máy chủ: ~25 màn.
- Ghép số thứ tự linh hoạt (tìm cụm số thứ tự trong câu, bỏ "trong danh sách/ở trên cùng/tôi muốn coi").

**5.4 `safePop`** (`core/router/safe_pop.dart`): thoát nếu có trang trước, không thì về Trang chủ (theo vai trò). Thay 27 chỗ; có test mọi màn Vy mở bằng `go`.

**5.5 Việc hằng ngày cục bộ** (`daily.ts`): giờ, ngày, thứ, nhắc giờ (lưu trên máy, dùng bộ nhắc có sẵn), cỡ chữ/âm lượng qua cài đặt; câu đáp ấm cho tâm sự.

**5.6 Vai trò và đối tượng**: truyền `role` vào bước `step`; thêm `subject` (mẹ, ba, tên người thân) cho các ý định đọc (huyết áp, thuốc, cảnh báo, gọi); tra quyền theo `can_view`. Cha/mẹ nhiều người thì hỏi chọn bằng chip.

**5.7 Trí nhớ hội thoại**: `state.last = {người nhận, tin vừa đọc, danh sách, bài}` để hiểu "trả lời", "gửi lại", "cái đó".

## 6. Các đợt làm

| Đợt | Nội dung | Kiểm thử | Phát hành |
|---|---|---|---|
| **0 (làm ngay)** | **L1 `safePop` toàn app; L2 bảng chuẩn hoá cách nói (coi…); L3 ghép số thứ tự linh hoạt + lưới an toàn cho tham chiếu; L4 lệnh cuộn và đọc danh sách ở màn Giải trí** | Bằng chữ + test màn: mọi màn mở bằng giọng thoát được | **b52 riêng** |
| 1 | An toàn: mở rộng khẩn cấp (D1–D9), kịch bản thuốc nguy hiểm (E4, E5), "gọi cấp cứu" → 115 có đếm ngược | Bằng chữ, có kiểm không báo động nhầm | b52 hoặc b53 |
| 2 | Sửa hiểu sai: F2, F3, G2–G6, các câu "cho mẹ" | Bằng chữ | b53 |
| 3 | Hằng ngày: I1–I4, I6; J2–J6 (câu đáp ấm, hỏi lại có gợi ý) | Bằng chữ | b53 |
| 4 | Điều hướng toàn cục K1–K2, cuộn mọi màn có danh sách, cài đặt bằng giọng | Bằng chữ + test màn | b54 |
| 5 | Thuốc bằng giọng E6–E9, lịch sử huyết áp F5, F8 | Bằng chữ | b54 |
| 6 | Vy cho người thân L1–L7 (theo quyền) | Bằng chữ + dữ liệu mẫu | b55 |
| 7 | Hội thoại nhiều lượt M1–M5 | Bằng chữ | b55 |
| 8 | Chạy toàn bộ danh mục qua LLM thật (Groq, miễn phí) để biết phần nào LLM đã gánh; **một lần** thử giọng thật cuối | Groq + giọng thật | — |

Nguyên tắc kiểm thử giữ như đã chốt: **bằng chữ trước, miễn phí; chỉ một lần giọng thật ở cuối.** Mỗi đợt thêm danh mục câu vào `api/_tests/` theo mẫu `video_intent.test.ts`, kèm biến thể vùng miền (mỗi câu nói ít nhất 3 kiểu: Bắc, Nam, ngập ngừng).

## 7. Quyết định cần chủ dự án (kèm đề xuất mặc định)

| # | Câu hỏi | Đề xuất |
|---|---|---|
| Q1 | "Gọi cấp cứu" có quay 115 luôn (có đếm ngược 2 giây và nút Huỷ, như "gọi 115")? | Có. Vẫn theo nguyên tắc 20/11: người dùng chủ động nói thì mới gọi, không tự gọi thay |
| Q2 | Câu khẩn cấp mơ hồ ("mệt lắm", "choáng") báo động ngay hay hỏi lại một câu? | Hỏi lại một câu có hai nút "Có, giúp con" / "Không sao", im lặng 10 giây thì coi là có |
| Q3 | Thời tiết lấy từ đâu (cần dịch vụ ngoài)? | Chưa làm; trả lời thật "con chưa xem được thời tiết", gợi ý mở app thời tiết. Làm sau |
| Q4 | Nhắc giờ ("nhắc tôi 8 giờ đi khám") lưu ở đâu? | Trên máy, dùng bộ nhắc có sẵn; người thân chưa thấy |
| Q5 | Vy cho người thân đến đâu? | Đọc huyết áp, thuốc, cảnh báo, gọi/nhắn, theo đúng quyền đã cấp; không sửa gì bằng giọng ở bản đầu |
| Q6 | Ngày âm lịch có đọc không? | Có nếu dễ (thư viện nhỏ), đặt sau |
| Q7 | Chuẩn hoá cách nói vùng miền có thể làm sai nghĩa với ít trường hợp ("ba" = số 3 / bố). Chấp nhận? | Chấp nhận, kiểm thử riêng từng cặp; ưu tiên ngữ cảnh số trước |
| Q8 | "Lướt xuống" cuộn bao nhiêu mỗi lần? | Một trang màn hình, rồi Vy đọc 3 mục mới hiện |
| Q9 | Phát hành lỗi L1–L4 riêng (b52) trước khi làm tiếp? | Có: lỗi L1 làm kẹt người dùng |

## 8. Rủi ro và chưa kiểm chứng
- Hành vi **LLM thật** với đa số câu ở mục 4 chưa rõ (cột "?"); đợt 8 sẽ đo.
- Bảng cách nói vùng miền là kiến thức của tôi, **cần bạn (và người dùng thật ở các vùng) bổ sung**; sai nghĩa hiếm nhưng có.
- `safePop` đụng 17 màn: cần chạy cả bộ test màn và thử tay các luồng đăng ký, SOS, thẻ y tế.
- Cuộn bằng giọng trên màn có bàn phím hoặc hộp thoại cần chốt hành vi (không cuộn nền khi có hộp thoại).
- Nút Back vật lý của Android chưa được thử trên máy thật trong bất kỳ lỗi nào ở trên.
- Chưa đo độ trễ cộng thêm của bảng chuẩn hoá và lưới an toàn (dự kiến không đáng kể vì chạy cục bộ).
