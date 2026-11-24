import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/router/routes.dart';
import '../data/shared_video.dart';
import 'entertainment_providers.dart';

/// Mở video người thân gửi. Không đặt chủ đề nên không tự nối thêm video lạ sau khi xem xong.
void openSharedVideo(WidgetRef ref, GoRouter router, SharedVideo v) {
  Analytics.track('video_open', {'from': 'shared'});
  final video = v.toVideo();
  ref.read(videoQueueProvider.notifier).set([video]);
  ref.read(videoTopicProvider.notifier).set('');
  ref.read(playerStartAtProvider.notifier).set(null);
  ref.read(playerStartSleepProvider.notifier).set(null);
  router.push(Routes.player, extra: video);
}
