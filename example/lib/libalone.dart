import 'dart:ffi';

import 'package:flutter_cpp_bridge/standalone_service.dart';

class AloneService extends StandaloneService {
  AloneService(super.libname) {
    hello = lib
        .lookup<NativeFunction<Void Function()>>('hello')
        .asFunction<void Function()>();
  }

  late Function hello;
}
