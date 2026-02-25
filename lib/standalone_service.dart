import 'service.dart';

/// A [Service] that starts itself immediately upon construction.
///
/// Use this when a service should run independently without being added to a
/// [ServicePool]. The service's `start_service` C function is called in the
/// constructor. Call [dispose] (inherited from [Service]) to invoke
/// `stop_service` and release the native callback when done.
///
/// ## Example
///
/// ```dart
/// class LoggerService extends StandaloneService {
///   LoggerService(super.libname) {
///     log = lib
///         .lookup<NativeFunction<Void Function()>>('log_message')
///         .asFunction<void Function()>();
///   }
///
///   late final void Function() log;
/// }
///
/// final logger = LoggerService('liblogger.so');
/// logger.log(); // C++ service already running
/// // ...
/// logger.dispose();
/// ```
class StandaloneService extends Service {
  /// Opens [libname], registers the notification callback, and immediately
  /// calls `start_service`.
  StandaloneService(super.libname) {
    startService();
  }
}
