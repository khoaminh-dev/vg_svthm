/// Một gói đang bán (do admin đặt trên trang quản trị).
class PlanOption {
  const PlanOption({required this.id, required this.name, required this.priceVnd, required this.days, this.note = ''});

  final String id;
  final String name;
  final int priceVnd;
  final int days;
  final String note;

  factory PlanOption.fromJson(Map<String, dynamic> m) => PlanOption(
    id: m['id'] as String,
    name: m['name'] as String,
    priceVnd: (m['price_vnd'] as num).toInt(),
    days: (m['days'] as num).toInt(),
    note: (m['note'] as String?) ?? '',
  );
}

enum PlanStatus { pending, active, expired, cancelled }

/// Đơn mua gói của chính mình.
class PlanOrder {
  const PlanOrder({
    required this.code,
    required this.planName,
    required this.priceVnd,
    required this.days,
    required this.status,
    this.expiresAt,
    this.createdAt,
  });

  final String code;
  final String planName;
  final int priceVnd;
  final int days;
  final PlanStatus status;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// Đang hiệu lực: đã xác nhận thanh toán và chưa hết hạn.
  bool isLiveAt(DateTime now) => status == PlanStatus.active && expiresAt != null && expiresAt!.isAfter(now);

  bool get isPending => status == PlanStatus.pending;

  factory PlanOrder.fromJson(Map<String, dynamic> m) => PlanOrder(
    code: m['order_code'] as String,
    planName: (m['plan_name'] as String?) ?? '',
    priceVnd: (m['price_vnd'] as num).toInt(),
    days: (m['days'] as num).toInt(),
    status: switch (m['status']) {
      'active' => PlanStatus.active,
      'expired' => PlanStatus.expired,
      'cancelled' => PlanStatus.cancelled,
      _ => PlanStatus.pending,
    },
    expiresAt: m['expires_at'] == null ? null : DateTime.tryParse(m['expires_at'] as String)?.toLocal(),
    createdAt: m['created_at'] == null ? null : DateTime.tryParse(m['created_at'] as String)?.toLocal(),
  );
}

/// Toàn cảnh gói của mình: các gói đang bán, hướng dẫn thanh toán, đơn mới nhất, và có được dùng Vy Live không.
class PlanOverview {
  const PlanOverview({
    this.plans = const [],
    this.payNote = '',
    this.mine,
    this.coveredBy,
    this.live = false,
  });

  final List<PlanOption> plans;
  final String payNote;
  final PlanOrder? mine;

  /// Tên người thân đang trả gói cho mình (khi mình được hưởng chứ không tự mua).
  final String? coveredBy;

  /// Máy chủ xác nhận mình đang được dùng Vy Live (tự mua hoặc người thân mua).
  final bool live;

  factory PlanOverview.fromJson(Map<String, dynamic> m) => PlanOverview(
    plans: [for (final p in (m['plans'] as List? ?? const [])) PlanOption.fromJson(Map<String, dynamic>.from(p as Map))],
    payNote: (m['pay_note'] as String?) ?? '',
    mine: m['mine'] == null ? null : PlanOrder.fromJson(Map<String, dynamic>.from(m['mine'] as Map)),
    coveredBy: m['covered_by'] as String?,
    live: m['live'] == true,
  );
}

/// "99.000đ" từ 99000.
String formatVnd(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${b}đ';
}

String formatDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
