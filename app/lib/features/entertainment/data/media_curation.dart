import '../../voice/live/live_hybrid.dart' show foldVi;

/// Danh mục tuyển chọn và rào chắn nội dung (kế hoạch docs/KE_HOACH_VY_GIAI_TRI.md mục 5.4, mục I).
/// Mọi chuỗi so sánh đã bỏ dấu, chữ thường.
///
/// QUAN TRỌNG: danh sách "nguồn tin cậy" dưới đây chỉ là dấu hiệu chung (bệnh viện, bác sĩ, viện, đài truyền hình),
/// KHÔNG phải danh sách kênh đã được chủ dự án và bác sĩ duyệt. Khi họ duyệt xong, thêm tên kênh vào
/// [trustedHealthMarkers] rồi đổi [healthStrictAllowlist] thành true: lúc đó nội dung sức khoẻ chỉ lấy từ nguồn tin cậy.

/// Chủ đề sức khoẻ: sai thông tin ở đây gây hại thật (bỏ thuốc, tập quá sức), nên phải lọc kỹ hơn nhạc hay hài.
const healthTopicWords = [
  'duong sinh', 'the duc', 'bai tap', 'yoga', 'thai cuc', 'khi cong', 'huyet ap', 'tieu duong', 'suc khoe',
  'xuong khop', 'dau lung', 'dot quy', 'tim mach', 'mo mau', 'giam can', 'an uong',
];

/// Lời hứa/khuyên nguy hiểm hay gặp: bỏ video có các cụm này trong tiêu đề (chữa khỏi, bỏ thuốc, mẹo thần kỳ...).
const riskyHealthClaims = [
  'chua khoi', 'khoi hoan toan', 'thuoc tien', 'than ky', 'than duoc', 'bo thuoc', 'ngung thuoc', 'dung uong thuoc',
  'khong can thuoc', 'khong can uong thuoc', 'dac tri', 'bi quyet', 'bi mat', 'bac si khong noi', 'bac si giau',
  'ha huyet ap ngay', 'giam nhanh', 'giam can than toc', 'cam ket', 'bao dam', 'tuyet chieu', 'meo hay',
  'nguoi benh khong biet', 'cuc ky nguy hiem', 'cuu mang', 'song them',
];

/// Dấu hiệu nguồn y tế/đài truyền hình đáng tin (trong tên kênh hoặc tiêu đề). Chưa phải danh sách đã duyệt: xem ghi chú đầu tệp.
const trustedHealthMarkers = [
  'benh vien', 'bv ', 'bac si', ' bs ', 'pgs', 'gs ts', 'ts bs', 'ths bs', 'trung tam y te', 'so y te',
  'bo y te', 'vien tim', 'vien lao khoa', 'hoi tim mach', 'phuc hoi chuc nang', 'vat ly tri lieu',
  'vtv', 'vov', 'thvl', 'htv',
];

/// Bật khi chủ dự án và bác sĩ đã duyệt xong danh sách: nội dung sức khoẻ CHỈ lấy từ nguồn tin cậy.
const healthStrictAllowlist = false;

/// Nguồn tin tức đáng tin: được cộng điểm (không loại ai), để "mở tin tức" ưu tiên bản tin thật thay vì video giật gân.
const trustedNewsMarkers = [
  'vtv', 'vov', 'thvl', 'htv', 'vnexpress', 'tuoi tre', 'thanh nien', 'dan tri', 'vietnamnet', 'nhan dan',
  'quan doi', 'cong an',
];

bool isHealthQuery(String query) {
  final f = ' ${foldVi(query)} ';
  return healthTopicWords.any((w) => f.contains(' $w '));
}

bool isNewsQuery(String query) {
  final f = ' ${foldVi(query)} ';
  return f.contains(' tin tuc ') || f.contains(' thoi su ') || f.contains(' ban tin ');
}

bool hasRiskyHealthClaim(String title) {
  final f = ' ${foldVi(title)} ';
  return riskyHealthClaims.any((w) => f.contains(' $w ') || (w.length > 4 && f.contains(w)));
}

bool isTrustedHealthSource(String title, String author) {
  final f = ' ${foldVi(title)} | ${foldVi(author)} ';
  return trustedHealthMarkers.any(f.contains);
}

bool isTrustedNewsSource(String author) {
  final f = ' ${foldVi(author)} ';
  return trustedNewsMarkers.any(f.contains);
}
