import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_cpp_bridge/service.dart';

import 'messages_fcb_msgs_generated.dart';

export 'messages_fcb_msgs_generated.dart';

/// Dart wrapper for libmessage.so.
///
/// Binds the two byte-buffer getters exported by [FCB_EXPORT_BYTES_SYMBOLS]
/// and exposes [getMessageBytes] for deserialising FlatBuffers payloads.
///
/// Typical usage:
/// ```dart
/// final svc = LibMessageService('libmessage.so');
/// svc.assignJob((msg) {
///   final message = svc.decode(msg);
///   if (message == null) return;
///   switch (message.payloadType) {
///     case Payload.colorMsg:
///       final c = message.payload as ColorMsg;
///       print('color: rgb(${c.r}, ${c.g}, ${c.b})');
///     case Payload.textMsg:
///       final t = message.payload as TextMsg;
///       print('text: ${t.text}');
///   }
/// });
/// servicePool.addService(svc);
/// ```
class LibMessageService extends Service {
  LibMessageService(super.libname) {
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

  /// Returns a zero-copy [Uint8List] view of the FlatBuffers buffer.
  ///
  /// Valid only for the duration of the [assignJob] callback — the C++
  /// side frees the buffer as soon as [freeMessage] is called.
  Uint8List getMessageBytes(Pointer<BackendMsg> msg) =>
      _getBytes(msg).asTypedList(_getLen(msg));

  /// Convenience method: deserialise the buffer into a [Message].
  Message? decode(Pointer<BackendMsg> msg) => Message(getMessageBytes(msg));
}
