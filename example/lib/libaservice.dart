import 'dart:ffi';

import 'package:flutter_cpp_bridge/service.dart';

class LibAService extends Service {
  LibAService(super.libname) {
    getHexaColor = lib
        .lookup<NativeFunction<Uint32 Function(Pointer<BackendMsg>)>>(
          'get_hexa_color',
        )
        .asFunction<int Function(Pointer<BackendMsg>)>();
  }
  late Function getHexaColor; // mandatory getter function
}
