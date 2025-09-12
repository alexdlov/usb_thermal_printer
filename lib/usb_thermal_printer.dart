// Export all public APIs
export 'src/usb_printer.dart';
export 'src/models/print_model.dart';
export 'src/receipt_builder.dart';
export 'src/error/printer_error.dart';
export 'src/platform/usb_printer_platform.dart' show UsbPrinterPlatform;

// Re-export useful ESC/POS classes for convenience
export 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart'
    show
        // Paper and alignment
        PaperSize,
        PosAlign,
        PosStyles,
        PosTextSize,
        PosCutMode,
        // Generator for advanced usage
        Generator,
        CapabilityProfile;
