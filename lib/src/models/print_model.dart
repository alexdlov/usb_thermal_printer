import 'package:meta/meta.dart';

/// USB Device information
@immutable
class UsbDevice {
  final int vendorId;
  final int productId;
  final String deviceName;
  final String? productName;
  final String? manufacturerName;
  final String? serialNumber;

  const UsbDevice({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
    this.productName,
    this.manufacturerName,
    this.serialNumber,
  });

  /// Create UsbDevice from map data
  factory UsbDevice.fromMap(Map<String, dynamic> map) {
    return UsbDevice(
      vendorId: map['vendorId'] as int,
      productId: map['productId'] as int,
      deviceName: map['deviceName'] as String,
      productName: map['productName'] as String?,
      manufacturerName: map['manufacturerName'] as String?,
      serialNumber: map['serialNumber'] as String?,
    );
  }

  /// Convert UsbDevice to map
  Map<String, dynamic> toMap() {
    return {
      'vendorId': vendorId,
      'productId': productId,
      'deviceName': deviceName,
      'productName': productName,
      'manufacturerName': manufacturerName,
      'serialNumber': serialNumber,
    };
  }

  /// Check if device is a known printer
  bool get isPrinter {
    // Common printer vendor IDs
    const printerVendors = [
      0x04B8, // Epson
      0x0519, // Star Micronics
      0x1504, // Bixolon
      0x0DD4, // Citizen
      0x0FE6, // Zebra
    ];
    return printerVendors.contains(vendorId);
  }

  /// Get display name for the device
  String get displayName => productName ?? 'USB Device ($vendorId:$productId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsbDevice &&
          vendorId == other.vendorId &&
          productId == other.productId &&
          deviceName == other.deviceName;

  @override
  int get hashCode => Object.hash(vendorId, productId, deviceName);

  @override
  String toString() =>
      'UsbDevice(vendorId: $vendorId, productId: $productId, name: $displayName)';
}

/// Printer connection state
enum PrinterState {
  /// No printer connected
  disconnected,

  /// Connecting to printer
  connecting,

  /// Printer connected and ready
  connected,

  /// Disconnecting from printer
  disconnecting,
  error,
}

/// Printer configuration
@immutable
class PrinterConfig {
  final int baudRate;
  final int dataBits;
  final int stopBits;
  final int timeout;
  final String? encoding;

  const PrinterConfig({
    this.baudRate = 9600,
    this.dataBits = 8,
    this.stopBits = 1,
    this.timeout = 5000,
    this.encoding,
  });

  /// Default configuration for most printers
  static const defaultConfig = PrinterConfig();

  /// Epson printer configuration
  static const epson = PrinterConfig(baudRate: 38400);

  /// Star printer configuration
  static const star = PrinterConfig(baudRate: 9600);

  /// Bixolon printer configuration
  static const bixolon = PrinterConfig(baudRate: 19200);

  Map<String, dynamic> toMap() => {
        'baudRate': baudRate,
        'dataBits': dataBits,
        'stopBits': stopBits,
        'timeout': timeout,
        'encoding': encoding,
      };
}

/// Print operation result
sealed class PrintResult {
  const PrintResult();

  /// Check if print was successful
  bool get isSuccess => this is PrintSuccess;

  /// Check if print failed
  bool get isFailure => this is PrintFailure;
}

/// Successful print result
class PrintSuccess extends PrintResult {
  final int bytesSent;
  final Duration duration;

  const PrintSuccess({
    required this.bytesSent,
    required this.duration,
  });

  @override
  String toString() =>
      'PrintSuccess(bytes: $bytesSent, duration: ${duration.inMilliseconds}ms)';
}

/// Failed print result
class PrintFailure extends PrintResult {
  final String error;
  final String? message;
  final Object? exception;

  const PrintFailure({
    required this.error,
    this.message,
    this.exception,
  });

  @override
  String toString() => 'PrintFailure(error: $error, message: $message)';
}
