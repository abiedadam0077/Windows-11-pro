import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/utils/app_version.dart';

/// Update information published with each GitHub Release.
class UpdateInfo {
  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.releaseUrl,
    required this.apkBytes,
  });

  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String sha256;
  final String releaseUrl;
  final int? apkBytes;
}

enum UpdateStatus { upToDate, updateAvailable }

class UpdateCheckResult {
  const UpdateCheckResult(this.status, this.latest);

  final UpdateStatus status;
  final UpdateInfo latest;
}

/// Reads the latest non-prerelease GitHub Release and its `winpilot-update.json`.
///
/// The app never installs anything itself. It shows the version and the APK
/// link; Android then shows its normal install confirmation.
class UpdateService {
  UpdateService({Dio? dio, this.repo = AppConfig.releasesRepo})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;
  final String repo;

  Future<UpdateCheckResult> check({required int installedVersionCode}) async {
    final info = await fetchLatest();
    final status = info.versionCode > installedVersionCode
        ? UpdateStatus.updateAvailable
        : UpdateStatus.upToDate;
    return UpdateCheckResult(status, info);
  }

  Future<UpdateInfo> fetchLatest() async {
    final release = await _getJson('https://api.github.com/repos/$repo/releases/latest');
    final assets = (release['assets'] as List?) ?? const [];
    Map<String, dynamic>? manifestAsset;
    Map<String, dynamic>? apkAsset;
    for (final a in assets.whereType<Map>()) {
      final asset = Map<String, dynamic>.from(a);
      if (asset['name'] == AppConfig.updateManifestAsset) manifestAsset = asset;
      if (asset['name'] == AppConfig.releaseApkAsset) apkAsset = asset;
    }
    if (manifestAsset == null || apkAsset == null) {
      throw const AppFailure(FailureKind.notFound, detail: 'release has no update manifest');
    }
    final manifest = await _getJson(manifestAsset['browser_download_url'].toString());
    return parseManifest(
      manifest,
      apkUrl: apkAsset['browser_download_url'].toString(),
      releaseUrl: release['html_url']?.toString() ?? '',
      apkBytes: (apkAsset['size'] as num?)?.toInt(),
    );
  }

  /// Validates the manifest. Pure, so it is unit tested.
  static UpdateInfo parseManifest(
    Map<String, dynamic> m, {
    required String apkUrl,
    required String releaseUrl,
    int? apkBytes,
  }) {
    final name = m['version']?.toString() ?? '';
    final code = m['versionCode'];
    final sha = m['sha256']?.toString().toLowerCase() ?? '';
    if (AppVersion.tryParse(name) == null) {
      throw const AppFailure(FailureKind.server, detail: 'bad version in manifest');
    }
    final versionCode = code is int ? code : int.tryParse(code?.toString() ?? '');
    if (versionCode == null) {
      throw const AppFailure(FailureKind.server, detail: 'bad versionCode in manifest');
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw const AppFailure(FailureKind.server, detail: 'bad sha256 in manifest');
    }
    if (!apkUrl.startsWith('https://')) {
      throw const AppFailure(FailureKind.server, detail: 'insecure apk url');
    }
    return UpdateInfo(
      versionName: name,
      versionCode: versionCode,
      apkUrl: apkUrl,
      sha256: sha,
      releaseUrl: releaseUrl,
      apkBytes: apkBytes,
    );
  }

  Future<Map<String, dynamic>> _getJson(String url) async {
    final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(
        url,
        options: Options(
          headers: {
            'Accept': 'application/vnd.github+json',
            'User-Agent': AppConfig.userAgent,
            'X-GitHub-Api-Version': AppConfig.githubApiVersion,
          },
          validateStatus: (_) => true,
        ),
      );
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const AppFailure(FailureKind.timeout);
      }
      throw const AppFailure(FailureKind.network);
    }
    final code = res.statusCode ?? 0;
    if (code == 404) throw const AppFailure(FailureKind.notFound);
    if (code == 403 || code == 429) throw const AppFailure(FailureKind.rateLimited);
    if (code < 200 || code >= 300) throw AppFailure(FailureKind.server, detail: 'HTTP $code');
    final raw = res.data;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const AppFailure(FailureKind.server, detail: 'not JSON');
  }
}
