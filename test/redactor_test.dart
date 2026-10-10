import 'package:flutter_test/flutter_test.dart';
import 'package:winpilot/core/security/redactor.dart';

void main() {
  test('masks key=value style secrets', () {
    final out = SecretRedactor.redact('password=Hunter2!extra and authkey: tskey-abcdefgh12345678');
    expect(out, isNot(contains('Hunter2')));
    expect(out, isNot(contains('tskey-abcdefgh12345678')));
    expect(out, contains('[REDACTED]'));
  });

  test('masks bearer tokens and credentials embedded in URLs', () {
    final out = SecretRedactor.redact(
      'Authorization: Bearer abc.def.ghi and https://user:topsecret@github.com/x',
    );
    expect(out, isNot(contains('abc.def.ghi')));
    expect(out, isNot(contains('topsecret')));
  });

  test('leaves ordinary log lines untouched', () {
    const line = 'Step 3 of 9: installing components';
    expect(SecretRedactor.redact(line), line);
  });
}
