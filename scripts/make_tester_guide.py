# -*- coding: utf-8 -*-
"""Tạo PDF hướng dẫn cho người thử nghiệm app Viegrand.

Chạy:  python scripts/make_tester_guide.py
Kết quả: docs/HUONG_DAN_TESTER.pdf
"""
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "app" / "assets" / "fonts"
OUT = ROOT / "docs" / "HUONG_DAN_TESTER.pdf"

pdfmetrics.registerFont(TTFont("BVP", str(FONTS / "BeVietnamPro-Regular.ttf")))
pdfmetrics.registerFont(TTFont("BVP-B", str(FONTS / "BeVietnamPro-Bold.ttf")))
pdfmetrics.registerFont(TTFont("BVP-SB", str(FONTS / "BeVietnamPro-SemiBold.ttf")))
pdfmetrics.registerFontFamily("BVP", normal="BVP", bold="BVP-B", italic="BVP", boldItalic="BVP-B")

NAVY = colors.HexColor("#0048A8")
DEEP = colors.HexColor("#0B2447")
SKY = colors.HexColor("#E8F3FC")
LINE = colors.HexColor("#C9D6E5")
WARM = colors.HexColor("#E0785F")

body = ParagraphStyle("body", fontName="BVP", fontSize=10.5, leading=16, textColor=DEEP, spaceAfter=4)
small = ParagraphStyle("small", parent=body, fontSize=9, leading=13)
h1 = ParagraphStyle("h1", fontName="BVP-B", fontSize=17, leading=22, textColor=NAVY, spaceBefore=14, spaceAfter=8)
h2 = ParagraphStyle("h2", fontName="BVP-SB", fontSize=12.5, leading=17, textColor=DEEP, spaceBefore=10, spaceAfter=4)
title = ParagraphStyle("title", fontName="BVP-B", fontSize=26, leading=32, textColor=NAVY, alignment=TA_CENTER)
subtitle = ParagraphStyle("subtitle", parent=body, fontSize=12, alignment=TA_CENTER, textColor=DEEP)
cell = ParagraphStyle("cell", parent=body, fontSize=9.5, leading=13, spaceAfter=0)
cellb = ParagraphStyle("cellb", parent=cell, fontName="BVP-SB", textColor=colors.white)
bullet = ParagraphStyle("bullet", parent=body, leftIndent=14, bulletIndent=2, spaceAfter=2)


def P(t, s=body):
    return Paragraph(t, s)


def bullets(items):
    return [Paragraph(t, bullet, bulletText="•") for t in items]


def steps(items):
    return [Paragraph(t, bullet, bulletText=f"{i}.") for i, t in enumerate(items, 1)]


def table(rows, widths, header=True):
    data = []
    for r, row in enumerate(rows):
        st = cellb if (header and r == 0) else cell
        data.append([Paragraph(str(c), st) for c in row])
    t = Table(data, colWidths=[w * mm for w in widths], repeatRows=1 if header else 0)
    style = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.5, LINE),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]
    if header:
        style.append(("BACKGROUND", (0, 0), (-1, 0), NAVY))
        for r in range(1, len(rows)):
            if r % 2 == 0:
                style.append(("BACKGROUND", (0, r), (-1, r), SKY))
    t.setStyle(TableStyle(style))
    return t


