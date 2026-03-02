import 'dart:ffi';

import 'package:flutter_cpp_bridge/standalone_service.dart';

class LibCService extends StandaloneService {
  LibCService(super.libname) {
    increment = lib
        .lookup<NativeFunction<Int32 Function()>>('increment')
        .asFunction<int Function()>();
  }

  late int Function() increment;
}
