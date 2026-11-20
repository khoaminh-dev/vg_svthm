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
