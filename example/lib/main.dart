import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cpp_bridge/service_pool.dart';
import 'libalone.dart';
import 'libaservice.dart';
import 'libbservice.dart';
import 'libcservice.dart';
import 'libmessageservice.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<int> color = ValueNotifier<int>(0x0000FFFF);
    final ValueNotifier<String> text = ValueNotifier<String>("abcde");
    final ValueNotifier<int> count = ValueNotifier<int>(0);
    // libmessage: FlatBuffers-based dispatch (ColorMsg or TextMsg)
    final ValueNotifier<Color> msgColor = ValueNotifier<Color>(Colors.grey);
    final ValueNotifier<String> msgLog = ValueNotifier<String>('waiting…');

    // Create services pool
    var servicePool = ServicePool();

    // Example of how to create a service
    var libaService = LibAService("liba.so");
    var libbService = LibBService("libb.so");

    // Example of standalone service (no-op start/stop)
    var libAlone = AloneService("libalone.so");

    // Example of standalone service with real start/stop (FCB_EXPORT_STANDALONE).
    // start_service() resets the counter; stop_service() clears it.
    var libC = LibCService("libc.so");

    // FlatBuffers byte-buffer service: single service dispatching multiple types.
    var libMsg = LibMessageService("libmessage.so");

    // Binding service to frontend.
    // No nullptr check needed: assignJob callbacks are only invoked for real
    // messages — the stream never emits nullptr since switching to NativeCallable.
    libaService.assignJob((message) {
      color.value = libaService.getHexaColor(message);
      libAlone.hello();
    });

    libbService.assignJob((message) {
      final cPtr = libbService.getText(message);
      text.value = cPtr.toDartString();
    });

    libMsg.assignJob((msg) {
      final message = libMsg.decode(msg);
      if (message == null) return;
      switch (message.payloadType) {
        case Payload.colorMsg:
          final c = message.payload as ColorMsg;
          msgColor.value = Color.fromARGB(255, c.r, c.g, c.b);
          msgLog.value = '#${c.r.toRadixString(16).padLeft(2, '0')}'
              '${c.g.toRadixString(16).padLeft(2, '0')}'
              '${c.b.toRadixString(16).padLeft(2, '0')}'
              ' (id=${message.id})';
        case Payload.textMsg:
          final t = message.payload as TextMsg;
          msgLog.value = '${t.text} (id=${message.id})';
      }
    });

    servicePool.addService(libaService);
    servicePool.addService(libbService);
    servicePool.addService(libMsg);

    // No startPolling() needed — delivery is event-driven via NativeCallable.

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: color,
                builder: (context, color, child) {
                  return Text(
                    'Hello World!',
                    style: TextStyle(
                      color: Color(color),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),

              ValueListenableBuilder<String>(
                valueListenable: text,
                builder: (context, text, child) {
                  return Text(
                    text,
                    style: TextStyle(
                      color: Color(0xFF000000),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // ── libmessage: FlatBuffers dispatch ──────────────────────────
              ValueListenableBuilder<Color>(
                valueListenable: msgColor,
                builder: (context, c, _) => Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: c,
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              ValueListenableBuilder<String>(
                valueListenable: msgLog,
                builder: (context, log, _) => Text(
                  log,
                  style: const TextStyle(fontSize: 16, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 24),

              ValueListenableBuilder<int>(
                valueListenable: count,
                builder: (context, count, child) {
                  return Text(
                    'Count: $count',
                    style: const TextStyle(fontSize: 20),
                  );
                },
              ),
              ElevatedButton(
                onPressed: () => count.value = libC.increment(),
                child: const Text('Increment (libc.so)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
