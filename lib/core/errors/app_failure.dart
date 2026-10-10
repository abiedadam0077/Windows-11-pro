/// Categories of failures that the UI can explain to the user.
enum FailureKind {
  network,
  unauthorized,
  forbidden,
  rateLimited,
  notFound,
  validation,
  conflict,
  server,
  notConfigured,
  unsupported,
  workflowMissing,
  runnerUnavailable,
  runNotFound,
  cancelled,
  timeout,
  storage,
  unknown,
}

/// A typed, user-safe error. `detail` is redacted before it is displayed.
class AppFailure implements Exception {
  const AppFailure(this.kind, {this.detail, this.retryAfter, this.resetAt});

  final FailureKind kind;
  final String? detail;
  final Duration? retryAfter;
  final DateTime? resetAt;

  String get titleKey => 'err_${kind.name}_title';
  String get hintKey => 'err_${kind.name}_hint';

  @override
  String toString() => 'AppFailure(${kind.name})';
}
