# Kế hoạch: Vy giải trí thông minh, người cao tuổi gần như không phải động tay

Ngày lập: 24/11/2026. Trạng thái: **bản nháp chờ chủ dự án duyệt, chưa viết mã**.
Phạm vi: người cao tuổi mở nhạc, video, tin tức, thiền, dưỡng sinh bằng giọng nói. Người thân điều khiển giúp ở mục K.

## 1. Mục tiêu

Một câu nói của người cao tuổi phải dẫn tới việc **nghe/xem được thứ họ cần và nó cứ phát tiếp** cho đến khi họ bảo dừng. Không phải chạm màn, không phải trả lời nhiều câu, không phải nhờ lại từng bài.

Thước đo:
| Thước đo | Mục tiêu |
|---|---|
| Từ lúc nói xong đến lúc có tiếng | dưới 8 giây (câu rõ), dưới 12 giây (câu mơ hồ) |
| Số câu Vy hỏi lại trước khi phát | tối đa **1**, và câu hỏi trả lời được bằng "ừ", "không", một số, hoặc im lặng |
| Số lần phải chạm màn để nghe một buổi | 0 |
| Số lần phải nhờ lại giữa buổi vì video hỏng, hết bài, sai bài | 0 (Vy tự xử lý) |
| Lần đầu chọn trúng ý | từ 3 lần tìm trở xuống |

## 2. Nguyên tắc thiết kế

1. **Làm trước, hỏi sau.** Có thể đoán hợp lý thì phát ngay, nói rõ đã phát gì, và cho đường lui bằng một lời ("bài khác", "không phải").
2. **Một câu hỏi, có mặc định.** Cần hỏi thì hỏi một câu, đưa tối đa 3 lựa chọn đọc thành tiếng. Im lặng 6 giây thì chọn mặc định đã nói ("con mở số 1 nhé").
3. **Phiên giải trí không bao giờ tự chết.** Hết bài thì tự tìm tiếp cùng thể loại. Bài hỏng thì tự bỏ qua. Mất mạng thì báo và tự thử lại. Chỉ dừng khi người dùng bảo, khi hẹn giờ, hoặc khi việc quan trọng hơn chen vào.
4. **Việc quan trọng chen vào thì nhường rồi trả lại.** SOS, nhắc thuốc, cuộc gọi, nhắn tin gấp, đo huyết áp: dừng/hạ nhạc, xong thì hỏi "con phát tiếp nhé?" hoặc tự phát tiếp nếu việc ngắn.
5. **Nhớ người dùng.** Bài hay nghe, ca sĩ, giờ nghe, bài vừa bị chê. Dùng để đoán, không hỏi lại điều đã biết.
6. **Nói thật.** Chỉ nói "con mở rồi" khi video đã phát. Chỉ nói "con tăng âm lượng" khi âm lượng thật sự đổi.
7. **Nội dung an toàn trước.** Nhất là nội dung sức khoẻ (mục I).
8. **Không biến thành màn hình phải đọc.** Mọi thứ Vy hiện trên màn cũng phải nghe được.

## 3. Mô hình "phiên giải trí"

```
Nói yêu cầu → HIỂU (loại, chủ đề, ca sĩ, tâm trạng, thời lượng)
            → QUYẾT ĐỊNH (rõ → phát; mơ hồ → đoán theo thói quen; vẫn mơ hồ → 1 câu hỏi có mặc định)
            → PHÁT (hàng đợi 10–20 mục, lọc hỏng, đã nói tên bài)
            → DUY TRÌ (hết bài tự nối, bài hỏng tự bỏ, hạ tiếng khi Vy nói, nhường việc quan trọng)
            → KẾT THÚC (người dùng bảo / hẹn giờ / không ai nghe / việc khẩn)
```

Dữ liệu phiên: chủ đề, hàng đợi, bài đã phát, bài bị chê, lý do dừng, giờ bắt đầu, hẹn giờ.

## 4. Danh mục tình huống

Cột "Hỏi?" = Vy có được hỏi lại không. Ký hiệu: **0** không hỏi, **1** tối đa một câu.
Cột tình trạng ghi hiện tại: ✅ chạy, 🟡 chạy một phần, ❌ chưa có (theo đọc mã 24/11 và thử 60 câu bằng chữ, chưa thử tầng LLM).

### A. Yêu cầu rõ ràng

