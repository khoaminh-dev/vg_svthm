import os
os.chdir('app')

def sub(p, a, b, imp=None):
    s = open(p, encoding='utf-8').read()
    assert a in s, (p, a[:60])
    s = s.replace(a, b, 1)
    if imp and imp not in s:
        lines = s.split('\n')
        idx = max(i for i, l in enumerate(lines) if l.startswith('import '))
        lines.insert(idx + 1, imp)
        s = '\n'.join(lines)
    open(p, 'w', encoding='utf-8').write(s)

# --- controller ---
p = 'lib/features/ocr/presentation/providers/ocr_controller.dart'
s = open(p, encoding='utf-8').read()
i = s.index('  Future<bool> save(')
j = s.index('  Future<bool> delete(')
new = '''  /// Lưu kết quả OCR; nếu có [reading] thì lưu luôn lần đo huyết áp liên kết với bản ghi đó.
  Future<bool> save(
    OcrDraft draft,
    String title,
    List<OcrValue> values, {
    BpReading? reading,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final record = await ref
          .read(ocrRepositoryProvider)
          .save(
            title: title,
            rawText: draft.rawText,
            values: values,
            localImagePath: draft.imagePath,
          );
      if (reading != null) {
        await ref
            .read(bpRepositoryProvider)
            .add(
              BpReading(
                systolic: reading.systolic,
                diastolic: reading.diastolic,
                pulse: reading.pulse,
                measuredAt: reading.measuredAt,
                source: reading.source,
                ocrRecordId: record.id,
              ),
            );
      }
    });
    if (!state.hasError) {
      ref.invalidate(ocrRecordsProvider);
      ref.invalidate(bpReadingsProvider);
    }
    return !state.hasError;
  }

'''
s = s[:i] + new + s[j:]
s = s.replace("import '../../domain/ocr_models.dart';",
  "import '../../../bp/domain/bp_models.dart';\nimport '../../../bp/presentation/providers/bp_providers.dart';\nimport '../../domain/ocr_models.dart';", 1)
open(p, 'w', encoding='utf-8').write(s)

# --- editor ---
p = 'lib/features/ocr/presentation/screens/ocr_editor_screen.dart'
sub(p, "  late final List<EditableOcrRow> _rows;\n", "  late final List<EditableOcrRow> _rows;\n  bool _saveBp = true;\n")
sub(p, "  Future<void> _save() async {", '''  /// Lần đo huyết áp suy ra từ các dòng đang hiển thị (null nếu không phải kết quả huyết áp).
  BpReading? _currentReading() => BpExtractor.fromValues(
    _rows.where((r) => !r.isEmpty).map((r) => r.toValue()).toList(),
    source: ref.read(ocrUseAiProvider) ? 'ocr_ai' : 'ocr_local',
  );

  Future<void> _save() async {''')
sub(p, '''    final ok = await ref
        .read(ocrControllerProvider.notifier)
        .save(widget.draft, _title.text, values);
    if (!mounted) return;
    if (ok) {''', '''    final reading = _saveBp ? _currentReading() : null;
    final ok = await ref
        .read(ocrControllerProvider.notifier)
        .save(widget.draft, _title.text, values, reading: reading);
    if (!mounted) return;
    if (ok) {
      Analytics.track('ocr_save', {'bp': reading != null, 'rows': values.length});''')
sub(p, '''            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(''', '''            ListenableBuilder(
              listenable: Listenable.merge([
                for (final r in _rows) ...[r.label, r.value],
              ]),
              builder: (context, _) {
                final r = _currentReading();
                if (r == null) return const SizedBox.shrink();
                return Card(
                  child: SwitchListTile(
                    value: _saveBp,
                    onChanged: (v) => setState(() => _saveBp = v),
                    title: const Text('Lưu vào theo dõi huyết áp'),
                    subtitle: Text(
                      '${r.systolic}/${r.diastolic}'
                      '${r.pulse != null ? ' · mạch ${r.pulse}' : ''} mmHg · ${r.category.label}',
                      style: TextStyle(color: r.category.color, fontWeight: FontWeight.w600),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            ExpansionTile(''')
sub(p, "import '../../domain/ocr_models.dart';",
    "import '../../../bp/domain/bp_models.dart';\nimport '../../domain/ocr_models.dart';\nimport '../providers/ocr_providers.dart';")

# --- routes / home ---
sub('lib/core/router/routes.dart', "  static const home = '/';", "  static const bp = '/bp';\n  static const home = '/';")
sub('lib/core/router/app_router.dart', "      GoRoute(path: Routes.ocr, builder:",
    "      GoRoute(path: Routes.bp, builder: (_, _) => const BpScreen()),\n      GoRoute(path: Routes.ocr, builder:",
    "import '../../features/bp/presentation/screens/bp_screen.dart';")
sub('lib/features/home/presentation/home_screen.dart', "                    const FeatureCard(icon: Icons.mic_none",
'''                    FeatureCard(
                      icon: Icons.monitor_heart_outlined,
                      label: 'Huyết áp',
                      onTap: () {
                        Analytics.track('tap_feature', {'feature': 'bp'});
                        context.push(Routes.bp);
                      },
                    ),
                    const FeatureCard(icon: Icons.mic_none''')
print('ok')
