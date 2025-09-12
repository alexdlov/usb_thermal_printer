import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart' as esc;
import 'package:image/image.dart' as img;

/// Fluent API for building receipts
///
/// Example:
/// ```dart
/// receipt
///   .title('STORE NAME')
///   .subtitle('123 Main St')
///   .feed(1)
///   .text('Order #12345')
///   .divider()
///   .item('Coffee', price: 3.50, qty: 2)
///   .item('Sandwich', price: 8.00)
///   .divider()
///   .total('Total:', 14.50)
///   .feed(2)
///   .qrcode('https://example.com/receipt/12345')
///   .cut();
/// ```
class ReceiptBuilder {
  final esc.Generator _generator;
  final List<List<int>> _commands = [];

  ReceiptBuilder(this._generator);

  /// Add raw bytes
  ReceiptBuilder raw(List<int> bytes) {
    _commands.add(bytes);
    return this;
  }

  /// Add text with optional styles
  ReceiptBuilder text(
    String text, {
    esc.PosStyles? styles,
    int linesAfter = 0,
  }) {
    _commands.add(_generator.text(text, styles: styles ?? esc.PosStyles()));
    if (linesAfter > 0) {
      feed(linesAfter);
    }
    return this;
  }

  /// Add title (centered, bold, size 2x)
  ReceiptBuilder title(String text) {
    return this.text(
      text,
      styles: esc.PosStyles(
        align: esc.PosAlign.center,
        bold: true,
        height: esc.PosTextSize.size2,
        width: esc.PosTextSize.size2,
      ),
    );
  }

  /// Add subtitle (centered, size 1x)
  ReceiptBuilder subtitle(String text) {
    return this.text(
      text,
      styles: esc.PosStyles(align: esc.PosAlign.center),
    );
  }

  /// Add divider line
  ReceiptBuilder divider({String char = '-', int? length}) {
    final dividerLength = length ?? 42; // Default width for 80mm paper
    return text(char * dividerLength);
  }

  /// Add double divider
  ReceiptBuilder doubleDivider() {
    return divider(char: '=');
  }

  /// Add row with columns
  ReceiptBuilder row(
    List<String> columns, {
    List<int>? widths,
    esc.PosStyles? styles,
  }) {
    _commands.add(_generator.row(
      columns
          .map((text) => esc.PosColumn(
                text: text,
                width: (widths != null && widths.length > columns.indexOf(text))
                    ? widths[columns.indexOf(text)]
                    : (12 ~/ columns.length),
                styles: styles ?? esc.PosStyles(),
              ))
          .toList(),
    ));
    return this;
  }

  /// Add item line (name and price)
  ReceiptBuilder item(
    String name, {
    required double price,
    int? qty,
    String? currency = '\$',
  }) {
    final qtyText = qty != null ? ' x$qty' : '';
    final priceText = '$currency${price.toStringAsFixed(2)}';
    return row([
      '$name$qtyText',
      priceText,
    ], widths: [
      8,
      4
    ]);
  }

  /// Add total line
  ReceiptBuilder total(
    String label,
    double amount, {
    String? currency = '\$',
    bool bold = true,
  }) {
    return row(
      [label, '$currency${amount.toStringAsFixed(2)}'],
      widths: [8, 4],
      styles: esc.PosStyles(bold: bold),
    );
  }

  /// Add image
  ReceiptBuilder image(
    img.Image image, {
    esc.PosAlign align = esc.PosAlign.center,
  }) {
    _commands.add(_generator.image(image, align: align));
    return this;
  }

  /// Add QR code
  ReceiptBuilder qrcode(
    String data, {
    esc.PosAlign align = esc.PosAlign.center,
    QRSize size = QRSize.medium,
  }) {
    // Use correct QRSize from esc_pos_utils_plus
    final qrSize = switch (size) {
      QRSize.small => esc.QRSize.size4,
      QRSize.medium => esc.QRSize.size6,
      QRSize.large => esc.QRSize.size8,
    };

    _commands.add(_generator.qrcode(
      data,
      align: align,
      size: qrSize,
    ));
    return this;
  }

  /// Add barcode
  ReceiptBuilder barcode(
    String data, {
    BarcodeType type = BarcodeType.code128,
    esc.PosAlign align = esc.PosAlign.center,
    int? width,
    int? height,
    BarcodeText textPos = BarcodeText.below,
  }) {
    final barcodeData = switch (type) {
      BarcodeType.code39 => esc.Barcode.code39(data.codeUnits),
      BarcodeType.code93 =>
        esc.Barcode.code128(data.codeUnits), // Use code128 as fallback
      BarcodeType.code128 => esc.Barcode.code128(data.codeUnits),
      BarcodeType.ean8 => esc.Barcode.ean8(data.codeUnits),
      BarcodeType.ean13 => esc.Barcode.ean13(data.codeUnits),
      BarcodeType.upcA => esc.Barcode.upcA(data.codeUnits),
      BarcodeType.upcE => esc.Barcode.upcE(data.codeUnits),
    };

    _commands.add(_generator.barcode(
      barcodeData,
      align: align,
      width: width,
      height: height,
    ));
    return this;
  }

  /// Feed paper
  ReceiptBuilder feed(int lines) {
    _commands.add(_generator.feed(lines));
    return this;
  }

  /// Cut paper
  ReceiptBuilder cut({bool partial = false}) {
    _commands.add(_generator.cut(
      mode: partial ? esc.PosCutMode.partial : esc.PosCutMode.full,
    ));
    return this;
  }

  /// Open cash drawer
  ReceiptBuilder openDrawer() {
    _commands.add(_generator.drawer());
    return this;
  }

  /// Add timestamp
  ReceiptBuilder timestamp({
    DateTime? date,
    String? format,
    esc.PosStyles? styles,
  }) {
    final dateTime = date ?? DateTime.now();
    final dateStr = format != null
        ? _formatDate(dateTime, format)
        : dateTime.toString().substring(0, 19);

    return text(dateStr, styles: styles);
  }

  /// Build the receipt
  List<int> build() {
    return _commands.expand((bytes) => bytes).toList();
  }

  String _formatDate(DateTime date, String format) {
    // Simple date formatter
    return format
        .replaceAll('yyyy', date.year.toString().padLeft(4, '0'))
        .replaceAll('MM', date.month.toString().padLeft(2, '0'))
        .replaceAll('dd', date.day.toString().padLeft(2, '0'))
        .replaceAll('HH', date.hour.toString().padLeft(2, '0'))
        .replaceAll('mm', date.minute.toString().padLeft(2, '0'))
        .replaceAll('ss', date.second.toString().padLeft(2, '0'));
  }
}

// Enums
enum QRSize { small, medium, large }

enum BarcodeType { code39, code93, code128, ean8, ean13, upcA, upcE }

enum BarcodeText { none, above, below, both }