| # | Người dùng nói | Vy làm | Hỏi? | Nay |
|---|---|---|---|---|
| A1 | "Mở bài Nối vòng tay lớn" | Tìm đúng bài, ưu tiên bản gốc/chính thức, phát, nói tên bài đã làm sạch | 0 | 🟡 lấy kết quả đầu |
| A2 | "Nghe Khánh Ly hát", "nhạc Trịnh Công Sơn" | Hiểu là ca sĩ/nhạc sĩ, tạo hàng đợi nhiều bài khác nhau của người đó | 0 | 🟡 |
| A3 | "Mở bài Đường chiều của Khánh Ly" | Khớp cả bài lẫn ca sĩ, tránh bản cover | 0 | ❌ |
| A4 | "Mở cải lương Lệ Thủy", "tuồng", "chèo" | Phát vở/trích đoạn dài, nối vở kế tiếp | 0 | ❌ rơi sang LLM |
| A5 | "Cho nghe tin tức", "thời sự" | Bản tin mới nhất trong ngày từ kênh uy tín đã duyệt | 0 | 🟡 từ khoá "tin tức hôm nay" |
| A6 | "Mở VTV1 / bản tin 19 giờ" | Bản tin đúng đài, đúng giờ | 0 | ❌ |
| A7 | "Mở phim Tây Du Ký / phim bộ xưa" | Tập đầu hoặc tập đang xem dở, tự nối tập sau | 1 nếu có nhiều bản | ❌ |
| A8 | "Xem hài Hoài Linh / Chí Tài" | Tiểu phẩm không quảng cáo dài, nối tiếp | 0 | ❌ |
| A9 | "Mở bóng đá / đá banh hôm qua" | Tóm tắt trận mới nhất của đội/giải nói tới | 1 nếu không nêu đội | ❌ |
| A10 | "Nghe kinh Phật / kinh Phật Bà / tụng kinh" | Kinh dài, giọng chậm, nối bài; không phát tin quảng cáo | 0 | ❌ |
| A11 | "Nghe đài / nghe radio / nghe truyện / truyện đêm khuya" | Kênh đài/truyện đọc đã duyệt, tự nối chương | 0 | ❌ |
| A12 | "Mở bài tập dưỡng sinh / thể dục cho người già" | Chỉ kênh y tế đã duyệt (mục I) | 0 | 🟡 nguy cơ nội dung sai |
| A13 | "Mở youtube", "mở giải trí" | Mở màn, **và** hỏi một câu "bác muốn nghe gì ạ?" kèm 3 gợi ý theo thói quen | 1 | ✅ mở màn, ❌ gợi ý |
| A14 | Nói lẫn tiếng Anh: "play nhạc Trịnh", "mở youtube nhạc xưa" | Hiểu như tiếng Việt | 0 | 🟡 |

### B. Yêu cầu mơ hồ, theo tâm trạng và mục đích

| # | Người dùng nói | Vy làm | Hỏi? | Nay |
|---|---|---|---|---|
| B1 | "Mở nhạc", "bật nhạc lên" | Đoán theo thói quen và giờ; chưa có thói quen thì đọc 3 gợi ý ("nhạc xưa, nhạc Trịnh, nhạc không lời") và mặc định số 1 sau 6 giây | 1 | ❌ ("bật nhạc lên" tìm "nhac len") |
| B2 | "Mở cái gì nghe cho vui", "buồn quá, mở gì đi" | Hiểu là cần khuây khoả: gợi ý hài hoặc nhạc vui, hỏi một câu | 1 | ❌ |
| B3 | "Tôi chán quá", "buồn ngủ không ngủ được", "nhớ nhà" | Gợi ý nhẹ nhàng: nhạc êm/thiền/truyện; không lên giọng khuyên | 1 | ❌ |
| B4 | "Mở cái gì ru ngủ", "để ngủ" | Nhạc/truyện êm, **hẹn giờ tắt mặc định 30–45 phút**, giảm dần âm lượng rồi tắt | 0 | ❌ |
| B5 | "Mở cái gì tập thể dục", "tập cho khoẻ" | Bài dưỡng sinh nhẹ đã duyệt; nhắc "ngồi ghế được ạ" nếu người dùng nói khó đi | 0 | 🟡 |
| B6 | "Nghe cái gì cho thư giãn" | Nhạc thiền/không lời, âm lượng vừa phải | 0 | 🟡 |
| B7 | "Nghe cho đỡ buồn lúc nấu cơm" | Nhạc xưa vui, phát nền, nối dài, không cần màn | 0 | ❌ |
| B8 | "Cho cháu nghe nhạc thiếu nhi" | Nhạc thiếu nhi, giữ bộ lọc an toàn | 0 | ❌ |
| B9 | "Mở cái gì hay hay", "tuỳ" | Chọn theo thói quen hôm nay, nói rõ đã chọn gì, 0 hỏi lại | 0 | ❌ |
| B10 | "Có gì mới không", "hôm nay có gì xem" | Đọc 3 mục: tin trong ngày, nhạc họ hay nghe, một mục mới | 1 | ❌ |
| B11 | "Mở nhạc như hôm qua", "bài lúc nãy", "bài tôi hay nghe", "tập hôm trước" | Dùng lịch sử (mục C) | 0 | ❌ (tìm đúng chữ đó) |

### C. Nhớ và dùng thói quen

