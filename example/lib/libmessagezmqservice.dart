import 'dart:ffi';

import 'package:flutter_cpp_bridge/service.dart';

import 'messages_fcb_msgs_generated.dart';

export 'messages_fcb_msgs_generated.dart';

/// Dart wrapper for libmessagezmq.so.
///
/// Receives FlatBuffers messages published by an external process over ZMQ
/// (SUB socket connected to `ipc:///tmp/zmq_test`).  The C++ worker holds a
/// switch-case that filters and routes messages before pushing them into the
/// [fcb::BytesQueue] — Dart only receives what C++ explicitly forwarded.
///
/// Usage:
/// ```dart
/// final svc = LibMessageZmqService();
/// svc.assignJob((msg) {
///   final message = svc.decode(msg);
///   if (message == null) return;
///   switch (message.payloadType) { ... }
/// });
/// servicePool.addService(svc);
/// ```
class LibMessageZmqService extends Service {
  LibMessageZmqService() : super('libmessagezmq.so') {
    _getBytes = lib
        .lookup<NativeFunction<Pointer<Uint8> Function(Pointer<BackendMsg>)>>(
          'get_msg_bytes',
        )
        .asFunction();
    _getLen = lib
        .lookup<NativeFunction<Uint32 Function(Pointer<BackendMsg>)>>(
          'get_msg_len',
        )
        .asFunction();
  }

  late final Pointer<Uint8> Function(Pointer<BackendMsg>) _getBytes;
  late final int Function(Pointer<BackendMsg>) _getLen;

  /// Deserialise the FlatBuffers buffer into a [Message].
  ///
  /// Valid only for the duration of the [assignJob] callback.
  Message? decode(Pointer<BackendMsg> msg) =>
      Message(_getBytes(msg).asTypedList(_getLen(msg)));
}
