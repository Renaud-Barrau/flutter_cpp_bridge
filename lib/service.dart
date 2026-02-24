import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';

/// Opaque type representing a message produced by a C++ service.
///
/// The actual memory layout is defined on the C++ side. Dart only ever
/// manipulates [Pointer<BackendMsg>] values — it never dereferences this type
/// directly. Use the extra functions exposed by your [Service] subclass to
/// read fields from the pointer.
final class BackendMsg extends Opaque {}

/// Base class for a C++ shared-library service accessed through `dart:ffi`.
///
/// A *service* is a shared library (`.so` / `.dll` / `.dylib`) that exports
/// at least these four C functions:
///
/// ```c
/// void start_service();
/// void stop_service();
/// T*   get_next_message();   // T is your message struct
/// void free_message(T*);
/// ```
///
/// ## Subclassing
///
/// Extend [Service] to bind any additional functions your library exposes:
///
/// ```dart
/// class ColorService extends Service {
///   ColorService(super.libname) {
///     getColor = lib
///         .lookup<NativeFunction<Uint32 Function(Pointer<BackendMsg>)>>('get_color')
///         .asFunction<int Function(Pointer<BackendMsg>)>();
///   }
///
///   late final int Function(Pointer<BackendMsg>) getColor;
/// }
/// ```
///
/// ## Receiving messages
///
/// Use [assignJob] to register a callback that is invoked for every message
/// polled from the C++ queue:
///
/// ```dart
/// colorService.assignJob((msg) {
///   if (msg != nullptr) {
///     myNotifier.value = colorService.getColor(msg);
///   }
/// });
/// ```
///
/// [freeMessage] is called automatically after the job returns, so you do
/// **not** need to call it manually inside the callback.
///
/// ## Lifecycle
///
/// Add the service to a [ServicePool] (which calls [startService] for you),
/// or subclass [StandaloneService] to start the service immediately.
class Service {
  /// Creates a [Service] by opening the shared library at [libname] and
  /// binding the four mandatory C functions.
  ///
  /// [libname] is the path passed to [DynamicLibrary.open] — typically just
  /// the file name (e.g. `"libaudio.so"`) when the library is bundled next to
  /// the executable.
  Service(this.libname) {
    lib = (DynamicLibrary.open(libname));

    startService = lib
        .lookup<NativeFunction<Void Function()>>('start_service')
        .asFunction<void Function()>();

    stopService = lib
        .lookup<NativeFunction<Void Function()>>('stop_service')
        .asFunction<void Function()>();

    getNextMessage = lib
        .lookup<NativeFunction<Pointer<BackendMsg> Function()>>(
          'get_next_message',
        )
        .asFunction<Pointer<BackendMsg> Function()>();

    freeMessage = lib
        .lookup<NativeFunction<Void Function(Pointer<BackendMsg>)>>(
          'free_message',
        )
        .asFunction<void Function(Pointer<BackendMsg>)>();
  }

  /// Registers a callback that is invoked each time a message is polled.
  ///
  /// [job] receives a [Pointer<BackendMsg>] which may be `nullptr` when the
  /// C++ queue is empty. [freeMessage] is called automatically once [job]
  /// returns (only when the pointer is non-null).
  @nonVirtual
  void assignJob(void Function(Pointer<BackendMsg>) job) {
    messageStream.listen((message) {
      job(message);
      if(message != nullptr)
      {
        freeMessage(message);
      }
    });
  }

  /// Path to the shared library, as passed to [DynamicLibrary.open].
  @protected
  final String libname;

  /// The opened [DynamicLibrary]. Available to subclasses for binding
  /// additional native functions.
  @protected
  late DynamicLibrary lib;

  /// Broadcast stream of raw message pointers polled from the C++ queue.
  ///
  /// Prefer [assignJob] over listening to this stream directly, as [assignJob]
  /// also handles calling [freeMessage].
  final StreamController<Pointer<BackendMsg>> messageController =
      StreamController<Pointer<BackendMsg>>.broadcast();

  /// The broadcast stream fed by [messageController].
  Stream<Pointer<BackendMsg>> get messageStream => messageController.stream;

  /// Bound to the C `start_service()` function.
  late Function startService;

  /// Bound to the C `stop_service()` function.
  late Function stopService;

  /// Bound to the C `get_next_message()` function.
  late Function getNextMessage;

  /// Bound to the C `free_message()` function.
  late Function freeMessage;
}
