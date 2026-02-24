import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_cpp_bridge_method_channel.dart';

abstract class FlutterCppBridgePlatform extends PlatformInterface {
  /// Constructs a FlutterCppBridgePlatform.
  FlutterCppBridgePlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterCppBridgePlatform _instance = MethodChannelFlutterCppBridge();

  /// The default instance of [FlutterCppBridgePlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterCppBridge].
  static FlutterCppBridgePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterCppBridgePlatform] when
  /// they register themselves.
  static set instance(FlutterCppBridgePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
