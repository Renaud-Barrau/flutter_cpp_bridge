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

/// Native type for the no-argument notification callback passed to
/// `set_message_callback`.
typedef _NotifyNative = Void Function();

/// Base class for a C++ shared-library service accessed through `dart:ffi`.
///
/// A *service* is a shared library (`.so` / `.dll` / `.dylib`) that exports
/// exactly these five C functions:
///
/// ```c
/// void start_service();
/// void stop_service();
/// T*   get_next_message();        // T is your message struct; nullptr = empty
/// void free_message(T*);
/// void set_message_callback(void (*cb)());  // store cb; call it when a message is ready
/// ```
///
/// Instead of a periodic polling timer, each service registers a
/// [NativeCallable] with `set_message_callback`. The C++ worker thread calls
/// the callback whenever a new message is pushed; Dart then drains the entire
/// queue in one shot on the event loop — zero CPU consumption at idle.
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
/// Use [assignJob] to register a callback that is invoked for every message:
///
/// ```dart
/// colorService.assignJob((msg) {
///   myNotifier.value = colorService.getColor(msg);
/// });
/// ```
///
/// [freeMessage] is called automatically after the job returns.
///
/// ## Lifecycle
///
/// Add the service to a [ServicePool] (which calls [startService] for you),
/// or subclass [StandaloneService] to start the service immediately.
/// Call [dispose] when done.
class Service {
  /// Creates a [Service] by opening the shared library at [libname], binding
  /// the five mandatory C functions, and registering the notification callback.
  ///
  /// [libname] is the path passed to [DynamicLibrary.open] — typically just
  /// the file name (e.g. `"libaudio.so"`) when the library is bundled next to
  /// the executable.
  Service(this.libname) {
    try {
      lib = DynamicLibrary.open(libname);

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

      _setMessageCallback = lib
          .lookup<
                  NativeFunction<
                      Void Function(Pointer<NativeFunction<_NotifyNative>>)>>(
              'set_message_callback')
          .asFunction<void Function(Pointer<NativeFunction<_NotifyNative>>)>();

      // NativeCallable.listener is safe to call from any thread: the C++ worker
      // posts the notification and Dart schedules _onNotify on the event loop.
      _callable = NativeCallable<_NotifyNative>.listener(_onNotify);
      _setMessageCallback(_callable!.nativeFunction);
    } catch (_) {
      // Construction failed (missing symbol, library not found, …).
      // Mark as disposed so that dispose() becomes a no-op if called via
      // try/finally. Close _callable if it was created before the exception —
      // leaving it open would prevent the Dart isolate from exiting cleanly.
      _disposed = true;
      _messageController.close();
      _callable?.close();
      rethrow;
    }
  }

  /// Called on the Dart event loop each time the C++ side signals a new
  /// message. Retrieves one message and pushes it onto [_messageController].
  ///
  /// One callback invocation = one message: C++ must call `cb()` exactly once
  /// per message pushed. A drain loop is intentionally avoided here because
  /// [_messageController] delivers asynchronously — [freeMessage] would not be
  /// called before the next [getNextMessage], causing an infinite loop on any
  /// service whose [getNextMessage] does not return `nullptr` immediately after
  /// the first call.
  void _onNotify() {
    if (_disposed) return;
    final msg = getNextMessage();
    if (msg != nullptr) {
      if (_messageController.hasListener) {
        _messageController.add(msg);
      } else {
        // No listener registered: free immediately to avoid a C++ memory leak.
        freeMessage(msg);
      }
    }
  }

  /// Registers [job] as the handler invoked for every message emitted by this
  /// service.
  ///
  /// [job] receives a non-null [Pointer<BackendMsg>]. [freeMessage] is called
  /// automatically once [job] returns.
  @nonVirtual
  void assignJob(void Function(Pointer<BackendMsg>) job) {
    assert(!_disposed, 'assignJob called on a disposed Service');
    assert(
      _subscriptions.isEmpty,
      'assignJob called twice on the same Service — '
      'each message pointer would be freed twice (double-free)',
    );
    _subscriptions.add(_messageStream.listen((message) {
      job(message);
      freeMessage(message);
    }));
  }

  /// Stops the service and releases the native callback.
  ///
  /// Calls the C++ `stop_service` function, cancels all stream subscriptions,
  /// closes the [StreamController], and closes the [NativeCallable], allowing
  /// the Dart isolate to exit cleanly. Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopService();
    // Nullify the C++ callback pointer before closing the NativeCallable.
    // stop_service() only sets a flag; the worker thread may still call
    // notify_cb() while the Dart side is tearing down. Passing nullptr makes
    // the C++ guard (if (notify_cb) notify_cb()) a safe no-op from that point.
    _setMessageCallback(nullptr);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _messageController.close();
    _callable?.close();
  }

  /// Path to the shared library, as passed to [DynamicLibrary.open].
  @protected
  final String libname;

  /// The opened [DynamicLibrary]. Available to subclasses for binding
  /// additional native functions.
  @protected
  late DynamicLibrary lib;

  /// Broadcast stream of raw message pointers drained from the C++ queue.
  ///
  /// Only non-null pointers are emitted. Prefer [assignJob] over listening
  /// to this stream directly, as [assignJob] also handles [freeMessage].
  Stream<Pointer<BackendMsg>> get _messageStream => _messageController.stream;

  /// Bound to the C `start_service()` function.
  late void Function() startService;

  /// Bound to the C `stop_service()` function.
  late void Function() stopService;

  /// Bound to the C `get_next_message()` function.
  late Pointer<BackendMsg> Function() getNextMessage;

  /// Bound to the C `free_message()` function.
  late void Function(Pointer<BackendMsg>) freeMessage;

  final StreamController<Pointer<BackendMsg>> _messageController =
      StreamController<Pointer<BackendMsg>>.broadcast();
  late void Function(Pointer<NativeFunction<_NotifyNative>>)
      _setMessageCallback;
  NativeCallable<_NotifyNative>? _callable;
  bool _disposed = false;
  final List<StreamSubscription<Pointer<BackendMsg>>> _subscriptions = [];
}
