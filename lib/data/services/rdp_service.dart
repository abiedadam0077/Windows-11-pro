import 'dart:io';

import '../../core/config/app_config.dart';

/// Network-level RDP helpers. Presence of an IP address is NOT treated as proof
/// that RDP works: [probe] attempts a real TCP connection to port 3389.
class RdpService {
  /// Returns true only when a TCP connection to the RDP port succeeds from this
  /// device (i.e. this phone is on the same tailnet and the port is open).
  Future<bool> probe(String ip, {Duration timeout = const Duration(seconds: 5)}) async {
    try {
      final socket = await Socket.connect(ip, AppConfig.rdpPort, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Builds an RDP deep link. Support depends on the installed RDP client.
  Uri? rdpUri(String ip, {String? username}) {
    try {
      final user = username == null ? '' : '&username=s:${Uri.encodeComponent(username)}';
      return Uri.parse('rdp://full%20address=s:$ip:${AppConfig.rdpPort}$user');
    } catch (_) {
      return null;
    }
  }
}
