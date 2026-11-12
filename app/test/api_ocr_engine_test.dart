import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vg_svthm/core/errors/app_failure.dart';
import 'package:vg_svthm/features/ocr/data/api_ocr_engine.dart';

void main() {
  late Directory dir;
  late String imagePath;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ocr_test');
    imagePath = '${dir.path}/a.jpg';
    File(imagePath).writeAsBytesSync([1, 2, 3]);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ApiOcrEngine engine(
    http.Client client, {
    String? token = 't',
    String base = 'https://api.test',
  }) => ApiOcrEngine(accessToken: () => token, client: client, baseUrl: base);

  test('gửi ảnh kèm token và đọc kết quả', () async {
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(
        jsonEncode({
          'values': [
            {'label': 'SYS', 'value': '118', 'unit': 'mmHg'},
            {'label': 'DIA', 'value': '78', 'unit': 'mmHg'},
          ],
          'raw_text': 'SYS 118',
        }),
        200,
      );
    });

    final scan = await engine(client).scan(imagePath);

    expect(sent.url.toString(), 'https://api.test/api/ocr');
    expect(sent.headers['Authorization'], 'Bearer t');
    expect(jsonDecode(sent.body)['image'], base64Encode([1, 2, 3]));
    expect(scan.values.map((v) => v.value), ['118', '78']);
    expect(scan.values.first.label, 'SYS');
    expect(scan.rawText, 'SYS 118');
  });

  test('báo lỗi dễ hiểu theo mã trạng thái', () async {
    for (final entry in {401: 'hết hạn', 413: 'quá lớn', 429: 'quá nhanh', 503: 'bận'}.entries) {
      final client = MockClient((_) async => http.Response('{}', entry.key));
      expect(
        engine(client).scan(imagePath),
        throwsA(isA<AppFailure>().having((e) => e.message, 'message', contains(entry.value))),
      );
    }
  });

  test('thiếu cấu hình hoặc chưa đăng nhập', () async {
    final client = MockClient((_) async => http.Response('{}', 200));
    expect(engine(client, base: '').scan(imagePath), throwsA(isA<AppFailure>()));
    expect(engine(client, token: null).scan(imagePath), throwsA(isA<AppFailure>()));
  });
}
