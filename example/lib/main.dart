import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cpp_bridge/service_pool.dart';
import 'libalone.dart';
import 'libaservice.dart';
import 'libbservice.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<int> color = ValueNotifier<int>(0x0000FFFF);
    final ValueNotifier<String> text = ValueNotifier<String>("abcde");

    // Create services pool
    var servicePool = ServicePool();

    // Example of how to create a service
    var libaService = LibAService("liba.so");
    var libbService = LibBService("libb.so");

    // Example of standalone service
    var libAlone = AloneService("libalone.so");

    // Binding service to frontend
    libaService.assignJob((message) {
      if (message != nullptr) {
        color.value = libaService.getHexaColor(message);
        libAlone.hello();
      }
    });

    libbService.assignJob((message) {
      if (message != nullptr) {
        final cPtr = libbService.getText(message);
        text.value = cPtr.toDartString();
      }
    });

    servicePool.addService(libaService);
    servicePool.addService(libbService);

    servicePool.startPolling();
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
            ],
          ),
        ),
      ),
    );
  }
}
