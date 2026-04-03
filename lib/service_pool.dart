import 'service.dart';

/// Manages a collection of [Service] instances.
///
/// Each service is started when added via [addService]. Message delivery is
/// event-driven: each [Service] registers a native callback with the C++ side
/// (`set_message_callback`) and drains its own queue when the C++ worker
/// notifies it. No periodic timer is involved.
///
/// ## Basic usage
///
/// ```dart
/// final pool = ServicePool();
///
/// final colorService = ColorService('libcolor.so');
/// colorService.assignJob((msg) { /* ... */ });
///
/// pool.addService(colorService);
/// // No startPolling() needed — messages are delivered on demand.
/// ```
///
/// Call [dispose] when the pool is no longer needed to stop all services.
class ServicePool {
  /// Stops all registered services and releases their native callbacks.
  ///
  /// Safe to call multiple times.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final service in _services) {
      service.dispose();
    }
  }

  /// Adds [newService] to the pool and calls its `start_service` function.
  ///
  /// Returns `true` on success.
  bool addService(Service newService) {
    assert(!_disposed, 'addService called on a disposed ServicePool');
    newService.startService();
    _services.add(newService);
    return true;
  }

  bool _disposed = false;
  final _services = <Service>{};
}
