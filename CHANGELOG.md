## 0.0.1

* Initial release.
* `Service`: base class to wrap a C++ shared library via `dart:ffi`. Binds the
  four mandatory C functions (`start_service`, `stop_service`,
  `get_next_message`, `free_message`) and exposes a broadcast message stream.
* `ServicePool`: manages multiple services and polls them at a configurable
  interval (default 100 ms).
* `StandaloneService`: a `Service` subclass that starts immediately on
  construction and exposes a `dispose()` method.
