import 'dart:ui';

/// Trạng thái làm việc của Vy (khớp VyPhase): quyết định hình dáng và nhịp chuyển động.
enum OrbMode { idle, listening, thinking, speaking }

/// Cảm xúc của Vy: quyết định màu và biểu cảm đôi mắt. Chỉ tác động khi Vy đã thức.
enum BlobMood {
  calm, // bình thường: xanh Vy
  happy, // vui, gửi xong: vàng ấm
  excited, // hào hứng, tin vui: hồng
  curious, // tò mò, hỏi lại, nghe gần giống: xanh ngọc
  worried, // lo, không hiểu, lỗi nhẹ: tím chàm
  sad, // buồn, xin lỗi: xanh xám
  alert, // cảnh báo thuốc, huyết áp: cam
  emergency, // SOS: đỏ
}

/// Bảng màu của thân: ba tầng gradient trên-giữa-dưới và màu nhấn (bóng, vòng sáng).
class BlobPalette {
  const BlobPalette(this.top, this.mid, this.low, this.accent);

  final Color top;
  final Color mid;
  final Color low;
  final Color accent;

  static BlobPalette lerp(BlobPalette a, BlobPalette b, double t) => BlobPalette(
    Color.lerp(a.top, b.top, t)!,
    Color.lerp(a.mid, b.mid, t)!,
    Color.lerp(a.low, b.low, t)!,
    Color.lerp(a.accent, b.accent, t)!,
  );

  /// Chưa đánh thức: xám, khói trôi chậm.
  static const sleeping = BlobPalette(Color(0xFF8D94A3), Color(0xFFB4BAC6), Color(0xFFE3E6EC), Color(0xFF9AA1AF));

  static BlobPalette of(BlobMood m) => switch (m) {
    BlobMood.calm => const BlobPalette(Color(0xFF7F93FF), Color(0xFF9DB6FF), Color(0xFFDDE8FF), Color(0xFF6F86FF)),
    BlobMood.happy => const BlobPalette(Color(0xFFFFB454), Color(0xFFFFCE86), Color(0xFFFFEFD0), Color(0xFFFFA630)),
    BlobMood.excited => const BlobPalette(Color(0xFFFF7FB6), Color(0xFFFFA5CC), Color(0xFFFFE0EE), Color(0xFFFF5FA2)),
    BlobMood.curious => const BlobPalette(Color(0xFF3FC7C0), Color(0xFF7ADAD4), Color(0xFFD5F6F3), Color(0xFF20B2AA)),
    BlobMood.worried => const BlobPalette(Color(0xFF8A74F0), Color(0xFFAB9BF5), Color(0xFFE6E0FC), Color(0xFF7459E8)),
    BlobMood.sad => const BlobPalette(Color(0xFF6E86B5), Color(0xFF93A8CC), Color(0xFFDCE4F2), Color(0xFF5E78AB)),
    BlobMood.alert => const BlobPalette(Color(0xFFFF9248), Color(0xFFFFB27E), Color(0xFFFFE6D3), Color(0xFFFF7A1F)),
    BlobMood.emergency => const BlobPalette(Color(0xFFF0505C), Color(0xFFF58690), Color(0xFFFFD9DC), Color(0xFFE5303E)),
  };
}
