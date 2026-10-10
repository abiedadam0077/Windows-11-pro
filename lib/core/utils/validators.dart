import 'dart:math';

abstract final class Validators {
  static final RegExp _windowsUser = RegExp(r'^[A-Za-z][A-Za-z0-9_-]{2,19}$');
  static final RegExp _ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
  static final RegExp repoName = RegExp(r'^[A-Za-z0-9._-]{1,100}$');
  static final RegExp workflowPath = RegExp(r'^\.github/workflows/[A-Za-z0-9._-]+\.ya?ml$');
  static const _reservedUsers = {
    'administrator', 'guest', 'defaultaccount', 'wdagutilityaccount', 'system', 'admin',
  };

  /// GitHub OAuth App Client IDs look like `Ov23li...` (or `Iv1.<16 hex>` for
  /// GitHub Apps, or 20 hex characters for legacy apps). A client *secret* is
  /// 40 hex characters and is rejected explicitly so users cannot paste it.
  static final RegExp _clientId = RegExp(r'^(Ov[A-Za-z0-9]{14,}|Iv1\.[0-9a-f]{16}|[0-9a-f]{20})$');
  static final RegExp _clientSecretLike = RegExp(r'^[0-9a-f]{40}$');

  static bool isLikelyClientSecret(String value) => _clientSecretLike.hasMatch(value.trim());

  static bool isValidClientId(String value) {
    final v = value.trim();
    if (isLikelyClientSecret(v)) return false;
    return _clientId.hasMatch(v);
  }

  static bool isValidWindowsUsername(String value) =>
      _windowsUser.hasMatch(value) && !_reservedUsers.contains(value.toLowerCase());

  static bool isValidIpv4(String ip) {
    final m = _ipv4.firstMatch(ip.trim());
    if (m == null) return false;
    return List.generate(4, (i) => int.parse(m.group(i + 1)!)).every((n) => n >= 0 && n <= 255);
  }

  /// Tailscale allocates addresses from 100.64.0.0/10.
  static bool isTailscaleIpv4(String ip) {
    if (!isValidIpv4(ip)) return false;
    final parts = ip.trim().split('.').map(int.parse).toList();
    return parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127;
  }

  static bool isValidWorkflowPath(String value) => workflowPath.hasMatch(value.trim());
}

abstract final class PasswordPolicy {
  static const minLength = 12;

  /// Returns localization keys for every rule the password violates.
  static List<String> violations(String password, {String? username}) {
    final out = <String>[];
    if (password.length < minLength) out.add('pw_rule_length');
    if (!RegExp(r'[A-Z]').hasMatch(password)) out.add('pw_rule_upper');
    if (!RegExp(r'[a-z]').hasMatch(password)) out.add('pw_rule_lower');
    if (!RegExp(r'[0-9]').hasMatch(password)) out.add('pw_rule_digit');
    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) out.add('pw_rule_symbol');
    if (username != null &&
        username.isNotEmpty &&
        password.toLowerCase().contains(username.toLowerCase())) {
      out.add('pw_rule_username');
    }
    return out;
  }

  /// Generates a password locally with a cryptographically secure RNG.
  /// The result is shown once to the user and never persisted by the app.
  static String generate({int length = 24, Random? random}) {
    final rnd = random ?? Random.secure();
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const symbols = '!@#%^*-_=+?';
    const all = '$upper$lower$digits$symbols';
    String pick(String set) => set[rnd.nextInt(set.length)];
    final chars = <String>[pick(upper), pick(lower), pick(digits), pick(symbols)];
    while (chars.length < length) {
      chars.add(pick(all));
    }
    chars.shuffle(rnd);
    return chars.join();
  }
}
