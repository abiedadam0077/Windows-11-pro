/// Semantic-version helpers for update checks. Pure Dart, no I/O.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// Parses `1.2.3`, `v1.2.3`, or `1.2` (missing parts are zero).
  /// Returns null for anything else, including pre-release suffixes.
  static AppVersion? tryParse(String raw) {
    final text = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final match = RegExp(r'^(\d{1,4})(?:\.(\d{1,4}))?(?:\.(\d{1,4}))?$').firstMatch(text);
    if (match == null) return null;
    int part(int i) => int.tryParse(match.group(i) ?? '0') ?? 0;
    return AppVersion(part(1), part(2), part(3));
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
