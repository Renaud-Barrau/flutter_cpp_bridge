
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:flutter_cpp_bridge/service.dart';

class LibBService extends Service
{
  LibBService(super.libname)
  {
    getText = lib.lookup<NativeFunction<Pointer<Utf8> Function(Pointer<BackendMsg>)>>('get_text')
      .asFunction<Pointer<Utf8> Function(Pointer<BackendMsg>)>();
  }
  late Pointer<Utf8> Function(Pointer<BackendMsg>) getText;   // mandatory getter function

}