| # | Tình huống | Vy làm |
|---|---|---|
| C1 | Có lịch sử ≥ 3 lần | "Mở nhạc" thì phát theo thể loại/ca sĩ hay nghe nhất vào khung giờ đó |
| C2 | "Mở lại bài hôm qua / bài lúc nãy" | Phát đúng bài trong lịch sử, nhớ cả vị trí đang dở nếu là tập phim/vở diễn |
| C3 | Nghe dở hôm trước | Lần sau mở: "Bác nghe dở tập 5, con mở tiếp nhé?" (mặc định có) |
| C4 | Người dùng bảo "bài này hay", "thích bài này" | Lưu yêu thích, lần sau ưu tiên |
| C5 | "Không thích bài này", "đừng mở bài này nữa", "bài này dở" | Bỏ qua ngay, chuyển bài khác, ghi nhớ không phát lại |
| C6 | "Nghe ca sĩ khác đi" | Giữ thể loại, đổi ca sĩ, ghi nhớ đã chán ca sĩ vừa rồi |
| C7 | Người dùng mới, chưa có lịch sử | Dùng mặc định theo lứa tuổi/giờ: sáng dưỡng sinh/tin, trưa nhạc xưa, tối nhạc nhẹ/kinh/truyện |
| C8 | Nhiều người dùng chung máy | Lịch sử theo tài khoản, không trộn |

### D. Vy chủ động (giữ yên lặng là mặc định, chỉ nhắc khi hợp lý)

| # | Tình huống | Vy làm |
|---|---|---|
| D1 | Sáng quen tập dưỡng sinh | Nhắc một lần "Bác tập dưỡng sinh nhé?" (người dùng bật mới nhắc) |
| D2 | Tối trước giờ ngủ thường nghe nhạc | Gợi ý một lần; bỏ qua thì không nhắc nữa tối đó |
| D3 | Người thân gửi bài "Mẹ nghe bài này nhé" | Vy báo "Con gái gửi cho bác một bài, bác nghe luôn không ạ?" (mặc định có sau 8 giây khi bác đang rảnh) |
| D4 | Vy không bao giờ chen vào lúc đang nghe, đang gọi, đang đo huyết áp, đang nhắc thuốc | Hoãn gợi ý |
| D5 | Nhắc quá nhiều | Giới hạn: tối đa 1 gợi ý chủ động/buổi, tắt được bằng lời "đừng gợi ý nữa" |

### E. Trong khi đang phát: điều khiển bằng lời

| # | Người dùng nói | Vy làm | Nay |
|---|---|---|---|
| E1 | "Dừng", "tạm dừng", "tắt nhạc đi" | Tạm dừng; im lặng sau đó 5 phút thì hỏi "bác còn nghe không ạ" rồi thoát | ✅ |
| E2 | "Tiếp tục", "phát tiếp", "bật lại" | Phát tiếp | ✅ |
| E3 | "Bài khác", "bài tiếp", "chuyển bài" | Sang bài kế trong hàng đợi, **không** bỏ chủ đề | ✅ |
| E4 | "Bài trước", "nghe lại bài vừa rồi" | Về bài trước | ✅ |
| E5 | "To lên", "nhỏ đi", "nhỏ tiếng chút", "nghe không rõ" | Chỉnh âm lượng thật; đã tối đa thì nói "con để to hết cỡ rồi, bác tăng nút bên hông máy giúp con". "Nghe không rõ" khi Vy vừa nói thì tăng giọng Vy chứ không tăng video | 🟡 báo tăng dù không đổi |
| E6 | "Tua lại", "lùi lại một chút", "lùi 30 giây", "tới 1 phút" | Tua đúng; không nói số thì lùi 15 giây | ❌ |
| E7 | "Phát lại từ đầu", "nghe lại bài này" | Về giây 0 | ❌ (tìm "lai tu dau") |
| E8 | "Bài này của ai", "bài gì đây", "tên bài" | Đọc tên bài, ca sĩ | ❌ |
| E9 | "Còn bao lâu", "bao nhiêu phút nữa" | Đọc thời gian còn lại | ❌ |
| E10 | "Hẹn giờ tắt sau 30 phút" | Hẹn giờ, báo lại, tắt từ từ; hỏi "bác còn thức không" trước khi tắt nếu đang giữa chừng | ❌ |
| E11 | "Phát lặp lại bài này" | Lặp bài | ❌ |
| E12 | "Tắt đi", "thoát", "thôi", "đóng video" | Dừng và quay về trang chủ hoặc màn trước | 🟡 |
| E13 | "Cho xem lại danh sách", "còn những bài nào" | Đọc 3 bài kế tiếp, hỏi muốn chuyển bài nào | ❌ |
| E14 | "Cái thứ hai", "bài số 3" khi đang xem danh sách | Chọn đúng bài | ✅ |
| E15 | Nói chuyện (không phải lệnh) khi video đang phát | Không coi tiếng video là lệnh (mục H); chỉ nhận câu có "Vy" hoặc câu lệnh rõ | ❌ |
| E16 | Không nói gì, nhạc phát nhiều giờ | Sau 2 giờ hỏi một lần "bác còn nghe không ạ"; không trả lời thì giảm dần rồi tắt | ❌ |

### F. Việc khác chen vào

