import 'dart:async';
import 'service.dart';

/// Manages a collection of [Service] instances and periodically polls them
/// for new messages.
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
/// pool.startPolling(); // polls every 100 ms by default
/// ```
///
/// Call [dispose] when the pool is no longer needed to stop all services.
class ServicePool {

  /// Stops all registered services and cancels the polling timer.
  void dispose()
  {
    for(final service in _services)
    {
      service.stopService();
    }
  }

  /// Adds [newService] to the pool and calls its `start_service` function.
  ///
  /// Returns `true` on success.
  bool addService(Service newService) {
    newService.startService();
    _services.add(newService);
    return true;
  }

  /// Starts periodic polling of all registered services.
  ///
  /// Every [interval] (default: 100 ms) [poll] is called, which pushes the
  /// next available message from each service onto its [Service.messageStream].
  ///
  /// Calling [startPolling] again cancels the previous timer before starting
  /// a new one.
  void startPolling({Duration interval = const Duration(milliseconds: 100)})
  {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (timer) {
      poll();
    });
  }

  /// Polls every registered service once and feeds the result into each
  /// service's [Service.messageController].
  ///
  /// You rarely need to call this directly — prefer [startPolling].
  void poll()
  {
    for(final service in _services)
    {
      var nextMsg = service.getNextMessage();
      service.messageController.add(nextMsg);
    }
  }

  final _services = <Service>{};
  Timer? _pollingTimer;
}
