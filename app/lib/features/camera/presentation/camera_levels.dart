import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/camera_events.dart';

/// Màu theo mức cảnh báo: thông tin xanh nhạt, cần chú ý vàng, khẩn cấp đỏ.
Color levelColor(AlertLevel l) => switch (l) {
  AlertLevel.info => AppColors.sky,
  AlertLevel.watch => AppColors.levelWatch,
  AlertLevel.urgent => AppColors.levelDanger,
};
