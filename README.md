# USB Thermal Printer

A comprehensive Flutter plugin for USB thermal printers with built-in ESC/POS support.

[![pub package](https://img.shields.io/pub/v/usb_thermal_printer.svg)](https://pub.dev/packages/usb_thermal_printer)
[![platform](https://img.shields.io/badge/platform-android-green.svg)](https://flutter.dev/)

## Features

✅ Easy device discovery and connection  
✅ Built-in ESC/POS command support  
✅ Fluent receipt builder API  
✅ Image printing support  
✅ QR code and barcode generation  
✅ Reactive streams for state management  
✅ Comprehensive error handling  
✅ Support for major printer brands (Epson, Star, Bixolon, etc.)

## Installation

```yaml
dependencies:
  usb_thermal_printer: ^1.0.0
```

## Usage

### Basic Setup

```dart
import 'package:usb_thermal_printer/usb_thermal_printer.dart';

// Initialize printer
final printer = UsbPrinter();
await printer.init();

// Scan for devices
final devices = await printer.scanDevices();

// Connect to a printer
await printer.connect(devices.first);

// Print text
await printer.printText('Hello, World!');
```

### Using Receipt Builder

```dart
await printer.printReceipt((receipt) {
  receipt
    .title('STORE NAME')
    .subtitle('123 Main Street')
    .feed(1)
    .timestamp()
    .divider()
    .item('Coffee', price: 3.50)
    .item('Sandwich', price: 8.00)
    .divider()
    .total('Total:', 11.50)
    .feed(2)
    .qrcode('https://example.com/receipt')
    .cut();
});
```

### Reactive State Management

```dart
// Listen to connection state
printer.state$.listen((state) {
  print('Printer state: $state');
});

// Listen to available devices
printer.devices$.listen((devices) {
  print('Found ${devices.length} devices');
});

// Listen to errors
printer.errors$.listen((error) {
  print('Error: ${error.message}');
});
```

### Advanced Features

#### Custom Styling

```dart
await printer.printText(
  'Important Notice',
  styles: PosStyles(
    bold: true,
    underline: true,
    align: PosAlign.center,
    height: PosTextSize.size2,
  ),
);
```

#### Print Images

```dart
final imageBytes = await rootBundle.load('assets/logo.png');
await printer.printImage(imageBytes.buffer.asUint8List());
```

#### Print Barcodes

```dart
// QR Code
await printer.printQRCode(
  'https://example.com',
  size: QRSize.large,
);

// Barcode
await printer.printBarcode(
  '1234567890',
  type: BarcodeType.ean13,
);
```

#### Table/Columns

```dart
await printer.printReceipt((r) {
  r.row(['Item', 'Qty', 'Price'], widths: [6, 3, 3])
   .row(['Coffee', '2', '\$7.00'], widths: [6, 3, 3])
   .row(['Tea', '1', '\$3.00'], widths: [6, 3, 3]);
});
```

## Printer Configuration

```dart
// Use predefined configs
await printer.connect(device, config: PrinterConfig.epson);

// Or custom config
await printer.connect(device, config: PrinterConfig(
  baudRate: 38400,
  timeout: 10000,
));
```

## Error Handling

```dart
try {
  await printer.connect(device);
} on PrinterException catch (e) {
  print('Printer error: $e');
}

// Or use result pattern
final result = await printer.printText('Hello');
switch (result) {
  case PrintSuccess(:final bytesSent, :final duration):
    print('Printed $bytesSent bytes in ${duration.inMilliseconds}ms');
  case PrintFailure(:final error, :final message):
    print('Print failed: $error - $message');
}
```

## Supported Printers

- Epson TM series
- Star Micronics
- Bixolon
- Citizen
- Zebra
- Generic ESC/POS compatible printers

## Platform Support

Currently supports **Android** only. iOS support is not possible due to iOS limitations with USB devices.

## License

MIT License - see LICENSE file for details