| # | Tình huống | Vy làm |
|---|---|---|
| F1 | Đến giờ uống thuốc | Hạ rồi dừng nhạc, đọc nhắc thuốc; xong hỏi "con mở nhạc tiếp nhé?" (mặc định có) |
| F2 | SOS hoặc dấu hiệu khẩn cấp | Dừng nhạc ngay, ưu tiên cao nhất, **không** tự phát tiếp |
| F3 | Có cuộc gọi, hoặc người dùng nói "gọi cho con" | Dừng nhạc, gọi; gọi xong hỏi phát tiếp |
| F4 | Tin nhắn mới từ người thân | Hạ nhạc, báo "có tin của con gái, bác nghe không", nghe thì dừng nhạc để đọc |
| F5 | Đến giờ đo huyết áp | Dừng nhạc (cần yên tĩnh theo chuẩn đo), hướng dẫn nghỉ 5 phút; **không phát nhạc trong lúc nghỉ/đo**; đo xong hỏi phát tiếp |
| F6 | Người dùng hỏi Vy việc khác ("mấy giờ rồi", "đọc huyết áp") | Hạ tiếng nhạc trong lúc Vy nói, trả lại sau |
| F7 | Người dùng mở màn khác thủ công | Phát nền được thì giữ; không thì dừng và nhớ vị trí |
| F8 | Màn hình tắt, khoá máy, app xuống nền | **Chưa rõ nhạc còn phát không** (WebView + không có dịch vụ nền); cần thử trên máy thật, xem mục 7 |
| F9 | Pin yếu dưới 15% | Báo một lần, giảm sáng, vẫn phát; dưới 5% thì ưu tiên giữ pin cho SOS |

### G. Lỗi kỹ thuật (người dùng không phải biết, không phải làm gì)

| # | Tình huống | Vy làm | Nay |
|---|---|---|---|
| G1 | Video bị chủ kênh cấm nhúng | Tự sang bài kế, nói ngắn "bài này không mở được, con mở bài khác" | ❌ chỉ hiện nút |
| G2 | Tìm không ra gì | Thử cách khác (bỏ dấu, bỏ tên ca sĩ, từ đồng nghĩa), vẫn không thì gợi ý thể loại gần | 🟡 |
| G3 | Mất mạng giữa chừng | Báo một lần "mạng yếu, con thử lại", tự thử 3 lần, vẫn mất thì xin lỗi và giữ vị trí | ❌ |
| G4 | Đang dùng dữ liệu di động, video nặng | Nhạc thì hỏi một lần "bác dùng 4G, con cho chạy chỉ tiếng nhé?" nếu có thể; không thì cảnh báo dung lượng | ❌ |
| G5 | Hết hạn mức YouTube/máy chủ lỗi | Dùng danh mục tuyển chọn sẵn (mục 5.4) và lịch sử, không báo "lỗi" cho người dùng | 🟡 rơi sang quét web |
| G6 | Video bị gỡ, riêng tư, giới hạn tuổi | Bỏ qua, sang bài kế | ❌ |
| G7 | Video quá dài (livestream 10 giờ, 1 giờ không bài) | Lọc khỏi hàng đợi hoặc báo độ dài trước khi mở | ❌ |
| G8 | Quảng cáo chen giữa | Giảm thiểu bằng ưu tiên kênh/bản không quảng cáo (không tắt được hoàn toàn) | ❌ |
| G9 | Mic mở khi nhạc to | Hạ tiếng video khi mic mở (mục H) | ❌ |
| G10 | Phát được nhưng không có tiếng (tắt tiếng máy) | Phát hiện âm lượng hệ thống bằng 0, nói "máy đang tắt tiếng, bác bấm nút to bên hông giúp con" | ❌ |

### H. Giọng nói và nhận dạng khó

| # | Tình huống | Vy làm |
|---|---|---|
| H1 | Nhận dạng sai tên bài ("Nối vòng tay lớn" → "nối vòng tay lên") | Tìm mờ, lấy kết quả khớp nhất và đọc tên đã chọn; sai thì người dùng nói "không phải" |
| H2 | Giọng vùng miền, nói ngọng, nói nhỏ | Câu chưa chắc → hỏi lại một lần bằng câu ngắn "bác nói tên bài lại giúp con" |
| H3 | Tiếng video lọt vào mic và bị coi là lệnh | Hạ tiếng video khi mic mở; bỏ câu độ tin thấp hoặc không có dấu hiệu lệnh; chỉ nhận lệnh điều khiển khi video đang phát nếu rõ ràng |
| H4 | Người dùng nói dài, nhiều ý ("mở nhạc xưa rồi nhỏ tiếng thôi") | Tách thành hai việc, làm theo thứ tự |
| H5 | Nói thừa đệm ("ờ, cái đó, mở giùm tôi") | Gọt đệm, giữ nội dung |
| H6 | Vy nghe tiếng TV/người khác | Chỉ nhận lệnh sau khi nghe tên "Vy" hoặc đang trong phiên hội thoại |
| H7 | Người dùng không nói gì sau câu hỏi | Chọn mặc định đã nêu sau 6 giây |

