## 1.0.1

* Update README installation instructions now that the package is on pub.dev.
* Remove unused `ffigen` dev dependency.

## 1.0.0

* First stable release — event-driven delivery is now the default and only
  delivery mechanism. No breaking changes relative to 0.1.0.
* Published on pub.dev.

## 0.1.0

* Replace the `Timer.periodic` polling loop with an event-driven delivery
  mechanism using `dart:ffi` `NativeCallable.listener`. Zero CPU consumption
  at idle.
* Each service now requires a fifth mandatory C symbol,
  `set_message_callback(void (*cb)())`. The C++ worker calls `cb` immediately
  after pushing a message; Dart processes it on the event loop.
* `ServicePool` no longer owns a periodic timer. The poll interval parameter
  has been removed.
* `Service.dispose()` closes the `NativeCallable` and stops the service.

## 0.0.0

* Initial release.
* `Service`: base class to wrap a C++ shared library via `dart:ffi`. Binds
  four mandatory C functions (`start_service`, `stop_service`,
  `get_next_message`, `free_message`) and exposes a broadcast message stream.
* `ServicePool`: manages multiple services and polls them at a configurable
  interval (default 100 ms).
* `StandaloneService`: a `Service` subclass that starts immediately on
  construction and exposes a `dispose()` method.
