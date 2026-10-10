/// Masks credentials that may appear in logs, API messages or error text.
abstract final class SecretRedactor {
  static const _mask = '[REDACTED]';

  static final List<RegExp> _valuePatterns = [
    RegExp(r'gh[pousr]_[A-Za-z0-9]{16,}'),
    RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
    RegExp(r'tskey-[A-Za-z0-9_\-]{8,}'),
    RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+', caseSensitive: false),
    RegExp(r'(x-access-token:)[^@\s]+', caseSensitive: false),
    RegExp(r'(https?://[^\s/:@]+:)[^@\s]+(@)', caseSensitive: false),
  ];

  static final RegExp _keyValue = RegExp(
    r'((?:password|passwd|pwd|secret|token|authkey|auth_key|access_token|client_secret)\s*[=:]\s*)[^\s,;"]+',
    caseSensitive: false,
  );

  static String redact(String input) {
    var out = input;
    for (final pattern in _valuePatterns) {
      out = out.replaceAllMapped(pattern, (m) {
        if (m.groupCount >= 2 && m.group(2) != null) {
          return '${m.group(1)}$_mask${m.group(2)}';
        }
        if (m.groupCount >= 1 && m.group(1) != null) {
          return '${m.group(1)}$_mask';
        }
        return _mask;
      });
    }
    out = out.replaceAllMapped(_keyValue, (m) => '${m.group(1)}$_mask');
    return out;
  }
}
