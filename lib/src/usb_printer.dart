import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as esc;
import 'package:image/image.dart' as img;
import 'package:usb_thermal_printer/usb_thermal_printer.dart';

/// USB Thermal Printer controller
///
/// Example:
/// ```dart
/// final printer = UsbPrinter();
/// await printer.init();
///
/// // Find and connect to printer
/// final devices = await printer.getDevices();
/// await printer.connect(devices.first);
///
/// // Print receipt
/// await printer.printReceipt((receipt) {
///   receipt
///     .text('My Store', styles: PosStyles(bold: true, align: PosAlign.center))
///     .feed(1)
///     .text('Thank you for your purchase!')
///     .cut();
/// });
/// ```
class UsbPrinter {
  static final _instance = UsbPrinter._internal();

  /// Get singleton instance
  factory UsbPrinter() => _instance;

  UsbPrinter._internal();

  final _platform = UsbPrinterPlatform.instance;
  late final esc.Generator _generator;

  // Reactive streams
  final _devicesSubject = BehaviorSubject<List<UsbDevice>>.seeded([]);
  final _stateSubject =
      BehaviorSubject<PrinterState>.seeded(PrinterState.disconnected);
  final _currentDeviceSubject = BehaviorSubject<UsbDevice?>.seeded(null);
  final _errorsSubject = PublishSubject<PrinterError>();

  /// Stream of available USB devices
  Stream<List<UsbDevice>> get devices$ => _devicesSubject.stream;

  /// Stream of printer connection state
  Stream<PrinterState> get state$ => _stateSubject.stream;

  /// Stream of currently connected device
  Stream<UsbDevice?> get currentDevice$ => _currentDeviceSubject.stream;

  /// Stream of printer errors
  Stream<PrinterError> get errors$ => _errorsSubject.stream;

  /// Current list of devices
  List<UsbDevice> get devices => _devicesSubject.value;

  /// Current printer state
  PrinterState get state => _stateSubject.value;

  /// Currently connected device
  UsbDevice? get currentDevice => _currentDeviceSubject.value;

  /// Check if printer is connected
  bool get isConnected => state == PrinterState.connected;

  /// Check if printer is ready to print
  bool get isReady => isConnected;

  PrinterConfig _config = PrinterConfig.defaultConfig;

  /// Initialize the printer service
  ///
  /// Must be called before using any printer functionality.
  ///
  /// [paperSize] - Paper size (default: 80mm)
  /// [profile] - Capability profile name (default: "default")
  /// [config] - Printer configuration
  Future<void> init({
    esc.PaperSize paperSize = esc.PaperSize.mm80,
    String profile = 'default',
    PrinterConfig? config,
  }) async {
    try {
      // Load capability profile
      final capabilityProfile = await esc.CapabilityProfile.load(name: profile);
      _generator = esc.Generator(paperSize, capabilityProfile);

      if (config != null) {
        _config = config;
      }

      // Setup platform event streams
      _platform.stateStream.listen((state) {
        _stateSubject.add(state);

        if (state == PrinterState.disconnected) {
          _currentDeviceSubject.add(null);
        }
      });

      _platform.errorStream.listen((error) {
        _errorsSubject.add(error);
      });

      // Initial device scan
      await scanDevices();
    } catch (e) {
      _errorsSubject.add(PrinterError(
        code: ErrorCode.initializationFailed,
        message: 'Failed to initialize printer: $e',
      ));
      rethrow;
    }
  }

  /// Scan for available USB devices
  Future<List<UsbDevice>> scanDevices() async {
    try {
      final devices = await _platform.getDevices();
      _devicesSubject.add(devices);
      return devices;
    } catch (e) {
      _errorsSubject.add(PrinterError(
        code: ErrorCode.scanFailed,
        message: 'Failed to scan devices: $e',
      ));
      return [];
    }
  }

  /// Connect to a USB device
  ///
  /// Will automatically request permission if needed.
  Future<bool> connect(UsbDevice device, {PrinterConfig? config}) async {
    if (isConnected) {
      await disconnect();
    }

    _stateSubject.add(PrinterState.connecting);

    try {
      // Check and request permission
      if (!await _platform.hasPermission(device)) {
        final granted = await _platform.requestPermission(device);
        if (!granted) {
          throw PrinterException(
              'Permission denied for device ${device.productName}');
        }
      }

      // Connect with config
      final connected = await _platform.connect(
        device,
        config ?? _config,
      );

      if (connected) {
        _currentDeviceSubject.add(device);
        _stateSubject.add(PrinterState.connected);

        // Initialize printer on connection
        await _initializePrinter();
      } else {
        _stateSubject.add(PrinterState.disconnected);
      }

      return connected;
    } catch (e) {
      _stateSubject.add(PrinterState.disconnected);
      _errorsSubject.add(PrinterError(
        code: ErrorCode.connectionFailed,
        message: 'Failed to connect: $e',
      ));
      rethrow;
    }
  }

  /// Disconnect from current printer
  Future<void> disconnect() async {
    if (!isConnected) return;

    _stateSubject.add(PrinterState.disconnecting);

    try {
      await _platform.disconnect();
      _currentDeviceSubject.add(null);
      _stateSubject.add(PrinterState.disconnected);
    } catch (e) {
      _errorsSubject.add(PrinterError(
        code: ErrorCode.disconnectionFailed,
        message: 'Failed to disconnect: $e',
      ));
    }
  }