### I. An toàn nội dung

| # | Tình huống | Vy làm |
|---|---|---|
| I1 | Tìm "chữa huyết áp / tiểu đường / bỏ thuốc" | Nội dung sức khoẻ **chỉ lấy từ kênh y tế đã duyệt** (bệnh viện, bác sĩ có tên, hội chuyên khoa); không phát video khuyên bỏ thuốc, thuốc "thần kỳ" |
| I2 | Dưỡng sinh có động tác mạnh/nguy hiểm | Chỉ phát bài đã duyệt cho người cao tuổi (chủ yếu ngồi, nhẹ) |
| I3 | Tin giả, tin giật gân, cảnh bạo lực | Tin tức chỉ từ nguồn uy tín đã duyệt; bật lọc an toàn nghiêm ngặt |
| I4 | Nội dung 18+, chính trị cực đoan | Chặn, nói "con không mở được cái này, mình nghe cái khác nhé" |
| I5 | Âm lượng đột ngột to (quảng cáo, đoạn kết nhạc) | Giới hạn trần âm lượng ứng dụng, có chuẩn hoá nếu được |
| I6 | Lời khuyên y tế của Vy khi nói chuyện giữa các bài | **Cấm.** Vy chỉ nói tên bài, không bình luận sức khoẻ; giữ quy tắc AHA đã có |
| I7 | Lừa đảo/quảng cáo bán hàng (thực phẩm chức năng...) | Lọc theo kênh và từ khoá; người thân xem được nhật ký |

### J. Kết thúc phiên

| # | Tình huống | Vy làm |
|---|---|---|
| J1 | "Thôi", "tắt đi", "đủ rồi" | Dừng, nói "dạ, con tắt rồi ạ", không hỏi thêm |
| J2 | Hẹn giờ tắt, ngủ quên | Giảm dần âm lượng 30 giây rồi tắt |
| J3 | Không có tín hiệu ai còn nghe (không chạm, không nói, nhiều giờ) | Hỏi "bác còn nghe không ạ"; im lặng thì hạ dần rồi dừng, ghi lại để người thân biết nếu bất thường |
| J4 | Hết hàng đợi | Tìm tiếp cùng chủ đề; không có gì mới thì báo "hết bài rồi, bác muốn nghe tiếp loại khác không" |
| J5 | Người dùng rời app | Tạm dừng và giữ vị trí |

### K. Người thân

| # | Tình huống | Vy làm |
|---|---|---|
| K1 | Người thân đặt "danh sách của mẹ" (bài mẹ thích, kênh tin tuyển chọn) | Vy ưu tiên danh sách này khi gợi ý |
| K2 | Người thân gửi một bài/playlist cho mẹ | Mục D3 |
| K3 | Người thân xem mẹ hay nghe gì, bao lâu | Màn Gia đình có tóm tắt ngắn; **không** ghi âm hay lưu lời nói |
| K4 | Người thân giới hạn thời lượng buổi tối | Hẹn giờ mặc định theo cài đặt của người thân |

### L. Ngoài phạm vi video

| # | Tình huống | Vy làm |
|---|---|---|
| L1 | "Đọc báo cho tôi nghe", "đọc tin" | Có thể là nội dung đọc bằng giọng Vy (quyết định riêng ở mục 6) |
| L2 | "Gọi video cho con" | Nói rõ chưa có, gợi ý gọi thoại hoặc nhắn tin |
| L3 | "Mở nhạc rồi nhắn tin cho con" | Làm lần lượt, nhạc hạ khi nhắn |

## 5. Việc kỹ thuật tương ứng

### 5.1 Hiểu ý định (giải trí)
- Thay luật "từ khoá cứng" bằng bộ hiểu có cấu trúc: `{loại, chủ đề, ca sĩ/nhạc sĩ, tên bài, tâm trạng, thời lượng, nhắc lại ("như hôm qua")}`.
- Luật nhanh miễn phí cho các mẫu phổ biến (≈ 80% câu), LLM chỉ cho câu lạ. Gọt chữ đệm ("của", "đó", "lên").
- Câu mơ hồ → sinh tối đa 3 gợi ý có mặc định từ thói quen + giờ.

### 5.2 Chọn và xếp hàng đợi
- Lọc: không Shorts, độ dài hợp lý theo loại (bài hát 2–10 phút, vở diễn/phim dài được), embeddable, bỏ cover/karaoke trừ khi xin.
- Xếp hạng theo độ khớp tiêu đề/kênh, kênh uy tín, lượt xem, độ dài; loại trùng.
- Hàng đợi 10–20 mục; còn 3 mục thì tìm bổ sung ngầm.
- Làm sạch tên bài trước khi đọc (bỏ emoji, `#`, "Official", "4K"...).

### 5.3 Phiên và bộ nhớ
- Bảng lịch sử/yêu thích/không thích theo người dùng (thêm migration, có cờ tắt và xoá được).
- Lưu vị trí xem dở theo video (cho phim, vở diễn, truyện).