def note(text):
    t = Table([[Paragraph(text, cell)]], colWidths=[174 * mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#FFF3EE")),
        ("LINEBEFORE", (0, 0), (0, -1), 3, WARM),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("BVP", 8)
    canvas.setFillColor(colors.HexColor("#6B7A90"))
    canvas.drawString(18 * mm, 10 * mm, "Viegrand - Hướng dẫn thử nghiệm ứng dụng")
    canvas.drawRightString(192 * mm, 10 * mm, f"Trang {doc.page}")
    canvas.restoreState()


s = []

# ---------------------------------------------------------------- Bìa
s += [Spacer(1, 50 * mm), P("Viegrand", title), Spacer(1, 4 * mm),
      P("Hướng dẫn dành cho người thử nghiệm", subtitle), Spacer(1, 3 * mm),
      P("Đợt thử nghiệm: thứ Bảy 14/11, Chủ nhật 15/11 và thứ Hai 16/11/2026", subtitle),
      Spacer(1, 18 * mm)]
s.append(table([
    ["Bạn cần làm", "Tóm tắt"],
    ["Cài app", "Android, tải file cài đặt từ link trong Zalo nhóm."],
    ["5 bài thử", "test1 Đăng nhập, test2 Nhắn tin, test3 Đo huyết áp, test4 Xem lịch sử sức khoẻ, test5 Nói chuyện với Vy."],
    ["Quay màn hình", "Mỗi lần làm bài đều quay lại, đặt tên đúng quy định, tải lên thư mục Drive mang tên MSSV của bạn."],
    ["Người thân", "Cài app cho một người thân trên 30 tuổi, làm lại bài nhắn tin 1 lần và đo huyết áp 3 lần."],
    ["Khảo sát", "Cuối đợt, điền Google Form khoảng 15 câu."],
], [40, 134]))
s.append(PageBreak())

# ---------------------------------------------------------------- 1. Mục đích
s += [P("1. Mục đích và thời gian", h1),
      P("Viegrand là ứng dụng chăm sóc người lớn tuổi bằng tiếng Việt: nhắn tin với người thân, "
        "đo huyết áp bằng cách chụp ảnh máy đo, xem lịch sử sức khoẻ và trò chuyện bằng giọng nói với trợ lý Vy. "
        "Nhóm cần bạn dùng thử như một người dùng thật, quay lại thao tác và báo lỗi để cải thiện app."),
      P("Đợt thử kéo dài 3 ngày: <b>thứ Bảy 14/11, Chủ nhật 15/11 và thứ Hai 16/11/2026</b>. "
        "Mỗi ngày bạn làm theo lịch ở mục 4."),
      P("Bạn sẽ được cung cấp (qua nhóm Zalo): link tải app, link thư mục Drive để nộp video, "
        "kịch bản nội dung nhắn tin (Phụ lục A), bộ ảnh máy đo huyết áp mẫu (nếu có) và link Google Form khảo sát."),
      ]

# ---------------------------------------------------------------- 2. Chuẩn bị
s += [P("2. Chuẩn bị", h1), P("Yêu cầu điện thoại", h2)]
s += bullets([
    "Điện thoại <b>Android</b> đời 7.0 trở lên (hầu hết máy từ 2017). iPhone chưa dùng được.",
    "Có kết nối mạng (Wi-Fi hoặc 4G) và còn ít nhất 300 MB trống.",
    "Bật được tính năng quay màn hình (xem mục 3).",
])
s.append(P("Cài app", h2))
s += steps([
    "Mở link tải app trong Zalo nhóm bằng trình duyệt của điện thoại và tải file <b>.apk</b>.",
    "Mở file vừa tải. Lần đầu máy sẽ hỏi cho phép \"Cài đặt ứng dụng không rõ nguồn\", hãy bật cho trình duyệt (hoặc ứng dụng Tệp) rồi quay lại.",
    "Nếu máy hiện thông báo <b>quét ứng dụng</b> hoặc cảnh báo bảo mật (Google Play Protect): chọn <b>không quét</b> hoặc <b>vẫn cài</b>, cứ cài là được.",
    "Mở app, cho phép khi app xin quyền <b>micro</b> và <b>camera</b>.",
])
s.append(Spacer(1, 3 * mm))
s.append(note("<b>Lưu ý:</b> app có thể hỏi bạn cập nhật khi có bản mới. Xem mục 7 để biết cách kiểm tra phiên bản."))

# ---------------------------------------------------------------- 3. Quay
s += [P("3. Quay màn hình và nộp video", h1), P("Cách quay màn hình trên Android", h2)]
s += bullets([
    "Vuốt từ trên xuống để mở thanh nhanh, chọn <b>Quay màn hình</b> (một số máy gọi là Ghi màn hình hoặc Screen recorder). Nếu chưa thấy, bấm nút bút chì hoặc dấu cộng để thêm vào.",
    "Khi máy hỏi có ghi âm thanh không: bài nào cũng <b>có thể tắt tiếng</b>, riêng bài 5 (Vy) cần tắt thu âm micro của trình quay để không tranh micro với app.",
    "Mỗi video nên ngắn (1 đến 3 phút) và quay <b>liền mạch</b> cả thao tác từ đầu đến khi có kết quả.",
])
s.append(P("Quy tắc mở đầu mỗi video", h2))
s.append(P("Việc đầu tiên trong mọi video: mở tab <b>Hồ sơ</b> để lộ dòng <b>\"Viegrand x.y.z (n)\"</b> (phiên bản app), "
           "sau đó mới làm bài. Nhờ vậy nhóm biết video quay trên bản nào."))
s.append(P("Quy tắc đặt tên", h2))
s.append(table([
    ["Thành phần", "Quy định", "Ví dụ"],
    ["Thư mục Drive", "Mỗi sinh viên một thư mục, tên là <b>mã số sinh viên</b>", "20241234"],
    ["Tên video", "<b>testN_ddmmyy_lần</b>. N là số bài, ddmmyy là ngày quay, \"lần\" là lần thứ mấy trong ngày (1, 2, 3)", "test2_141126_2"],
    ["Video của người thân", "Thêm <b>_nt</b> ở cuối tên", "test3_151126_1_nt"],
    ["Bài làm 1 lần", "Vẫn ghi lần là 1", "test1_141126_1"],
], [38, 96, 40]))
s.append(Spacer(1, 3 * mm))
s.append(P("Nộp video: tải từng video lên đúng thư mục Drive mang tên MSSV của bạn (link thư mục sẽ được gửi sau). "
           "Hãy tải lên ngay sau mỗi lần quay để khỏi dồn lại cuối đợt."))

# ---------------------------------------------------------------- 4. Lịch
s += [P("4. Lịch làm bài trong đợt thử", h1)]
s.append(table([
    ["Bài", "Nội dung", "Số lần", "Quy định giờ giấc"],
    ["test1", "Đăng nhập", "1 lần cả đợt (có thể thêm nếu muốn thử lại)", "Làm ngay sáng thứ Bảy 14/11"],
    ["test2", "Nhắn tin với 3 thành viên", "3 lần mỗi ngày", "Cách nhau <b>4 tiếng</b>. Gợi ý 8h, 12h, 16h"],
    ["test3", "Đo huyết áp bằng ảnh", "3 lần mỗi ngày", "Cách nhau <b>ít nhất 6 tiếng</b>. Gợi ý 7h, 13h, 19h. Ảnh mỗi lần phải khác nhau"],
    ["test4", "Xem lịch sử sức khoẻ", "1 lần mỗi ngày", "Làm sau khi đã có ít nhất 1 lần đo ở test3"],
    ["test5", "Nói chuyện với Vy", "1 lần mỗi ngày", "Giờ tuỳ bạn"],
    ["Người thân", "Cài app cho người trên 30 tuổi; chat 1 lần, đo huyết áp 3 lần", "1 lần cả đợt", "Trong cùng 3 ngày, đo huyết áp cách nhau ít nhất 6 tiếng"],
], [18, 46, 50, 60]))
s.append(Spacer(1, 4 * mm))
s.append(P("Tổng số video tối thiểu của một sinh viên: test1 (1) + 3 ngày x [test2 (3) + test3 (3) + test4 (1) + test5 (1)] = <b>25 video</b>, "
           "cộng thêm video của người thân (khoảng 4 video)."))
s.append(P("Bạn có thể tích vào bảng lịch này để theo dõi:", small))
rows = [["Ngày", "test2 (3 lần)", "test3 (3 lần)", "test4", "test5"]]
for d in ["Thứ 7 14/11", "Chủ nhật 15/11", "Thứ 2 16/11"]:
    rows.append([d, "[ ] 1  [ ] 2  [ ] 3", "[ ] 1  [ ] 2  [ ] 3", "[ ]", "[ ]"])
s.append(table(rows, [34, 44, 44, 26, 26]))

# ---------------------------------------------------------------- 5. Từng bài
s += [P("5. Hướng dẫn từng bài", h1)]

s.append(KeepTogether([P("test1 - Đăng nhập", h2),
    P("Mục tiêu: kiểm tra đăng ký bằng email, xác nhận email, đăng nhập và đăng xuất."),
    *steps([
        "Bật quay màn hình. Ở trang đăng nhập, bấm <b>Đăng ký</b> và nhập tên hiển thị, tên người dùng (chữ thường không dấu), email thật, mật khẩu.",
        "Mở hộp thư của email đó, bấm link <b>xác nhận email</b> (kiểm tra cả mục Thư rác nếu không thấy).",
        "Quay lại app, đăng nhập bằng email vừa đăng ký. Mở tab Hồ sơ cho thấy phiên bản app.",
        "Thử đăng xuất rồi đăng nhập lại. Có thể thử thêm đăng nhập sai mật khẩu để xem thông báo lỗi.",
    ]),
    P("Kết quả mong đợi: đăng ký thành công, nhận được email xác nhận, đăng nhập vào được trang chủ.", small)]))

s.append(KeepTogether([P("test2 - Nhắn tin với 3 thành viên", h2),
    P("Mục tiêu: kiểm tra gửi và nhận tin nhắn, gửi ảnh, trò chuyện với nhiều người."),
    *steps([
        "Bật quay màn hình, mở tab Hồ sơ cho thấy phiên bản, rồi vào <b>Tin nhắn</b>.",
        "Lần đầu: vào phần <b>Cộng đồng</b> (nơi hiển thị mọi người dùng app), kết bạn với <b>3 thành viên bất kỳ</b>, mở trò chuyện với từng người.",
        "Gửi các tin theo kịch bản chuẩn bị sẵn (Phụ lục A) cho từng người, gồm ít nhất 1 tin có ảnh. Chờ và đọc tin trả lời.",
        "Lặp lại đủ <b>3 lần mỗi ngày</b>, cách nhau 4 tiếng, mỗi lần quay một video riêng.",
    ]),
    P("Kết quả mong đợi: tin gửi nhanh, hiện đúng bên người gửi, ảnh xem được. Lưu ý: nội dung nhắn với ai cũng được, quan trọng là có nhắn.", small)]))

s.append(KeepTogether([P("test3 - Đo huyết áp", h2),
    P("Mục tiêu: app tự đọc chỉ số từ ảnh màn hình máy đo huyết áp, lưu và nhận xét."),
    *steps([
        "Bật quay màn hình, mở tab Hồ sơ, rồi vào trang chủ và bấm <b>Đo huyết áp</b>.",
        "Chụp màn hình máy đo huyết áp thật. Nếu <b>không có máy đo</b>, dùng ảnh có sẵn trên mạng hoặc bộ ảnh mẫu của nhóm và chọn ảnh từ thư viện.",
        "Chờ app đọc và lưu. Ghi nhận 3 chỉ số: tâm thu, tâm trương, nhịp tim, cùng lời nhận xét của app.",
        "Đo <b>3 lần mỗi ngày</b>, cách nhau <b>ít nhất 6 tiếng</b>, và <b>ảnh mỗi lần phải khác nhau</b> (chỉ số khác nhau).",
    ]),
    P("Kết quả mong đợi: app đọc đúng các số trong ảnh. Ảnh cần thấy rõ cả 3 chỉ số, không bị mờ hoặc chói. Nếu app đọc sai, ghi lại trong form khảo sát.", small)]))

s.append(KeepTogether([P("test4 - Xem lịch sử sức khoẻ", h2),
    P("Mục tiêu: xem biểu đồ và danh sách các lần đo."),
    *steps([
        "Làm sau khi đã có ít nhất 1 lần đo ở test3. Bật quay màn hình, mở tab Hồ sơ cho thấy phiên bản.",
        "Vào tab <b>Sức khoẻ</b>. Xem chỉ số gần nhất, biểu đồ và danh sách lịch sử, kiểm tra số liệu có khớp các lần đo vừa làm.",
        "Thử kéo xuống để làm mới danh sách. Có thể thử xoá một lần đo (nếu chắc đó là số thử).",
    ]),
    P("Kết quả mong đợi: các lần đo vừa làm đều có trong lịch sử, đúng giờ và đúng chỉ số.", small)]))

s.append(KeepTogether([P("test5 - Nói chuyện với Vy (voice chat)", h2),
    P("Mục tiêu: dùng giọng nói để điều khiển app."),
    *steps([
        "Tắt thu âm micro của trình quay màn hình (xem mục 3), bật quay, mở tab Hồ sơ cho thấy phiên bản.",
        "Ở trang chủ bấm <b>Nói chuyện với Vy</b>, cho phép micro nếu được hỏi. Nói rõ ràng ở nơi yên tĩnh.",
        "Thử khoảng 5 câu, ví dụ: \"Mở tin nhắn\", \"Cho tôi xem huyết áp\", \"Đo huyết áp\", \"Nhắn tin cho [tên] là chiều nay tôi ghé thăm\", \"Mở trang chủ\".",
        "Với lệnh gửi tin, Vy sẽ hỏi xác nhận: bấm <b>Gửi</b>, <b>Sửa</b> hoặc <b>Hủy</b>.",
    ]),
    P("Chưa cần nghe tiếng Vy trả lời, chỉ cần quay màn hình. Ghi nhận Vy hiểu đúng được mấy trong 5 câu và phản hồi nhanh hay chậm.", small)]))

# ---------------------------------------------------------------- 6. Người thân
s += [P("6. Bài của người thân (trên 30 tuổi)", h1)]
s.append(P("Mỗi sinh viên cài app cho <b>một người thân trên 30 tuổi</b> (cha, mẹ, cô, dì, chú, bác...) để xem người lớn tuổi dùng thực tế ra sao."))
s += bullets([
    "Xin phép người thân trước khi quay video và chia sẻ.",
    "Người thân dùng <b>tài khoản riêng</b> (tự đăng ký email riêng), không dùng chung tài khoản của bạn.",
    "Điện thoại cũng phải là Android. Bạn giúp cài app và hướng dẫn lần đầu, sau đó để người thân tự thao tác, bạn chỉ quay.",
    "Làm lại <b>bài nhắn tin 1 lần</b> (test2, nhắn với bất kỳ ai) và <b>bài đo huyết áp 3 lần</b> (test3, cách nhau ít nhất 6 tiếng, ảnh khác nhau).",
    "Tên video thêm <b>_nt</b>, ví dụ test2_141126_1_nt.",
    "Ghi lại nhận xét: chữ có đủ to không, nút có dễ bấm không, chỗ nào người thân lúng túng. Điền vào câu khảo sát cuối.",
])

# ---------------------------------------------------------------- 7. Cập nhật
s += [P("7. Kiểm tra bản cập nhật", h1)]
s.append(P("Trong 3 ngày thử, nhóm có thể phát hành bản sửa lỗi. Hãy <b>thường xuyên kiểm tra</b> bản cập nhật:"))
s += steps([
    "<b>Tắt hẳn app</b>: mở danh sách ứng dụng gần đây (nút vuông hoặc vuốt từ dưới lên giữ lại), vuốt app Viegrand lên để đóng.",
    "Mở lại app. Nếu có bản mới, hộp thoại <b>Có bản cập nhật</b> sẽ hiện, bấm <b>Cập nhật</b>, đợi tải xong rồi bấm xác nhận cài.",
    "Nếu máy hỏi quét hay cảnh báo, chọn không quét hoặc vẫn cài như lúc cài lần đầu.",
    "Kiểm tra lại số phiên bản trong tab <b>Hồ sơ</b>.",
])
s.append(Spacer(1, 3 * mm))
s.append(note("App chỉ kiểm tra bản mới khi <b>mở lại từ đầu</b>, nên chỉ để app chạy nền thì sẽ không thấy hộp thoại. Hãy tắt hẳn rồi mở lại."))

# ---------------------------------------------------------------- 8. Lỗi
s += [P("8. Lỗi đã biết và cách báo lỗi", h1), P("Những điều có thể gặp (không cần báo trùng)", h2)]
s += bullets([
    "Vy đôi khi nghe nhầm một từ (ví dụ \"nhắn\" thành \"nhận\") hoặc hiện câu lạ khi nơi bạn đứng ồn.",
    "Giọng đọc là giọng của điện thoại nên hơi cứng.",
    "Đôi khi Vy trả lời chậm vài giây.",
    "Ảnh trong tin nhắn có thể tải chậm khi mạng yếu.",
])
s.append(P("Khi gặp lỗi", h2))
s += bullets([
    "Báo ngay trong <b>nhóm Zalo</b> chung của đợt thử nghiệm: ghi tên bạn, bài đang làm, bạn thấy gì, kèm ảnh hoặc video nếu có.",
    "Ghi lại lỗi nghiêm trọng nhất trong Google Form cuối đợt.",
    "Nếu app đứng hẳn, thử tắt hẳn rồi mở lại; nếu vẫn lỗi, gỡ và cài lại bản mới nhất.",
])

# ---------------------------------------------------------------- 9. Hạn nộp
s += [P("9. Hạn nộp và liên hệ", h1)]
s.append(table([
    ["Việc", "Hạn nộp"],
    ["Tải video lên thư mục Drive", "[sẽ bổ sung]"],
    ["Điền Google Form khảo sát", "[sẽ bổ sung]"],
    ["Link thư mục Drive gốc", "[sẽ gửi trong nhóm Zalo]"],
    ["Link tải app", "[sẽ gửi trong nhóm Zalo]"],
    ["Liên hệ khi cần hỗ trợ", "Nhóm Zalo của đợt thử nghiệm"],
], [100, 74]))
s.append(PageBreak())

# ---------------------------------------------------------------- Phụ lục A
s += [P("Phụ lục A. Kịch bản nhắn tin (bài test2)", h1),
      P("Mỗi lần chat, gửi khoảng 4 đến 5 tin cho mỗi người trong số 3 thành viên, gồm hỏi thăm, ăn uống, nghỉ ngơi, hẹn giờ và <b>ít nhất 1 ảnh</b> (ví dụ ảnh bữa ăn, bầu trời, cây cối). "
        "Bạn có thể đổi lời cho tự nhiên, miễn cùng chủ đề đời thường.")]
s.append(table([
    ["Lần", "Giờ gợi ý", "Nội dung mẫu"],
    ["Lần 1", "Khoảng 8h",
     "\"Chào buổi sáng, hôm nay bạn khoẻ không?\"<br/>\"Sáng nay bạn ăn gì rồi?\"<br/>\"Nhớ uống đủ nước nhé.\"<br/>[gửi 1 ảnh bữa sáng hoặc bầu trời buổi sáng]"],
    ["Lần 2", "Khoảng 12h",
     "\"Trưa rồi, bạn đã ăn cơm chưa?\"<br/>\"Hôm nay có món gì ngon không?\"<br/>\"Chiều nay bạn có định ra ngoài không?\"<br/>[gửi 1 ảnh bữa trưa]"],
    ["Lần 3", "Khoảng 16h",
     "\"Chiều nay trời đẹp, đi dạo một chút nhé.\"<br/>\"Tối nay bạn muốn ăn gì?\"<br/>\"Nhớ uống thuốc đúng giờ nhé.\"<br/>[gửi 1 ảnh khung cảnh bên ngoài]"],
], [16, 30, 128]))
s.append(Spacer(1, 3 * mm))
s.append(P("Câu trả lời nhanh có sẵn trong ô chat: <b>Dạ</b>, <b>Cảm ơn</b>, <b>Đã ăn cơm rồi</b>, <b>Gọi lại giúp nhé</b>. "
           "Bạn nên dùng thử một vài câu này trong mỗi lần.", small))

# ---------------------------------------------------------------- Phụ lục B
s += [P("Phụ lục B. Chọn ảnh máy đo huyết áp (bài test3)", h1)]
s += bullets([
    "Ảnh phải thấy <b>rõ cả 3 số</b>: tâm thu (SYS), tâm trương (DIA) và nhịp tim (PULSE).",
    "Chụp thẳng, không bị chói sáng hay nghiêng quá nhiều.",
    "Mỗi lần đo dùng một ảnh khác nhau, chỉ số khác nhau. Không dùng lại ảnh cũ.",
    "Có thể chọn ảnh từ thư viện (nút chọn ảnh trong màn đo) hoặc chụp màn hình khác hiển thị ảnh trên mạng.",
    "Chỉ số dùng trong thử nghiệm không phải số liệu sức khoẻ thật của bạn nên đừng lo nếu số hơi cao hoặc thấp.",
])

SimpleDocTemplate(
    str(OUT), pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm, topMargin=16 * mm, bottomMargin=18 * mm,
    title="Viegrand - Hướng dẫn người thử nghiệm", author="Viegrand",
).build(s, onFirstPage=footer, onLaterPages=footer)
print("OK", OUT)