  /// Print raw bytes
  Future<PrintResult> printBytes(List<int> bytes) async {
    if (!isConnected) {
      throw PrinterException('Printer not connected');
    }

    try {
      final result = await _platform.print(bytes);
      return result;
    } catch (e) {
      _errorsSubject.add(PrinterError(
        code: ErrorCode.printFailed,
        message: 'Print failed: $e',
      ));
      rethrow;
    }
  }

  /// Print text with optional styling
  Future<PrintResult> printText(
    String text, {
    esc.PosStyles? styles,
    int linesAfter = 0,
  }) async {
    final bytes = _generator.text(text, styles: styles ?? esc.PosStyles());
    if (linesAfter > 0) {
      bytes.addAll(_generator.feed(linesAfter));
    }
    return printBytes(bytes);
  }

  /// Print a receipt using builder pattern
  ///
  /// Example:
  /// ```dart
  /// await printer.printReceipt((receipt) {
  ///   receipt
  ///     .title('RECEIPT')
  ///     .text('Date: ${DateTime.now()}')
  ///     .divider()
  ///     .row(['Item', 'Price'])
  ///     .row(['Coffee', '\$3.50'])
  ///     .divider()
  ///     .total('Total:', '\$3.50')
  ///     .feed(2)
  ///     .cut();
  /// });
  /// ```
  Future<PrintResult> printReceipt(
    void Function(ReceiptBuilder) builder,
  ) async {
    final receipt = ReceiptBuilder(_generator);
    builder(receipt);
    return printBytes(receipt.build());
  }

  /// Print an image
  Future<PrintResult> printImage(
    Uint8List imageBytes, {
    esc.PosAlign align = esc.PosAlign.center,
  }) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        throw PrinterException('Failed to decode image');
      }

      final bytes = _generator.image(image, align: align);
      return printBytes(bytes);
    } catch (e) {
      _errorsSubject.add(PrinterError(
        code: ErrorCode.printFailed,
        message: 'Failed to print image: $e',
      ));
      rethrow;
    }
  }

  /// Print QR code
  Future<PrintResult> printQRCode(
    String data, {
    esc.PosAlign align = esc.PosAlign.center,
    QRSize size = QRSize.medium,
  }) async {
    final qrSize = switch (size) {
      QRSize.small => esc.QRSize.size4,
      QRSize.medium => esc.QRSize.size6,
      QRSize.large => esc.QRSize.size8,
    };

    final bytes = _generator.qrcode(
      data,
      align: align,
      size: qrSize,
    );
    return printBytes(bytes);
  }

  /// Print barcode
  Future<PrintResult> printBarcode(
    String data, {
    BarcodeType type = BarcodeType.code128,
    esc.PosAlign align = esc.PosAlign.center,
    BarcodeText textPos = BarcodeText.below,
  }) async {
    final bytes = _generator.barcode(
      esc.Barcode.code128(data.codeUnits),
      align: align,
    );
    return printBytes(bytes);
  }

  /// Feed paper
  Future<PrintResult> feed(int lines) async {
    return printBytes(_generator.feed(lines));
  }

  /// Cut paper
  Future<PrintResult> cut({bool partial = false}) async {
    return printBytes(_generator.cut(
        mode: partial ? esc.PosCutMode.partial : esc.PosCutMode.full));
  }

  /// Open cash drawer
  Future<PrintResult> openDrawer() async {
    return printBytes(_generator.drawer());
  }

  /// Print test page
  Future<PrintResult> printTestPage() async {
    return printReceipt((r) {
      r
          .title('PRINTER TEST PAGE')
          .feed(1)
          .text('Connection: OK ✓', styles: PosStyles(bold: true))
          .text('Device: ${currentDevice?.productName ?? "Unknown"}')
          .text('Date: ${DateTime.now()}')
          .divider()
          .text('Text Styles:', styles: PosStyles(underline: true))
          .text('Normal text')
          .text('Bold text', styles: PosStyles(bold: true))
          .text('Underlined', styles: PosStyles(underline: true))
          .text('Size 2x',
              styles: PosStyles(
                  height: PosTextSize.size2, width: PosTextSize.size2))
          .divider()
          .text('Alignments:', styles: PosStyles(underline: true))
          .text('Left aligned', styles: PosStyles(align: PosAlign.left))
          .text('Center aligned', styles: PosStyles(align: PosAlign.center))
          .text('Right aligned', styles: PosStyles(align: PosAlign.right))
          .divider()
          .row(['Column 1', 'Column 2', 'Column 3'])
          .row(['Data 1', 'Data 2', 'Data 3'])
          .divider()
          .qrcode('https://flutter.dev')
          .feed(2)
          .text('Test completed successfully!',
              styles: PosStyles(align: PosAlign.center))
          .feed(3)
          .cut();
    });
  }

  // Private methods
  Future<void> _initializePrinter() async {
    // Send initialization commands
    await printBytes(_generator.reset());
  }

  /// Dispose resources
  void dispose() {
    _devicesSubject.close();
    _stateSubject.close();
    _currentDeviceSubject.close();
    _errorsSubject.close();
  }
}