### 5.4 Danh mục tuyển chọn
- Danh sách phát/kênh đã duyệt cho: nhạc xưa, bolero, Trịnh, cải lương, tuồng/chèo, thiền, kinh, dưỡng sinh, tin tức, truyện đêm khuya, nhạc thiếu nhi.
- Dùng làm nguồn đầu tiên cho thể loại chung, và làm nguồn dự phòng khi hết hạn mức tìm kiếm.
- Nội dung sức khoẻ **chỉ** từ đây (mục I1).

### 5.5 Điều khiển và trình phát
- Thêm hành động: tua theo giây, lặp, về đầu, đọc tên bài, thời gian còn lại, hẹn giờ, thoát.
- Đăng ký `VyControl` cho màn phát (nút bài trước/sau, tua, mở bằng YouTube).
- Âm lượng: đọc giá trị thật, báo đúng; trần âm lượng ứng dụng.
- Tự bỏ bài hỏng, báo bằng một câu ngắn.

### 5.6 Âm thanh và nền
- Hạ tiếng video khi mic mở; tạm dừng khi Vy nói dài; trả lại sau. Giai đoạn 0 đã chứng minh hạ tiếng qua API trình phát chạy.
- Ưu tiên âm thanh: SOS > nhắc thuốc > cuộc gọi > nhắc đo > Vy nói > nhạc (đã chốt ở đợt 3 ngày 20/11).
- Kiểm tra phát khi tắt màn hình/ra nền; nếu không được thì cân nhắc dịch vụ nền hoặc giữ màn sáng khi phát.

### 5.7 Hạn mức và chi phí
- Mỗi lệnh chỉ **một** lần tìm (hiện hai: `_playVideo` limit 10 rồi màn Giải trí limit 12, khoá đệm khác nhau).
- Bộ đệm chung trong cơ sở dữ liệu thay vì bộ nhớ từng máy chủ.
- Đo số lần tìm/ngày, cảnh báo trước khi chạm hạn mức.
- Ưu tiên danh mục tuyển chọn để giảm số lần tìm mới.

## 6. Quyết định cần chủ dự án

**Đã duyệt: lấy toàn bộ mặc định đề xuất (24/11/2026).** Q7 và Q8 là mặc định kèm điều kiện: "đọc tin bằng giọng Vy" để sau, "phát khi tắt màn hình" chờ thử máy thật.

| # | Câu hỏi | Đề xuất (đã duyệt) |
|---|---|---|
| Q1 | Vy hỏi tối đa mấy câu trước khi phát? | 1 câu, có mặc định sau 6 giây |
| Q2 | Lưu lịch sử nghe của người dùng (có thể tắt, người thân xem tóm tắt) | Có, theo tài khoản, người dùng xoá được; người thân chỉ xem thể loại và thời lượng |
| Q3 | Nội dung sức khoẻ chỉ từ kênh đã duyệt, ai duyệt danh sách? | Chủ dự án duyệt; có bác sĩ xem lại |
| Q4 | Có làm danh mục tuyển chọn (cần nhập tay ban đầu) | Có, bắt đầu với 8–10 danh sách phát |
| Q5 | Vy có chủ động gợi ý giải trí không | Có nhưng tối đa 1 lần/buổi, tắt được, không chen lúc đang bận |
| Q6 | Hẹn giờ ngủ mặc định (B4) | 30 phút, giảm dần 30 giây |
| Q7 | "Đọc tin" (L1) làm bằng giọng Vy đọc hay chỉ mở video bản tin | Bản đầu mở video bản tin; đọc bằng giọng Vy để sau |
| Q8 | Nhạc khi tắt màn hình có bắt buộc không | Nên có (người cao tuổi hay nghe với màn tắt); cần thử máy thật để biết tốn gì |

## 7. Chưa kiểm chứng

- Khoá và hạn mức YouTube thật; lượng dùng/ngày.
- Phát khi tắt màn hình/ra nền (chưa thấy `wakelock` hay dịch vụ nền trong `pubspec.yaml`, nên khả năng cao là **dừng**).
- Tầng LLM với các câu mơ hồ và tâm trạng.
- Tỷ lệ video chặn nhúng trong nhạc xưa/cải lương thực tế.
- Phản ứng của người cao tuổi với câu hỏi mặc định 6 giây (cần quan sát).
- Mic có nhận lệnh khi nhạc to ở loa máy thật không.

## 8. Phân đợt đề xuất

| Đợt | Nội dung | Kiểm thử |
|---|---|---|
| 1 | Sửa lỗi chắc chắn: một lần tìm/lệnh, nói sai âm lượng, gọt chữ đệm, tự bỏ bài hỏng, làm sạch tên bài, lệnh tua/thoát/hẹn giờ | Bằng chữ, miễn phí |
| 2 | Bộ hiểu ý định mới + lọc/xếp hạng + hàng đợi tự bổ sung | Bằng chữ, 150+ câu trong danh mục trên |
| 3 | Âm thanh: hạ tiếng khi mic mở, chen việc khác (F), phát nền | Máy thật |
| 4 | Bộ nhớ + gợi ý theo thói quen + danh mục tuyển chọn | Bằng chữ + dữ liệu mẫu |
| 5 | Chủ động và người thân (D, K) | Máy thật |
| 6 | Một lần thử giọng thật | Cuối cùng, một lần |

