/// Base exception for printer errors
class PrinterException implements Exception {
  final String message;
  final Object? cause;

  const PrinterException(this.message, [this.cause]);

  @override
  String toString() =>
      'PrinterException: $message${cause != null ? ' (cause: $cause)' : ''}';
}

/// Printer error with code
class PrinterError {
  final ErrorCode code;
  final String message;
  final Object? exception;

  const PrinterError({
    required this.code,
    required this.message,
    this.exception,
  });

  @override
  String toString() => 'PrinterError($code): $message';
}

/// Error codes
enum ErrorCode {
  initializationFailed,
  scanFailed,
  connectionFailed,
  disconnectionFailed,
  printFailed,
  permissionDenied,
  deviceNotFound,
  timeout,
  unknown,
}
