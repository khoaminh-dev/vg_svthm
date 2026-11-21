import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ios_components.dart';
import '../core/vy_card.dart';

const _navy = Color(0xFF14213D);
const _muted = Color(0xFF7A8699);

/// Vẽ một thẻ của Vy. Các nút trên thẻ gọi [onAction] (chạm = nói).
class VyCardView extends StatelessWidget {
  const VyCardView({super.key, required this.card, required this.onAction});

  final VyCard card;

  /// Mọi chạm trên thẻ (nút hoặc dòng video) đi qua đây để panel thu về thanh nhỏ sau khi làm việc.
  final ValueChanged<VyCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    final c = card;
    final body = switch (c) {
      BpCard() => _BpBody(card: c),
      MedCard() => _MedBody(card: c),
      SentCard() => _SentBody(card: c),
      MsgCard() => _MsgBody(card: c, onAction: onAction),
      CallCard() => _CallBody(card: c),
      NoticeCard() => _NoticeBody(card: c),
      SosCard() => _SosBody(card: c),
      SendCard() => _SendBody(card: c),
    };
    return Container(
      key: Key('vy-card-${c.runtimeType}'),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          body,
          if (c.actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Actions(actions: c.actions, onAction: onAction),
          ],
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.actions, required this.onAction});

  final List<VyCardAction> actions;
  final ValueChanged<VyCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    void tap(VyCardAction a) {
      HapticFeedback.selectionClick();
      onAction(a);
    }

    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: actions[i].primary
                ? FilledButton(
                    key: Key('vy-card-action-$i'),
                    onPressed: () => tap(actions[i]),
                    child: Text(actions[i].label),
                  )
                : OutlinedButton(
                    key: Key('vy-card-action-$i'),
                    onPressed: () => tap(actions[i]),
                    child: Text(actions[i].label),
                  ),
          ),
        ],
      ],
    );
  }
}

class _BpBody extends StatelessWidget {
  const _BpBody({required this.card});

  final BpCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBadge(label: card.levelLabel, color: card.levelColor),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${card.systolic}/${card.diastolic}',
                  style: const TextStyle(
                    fontSize: 60,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -2,
                    color: _navy,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('mmHg', style: TextStyle(fontSize: 18, color: _muted)),
            ),
            const Spacer(),
            if (card.pulse != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Mạch ${card.pulse}', style: const TextStyle(fontSize: 20, color: _navy)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(card.when, style: const TextStyle(fontSize: 16, color: _muted)),
      ],
    );
  }
}

class _MedBody extends StatelessWidget {
  const _MedBody({required this.card});

  final MedCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(card.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 10),
        for (var i = 0; i < card.rows.length; i++) ...[
          if (i > 0) const Divider(height: 22, thickness: 1, color: Color(0xFFE3E7EF)),
          _MedRowView(row: card.rows[i]),
        ],
      ],
    );
  }
}

class _MedRowView extends StatelessWidget {
  const _MedRowView({required this.row});

  final MedRow row;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              row.time,
              style: TextStyle(
                fontSize: row.highlight ? 30 : 24,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                color: _navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(row.name, style: const TextStyle(fontSize: 18, color: _navy)),
            ),
            StatusBadge(label: row.status, color: row.statusColor),
          ],
        ),
        for (final it in row.items)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(it, style: const TextStyle(fontSize: 17, color: Color(0xFF44516B))),
          ),
      ],
    );
  }
}

class _SentBody extends StatelessWidget {
  const _SentBody({required this.card});

  final SentCard card;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.levelGood.withValues(alpha: 0.16), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: AppColors.levelGood, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đã nhắn cho ${card.to}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _navy)),
              const SizedBox(height: 4),
              Text('“${card.text}”', style: const TextStyle(fontSize: 18, height: 1.3, color: Color(0xFF44516B))),
            ],
          ),
        ),
      ],
    );
  }
}

class _MsgBody extends StatelessWidget {
  const _MsgBody({required this.card, required this.onAction});