Cập nhật `docs/APP_MAP.md` cho mỗi thay đổi giao diện/điều khiển theo quy ước.

## 9. Tiến độ

**Đợt 1 xong (24/11/2026), chưa thử máy thật, chưa phát hành:**
- Hiểu lệnh: gọt đệm ("của", "đó", "lên", "nhé"); câu chưa cụ thể ("bật nhạc lên", "mở bài đó đi", "xem phim", "bài tôi hay nghe", "nhạc như hôm qua") không còn bị tìm chữ vô nghĩa mà hỏi "bác muốn xem hoặc nghe gì" kèm 3 gợi ý (B1, B9, B11 tạm; hết hẳn khi có lịch sử ở đợt 4).
- Tìm một lần mỗi lệnh (bộ nhớ 20 phút, kết quả rỗng không nhớ).
- Điều khiển mới: tua (E6), phát lại từ đầu (E7), tắt video/thoát (E12), hẹn giờ tắt nhỏ dần (E10, B4 một phần), "bài này của ai" (E8), âm lượng nói tự nhiên (E5).
- Nói thật về âm lượng (E5); tên bài đọc được làm sạch (A1).
- Video bị cấm nhúng tự sang bài kế (G1); màn phát có điều khiển cho Vy.
- Kiểm thử bằng chữ: 213 test máy chủ, thêm 38 mẫu câu mới; Dart: bộ nhớ tìm kiếm, làm sạch tên, điều khiển video (tua, hẹn giờ, âm lượng thật, đọc tên).
- Chưa làm trong đợt 1: "còn bao lâu" (E9), lặp bài (E11), đọc danh sách (E13), hạ tiếng khi Vy nói (đợt 3), lịch sử và gợi ý (đợt 4).

**Đợt 2 xong (24/11/2026), chưa thử máy thật, chưa phát hành:**
- Máy chủ `api/_lib/voice/video_nlu.ts`: 33 chủ đề (nhạc theo thể loại, sân khấu, hài, phim, tin tức, bóng đá, kinh, truyện, đài, thiền, dưỡng sinh, nấu ăn, karaoke) hiểu bằng luật, không gọi LLM; có tên nghệ sĩ đi kèm thì giữ.
- Câu chung chung (A13, B1, B2, B3, B9, B10), tâm trạng (chán, buồn, cô đơn, nhớ nhà), khó ngủ: Vy hỏi đúng **một** câu có gợi ý chạm được, theo hoàn cảnh. "Buồn ngủ", "buồn cười", "đau chân" **không** bị hiểu nhầm là tâm trạng.
- Sửa lỗi cũ: "dừng lại" khi đang phát video là tạm dừng (I14); "nghe lại từ đầu" là phát lại (E7).
- App: `video_rank.dart` lọc/xếp hạng (G7, I-nhóm chất lượng), hàng đợi tự bổ sung (J4, E16 một phần), tự mở số 1 sau 10 giây khi Vy chờ chọn (nguyên tắc 2), "để ngủ" tự hẹn giờ 30 phút (B4).
- Kiểm thử bằng chữ: `api/_tests/video_intent.test.ts` 187 câu/tình huống; máy chủ 431 test, Flutter 510 test đều đạt.
- Chưa làm trong đợt 2: Vy đọc 3 tên bài khi hỏi chọn (cần giọng), nhớ "như hôm qua" (đợt 4), kênh y tế đã duyệt (cần chủ dự án duyệt danh sách), hạ tiếng/nhường việc chen vào (đợt 3).
- Lưu ý: tự mở số 1 sau 10 giây là mặc định theo "6 giây sau khi Vy nói xong"; chưa thử máy thật để chỉnh con số.

