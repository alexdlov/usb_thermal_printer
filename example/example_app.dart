import 'package:flutter/material.dart';
import 'package:usb_thermal_printer/usb_thermal_printer.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'USB Printer Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: PrinterDemo(),
    );
  }
}

class PrinterDemo extends StatefulWidget {
  const PrinterDemo({super.key});

  @override
  State<PrinterDemo> createState() => _PrinterDemoState();
}

class _PrinterDemoState extends State<PrinterDemo> {
  final printer = UsbPrinter();

  @override
  void initState() {
    super.initState();
    _initPrinter();
  }

  Future<void> _initPrinter() async {
    try {
      await printer.init();

      // Listen to errors
      printer.errors$.listen((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      });
    } catch (e) {
      debugPrint('Failed to initialize printer: $e');
    }
  }

  Future<void> _connectToPrinter(UsbDevice device) async {
    try {
      // Choose config based on vendor
      final config = switch (device.vendorId) {
        0x04B8 => PrinterConfig.epson,
        0x0519 => PrinterConfig.star,
        _ => PrinterConfig.defaultConfig,
      };

      await printer.connect(device, config: config);
    } catch (e) {
      debugPrint('Failed to connect: $e');
    }
  }

  Future<void> _printSampleReceipt() async {
    try {
      final result = await printer.printReceipt((r) {
        r
            .title('COFFEE SHOP')
            .subtitle('123 Main Street')
            .subtitle('Tel: (555) 123-4567')
            .feed(1)
            .timestamp(format: 'yyyy-MM-dd HH:mm:ss')
            .text('Order #: 00123')
            .text('Cashier: John Doe')
            .doubleDivider()
            .item('Cappuccino (L)', price: 4.50)
            .item('Croissant', price: 3.25, qty: 2)
            .item('Orange Juice', price: 3.00)
            .divider()
            .row(['Subtotal:', '\$13.00'], widths: [8, 4])
            .row(['Tax (10%):', '\$1.30'], widths: [8, 4])
            .doubleDivider()
            .total('TOTAL:', 14.30)
            .feed(2)
            .text('Payment: VISA ****1234',
                styles: PosStyles(align: PosAlign.center))
            .feed(2)
            .qrcode('https://coffeeshop.com/receipt/00123')
            .feed(1)
            .text('Thank you for your visit!',
                styles: PosStyles(align: PosAlign.center, bold: true))
            .text('Please come again',
                styles: PosStyles(align: PosAlign.center))
            .feed(3)
            .cut();
      });

      if (result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Receipt printed successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Print failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('USB Printer Demo'),
      ),
      body: Column(
        children: [
          // Connection status
          StreamBuilder<PrinterState>(
            stream: printer.state$,
            builder: (context, snapshot) {
              final state = snapshot.data ?? PrinterState.disconnected;
              return Card(
                child: ListTile(
                  leading: Icon(
                    state == PrinterState.connected
                        ? Icons.check_circle
                        : Icons.error,
                    color: state == PrinterState.connected
                        ? Colors.green
                        : Colors.red,
                  ),
                  title: Text('Status: ${state.name}'),
                  subtitle: StreamBuilder<UsbDevice?>(
                    stream: printer.currentDevice$,
                    builder: (context, snapshot) {
                      final device = snapshot.data;
                      return Text(device?.displayName ?? 'No device');
                    },
                  ),
                ),
              );
            },
          ),

          // Device list
          Expanded(
            child: StreamBuilder<List<UsbDevice>>(
              stream: printer.devices$,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.print_disabled,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No USB devices found'),
                        SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: printer.scanDevices,
                          icon: Icon(Icons.refresh),
                          label: Text('Scan Again'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          device.isPrinter ? Icons.print : Icons.usb,
                          size: 32,
                        ),
                        title: Text(device.displayName),
                        subtitle: Text(
                            'VID: ${device.vendorId.toRadixString(16).toUpperCase()} '
                            'PID: ${device.productId.toRadixString(16).toUpperCase()}'),
                        trailing: StreamBuilder<UsbDevice?>(
                          stream: printer.currentDevice$,
                          builder: (context, snapshot) {
                            final isConnected = snapshot.data == device;
                            return isConnected
                                ? Icon(Icons.check, color: Colors.green)
                                : ElevatedButton(
                                    onPressed: () => _connectToPrinter(device),
                                    child: Text('Connect'),
                                  );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Action buttons
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: printer.scanDevices,
                  icon: Icon(Icons.search),
                  label: Text('Scan'),
                ),
                StreamBuilder<PrinterState>(
                  stream: printer.state$,
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data == PrinterState.connected;
                    return ElevatedButton.icon(
                      onPressed: isConnected ? _printSampleReceipt : null,
                      icon: Icon(Icons.receipt),
                      label: Text('Print Receipt'),
                    );
                  },
                ),
                StreamBuilder<PrinterState>(
                  stream: printer.state$,
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data == PrinterState.connected;
                    return ElevatedButton.icon(
                      onPressed: isConnected ? printer.printTestPage : null,
                      icon: Icon(Icons.print),
                      label: Text('Test'),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    printer.dispose();
    super.dispose();
  }
}