  final MsgCard card;
  final ValueChanged<VyCardAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tin nhắn gần đây', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 8),
        for (var i = 0; i < card.rows.length; i++) ...[
          if (i > 0) const Divider(height: 18, thickness: 1, color: Color(0xFFE3E7EF)),
          InkWell(
            key: Key('vy-msg-$i'),
            borderRadius: BorderRadius.circular(14),
            onTap: card.rows[i].onOpen == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onAction(VyCardAction(label: card.rows[i].from, run: card.rows[i].onOpen!));
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(card.rows[i].from, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _navy)),
                      ),
                      Text(card.rows[i].time, style: const TextStyle(fontSize: 15, color: _muted)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(card.rows[i].text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, height: 1.3, color: Color(0xFF44516B))),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Đếm ngược dùng chung (gọi điện, SOS): hết giờ thì chạy [onDone] đúng MỘT lần. Gỡ widget thì huỷ bộ đếm (không chạy).
class _Countdown extends StatefulWidget {
  const _Countdown({required this.seconds, required this.onDone, required this.builder});

  final int seconds;
  final VoidCallback onDone;
  final Widget Function(BuildContext context, int left, bool done) builder;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late int _left = widget.seconds;
  Timer? _t;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        setState(() {
          _left = 0;
          _done = true;
        });
        widget.onDone();
      } else {
        setState(() => _left--);
      }
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _left, _done);
}

class _Ring extends StatelessWidget {
  const _Ring({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 84,
    height: 84,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}

class _CallBody extends StatelessWidget {
  const _CallBody({required this.card});

  final CallCard card;

  @override
  Widget build(BuildContext context) {
    return _Countdown(
      seconds: card.seconds,
      onDone: card.onCall,
      builder: (context, left, done) => Row(
        key: const Key('vy-call'),
        children: [
          _Ring(
            color: _navy,
            child: done
                ? const Icon(Icons.call, color: Colors.white, size: 38)
                : Text('$left', key: const Key('vy-call-count'), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w600, height: 1)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Đang gọi…' : 'Sắp gọi', style: const TextStyle(fontSize: 16, color: _muted)),
                Text(card.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: _navy)),
                Text(card.number, style: const TextStyle(fontSize: 20, color: Color(0xFF44516B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SendBody extends StatelessWidget {
  const _SendBody({required this.card});

  final SendCard card;

  @override
  Widget build(BuildContext context) {
    return _Countdown(
      seconds: card.seconds,
      onDone: card.onSend,
      builder: (context, left, done) => Column(
        key: const Key('vy-send'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Ring(
                color: _navy,
                child: done
                    ? const Icon(Icons.send_rounded, color: Colors.white, size: 36)
                    : Text('$left', key: const Key('vy-send-count'), style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w600, height: 1)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(done ? 'Đang gửi cho' : 'Sắp gửi cho', style: const TextStyle(fontSize: 17, color: _muted)),
                    Text(
                      card.name,
                      key: const Key('vy-send-name'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 32, height: 1.1, fontWeight: FontWeight.w800, color: _navy),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (card.fuzzy) ...[
            const SizedBox(height: 10),
            Container(
              key: const Key('vy-send-fuzzy'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFFFFF3D6), borderRadius: BorderRadius.circular(14)),
              child: const Text('Vy nghe tên này gần giống. Bấm Huỷ nếu sai người.', style: TextStyle(fontSize: 17, color: Color(0xFF7A5200))),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Text(card.text, key: const Key('vy-send-text'), style: const TextStyle(fontSize: 22, height: 1.3, color: _navy)),
          ),
        ],
      ),
    );
  }
}

class _SosBody extends StatelessWidget {
  const _SosBody({required this.card});

  final SosCard card;

  @override
  Widget build(BuildContext context) {
    const red = Color(0xFFC94A4A);
    return _Countdown(
      seconds: card.seconds,
      onDone: card.onFire,
      builder: (context, left, done) => Row(
        key: const Key('vy-sos'),
        children: [
          _Ring(
            color: red,
            child: done
                ? const Icon(Icons.sos_rounded, color: Colors.white, size: 44)
                : Text('$left', key: const Key('vy-sos-count'), style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w600, height: 1)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(done ? 'Đã báo SOS' : 'Sắp báo SOS cho người thân', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _navy)),
                const SizedBox(height: 2),
                Text(done ? 'Người thân đã nhận được tin' : 'Bấm Huỷ nếu bấm nhầm', style: const TextStyle(fontSize: 17, color: Color(0xFF44516B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeBody extends StatelessWidget {
  const _NoticeBody({required this.card});

  final NoticeCard card;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('vy-notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(card.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _navy)),
        const SizedBox(height: 6),
        Text(card.body, style: const TextStyle(fontSize: 19, height: 1.35, color: Color(0xFF44516B))),
      ],
    );
  }
}