**Đợt 3 xong (24/11/2026), chưa thử máy thật, chưa phát hành:**
- Bộ điều phối âm thanh `media_audio.dart`: Vy mở thì video hạ còn 20% (G9, H3, E15 một phần); Vy thường nói liền quá 8 giây thì tạm dừng rồi tự phát tiếp (F6, mục 5.6); người dùng tự dừng thì không tự phát hộ.
- SOS và khẩn cấp: video dừng hẳn, không tự phát lại (F2, H18 trong kịch bản Vy Live).
- Đo huyết áp (F5): đã đúng sẵn vì mở màn đo bằng `router.go` nên màn phát bị đóng; xong đo không tự phát lại (người dùng nói "mở nhạc" lại).
- Kiểm thử: 16 test cho quy tắc, chuyển chế độ, bộ hẹn giờ 8 giây; Flutter 526 test đạt.
**Đợt 4 xong (24/11/2026), chưa thử máy thật, chưa phát hành:**
- Bộ nhớ nghe/xem ở `media_memory.dart` (C1–C8): lịch sử, bài thích/không thích, chỗ xem dở, chủ đề hay nghe theo khung giờ (cần ≥ 2 lượt; cùng khung giờ tính gấp đôi; quá 45 ngày bỏ).
- Vy hiểu "như hôm qua", "bài lúc nãy", "xem tiếp", "bài tôi thích" (B11, C2, C3), đoán chủ đề khi người dùng chỉ nói "mở nhạc" (B1, B9, C1), "bài này hay"/"không thích bài này" (C4, C5).
- Giải trí có thẻ "Xem tiếp"/"Nghe lại"; Cá nhân có công tắc nhớ và nút xoá lịch sử (Q2: tắt được, xoá được).
- Rào nội dung sức khoẻ và ưu tiên nguồn tin tức đáng tin (I1, I2, I3) ở `media_curation.dart`.
- **Lệch so với kế hoạch**: lịch sử lưu **trên máy** (SharedPreferences, theo tài khoản), chưa có bảng trên máy chủ. Lý do: không cần chạy migration, dùng được khi mất mạng, và chưa có quyết định về việc người thân xem. Hệ quả: gỡ app hoặc đổi máy thì mất lịch sử. Đồng bộ và tóm tắt cho người thân (K3) để đợt 5.
- **Danh mục tuyển chọn (5.4) chưa làm đúng nghĩa**: tôi không thể tự xác nhận danh sách phát/kênh YouTube thật, nên chưa nhập. Thay bằng bộ lọc từ khoá và dấu hiệu nguồn. Khi chủ dự án và bác sĩ duyệt danh sách kênh, thêm vào `trustedHealthMarkers` và đổi `healthStrictAllowlist = true`.
- Kiểm thử: `media_memory_test.dart` 32 test; `video_intent.test.ts` thêm 70 câu nhớ/khen/chê/thói quen; máy chủ 471 test.
- Chưa chắc: ngưỡng "≥ 2 lượt mới tính thói quen" và "xem dở ≥ 15 phút" là đoán; chưa thử xem tiếp trên máy thật (`startSeconds` của khung YouTube).

**Đợt 5 xong (24/11/2026), chưa thử máy thật, chưa phát hành:**
- Gợi ý chủ động đúng giờ quen (D1, D2, D4, D5): `media_suggest.dart` + loại nhắc mới `ReminderKind.media` (thấp nhất, sau thuốc, đo huyết áp, tin nhắn; tối đa một lần mỗi buổi; không ban đêm; không giờ yên tĩnh; cách lần nhắc trước ≥ 30 phút). Tắt bằng công tắc ở Cá nhân hoặc nói "đừng gợi ý nữa".
- Người thân gửi video (D3, K2): không cần bảng riêng, là tin nhắn có đường dẫn YouTube. Người thân bấm "Gửi video" trong khung chat; cha/mẹ thấy thẻ video và Vy báo "con gái gửi bác một video… bác xem luôn không ạ?".
- Tóm tắt cho người thân (K3): migration `0036_media_daily.sql`, app gửi thể loại + số giây mỗi phút nghe (không tên bài, chỉ người cao tuổi đang bật "Nhớ những gì tôi đã nghe"), người thân xem ở thẻ trong màn người thân nếu được cấp quyền `vy_history`.
- Kiểm thử: `media_proactive_test.dart` 25 test, thêm 8 câu "đừng gợi ý nữa" bằng chữ; máy chủ 479 test.
- **Phải làm trước khi dùng thật**: chạy `0036_media_daily.sql` trên Supabase. Chưa chạy thì thẻ tóm tắt của người thân trống (lỗi bị nuốt, không ảnh hưởng gì khác).
- **Quyết định tôi đã tự chọn, bạn nên xem lại**: (1) dùng quyền `vy_history` (mặc định TẮT) cho phần tóm tắt, để cha/mẹ chủ động cho phép, thay vì mặc định mở cho người thân đang liên kết; (2) đổi nhãn quyền đó cho khớp; (3) video người thân gửi dùng chung kênh chat nên người nhận thấy cả đường dẫn nếu mở bằng bản app cũ.
- Chưa làm: K1 (danh sách của mẹ), K4 (giới hạn thời lượng buổi tối), tự phát video người thân gửi sau 8 giây im lặng (D3 gốc), nhắc "hỏi phát tiếp" sau việc khẩn.

- **Chưa làm / chưa chắc (đợt 3)**: (a) báo thức thuốc là thông báo hệ điều hành phát tiếng riêng, app chưa hạ nhạc được (F1 chỉ đúng khi nhắc thuốc đi qua Vy); (b) cuộc gọi đi ra ứng dụng gọi của máy, chưa biết WebView có tiếp tục phát nền hay không; (c) **phát khi tắt màn hình (F8, Q8) vẫn cần thử máy thật**; (d) Live không có pha "đang nói" nên chỉ hạ tiếng, không tự tạm dừng khi Vy nói dài; (e) "xong việc khẩn thì hỏi phát tiếp" (F1, F3, F5) chưa có, hiện người dùng tự nói "mở nhạc".
