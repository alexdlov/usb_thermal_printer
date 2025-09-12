import 'dart:async';
import 'package:flutter/services.dart';
import 'package:usb_thermal_printer/src/models/print_model.dart';
import 'package:usb_thermal_printer/src/error/printer_error.dart';

/// Platform interface for USB thermal printer
abstract class UsbPrinterPlatform {
  static UsbPrinterPlatform? _instance;

  /// The default instance of [UsbPrinterPlatform] to use
  static UsbPrinterPlatform get instance =>
      _instance ??= MethodChannelUsbPrinter();

  /// Platform-specific implementation may override this with their own instance
  static set instance(UsbPrinterPlatform instance) {
    _instance = instance;
  }

  /// Get available USB devices
  Future<List<UsbDevice>> getDevices();

  /// Check if app has permission for the device
  Future<bool> hasPermission(UsbDevice device);

  /// Request permission for the device
  Future<bool> requestPermission(UsbDevice device);

  /// Connect to a USB device
  Future<bool> connect(UsbDevice device, PrinterConfig config);

  /// Disconnect from current device
  Future<bool> disconnect();

  /// Print data to connected device
  Future<PrintResult> print(List<int> data);

  /// Check if device is connected
  Future<bool> isConnected();

  /// Stream of connection state changes
  Stream<PrinterState> get stateStream;

  /// Stream of errors
  Stream<PrinterError> get errorStream;
}

/// Method channel implementation of [UsbPrinterPlatform]
class MethodChannelUsbPrinter extends UsbPrinterPlatform {
  static const MethodChannel _methodChannel =
      MethodChannel('usb_thermal_printer');
  static const EventChannel _eventChannel =
      EventChannel('usb_thermal_printer/events');

  // Stream controllers
  StreamController<PrinterState>? _stateController;
  StreamController<PrinterError>? _errorController;

  @override
  Future<List<UsbDevice>> getDevices() async {
    try {
      final List<dynamic> devices =
          await _methodChannel.invokeMethod('getDevices');
      return devices
          .map((device) => UsbDevice.fromMap(Map<String, dynamic>.from(device)))
          .toList();
    } catch (e) {
      throw PrinterException('Failed to get devices: $e');
    }
  }

  @override
  Future<bool> hasPermission(UsbDevice device) async {
    try {
      final bool result = await _methodChannel.invokeMethod('hasPermission', {
        'vendorId': device.vendorId,
        'productId': device.productId,
      });
      return result;
    } catch (e) {
      throw PrinterException('Failed to check permission: $e');
    }
  }

  @override
  Future<bool> requestPermission(UsbDevice device) async {
    try {
      final bool result =
          await _methodChannel.invokeMethod('requestPermission', {
        'vendorId': device.vendorId,
        'productId': device.productId,
      });
      return result;
    } catch (e) {
      throw PrinterException('Failed to request permission: $e');
    }
  }

  @override
  Future<bool> connect(UsbDevice device, PrinterConfig config) async {
    try {
      final bool result = await _methodChannel.invokeMethod('connect', {
        'vendorId': device.vendorId,
        'productId': device.productId,
        'config': config.toMap(),
      });
      return result;
    } catch (e) {
      throw PrinterException('Failed to connect: $e');
    }
  }

  @override
  Future<bool> disconnect() async {
    try {
      final bool result = await _methodChannel.invokeMethod('disconnect');
      return result;
    } catch (e) {
      throw PrinterException('Failed to disconnect: $e');
    }
  }

  @override
  Future<PrintResult> print(List<int> data) async {
    try {
      final bool result = await _methodChannel.invokeMethod('print', {
        'data': data,
      });

      if (result) {
        return PrintSuccess(
          bytesSent: data.length,
          duration: Duration(milliseconds: 100), // Estimate
        );
      } else {
        return PrintFailure(
          error: 'print_failed',
          message: 'Failed to send data to printer',
        );
      }
    } catch (e) {
      return PrintFailure(
        error: 'unknown',
        message: e.toString(),
      );
    }
  }

  @override
  Future<bool> isConnected() async {
    try {
      final bool result = await _methodChannel.invokeMethod('isConnected');
      return result;
    } catch (e) {
      return false;
    }
  }

  @override
  Stream<PrinterState> get stateStream {
    _stateController ??= StreamController<PrinterState>.broadcast(
      onListen: () {
        _eventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            if (event is Map) {
              final connected = event['connected'] as bool?;
              if (connected != null) {
                final state = connected
                    ? PrinterState.connected
                    : PrinterState.disconnected;
                _stateController?.add(state);
              }
            }
          },
          onError: (dynamic error) {
            _errorController?.add(PrinterError(
              code: ErrorCode.unknown,
              message: error.toString(),
            ));
          },
        );
      },
    );
    return _stateController!.stream;
  }

  @override
  Stream<PrinterError> get errorStream {
    _errorController ??= StreamController<PrinterError>.broadcast();
    return _errorController!.stream;
  }

  /// Dispose resources
  void dispose() {
    _stateController?.close();
    _errorController?.close();
    _stateController = null;
    _errorController = null;
  }
}
